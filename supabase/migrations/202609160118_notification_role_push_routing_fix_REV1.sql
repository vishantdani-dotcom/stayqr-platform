-- StayQR notification department isolation + Restaurant background food push — REV1
-- Migration: 202609160118
--
-- Scope is deliberately narrow:
--   1. Align server-side notification recipients with the already-approved
--      frontend role/department routing.
--   2. Add server notification-outbox events for NEW and CANCELLED food orders
--      so Restaurant/Kitchen devices receive real Service Worker background push.
--
-- Does NOT alter:
--   Navbar foreground/recovery logic, ringtone assets, service worker,
--   background-push edge function, Guest Guide, QR, billing, RLS, hotel data,
--   rooms/reservations/folios, UI/theme, or The Velvet Loom demo content.
--
-- Existing notification_recipients are not deleted or rewritten. The new routing
-- applies to notifications created after this migration.

begin;

-- ---------------------------------------------------------------------------
-- 0. Hard preflight
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('public.staff') is null
     or to_regclass('public.notification_event_catalog') is null
     or to_regclass('public.notification_templates') is null
     or to_regclass('public.notification_outbox') is null
     or to_regclass('public.notification_recipients') is null
     or to_regclass('public.food_orders') is null
  then
    raise exception 'Migration 118 stopped: required notification/food tables are missing.';
  end if;

  if to_regprocedure(
       'private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid)'
     ) is null
     or to_regprocedure(
       'private.day17_render_notification_text(text,jsonb)'
     ) is null
  then
    raise exception 'Migration 118 stopped: accepted Day 17 notification kernel is missing.';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'day17_enqueue_notification_event_internal'
      and pg_get_functiondef(p.oid) like '%from public.staff s%'
      and pg_get_functiondef(p.oid) like '%s.status = ''active''%'
      and pg_get_functiondef(p.oid) like '%s.auth_user_id is not null%'
  ) then
    raise exception 'Migration 118 stopped: Day 17 recipient loop does not match the accepted baseline.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Server-side role/department routing helper.
--    Mirrors src/lib/departmentNotificationRouting.js:
--      Dashboard roles = global hotel observer
--      Restaurant/Kitchen = food + restaurant service requests
--      Housekeeping = housekeeping/maintenance/laundry requests
--      Accounts = payment/invoice + accounts requests
-- ---------------------------------------------------------------------------
create or replace function private.day118_role_can_receive_notification(
  p_event_key text,
  p_source_type text,
  p_payload jsonb,
  p_staff_role text
) returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_role text := regexp_replace(
    lower(trim(coalesce(p_staff_role, ''))),
    '[^a-z0-9]+',
    '_',
    'g'
  );
  v_event text := lower(trim(coalesce(p_event_key, '')));
  v_source text := lower(trim(coalesce(p_source_type, '')));
  v_department text := regexp_replace(
    lower(trim(coalesce(p_payload ->> 'department', ''))),
    '[^a-z0-9]+',
    '_',
    'g'
  );
  v_haystack text := v_source || ' ' || v_event;
begin
  -- Global hotel operational observers.
  if v_role = any (
    array[
      'owner','manager','reception','front_desk','frontdesk',
      'hotel_admin','admin','platform_admin','super_admin',
      'platform_support'
    ]::text[]
  ) then
    return true;
  end if;

  -- Service requests are routed by their authoritative department.
  if v_source = 'service_request'
     or v_event like 'service_request.%'
  then
    if v_department = 'restaurant' then
      return v_role = any (array['restaurant','kitchen','chef']::text[]);
    elsif v_department = any (
      array['housekeeping','maintenance','laundry']::text[]
    ) then
      return v_role = any (
        array['housekeeping','housekeeper','maintenance','laundry']::text[]
      );
    elsif v_department = 'accounts' then
      return v_role = any (array['accounts','accounting']::text[]);
    else
      -- front_office / guest_services / transport / management and unknown
      -- service departments remain visible to dashboard/global observers only.
      return false;
    end if;
  end if;

  -- Department event families.
  if v_haystack like '%food%' then
    return v_role = any (array['restaurant','kitchen','chef']::text[]);
  end if;

  if v_haystack like '%housekeeping%'
     or v_haystack like '%maintenance%'
  then
    return v_role = any (
      array['housekeeping','housekeeper','maintenance','laundry']::text[]
    );
  end if;

  if v_haystack like '%payment%'
     or v_haystack like '%invoice%'
  then
    return v_role = any (array['accounts','accounting']::text[]);
  end if;

  -- Non-dashboard department accounts must not receive unrelated hotel-wide
  -- events (reservation/support/announcement/etc.).
  return false;
end;
$$;

revoke all on function
  private.day118_role_can_receive_notification(text,text,jsonb,text)
from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- 2. Keep the accepted Day 17 kernel, changing only the recipient WHERE clause.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "private"."day17_enqueue_notification_event_internal"("p_hotel_id" "uuid", "p_event_key" "text", "p_source_id" "uuid", "p_payload" "jsonb", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_catalog public.notification_event_catalog%rowtype;
  v_outbox public.notification_outbox%rowtype;
  v_existing public.notification_outbox%rowtype;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_idempotency_key text;
  v_recipient record;
  v_title_template text;
  v_body_template text;
  v_title text;
  v_body text;
  v_locale text;
  v_recipient_count integer := 0;
  v_pending_count integer := 0;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'Notification payload must be a JSON object.';
  end if;

  select *
  into v_catalog
  from public.notification_event_catalog nec
  where nec.event_key = p_event_key
    and nec.is_active;

  if not found then
    raise exception 'Unsupported notification event key: %', p_event_key;
  end if;

  if not exists (
    select 1
    from public.hotels h
    where h.id = p_hotel_id
  ) then
    raise exception 'Notification hotel was not found.';
  end if;

  v_idempotency_key := coalesce(
    nullif(trim(v_payload ->> 'idempotency_key'), ''),
    p_event_key || ':' || p_source_id::text || ':' ||
      coalesce(
        nullif(trim(v_payload ->> 'status'), ''),
        nullif(trim(v_payload ->> 'event_version'), ''),
        'base'
      )
  );

  insert into public.notification_outbox (
    hotel_id,
    event_key,
    source_type,
    source_id,
    idempotency_key,
    payload,
    business_date,
    status,
    created_by,
    occurred_at,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    p_event_key,
    v_catalog.source_type,
    p_source_id,
    v_idempotency_key,
    v_payload - 'idempotency_key',
    private.resolve_hotel_business_date(
      p_hotel_id,
      coalesce(
        nullif(v_payload ->> 'occurred_at', '')::timestamptz,
        now()
      )
    ),
    'processing',
    p_actor_user_id,
    coalesce(
      nullif(v_payload ->> 'occurred_at', '')::timestamptz,
      now()
    ),
    now(),
    now()
  )
  on conflict (hotel_id, idempotency_key) do nothing
  returning * into v_outbox;

  if v_outbox.id is null then
    select *
    into v_existing
    from public.notification_outbox nox
    where nox.hotel_id = p_hotel_id
      and nox.idempotency_key = v_idempotency_key;

    return jsonb_build_object(
      'outbox_id', v_existing.id,
      'idempotent', true,
      'status', v_existing.status
    );
  end if;

  for v_recipient in
    select
      s.auth_user_id as user_id,
      nullif(trim(s.email), '') as email,
      nullif(trim(s.phone), '') as phone,
      coalesce(np.locale, 'en') as locale,
      coalesce(np.in_app_enabled, true) as in_app_enabled,
      coalesce(np.email_enabled, false) as email_enabled,
      coalesce(np.manual_whatsapp_enabled, false)
        as manual_whatsapp_enabled
    from public.staff s
    left join public.notification_preferences np
      on np.hotel_id = s.hotel_id
     and np.user_id = s.auth_user_id
    where s.hotel_id = p_hotel_id
      and s.status = 'active'
      and s.auth_user_id is not null
      and private.day118_role_can_receive_notification(
        p_event_key,
        v_catalog.source_type,
        v_payload,
        s.role
      )
  loop
    v_locale := v_recipient.locale;

    select
      nt.title_template,
      nt.body_template
    into
      v_title_template,
      v_body_template
    from public.notification_templates nt
    where nt.event_key = p_event_key
      and nt.channel = 'in_app'
      and nt.status = 'published'
      and (nt.hotel_id = p_hotel_id or nt.hotel_id is null)
      and nt.locale in (v_locale, 'en')
    order by
      case when nt.hotel_id = p_hotel_id then 0 else 1 end,
      case when nt.locale = v_locale then 0 else 1 end,
      nt.updated_at desc
    limit 1;

    v_title := private.day17_render_notification_text(
      coalesce(v_title_template, v_catalog.default_title),
      v_payload
    );
    v_body := private.day17_render_notification_text(
      coalesce(v_body_template, v_catalog.default_body),
      v_payload
    );

    if v_catalog.default_channels ? 'in_app'
       and v_recipient.in_app_enabled
    then
      insert into public.notification_recipients (
        outbox_id,
        hotel_id,
        user_id,
        title,
        message,
        severity,
        status,
        metadata,
        created_at,
        updated_at
      ) values (
        v_outbox.id,
        p_hotel_id,
        v_recipient.user_id,
        v_title,
        v_body,
        v_catalog.severity,
        'unread',
        jsonb_build_object(
          'event_key', p_event_key,
          'source_type', v_catalog.source_type,
          'source_id', p_source_id,
          'business_date', v_outbox.business_date
        ),
        now(),
        now()
      )
      on conflict (outbox_id, user_id) do nothing;

      insert into public.notification_deliveries (
        outbox_id,
        hotel_id,
        recipient_user_id,
        channel,
        address_snapshot,
        locale,
        rendered_title,
        rendered_body,
        status,
        attempt_count,
        delivered_at,
        metadata,
        created_at,
        updated_at
      ) values (
        v_outbox.id,
        p_hotel_id,
        v_recipient.user_id,
        'in_app',
        v_recipient.user_id::text,
        v_locale,
        v_title,
        v_body,
        'delivered',
        1,
        now(),
        jsonb_build_object('delivery_mode', 'realtime_in_app'),
        now(),
        now()
      )
      on conflict do nothing;

      v_recipient_count := v_recipient_count + 1;
    end if;

    if v_catalog.default_channels ? 'email'
       and v_recipient.email_enabled
       and v_recipient.email is not null
    then
      insert into public.notification_deliveries (
        outbox_id,
        hotel_id,
        recipient_user_id,
        channel,
        address_snapshot,
        locale,
        rendered_title,
        rendered_body,
        status,
        metadata,
        created_at,
        updated_at
      ) values (
        v_outbox.id,
        p_hotel_id,
        v_recipient.user_id,
        'email',
        v_recipient.email,
        v_locale,
        v_title,
        v_body,
        'pending',
        jsonb_build_object('delivery_mode', 'provider_adapter'),
        now(),
        now()
      )
      on conflict do nothing;

      v_pending_count := v_pending_count + 1;
    end if;
  end loop;

  update public.notification_outbox nox
  set
    status = case
      when v_pending_count > 0 then 'pending'
      else 'completed'
    end,
    pending_delivery_count = v_pending_count,
    completed_delivery_count = v_recipient_count,
    failed_delivery_count = 0,
    updated_at = now()
  where nox.id = v_outbox.id
  returning * into v_outbox;

  insert into public.activity_logs (
    hotel_id,
    actor_user_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    description,
    metadata,
    created_at
  ) values (
    p_hotel_id,
    p_actor_user_id,
    case
      when p_actor_user_id is null then 'system'
      else 'authenticated'
    end,
    'notification_event_enqueued',
    v_catalog.source_type,
    p_source_id,
    p_event_key,
    jsonb_build_object(
      'outbox_id', v_outbox.id,
      'recipient_count', v_recipient_count,
      'pending_delivery_count', v_pending_count,
      'business_date', v_outbox.business_date
    ),
    now()
  );

  return jsonb_build_object(
    'outbox_id', v_outbox.id,
    'idempotent', false,
    'status', v_outbox.status,
    'recipient_count', v_recipient_count,
    'pending_delivery_count', v_pending_count,
    'business_date', v_outbox.business_date
  );
end;
$$;


ALTER FUNCTION "private"."day17_enqueue_notification_event_internal"("p_hotel_id" "uuid", "p_event_key" "text", "p_source_id" "uuid", "p_payload" "jsonb", "p_actor_user_id" "uuid") OWNER TO "postgres";


-- ---------------------------------------------------------------------------
-- 3. Food-order notification catalogue/templates.
-- ---------------------------------------------------------------------------
insert into public.notification_event_catalog (
  event_key,
  source_type,
  audience,
  severity,
  default_channels,
  default_title,
  default_body,
  is_critical,
  is_active,
  created_at,
  updated_at
) values
(
  'food_order.created',
  'food_order',
  'all_staff',
  'info',
  '["in_app"]'::jsonb,
  'New food order',
  'New guest food order{{room_label}}.',
  false,
  true,
  now(),
  now()
),
(
  'food_order.cancelled',
  'food_order',
  'all_staff',
  'warning',
  '["in_app"]'::jsonb,
  'Food order cancelled',
  'Guest food order{{room_label}} was cancelled.',
  false,
  true,
  now(),
  now()
)
on conflict (event_key)
do update set
  source_type = excluded.source_type,
  audience = excluded.audience,
  severity = excluded.severity,
  default_channels = excluded.default_channels,
  default_title = excluded.default_title,
  default_body = excluded.default_body,
  is_critical = excluded.is_critical,
  is_active = true,
  updated_at = now();

insert into public.notification_templates (
  hotel_id,
  event_key,
  channel,
  locale,
  title_template,
  body_template,
  status,
  current_version,
  created_at,
  updated_at,
  published_at
) values
(
  null,
  'food_order.created',
  'in_app',
  'en',
  'New food order',
  'New guest food order{{room_label}}.',
  'published',
  1,
  now(),
  now(),
  now()
),
(
  null,
  'food_order.cancelled',
  'in_app',
  'en',
  'Food order cancelled',
  'Guest food order{{room_label}} was cancelled.',
  'published',
  1,
  now(),
  now(),
  now()
)
on conflict (event_key, channel, locale)
where hotel_id is null
do update set
  title_template = excluded.title_template,
  body_template = excluded.body_template,
  status = 'published',
  updated_at = now(),
  published_at = coalesce(public.notification_templates.published_at, now());

-- ---------------------------------------------------------------------------
-- 4. Food-order capture: NEW order + cancellation only.
--    Foreground React Realtime remains the primary visible/ringtone path.
--    This creates the server recipient needed by Background Push.
-- ---------------------------------------------------------------------------
create or replace function private.day118_capture_food_order_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_key text;
  v_room_number text;
  v_room_label text := '';
  v_occurred_at timestamptz;
begin
  if tg_op = 'INSERT' then
    v_event_key := 'food_order.created';
    v_occurred_at := coalesce(new.created_at, now());
  elsif tg_op = 'UPDATE'
        and new.order_status is distinct from old.order_status
        and lower(coalesce(new.order_status, '')) = 'cancelled'
  then
    v_event_key := 'food_order.cancelled';
    v_occurred_at := coalesce(new.cancelled_at, new.updated_at, now());
  else
    return new;
  end if;

  if new.room_id is not null then
    select r.room_number
    into v_room_number
    from public.rooms r
    where r.hotel_id = new.hotel_id
      and r.id = new.room_id;

    if nullif(trim(coalesce(v_room_number, '')), '') is not null then
      v_room_label := ' from Room ' || trim(v_room_number);
    end if;
  end if;

  perform private.day17_enqueue_notification_event_internal(
    new.hotel_id,
    v_event_key,
    new.id,
    jsonb_strip_nulls(
      jsonb_build_object(
        'idempotency_key',
          v_event_key || ':' || new.id::text,
        'source_type', 'food_order',
        'source_id', new.id,
        'status', new.order_status,
        'department', 'restaurant',
        'guest_session_id', new.guest_session_id,
        'room_id', new.room_id,
        'room_number', v_room_number,
        'room_label', v_room_label,
        'occurred_at', v_occurred_at
      )
    ),
    (select auth.uid())
  );

  return new;
end;
$$;

revoke all on function
  private.day118_capture_food_order_notification()
from public, anon, authenticated;

drop trigger if exists
  day118_food_order_notification_event
on public.food_orders;

create trigger day118_food_order_notification_event
after insert or update of order_status
on public.food_orders
for each row
execute function private.day118_capture_food_order_notification();

-- ---------------------------------------------------------------------------
-- 5. Acceptance: pure routing assertions + installed objects.
-- ---------------------------------------------------------------------------
do $acceptance$
declare
  v_trigger_count integer;
begin
  if not private.day118_role_can_receive_notification(
    'food_order.created','food_order','{"department":"restaurant"}'::jsonb,'restaurant'
  ) then
    raise exception 'Migration 118 acceptance failed: Restaurant must receive food orders.';
  end if;

  if private.day118_role_can_receive_notification(
    'service_request.created','service_request','{"department":"housekeeping"}'::jsonb,'restaurant'
  ) then
    raise exception 'Migration 118 acceptance failed: Restaurant must NOT receive housekeeping requests.';
  end if;

  if not private.day118_role_can_receive_notification(
    'service_request.created','service_request','{"department":"housekeeping"}'::jsonb,'housekeeping'
  ) then
    raise exception 'Migration 118 acceptance failed: Housekeeping must receive housekeeping requests.';
  end if;

  if not private.day118_role_can_receive_notification(
    'service_request.created','service_request','{"department":"housekeeping"}'::jsonb,'owner'
  ) then
    raise exception 'Migration 118 acceptance failed: Owner/global observer must receive hotel operations.';
  end if;

  if private.day118_role_can_receive_notification(
    'reservation.created','reservation','{}'::jsonb,'restaurant'
  ) then
    raise exception 'Migration 118 acceptance failed: Restaurant must not receive unrelated reservation events.';
  end if;

  select count(*)
  into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal
    and n.nspname = 'public'
    and c.relname = 'food_orders'
    and t.tgname = 'day118_food_order_notification_event'
    and t.tgenabled = 'O';

  if v_trigger_count <> 1 then
    raise exception 'Migration 118 acceptance failed: food-order notification trigger missing/disabled.';
  end if;

  if (
    select count(*)
    from public.notification_event_catalog
    where event_key in ('food_order.created','food_order.cancelled')
      and source_type = 'food_order'
      and is_active
  ) <> 2 then
    raise exception 'Migration 118 acceptance failed: food event catalogue incomplete.';
  end if;

  if (
    select count(*)
    from public.notification_templates
    where hotel_id is null
      and event_key in ('food_order.created','food_order.cancelled')
      and channel = 'in_app'
      and locale = 'en'
      and status = 'published'
  ) <> 2 then
    raise exception 'Migration 118 acceptance failed: food notification templates incomplete.';
  end if;
end;
$acceptance$;

commit;

select jsonb_build_object(
  'status', 'NOTIFICATION_ROLE_PUSH_ROUTING_REV1_PASSED',
  'restaurant_food_allowed',
    private.day118_role_can_receive_notification(
      'food_order.created','food_order','{"department":"restaurant"}'::jsonb,'restaurant'
    ),
  'restaurant_housekeeping_blocked',
    not private.day118_role_can_receive_notification(
      'service_request.created','service_request','{"department":"housekeeping"}'::jsonb,'restaurant'
    ),
  'housekeeping_housekeeping_allowed',
    private.day118_role_can_receive_notification(
      'service_request.created','service_request','{"department":"housekeeping"}'::jsonb,'housekeeping'
    ),
  'owner_global_observer_preserved',
    private.day118_role_can_receive_notification(
      'service_request.created','service_request','{"department":"housekeeping"}'::jsonb,'owner'
    ),
  'food_trigger_enabled',
    exists (
      select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal
        and n.nspname = 'public'
        and c.relname = 'food_orders'
        and t.tgname = 'day118_food_order_notification_event'
        and t.tgenabled = 'O'
    )
) as final_acceptance;
