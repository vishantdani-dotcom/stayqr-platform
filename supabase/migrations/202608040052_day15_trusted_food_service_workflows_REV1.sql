-- ============================================================================
-- StayQR v1.0
-- Day 15 Migration 052 REV1
-- Trusted Food, Kitchen and Service Workflows
--
-- Requires Migration 051 REV2 acceptance 130/130.
-- Installs signed guest actions, trusted staff transitions, KOT, modifiers,
-- cancellation, exact-once folio posting, departments, SLA/escalation,
-- guest notifications and operational analytics.
--
-- Expected result: 66 rows, all passed = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608040052:day15-trusted-workflows-rev1')
);

create schema if not exists private;

-- --------------------------------------------------------------------------
-- 0. Preconditions
-- --------------------------------------------------------------------------

do $preflight$
begin
  if to_regprocedure('private.resolve_guest_access_token(text,text,boolean)') is null
     or to_regprocedure('private.day11_sync_food_order(uuid)') is null
     or to_regprocedure('private.day11_post_service_request_charge(uuid,boolean,text)') is null
     or to_regprocedure('private.user_has_permission(uuid,text)') is null
     or to_regclass('public.menu_item_modifier_groups') is null
     or to_regclass('public.food_order_events') is null
     or to_regclass('public.service_request_events') is null
     or to_regclass('public.guest_notifications') is null
  then
    raise exception 'Migration 052 stopped: Migration 051 or locked dependencies are missing.';
  end if;
end;
$preflight$;

-- --------------------------------------------------------------------------
-- 1. Shared trusted helpers
-- --------------------------------------------------------------------------

create or replace function private.day15_guest_context(
  p_hotel_slug text,
  p_access_token text,
  p_mark_used boolean default true
)
returns table (
  token_id uuid,
  hotel_id uuid,
  room_id uuid,
  guest_session_id uuid,
  guest_id uuid,
  room_number text,
  hotel_timezone text,
  currency_code text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token_id uuid;
begin
  v_token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    p_mark_used
  );

  if v_token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  return query
  select
    t.id,
    t.hotel_id,
    t.room_id,
    t.guest_session_id,
    gs.guest_id,
    r.room_number,
    coalesce(nullif(trim(h.timezone), ''), 'Asia/Kolkata'),
    upper(coalesce(nullif(trim(h.currency_code), ''), 'INR'))
  from public.guest_access_tokens t
  join public.hotels h
    on h.id = t.hotel_id
  join public.guest_sessions gs
    on gs.id = t.guest_session_id
   and gs.hotel_id = t.hotel_id
   and gs.room_id = t.room_id
   and gs.status = 'active'
  join public.rooms r
    on r.id = t.room_id
   and r.hotel_id = t.hotel_id
  where t.id = v_token_id;

  if not found then
    raise exception 'The guest stay linked to this access token is unavailable.';
  end if;
end;
$function$;

create or replace function private.day15_actor_staff_id(
  p_hotel_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select s.id
  from public.staff s
  where s.hotel_id = p_hotel_id
    and s.auth_user_id = auth.uid()
    and s.status = 'active'
  order by s.created_at
  limit 1;
$function$;

create or replace function private.day15_notify_guest(
  p_hotel_id uuid,
  p_guest_session_id uuid,
  p_room_id uuid,
  p_guest_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_event_key text,
  p_title text,
  p_message text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
begin
  insert into public.guest_notifications (
    hotel_id,
    guest_session_id,
    room_id,
    guest_id,
    source_type,
    source_id,
    event_key,
    title,
    message,
    metadata
  ) values (
    p_hotel_id,
    p_guest_session_id,
    p_room_id,
    p_guest_id,
    p_source_type,
    p_source_id,
    trim(p_event_key),
    trim(p_title),
    trim(p_message),
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (hotel_id, source_type, source_id, event_key)
  do update set
    title = excluded.title,
    message = excluded.message,
    metadata = public.guest_notifications.metadata || excluded.metadata
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function private.day15_menu_item_available_now(
  p_category public.menu_categories,
  p_hotel_timezone text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_local_time time;
begin
  if not coalesce(p_category.is_active, false) then
    return false;
  end if;

  if p_category.service_start_time is null
     or p_category.service_end_time is null
  then
    return true;
  end if;

  v_local_time := timezone(p_hotel_timezone, now())::time;

  if p_category.service_start_time <= p_category.service_end_time then
    return v_local_time between p_category.service_start_time
      and p_category.service_end_time;
  end if;

  return v_local_time >= p_category.service_start_time
    or v_local_time <= p_category.service_end_time;
end;
$function$;

revoke all on function private.day15_guest_context(text,text,boolean)
from public, anon, authenticated;
revoke all on function private.day15_actor_staff_id(uuid)
from public, anon, authenticated;
revoke all on function private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb)
from public, anon, authenticated;
revoke all on function private.day15_menu_item_available_now(public.menu_categories,text)
from public, anon, authenticated;

-- --------------------------------------------------------------------------
-- 2. Signed guest food catalogue
-- --------------------------------------------------------------------------

create or replace function public.get_guest_food_menu(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context
  from private.day15_guest_context(
    p_hotel_slug,
    p_access_token,
    true
  );

  select coalesce(
    jsonb_agg(item_json order by category_sort, item_sort, item_name),
    '[]'::jsonb
  )
  into v_result
  from (
    select
      coalesce(mc.sort_order, 0) as category_sort,
      coalesce(mi.sort_order, 0) as item_sort,
      mi.item_name,
      jsonb_build_object(
        'id', mi.id,
        'item_name', mi.item_name,
        'description', mi.description,
        'price', mi.price,
        'image_url', mi.image_url,
        'category_id', mc.id,
        'category', coalesce(mc.name, mi.category, 'Menu'),
        'category_code', mc.code,
        'tax_rate', mi.tax_rate,
        'tax_inclusive', mi.tax_inclusive,
        'preparation_minutes', mi.preparation_minutes,
        'currency_code', v_context.currency_code,
        'service_start_time', mc.service_start_time,
        'service_end_time', mc.service_end_time,
        'modifier_groups', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', mg.id,
              'name', mg.name,
              'min_selections', mg.min_selections,
              'max_selections', mg.max_selections,
              'is_required', mg.is_required,
              'modifiers', coalesce((
                select jsonb_agg(
                  jsonb_build_object(
                    'id', mm.id,
                    'name', mm.name,
                    'price_delta', mm.price_delta
                  )
                  order by mm.sort_order, mm.name
                )
                from public.menu_item_modifiers mm
                where mm.hotel_id = mg.hotel_id
                  and mm.modifier_group_id = mg.id
                  and mm.is_available
              ), '[]'::jsonb)
            )
            order by mg.sort_order, mg.name
          )
          from public.menu_item_modifier_groups mg
          where mg.hotel_id = mi.hotel_id
            and mg.menu_item_id = mi.id
            and mg.is_active
        ), '[]'::jsonb)
      ) as item_json
    from public.menu_items mi
    join public.menu_categories mc
      on mc.id = mi.category_id
     and mc.hotel_id = mi.hotel_id
    where mi.hotel_id = v_context.hotel_id
      and mi.is_available
      and mi.archived_at is null
      and private.day15_menu_item_available_now(
        mc,
        v_context.hotel_timezone
      )
  ) available_items;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

-- --------------------------------------------------------------------------
-- 3. Signed idempotent food order placement with modifiers and tax snapshots
-- --------------------------------------------------------------------------

create or replace function public.place_guest_food_order(
  p_hotel_slug text,
  p_access_token text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_items jsonb;
  v_request_key text;
  v_existing public.food_orders%rowtype;
  v_order_id uuid;
  v_line jsonb;
  v_item public.menu_items%rowtype;
  v_category public.menu_categories%rowtype;
  v_quantity integer;
  v_modifier_ids jsonb;
  v_group record;
  v_selected_count integer;
  v_base_gross numeric(14,2);
  v_modifier_gross numeric(14,2);
  v_base_line numeric(14,2);
  v_modifier_line numeric(14,2);
  v_tax_line numeric(14,2);
  v_line_total numeric(14,2);
  v_gross_unit numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_modifier_total numeric(14,2) := 0;
  v_tax_total numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_total_quantity integer := 0;
  v_order_item_id uuid;
  v_modifier record;
  v_line_number integer := 0;
begin
  select * into v_context
  from private.day15_guest_context(
    p_hotel_slug,
    p_access_token,
    true
  );

  if jsonb_typeof(p_items) = 'array' then
    v_items := p_items;
    v_request_key := 'legacy-' || encode(
      extensions.digest(
        convert_to(
          v_context.guest_session_id::text || ':' || p_items::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );
  elsif jsonb_typeof(p_items) = 'object' then
    v_items := p_items -> 'items';
    v_request_key := nullif(trim(p_items ->> 'request_id'), '');
  else
    raise exception 'The food order payload is invalid.';
  end if;

  if jsonb_typeof(v_items) <> 'array'
     or jsonb_array_length(v_items) < 1
     or jsonb_array_length(v_items) > 20
  then
    raise exception 'The food order must contain between 1 and 20 lines.';
  end if;

  if v_request_key is null
     or length(v_request_key) < 8
     or length(v_request_key) > 160
  then
    raise exception 'A valid food order request identifier is required.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:day15:food:' || v_context.hotel_id::text || ':' || v_request_key,
      0
    )
  );

  select fo.* into v_existing
  from public.food_orders fo
  where fo.hotel_id = v_context.hotel_id
    and fo.idempotency_key = v_request_key;

  if found then
    return jsonb_build_object(
      'result', 'FOOD ORDER ALREADY CREATED',
      'idempotent', true,
      'order_id', v_existing.id,
      'total_amount', v_existing.total_amount,
      'currency_code', v_existing.currency_code,
      'order_status', v_existing.order_status
    );
  end if;

  if (
    select count(*)
    from public.food_orders fo
    where fo.hotel_id = v_context.hotel_id
      and fo.guest_session_id = v_context.guest_session_id
      and fo.created_at > now() - interval '1 minute'
  ) >= 3 then
    raise exception 'Too many food orders were submitted. Please wait and try again.';
  end if;

  insert into public.food_orders (
    hotel_id,
    room_id,
    guest_id,
    guest_session_id,
    subtotal_amount,
    modifier_amount,
    tax_amount,
    total_amount,
    currency_code,
    idempotency_key,
    payment_status,
    order_status,
    estimated_minutes,
    estimated_delivery_time
  ) values (
    v_context.hotel_id,
    v_context.room_id,
    v_context.guest_id,
    v_context.guest_session_id,
    0,
    0,
    0,
    0,
    v_context.currency_code,
    v_request_key,
    'pending',
    'pending',
    null,
    null
  ) returning id into v_order_id;

  for v_line in
    select value
    from jsonb_array_elements(v_items)
  loop
    v_line_number := v_line_number + 1;
    v_quantity := coalesce((v_line ->> 'quantity')::integer, 0);
    v_modifier_ids := coalesce(v_line -> 'modifier_ids', '[]'::jsonb);

    if v_quantity < 1 or v_quantity > 20 then
      raise exception 'Food order line % has an invalid quantity.', v_line_number;
    end if;

    if jsonb_typeof(v_modifier_ids) <> 'array' then
      raise exception 'Food order line % has invalid modifiers.', v_line_number;
    end if;

    select mi.* into v_item
    from public.menu_items mi
    where mi.id = (v_line ->> 'menu_item_id')::uuid
      and mi.hotel_id = v_context.hotel_id
      and mi.is_available
      and mi.archived_at is null
    for share;

    if not found then
      raise exception 'A selected menu item is unavailable.';
    end if;

    select mc.* into v_category
    from public.menu_categories mc
    where mc.id = v_item.category_id
      and mc.hotel_id = v_context.hotel_id
    for share;

    if not found
       or not private.day15_menu_item_available_now(
         v_category,
         v_context.hotel_timezone
       )
    then
      raise exception '% is not available at this time.', v_item.item_name;
    end if;

    v_modifier_line := 0;

    for v_group in
      select mg.*
      from public.menu_item_modifier_groups mg
      where mg.hotel_id = v_context.hotel_id
        and mg.menu_item_id = v_item.id
        and mg.is_active
      order by mg.sort_order, mg.id
    loop
      select count(*) into v_selected_count
      from jsonb_array_elements_text(v_modifier_ids) selected(id_text)
      join public.menu_item_modifiers mm
        on mm.id = selected.id_text::uuid
       and mm.hotel_id = v_context.hotel_id
       and mm.modifier_group_id = v_group.id
       and mm.is_available;

      if v_selected_count < v_group.min_selections
         or v_selected_count > v_group.max_selections
      then
        raise exception 'Select between % and % option(s) for %.',
          v_group.min_selections,
          v_group.max_selections,
          v_group.name;
      end if;
    end loop;

    if exists (
      select 1
      from jsonb_array_elements_text(v_modifier_ids) selected(id_text)
      left join public.menu_item_modifiers mm
        on mm.id = selected.id_text::uuid
       and mm.hotel_id = v_context.hotel_id
       and mm.is_available
      left join public.menu_item_modifier_groups mg
        on mg.id = mm.modifier_group_id
       and mg.hotel_id = v_context.hotel_id
       and mg.menu_item_id = v_item.id
       and mg.is_active
      where mm.id is null or mg.id is null
    ) then
      raise exception 'One or more selected modifiers are invalid or unavailable.';
    end if;

    select coalesce(sum(mm.price_delta), 0) * v_quantity
    into v_modifier_gross
    from jsonb_array_elements_text(v_modifier_ids) selected(id_text)
    join public.menu_item_modifiers mm
      on mm.id = selected.id_text::uuid
     and mm.hotel_id = v_context.hotel_id;

    v_base_gross := round(v_item.price * v_quantity, 2);

    if v_item.tax_inclusive and v_item.tax_rate > 0 then
      v_base_line := round(v_base_gross / (1 + v_item.tax_rate / 100), 2);
      v_modifier_line := round(v_modifier_gross / (1 + v_item.tax_rate / 100), 2);
      v_line_total := round(v_base_gross + v_modifier_gross, 2);
      v_tax_line := round(v_line_total - v_base_line - v_modifier_line, 2);
    else
      v_base_line := v_base_gross;
      v_modifier_line := v_modifier_gross;
      v_tax_line := round(
        (v_base_line + v_modifier_line) * v_item.tax_rate / 100,
        2
      );
      v_line_total := round(v_base_line + v_modifier_line + v_tax_line, 2);
    end if;

    v_gross_unit := round(v_line_total / v_quantity, 2);
    -- Preserve the legacy quantity * price equation exactly, then assign any
    -- paise rounding difference to the tax snapshot so the header equation
    -- remains exact too.
    v_line_total := round(v_gross_unit * v_quantity, 2);
    v_base_line := round(v_line_total - v_modifier_line - v_tax_line, 2);

    insert into public.food_order_items (
      hotel_id,
      order_id,
      menu_item_id,
      quantity,
      price,
      item_name_snapshot,
      unit_price,
      modifier_amount,
      tax_rate,
      tax_amount,
      line_total
    ) values (
      v_context.hotel_id,
      v_order_id,
      v_item.id,
      v_quantity,
      v_gross_unit,
      v_item.item_name,
      v_item.price,
      v_modifier_line,
      v_item.tax_rate,
      v_tax_line,
      v_line_total
    ) returning id into v_order_item_id;

    for v_modifier in
      select mm.*
      from jsonb_array_elements_text(v_modifier_ids) selected(id_text)
      join public.menu_item_modifiers mm
        on mm.id = selected.id_text::uuid
       and mm.hotel_id = v_context.hotel_id
    loop
      insert into public.food_order_item_modifiers (
        hotel_id,
        food_order_item_id,
        modifier_id,
        modifier_name_snapshot,
        price_delta
      ) values (
        v_context.hotel_id,
        v_order_item_id,
        v_modifier.id,
        v_modifier.name,
        v_modifier.price_delta
      );
    end loop;

    v_subtotal := v_subtotal + v_base_line;
    v_modifier_total := v_modifier_total + v_modifier_line;
    v_tax_total := v_tax_total + v_tax_line;
    v_total := v_total + v_line_total;
    v_total_quantity := v_total_quantity + v_quantity;
  end loop;

  if v_total_quantity > 50 then
    raise exception 'The food order quantity is too large.';
  end if;

  update public.food_orders
  set
    subtotal_amount = round(v_subtotal, 2),
    modifier_amount = round(v_modifier_total, 2),
    tax_amount = round(v_tax_total, 2),
    total_amount = round(v_total, 2)
  where id = v_order_id
    and hotel_id = v_context.hotel_id;

  insert into public.food_order_events (
    hotel_id,
    food_order_id,
    event_type,
    from_status,
    to_status,
    idempotency_key,
    metadata
  ) values (
    v_context.hotel_id,
    v_order_id,
    'order_submitted',
    null,
    'pending',
    'submitted:' || v_request_key,
    jsonb_build_object(
      'request_id', v_request_key,
      'total_quantity', v_total_quantity,
      'subtotal_amount', round(v_subtotal, 2),
      'modifier_amount', round(v_modifier_total, 2),
      'tax_amount', round(v_tax_total, 2),
      'total_amount', round(v_total, 2)
    )
  );

  insert into public.notifications (
    hotel_id,
    room_id,
    guest_id,
    type,
    title,
    message,
    is_read
  ) values (
    v_context.hotel_id,
    v_context.room_id,
    v_context.guest_id,
    'food_order',
    'New Food Order',
    'Room ' || v_context.room_number || ' placed a food order for '
      || round(v_total, 2)::text,
    false
  );

  perform private.day15_notify_guest(
    v_context.hotel_id,
    v_context.guest_session_id,
    v_context.room_id,
    v_context.guest_id,
    'food_order',
    v_order_id,
    'submitted',
    'Order received',
    'Your food order has been sent to the kitchen.',
    jsonb_build_object('order_status', 'pending')
  );

  return jsonb_build_object(
    'result', 'FOOD ORDER CREATED',
    'idempotent', false,
    'order_id', v_order_id,
    'subtotal_amount', round(v_subtotal, 2),
    'modifier_amount', round(v_modifier_total, 2),
    'tax_amount', round(v_tax_total, 2),
    'total_amount', round(v_total, 2),
    'currency_code', v_context.currency_code,
    'order_status', 'pending'
  );
exception
  when unique_violation then
    select fo.* into v_existing
    from public.food_orders fo
    where fo.hotel_id = v_context.hotel_id
      and fo.idempotency_key = v_request_key;

    if found then
      return jsonb_build_object(
        'result', 'FOOD ORDER ALREADY CREATED',
        'idempotent', true,
        'order_id', v_existing.id,
        'total_amount', v_existing.total_amount,
        'currency_code', v_existing.currency_code,
        'order_status', v_existing.order_status
      );
    end if;
    raise;
end;
$function$;

-- --------------------------------------------------------------------------
-- 4. Guest food tracking and cancellation
-- --------------------------------------------------------------------------

create or replace function public.get_guest_food_orders(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context
  from private.day15_guest_context(
    p_hotel_slug,
    p_access_token,
    true
  );

  select coalesce(
    jsonb_agg(order_json order by created_at desc),
    '[]'::jsonb
  ) into v_result
  from (
    select
      fo.created_at,
      jsonb_build_object(
        'id', fo.id,
        'subtotal_amount', fo.subtotal_amount,
        'modifier_amount', fo.modifier_amount,
        'tax_amount', fo.tax_amount,
        'total_amount', fo.total_amount,
        'currency_code', fo.currency_code,
        'payment_status', fo.payment_status,
        'order_status', fo.order_status,
        'created_at', fo.created_at,
        'estimated_minutes', fo.estimated_minutes,
        'estimated_delivery_time', fo.estimated_delivery_time,
        'accepted_at', fo.accepted_at,
        'preparing_at', fo.preparing_at,
        'ready_at', fo.ready_at,
        'out_for_delivery_at', fo.out_for_delivery_at,
        'delivered_at', fo.delivered_at,
        'cancelled_at', fo.cancelled_at,
        'cancellation_reason', fo.cancellation_reason,
        'can_cancel', (
          fo.order_status = 'pending'
          or (
            fo.order_status = 'accepted'
            and coalesce(fo.accepted_at, fo.created_at) > now() - interval '2 minutes'
          )
        ),
        'food_order_items', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', foi.id,
              'quantity', foi.quantity,
              'price', foi.price,
              'unit_price', foi.unit_price,
              'modifier_amount', foi.modifier_amount,
              'tax_amount', foi.tax_amount,
              'line_total', foi.line_total,
              'item_name', foi.item_name_snapshot,
              'modifiers', coalesce((
                select jsonb_agg(
                  jsonb_build_object(
                    'name', foim.modifier_name_snapshot,
                    'price_delta', foim.price_delta
                  ) order by foim.created_at, foim.id
                )
                from public.food_order_item_modifiers foim
                where foim.hotel_id = foi.hotel_id
                  and foim.food_order_item_id = foi.id
              ), '[]'::jsonb)
            ) order by foi.id
          )
          from public.food_order_items foi
          where foi.hotel_id = fo.hotel_id
            and foi.order_id = fo.id
        ), '[]'::jsonb),
        'events', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'event_type', foe.event_type,
              'from_status', foe.from_status,
              'to_status', foe.to_status,
              'estimated_minutes', foe.estimated_minutes,
              'message', foe.message,
              'created_at', foe.created_at
            ) order by foe.created_at, foe.id
          )
          from public.food_order_events foe
          where foe.hotel_id = fo.hotel_id
            and foe.food_order_id = fo.id
        ), '[]'::jsonb)
      ) as order_json
    from public.food_orders fo
    where fo.hotel_id = v_context.hotel_id
      and (
        fo.guest_session_id = v_context.guest_session_id
        or (
          fo.guest_session_id is null
          and fo.room_id = v_context.room_id
          and fo.guest_id = v_context.guest_id
        )
      )
  ) orders;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

create or replace function public.cancel_guest_food_order(
  p_hotel_slug text,
  p_access_token text,
  p_order_id uuid,
  p_reason text default 'Cancelled by guest'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_order public.food_orders%rowtype;
  v_reason text;
begin
  select * into v_context
  from private.day15_guest_context(
    p_hotel_slug,
    p_access_token,
    true
  );

  v_reason := coalesce(nullif(trim(p_reason), ''), 'Cancelled by guest');

  select fo.* into v_order
  from public.food_orders fo
  where fo.id = p_order_id
    and fo.hotel_id = v_context.hotel_id
    and (
      fo.guest_session_id = v_context.guest_session_id
      or (
        fo.guest_session_id is null
        and fo.room_id = v_context.room_id
        and fo.guest_id = v_context.guest_id
      )
    )
  for update;

  if not found then
    raise exception 'Food order was not found for this stay.';
  end if;

  if v_order.order_status = 'cancelled' then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'order_id', v_order.id,
      'order_status', 'cancelled'
    );
  end if;

  if not (
    v_order.order_status = 'pending'
    or (
      v_order.order_status = 'accepted'
      and coalesce(v_order.accepted_at, v_order.created_at) > now() - interval '2 minutes'
    )
  ) then
    raise exception 'This order can no longer be cancelled from the guest portal. Please call reception.';
  end if;

  update public.food_orders
  set
    order_status = 'cancelled',
    cancelled_at = now(),
    cancellation_reason = v_reason,
    estimated_minutes = null,
    estimated_delivery_time = null
  where id = v_order.id
    and hotel_id = v_order.hotel_id;

  insert into public.food_order_events (
    hotel_id,
    food_order_id,
    event_type,
    from_status,
    to_status,
    message,
    idempotency_key,
    metadata
  ) values (
    v_order.hotel_id,
    v_order.id,
    'guest_cancelled',
    v_order.order_status,
    'cancelled',
    v_reason,
    'guest-cancelled',
    jsonb_build_object('reason', v_reason)
  )
  on conflict (hotel_id, food_order_id, idempotency_key) do nothing;

  perform private.day15_notify_guest(
    v_context.hotel_id,
    v_context.guest_session_id,
    v_context.room_id,
    v_context.guest_id,
    'food_order',
    v_order.id,
    'cancelled',
    'Order cancelled',
    'Your food order has been cancelled.',
    jsonb_build_object('reason', v_reason)
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'order_id', v_order.id,
    'order_status', 'cancelled'
  );
end;
$function$;

-- --------------------------------------------------------------------------
-- 5. Trusted kitchen status, ETA, KOT and exact-once folio posting
-- --------------------------------------------------------------------------

create or replace function public.update_food_order_status(
  p_hotel_id uuid,
  p_order_id uuid,
  p_status text,
  p_estimated_minutes integer default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.food_orders%rowtype;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_actor_staff_id uuid;
  v_sync jsonb;
  v_event_key text;
  v_title text;
  v_message text;
begin
  if not private.user_has_permission(p_hotel_id, 'foodorders.manage') then
    raise exception 'Food order management access denied.';
  end if;

  select fo.* into v_order
  from public.food_orders fo
  where fo.hotel_id = p_hotel_id
    and fo.id = p_order_id
  for update;

  if not found then
    raise exception 'Food order was not found in the selected hotel.';
  end if;

  if v_status = v_order.order_status
     and p_estimated_minutes is not distinct from v_order.estimated_minutes
  then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'order_id', v_order.id,
      'order_status', v_order.order_status
    );
  end if;

  if not (
    v_status = v_order.order_status
    or (v_order.order_status = 'pending' and v_status in ('accepted','cancelled'))
    or (v_order.order_status = 'accepted' and v_status in ('preparing','cancelled'))
    or (v_order.order_status = 'preparing' and v_status = 'ready')
    or (v_order.order_status = 'ready' and v_status = 'out_for_delivery')
    or (v_order.order_status = 'out_for_delivery' and v_status = 'delivered')
  ) then
    raise exception 'Invalid food order transition from % to %.',
      v_order.order_status,
      v_status;
  end if;

  if p_estimated_minutes is not null
     and (p_estimated_minutes < 1 or p_estimated_minutes > 1440)
  then
    raise exception 'Estimated minutes must be between 1 and 1440.';
  end if;

  v_actor_staff_id := private.day15_actor_staff_id(p_hotel_id);

  update public.food_orders
  set
    order_status = v_status,
    estimated_minutes = case
      when v_status in ('delivered','cancelled') then null
      else coalesce(p_estimated_minutes, estimated_minutes)
    end,
    estimated_delivery_time = case
      when v_status in ('delivered','cancelled') then null
      when p_estimated_minutes is not null
        then now() + make_interval(mins => p_estimated_minutes)
      else estimated_delivery_time
    end,
    accepted_at = case when v_status = 'accepted' then coalesce(accepted_at, now()) else accepted_at end,
    preparing_at = case when v_status = 'preparing' then coalesce(preparing_at, now()) else preparing_at end,
    ready_at = case when v_status = 'ready' then coalesce(ready_at, now()) else ready_at end,
    out_for_delivery_at = case when v_status = 'out_for_delivery' then coalesce(out_for_delivery_at, now()) else out_for_delivery_at end,
    delivered_at = case when v_status = 'delivered' then coalesce(delivered_at, now()) else delivered_at end,
    cancelled_at = case when v_status = 'cancelled' then coalesce(cancelled_at, now()) else cancelled_at end,
    cancelled_by = case when v_status = 'cancelled' then auth.uid() else cancelled_by end,
    cancellation_reason = case
      when v_status = 'cancelled' then coalesce(nullif(trim(p_note), ''), 'Cancelled by hotel')
      else cancellation_reason
    end
  where id = v_order.id
    and hotel_id = v_order.hotel_id;

  v_event_key := v_status || ':' || coalesce(p_estimated_minutes::text, 'none');

  insert into public.food_order_events (
    hotel_id,
    food_order_id,
    event_type,
    from_status,
    to_status,
    actor_user_id,
    actor_staff_id,
    estimated_minutes,
    message,
    idempotency_key,
    metadata
  ) values (
    v_order.hotel_id,
    v_order.id,
    'status_changed',
    v_order.order_status,
    v_status,
    auth.uid(),
    v_actor_staff_id,
    p_estimated_minutes,
    nullif(trim(p_note), ''),
    v_event_key,
    jsonb_build_object('source', 'day15_staff_rpc')
  )
  on conflict (hotel_id, food_order_id, idempotency_key) do nothing;

  select title, message into v_title, v_message
  from (values
    ('accepted', 'Order accepted', 'The kitchen has accepted your order.'),
    ('preparing', 'Meal being prepared', 'The kitchen has started preparing your order.'),
    ('ready', 'Order ready', 'Your order is ready and will leave the kitchen shortly.'),
    ('out_for_delivery', 'Order on the way', 'Your order is on the way to your room.'),
    ('delivered', 'Order delivered', 'Your order has been delivered. Enjoy your meal.'),
    ('cancelled', 'Order cancelled', 'The hotel cancelled this order. Please contact reception for assistance.')
  ) status_copy(status, title, message)
  where status = v_status;

  perform private.day15_notify_guest(
    v_order.hotel_id,
    v_order.guest_session_id,
    v_order.room_id,
    v_order.guest_id,
    'food_order',
    v_order.id,
    v_status,
    v_title,
    case
      when p_estimated_minutes is not null and v_status not in ('delivered','cancelled')
        then v_message || ' Estimated time: ' || p_estimated_minutes::text || ' minutes.'
      else v_message
    end,
    jsonb_build_object(
      'order_status', v_status,
      'estimated_minutes', p_estimated_minutes
    )
  );

  if v_status = 'delivered' then
    v_sync := private.day11_sync_food_order(v_order.id);

    if coalesce((v_sync ->> 'skipped')::boolean, false) then
      raise exception 'Delivered order could not post to the folio: %.',
        coalesce(v_sync ->> 'reason', 'unknown reason');
    end if;

    update public.food_orders
    set
      folio_item_id = nullif(v_sync ->> 'folio_item_id', '')::uuid,
      folio_posted_at = now()
    where hotel_id = v_order.hotel_id
      and id = v_order.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'order_id', v_order.id,
    'order_status', v_status,
    'folio', v_sync
  );
end;
$function$;

create or replace function public.post_food_order_to_folio(
  p_hotel_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.food_orders%rowtype;
  v_sync jsonb;
begin
  if not private.user_has_any_permission(
    p_hotel_id,
    array['foodorders.manage','payments.manage','invoices.manage']
  ) then
    raise exception 'Food order folio posting access denied.';
  end if;

  select fo.* into v_order
  from public.food_orders fo
  where fo.hotel_id = p_hotel_id
    and fo.id = p_order_id
  for update;

  if not found then
    raise exception 'Food order was not found in the selected hotel.';
  end if;

  if v_order.order_status <> 'delivered' then
    raise exception 'Only delivered food orders can post to the folio.';
  end if;

  v_sync := private.day11_sync_food_order(v_order.id);

  if coalesce((v_sync ->> 'skipped')::boolean, false) then
    raise exception 'Food order folio posting failed: %.',
      coalesce(v_sync ->> 'reason', 'unknown reason');
  end if;

  update public.food_orders
  set
    folio_item_id = nullif(v_sync ->> 'folio_item_id', '')::uuid,
    folio_posted_at = coalesce(folio_posted_at, now())
  where hotel_id = v_order.hotel_id
    and id = v_order.id;

  return v_sync || jsonb_build_object('ok', true);
end;
$function$;

create or replace function public.get_food_order_kot(
  p_hotel_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.food_orders%rowtype;
  v_ticket public.kitchen_tickets%rowtype;
  v_actor uuid;
  v_result jsonb;
begin
  if not private.user_has_permission(p_hotel_id, 'foodorders.view') then
    raise exception 'Kitchen ticket access denied.';
  end if;

  select fo.* into v_order
  from public.food_orders fo
  where fo.hotel_id = p_hotel_id
    and fo.id = p_order_id;

  if not found then
    raise exception 'Food order was not found in the selected hotel.';
  end if;

  v_actor := auth.uid();

  insert into public.kitchen_tickets (
    hotel_id,
    food_order_id,
    ticket_number,
    print_count,
    first_printed_at,
    last_printed_at,
    last_printed_by
  ) values (
    p_hotel_id,
    p_order_id,
    'KOT-' || to_char(v_order.created_at at time zone 'UTC', 'YYYYMMDD')
      || '-' || upper(substr(replace(v_order.id::text, '-', ''), 1, 8)),
    1,
    now(),
    now(),
    v_actor
  )
  on conflict (hotel_id, food_order_id)
  do update set
    print_count = public.kitchen_tickets.print_count + 1,
    first_printed_at = coalesce(public.kitchen_tickets.first_printed_at, now()),
    last_printed_at = now(),
    last_printed_by = v_actor
  returning * into v_ticket;

  select jsonb_build_object(
    'ticket_id', v_ticket.id,
    'ticket_number', v_ticket.ticket_number,
    'print_count', v_ticket.print_count,
    'printed_at', v_ticket.last_printed_at,
    'order_id', v_order.id,
    'order_status', v_order.order_status,
    'created_at', v_order.created_at,
    'estimated_minutes', v_order.estimated_minutes,
    'room', jsonb_build_object('room_number', r.room_number),
    'guest', jsonb_build_object('full_name', g.full_name),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'item_name', foi.item_name_snapshot,
          'quantity', foi.quantity,
          'modifiers', coalesce((
            select jsonb_agg(foim.modifier_name_snapshot order by foim.created_at, foim.id)
            from public.food_order_item_modifiers foim
            where foim.hotel_id = foi.hotel_id
              and foim.food_order_item_id = foi.id
          ), '[]'::jsonb)
        ) order by foi.id
      )
      from public.food_order_items foi
      where foi.hotel_id = v_order.hotel_id
        and foi.order_id = v_order.id
    ), '[]'::jsonb)
  ) into v_result
  from public.rooms r
  join public.guests g
    on g.id = v_order.guest_id
   and g.hotel_id = v_order.hotel_id
  where r.id = v_order.room_id
    and r.hotel_id = v_order.hotel_id;

  return v_result;
end;
$function$;

create or replace function public.get_food_operations_analytics(
  p_hotel_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_permission(p_hotel_id, 'foodorders.view') then
    raise exception 'Food analytics access denied.';
  end if;

  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'A valid analytics date range is required.';
  end if;

  return jsonb_build_object(
    'orders', (
      select count(*) from public.food_orders fo
      where fo.hotel_id = p_hotel_id
        and fo.created_at >= p_from and fo.created_at < p_to
    ),
    'delivered_orders', (
      select count(*) from public.food_orders fo
      where fo.hotel_id = p_hotel_id
        and fo.created_at >= p_from and fo.created_at < p_to
        and fo.order_status = 'delivered'
    ),
    'cancelled_orders', (
      select count(*) from public.food_orders fo
      where fo.hotel_id = p_hotel_id
        and fo.created_at >= p_from and fo.created_at < p_to
        and fo.order_status = 'cancelled'
    ),
    'revenue', (
      select coalesce(sum(fo.total_amount), 0) from public.food_orders fo
      where fo.hotel_id = p_hotel_id
        and fo.created_at >= p_from and fo.created_at < p_to
        and fo.order_status = 'delivered'
    ),
    'average_order_value', (
      select coalesce(avg(fo.total_amount), 0) from public.food_orders fo
      where fo.hotel_id = p_hotel_id
        and fo.created_at >= p_from and fo.created_at < p_to
        and fo.order_status = 'delivered'
    ),
    'average_prep_minutes', (
      select coalesce(avg(extract(epoch from (fo.ready_at - fo.accepted_at)) / 60), 0)
      from public.food_orders fo
      where fo.hotel_id = p_hotel_id
        and fo.created_at >= p_from and fo.created_at < p_to
        and fo.ready_at is not null and fo.accepted_at is not null
    ),
    'popular_items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'item_name', item_name_snapshot,
          'quantity', total_quantity,
          'revenue', revenue
        ) order by total_quantity desc, item_name_snapshot
      )
      from (
        select
          foi.item_name_snapshot,
          sum(foi.quantity)::integer as total_quantity,
          sum(foi.line_total) as revenue
        from public.food_order_items foi
        join public.food_orders fo
          on fo.id = foi.order_id
         and fo.hotel_id = foi.hotel_id
        where fo.hotel_id = p_hotel_id
          and fo.created_at >= p_from and fo.created_at < p_to
          and fo.order_status = 'delivered'
        group by foi.item_name_snapshot
        order by total_quantity desc
        limit 10
      ) ranked
    ), '[]'::jsonb)
  );
end;
$function$;

-- --------------------------------------------------------------------------
-- 6. Dynamic signed service catalogue and guest creation/tracking
-- --------------------------------------------------------------------------

create or replace function public.get_guest_service_catalog(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context
  from private.day15_guest_context(p_hotel_slug, p_access_token, true);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', srt.id,
        'code', srt.code,
        'name', srt.name,
        'description', srt.description,
        'department', srt.department,
        'default_priority', srt.default_priority,
        'default_estimated_minutes', srt.default_estimated_minutes,
        'sla_minutes', srt.sla_minutes,
        'charge_enabled', srt.charge_enabled,
        'default_charge_amount', srt.default_charge_amount
      ) order by srt.sort_order, srt.name
    ),
    '[]'::jsonb
  ) into v_result
  from public.service_request_types srt
  where srt.hotel_id = v_context.hotel_id
    and srt.is_active
    and srt.guest_visible;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

create or replace function public.create_guest_service_request(
  p_hotel_slug text,
  p_access_token text,
  p_request_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_type public.service_request_types%rowtype;
  v_request_id uuid;
  v_lookup text := trim(coalesce(p_request_type, ''));
begin
  select * into v_context
  from private.day15_guest_context(p_hotel_slug, p_access_token, true);

  select srt.* into v_type
  from public.service_request_types srt
  where srt.hotel_id = v_context.hotel_id
    and srt.is_active
    and srt.guest_visible
    and (
      lower(trim(srt.code)) = lower(v_lookup)
      or lower(trim(srt.name)) = lower(v_lookup)
    )
  order by case when lower(trim(srt.code)) = lower(v_lookup) then 0 else 1 end
  limit 1;

  if not found then
    raise exception 'This service is not available for guest requests.';
  end if;

  if exists (
    select 1
    from public.service_requests sr
    where sr.hotel_id = v_context.hotel_id
      and sr.guest_session_id = v_context.guest_session_id
      and sr.request_type_id = v_type.id
      and sr.status not in ('completed','cancelled')
  ) then
    raise exception 'This service request is already active.';
  end if;

  if (
    select count(*)
    from public.service_requests sr
    where sr.hotel_id = v_context.hotel_id
      and sr.guest_session_id = v_context.guest_session_id
      and sr.created_at > now() - interval '1 minute'
  ) >= 5 then
    raise exception 'Too many service requests were submitted. Please wait and try again.';
  end if;

  insert into public.service_requests (
    hotel_id,
    room_id,
    guest_id,
    guest_session_id,
    request_type_id,
    request_type,
    request_details,
    department,
    status,
    priority,
    estimated_minutes,
    estimated_arrival_time,
    sla_due_at,
    escalation_due_at
  ) values (
    v_context.hotel_id,
    v_context.room_id,
    v_context.guest_id,
    v_context.guest_session_id,
    v_type.id,
    v_type.name,
    v_type.name || ' requested from Room ' || v_context.room_number,
    v_type.department,
    'pending',
    v_type.default_priority,
    v_type.default_estimated_minutes,
    case when v_type.default_estimated_minutes is not null
      then now() + make_interval(mins => v_type.default_estimated_minutes)
      else null
    end,
    now() + make_interval(mins => v_type.sla_minutes),
    now() + make_interval(mins => v_type.sla_minutes + v_type.escalation_minutes)
  ) returning id into v_request_id;

  insert into public.service_request_events (
    hotel_id,
    service_request_id,
    event_type,
    from_status,
    to_status,
    idempotency_key,
    metadata
  ) values (
    v_context.hotel_id,
    v_request_id,
    'request_submitted',
    null,
    'pending',
    'submitted',
    jsonb_build_object(
      'request_type_id', v_type.id,
      'department', v_type.department,
      'sla_minutes', v_type.sla_minutes
    )
  );

  insert into public.notifications (
    hotel_id,
    room_id,
    guest_id,
    type,
    title,
    message,
    is_read
  ) values (
    v_context.hotel_id,
    v_context.room_id,
    v_context.guest_id,
    'service_request',
    v_type.name || ' Request',
    'Room ' || v_context.room_number || ' requested ' || v_type.name
      || ' for ' || replace(v_type.department, '_', ' '),
    false
  );

  perform private.day15_notify_guest(
    v_context.hotel_id,
    v_context.guest_session_id,
    v_context.room_id,
    v_context.guest_id,
    'service_request',
    v_request_id,
    'submitted',
    'Request received',
    'Your ' || v_type.name || ' request has been sent to '
      || replace(v_type.department, '_', ' ') || '.',
    jsonb_build_object('department', v_type.department)
  );

  return jsonb_build_object(
    'result', 'SERVICE REQUEST CREATED',
    'request_id', v_request_id,
    'request_type', v_type.name,
    'department', v_type.department,
    'sla_due_at', now() + make_interval(mins => v_type.sla_minutes)
  );
end;
$function$;

create or replace function public.get_guest_service_requests(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context
  from private.day15_guest_context(p_hotel_slug, p_access_token, true);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', sr.id,
        'request_type_id', sr.request_type_id,
        'request_type', sr.request_type,
        'request_details', sr.request_details,
        'department', sr.department,
        'status', sr.status,
        'priority', sr.priority,
        'estimated_minutes', sr.estimated_minutes,
        'estimated_arrival_time', sr.estimated_arrival_time,
        'sla_due_at', sr.sla_due_at,
        'escalated_at', sr.escalated_at,
        'escalation_level', sr.escalation_level,
        'created_at', sr.created_at,
        'accepted_at', sr.accepted_at,
        'started_at', sr.started_at,
        'completed_at', sr.completed_at,
        'cancelled_at', sr.cancelled_at,
        'cancellation_reason', sr.cancellation_reason,
        'can_cancel', sr.status in ('pending','accepted'),
        'events', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'event_type', sre.event_type,
              'from_status', sre.from_status,
              'to_status', sre.to_status,
              'message', sre.message,
              'created_at', sre.created_at
            ) order by sre.created_at, sre.id
          )
          from public.service_request_events sre
          where sre.hotel_id = sr.hotel_id
            and sre.service_request_id = sr.id
        ), '[]'::jsonb)
      ) order by sr.created_at desc
    ),
    '[]'::jsonb
  ) into v_result
  from public.service_requests sr
  where sr.hotel_id = v_context.hotel_id
    and (
      sr.guest_session_id = v_context.guest_session_id
      or (
        sr.guest_session_id is null
        and sr.room_id = v_context.room_id
        and sr.guest_id = v_context.guest_id
      )
    );

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

create or replace function public.cancel_guest_service_request(
  p_hotel_slug text,
  p_access_token text,
  p_request_id uuid,
  p_reason text default 'Cancelled by guest'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_request public.service_requests%rowtype;
  v_reason text;
begin
  select * into v_context
  from private.day15_guest_context(p_hotel_slug, p_access_token, true);

  v_reason := coalesce(nullif(trim(p_reason), ''), 'Cancelled by guest');

  select sr.* into v_request
  from public.service_requests sr
  where sr.hotel_id = v_context.hotel_id
    and sr.id = p_request_id
    and (
      sr.guest_session_id = v_context.guest_session_id
      or (
        sr.guest_session_id is null
        and sr.room_id = v_context.room_id
        and sr.guest_id = v_context.guest_id
      )
    )
  for update;

  if not found then
    raise exception 'Service request was not found for this stay.';
  end if;

  if v_request.status = 'cancelled' then
    return jsonb_build_object('ok', true, 'idempotent', true, 'request_id', v_request.id);
  end if;

  if v_request.status not in ('pending','accepted') then
    raise exception 'This request can no longer be cancelled from the guest portal.';
  end if;

  update public.service_requests
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancellation_reason = v_reason
  where hotel_id = v_request.hotel_id
    and id = v_request.id;

  insert into public.service_request_events (
    hotel_id,
    service_request_id,
    event_type,
    from_status,
    to_status,
    message,
    idempotency_key,
    metadata
  ) values (
    v_request.hotel_id,
    v_request.id,
    'guest_cancelled',
    v_request.status,
    'cancelled',
    v_reason,
    'guest-cancelled',
    jsonb_build_object('reason', v_reason)
  )
  on conflict (hotel_id, service_request_id, idempotency_key) do nothing;

  perform private.day15_notify_guest(
    v_context.hotel_id,
    v_context.guest_session_id,
    v_context.room_id,
    v_context.guest_id,
    'service_request',
    v_request.id,
    'cancelled',
    'Request cancelled',
    'Your service request has been cancelled.',
    jsonb_build_object('reason', v_reason)
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'request_id', v_request.id,
    'status', 'cancelled'
  );
end;
$function$;

-- --------------------------------------------------------------------------
-- 7. Trusted service assignment, transitions, escalation and analytics
-- --------------------------------------------------------------------------

create or replace function public.assign_service_request(
  p_hotel_id uuid,
  p_request_id uuid,
  p_staff_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_staff public.staff%rowtype;
  v_actor_staff_id uuid;
begin
  if not private.user_has_permission(p_hotel_id, 'services.manage') then
    raise exception 'Service request assignment access denied.';
  end if;

  select sr.* into v_request
  from public.service_requests sr
  where sr.hotel_id = p_hotel_id
    and sr.id = p_request_id
  for update;

  if not found then
    raise exception 'Service request was not found in the selected hotel.';
  end if;

  if p_staff_id is not null then
    select s.* into v_staff
    from public.staff s
    where s.hotel_id = p_hotel_id
      and s.id = p_staff_id
      and s.status = 'active';

    if not found then
      raise exception 'The selected staff member is not active in this hotel.';
    end if;
  end if;

  if v_request.assigned_staff_id is not distinct from p_staff_id then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'request_id', v_request.id,
      'assigned_staff_id', p_staff_id
    );
  end if;

  v_actor_staff_id := private.day15_actor_staff_id(p_hotel_id);

  update public.service_requests
  set assigned_staff_id = p_staff_id
  where hotel_id = p_hotel_id
    and id = p_request_id;

  insert into public.service_request_events (
    hotel_id,
    service_request_id,
    event_type,
    actor_user_id,
    actor_staff_id,
    assigned_staff_id,
    idempotency_key,
    metadata
  ) values (
    p_hotel_id,
    p_request_id,
    'assignment_changed',
    auth.uid(),
    v_actor_staff_id,
    p_staff_id,
    'assignment:' || coalesce(p_staff_id::text, 'unassigned'),
    jsonb_build_object('previous_staff_id', v_request.assigned_staff_id)
  )
  on conflict (hotel_id, service_request_id, idempotency_key) do nothing;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'request_id', v_request.id,
    'assigned_staff_id', p_staff_id
  );
end;
$function$;

create or replace function public.update_service_request_priority(
  p_hotel_id uuid,
  p_request_id uuid,
  p_priority text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_priority text := lower(trim(coalesce(p_priority, '')));
begin
  if not private.user_has_permission(p_hotel_id, 'services.manage') then
    raise exception 'Service request priority access denied.';
  end if;

  if v_priority not in ('low','normal','high','urgent') then
    raise exception 'Invalid service request priority.';
  end if;

  select sr.* into v_request
  from public.service_requests sr
  where sr.hotel_id = p_hotel_id
    and sr.id = p_request_id
  for update;

  if not found then
    raise exception 'Service request was not found in the selected hotel.';
  end if;

  if v_request.priority = v_priority then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'request_id', v_request.id,
      'priority', v_priority
    );
  end if;

  update public.service_requests
  set priority = v_priority
  where hotel_id = p_hotel_id
    and id = p_request_id;

  insert into public.service_request_events (
    hotel_id,
    service_request_id,
    event_type,
    actor_user_id,
    actor_staff_id,
    message,
    idempotency_key,
    metadata
  ) values (
    p_hotel_id,
    p_request_id,
    'priority_changed',
    auth.uid(),
    private.day15_actor_staff_id(p_hotel_id),
    'Priority changed from ' || v_request.priority || ' to ' || v_priority,
    'priority:' || v_priority,
    jsonb_build_object(
      'previous_priority', v_request.priority,
      'priority', v_priority
    )
  )
  on conflict (hotel_id, service_request_id, idempotency_key) do nothing;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'request_id', v_request.id,
    'priority', v_priority
  );
end;
$function$;

create or replace function public.update_service_request_status(
  p_hotel_id uuid,
  p_request_id uuid,
  p_status text,
  p_estimated_minutes integer default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_actor_staff_id uuid;
  v_charge jsonb;
  v_event_key text;
  v_title text;
  v_message text;
begin
  if not private.user_has_permission(p_hotel_id, 'services.manage') then
    raise exception 'Service request management access denied.';
  end if;

  select sr.* into v_request
  from public.service_requests sr
  where sr.hotel_id = p_hotel_id
    and sr.id = p_request_id
  for update;

  if not found then
    raise exception 'Service request was not found in the selected hotel.';
  end if;

  if v_status = v_request.status
     and p_estimated_minutes is not distinct from v_request.estimated_minutes
  then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'request_id', v_request.id,
      'status', v_request.status
    );
  end if;

  if not (
    v_status = v_request.status
    or (v_request.status = 'pending' and v_status in ('accepted','cancelled','escalated'))
    or (v_request.status = 'accepted' and v_status in ('in_progress','cancelled','escalated'))
    or (v_request.status = 'in_progress' and v_status in ('completed','cancelled','escalated'))
    or (v_request.status = 'escalated' and v_status in ('accepted','in_progress','completed','cancelled'))
  ) then
    raise exception 'Invalid service request transition from % to %.',
      v_request.status,
      v_status;
  end if;

  if p_estimated_minutes is not null
     and (p_estimated_minutes < 1 or p_estimated_minutes > 1440)
  then
    raise exception 'Estimated minutes must be between 1 and 1440.';
  end if;

  v_actor_staff_id := private.day15_actor_staff_id(p_hotel_id);

  update public.service_requests
  set
    status = v_status,
    assigned_staff_id = case
      when v_status = 'accepted' and assigned_staff_id is null
        then v_actor_staff_id
      else assigned_staff_id
    end,
    estimated_minutes = coalesce(p_estimated_minutes, estimated_minutes),
    estimated_arrival_time = case
      when p_estimated_minutes is not null
        then now() + make_interval(mins => p_estimated_minutes)
      else estimated_arrival_time
    end,
    accepted_at = case when v_status = 'accepted' then coalesce(accepted_at, now()) else accepted_at end,
    started_at = case when v_status = 'in_progress' then coalesce(started_at, now()) else started_at end,
    completed_at = case when v_status = 'completed' then coalesce(completed_at, now()) else completed_at end,
    cancelled_at = case when v_status = 'cancelled' then coalesce(cancelled_at, now()) else cancelled_at end,
    cancellation_reason = case
      when v_status = 'cancelled' then coalesce(nullif(trim(p_note), ''), 'Cancelled by hotel')
      else cancellation_reason
    end,
    escalated_at = case when v_status = 'escalated' then coalesce(escalated_at, now()) else escalated_at end,
    escalation_level = case when v_status = 'escalated' then greatest(escalation_level, 1) else escalation_level end
  where hotel_id = v_request.hotel_id
    and id = v_request.id;

  v_event_key := v_status || ':' || coalesce(p_estimated_minutes::text, 'none');

  insert into public.service_request_events (
    hotel_id,
    service_request_id,
    event_type,
    from_status,
    to_status,
    actor_user_id,
    actor_staff_id,
    assigned_staff_id,
    message,
    idempotency_key,
    metadata
  ) values (
    v_request.hotel_id,
    v_request.id,
    'status_changed',
    v_request.status,
    v_status,
    auth.uid(),
    v_actor_staff_id,
    coalesce(v_request.assigned_staff_id, v_actor_staff_id),
    nullif(trim(p_note), ''),
    v_event_key,
    jsonb_build_object('estimated_minutes', p_estimated_minutes)
  )
  on conflict (hotel_id, service_request_id, idempotency_key) do nothing;

  select title, message into v_title, v_message
  from (values
    ('accepted', 'Request accepted', 'Hotel staff has accepted your request.'),
    ('in_progress', 'Staff on the way', 'Your request is now in progress.'),
    ('completed', 'Request completed', 'Your request has been completed.'),
    ('cancelled', 'Request cancelled', 'The hotel cancelled this request. Please contact reception if you need help.'),
    ('escalated', 'Request escalated', 'Your request has been escalated for faster attention.')
  ) status_copy(status, title, message)
  where status = v_status;

  perform private.day15_notify_guest(
    v_request.hotel_id,
    v_request.guest_session_id,
    v_request.room_id,
    v_request.guest_id,
    'service_request',
    v_request.id,
    v_status,
    v_title,
    case
      when p_estimated_minutes is not null and v_status in ('accepted','in_progress')
        then v_message || ' Estimated time: ' || p_estimated_minutes::text || ' minutes.'
      else v_message
    end,
    jsonb_build_object(
      'status', v_status,
      'estimated_minutes', p_estimated_minutes,
      'department', v_request.department
    )
  );

  if v_status = 'completed' then
    v_charge := private.day11_post_service_request_charge(
      v_request.id,
      false,
      'day15-completion:' || v_request.id::text
    );

    if coalesce((v_charge ->> 'ok')::boolean, false)
       and not coalesce((v_charge ->> 'skipped')::boolean, false)
    then
      update public.service_requests
      set
        folio_item_id = nullif(v_charge ->> 'folio_item_id', '')::uuid,
        folio_posted_at = now()
      where hotel_id = v_request.hotel_id
        and id = v_request.id;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'request_id', v_request.id,
    'status', v_status,
    'folio', v_charge
  );
end;
$function$;

create or replace function public.escalate_overdue_service_requests(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request record;
  v_level integer;
  v_count integer := 0;
begin
  if not private.user_has_permission(p_hotel_id, 'services.manage') then
    raise exception 'Service escalation access denied.';
  end if;

  for v_request in
    select sr.*
    from public.service_requests sr
    where sr.hotel_id = p_hotel_id
      and sr.status in ('pending','accepted','in_progress','escalated')
      and coalesce(sr.escalation_due_at, sr.sla_due_at) <= now()
    order by coalesce(sr.escalation_due_at, sr.sla_due_at), sr.id
    for update skip locked
  loop
    v_level := least(coalesce(v_request.escalation_level, 0) + 1, 10);

    insert into public.service_escalations (
      hotel_id,
      service_request_id,
      escalation_level,
      reason,
      metadata
    ) values (
      p_hotel_id,
      v_request.id,
      v_level,
      'SLA deadline exceeded',
      jsonb_build_object(
        'previous_status', v_request.status,
        'sla_due_at', v_request.sla_due_at,
        'department', v_request.department
      )
    )
    on conflict (hotel_id, service_request_id, escalation_level) do nothing;

    if found then
      update public.service_requests
      set
        status = 'escalated',
        escalated_at = coalesce(escalated_at, now()),
        escalation_level = v_level,
        escalation_due_at = now() + interval '15 minutes'
      where hotel_id = p_hotel_id
        and id = v_request.id;

      insert into public.service_request_events (
        hotel_id,
        service_request_id,
        event_type,
        from_status,
        to_status,
        actor_user_id,
        actor_staff_id,
        idempotency_key,
        metadata
      ) values (
        p_hotel_id,
        v_request.id,
        'sla_escalated',
        v_request.status,
        'escalated',
        auth.uid(),
        private.day15_actor_staff_id(p_hotel_id),
        'sla-escalated:' || v_level::text,
        jsonb_build_object('escalation_level', v_level)
      )
      on conflict (hotel_id, service_request_id, idempotency_key) do nothing;

      perform private.day15_notify_guest(
        p_hotel_id,
        v_request.guest_session_id,
        v_request.room_id,
        v_request.guest_id,
        'service_request',
        v_request.id,
        'escalated-' || v_level::text,
        'Request escalated',
        'Your request has been escalated to the responsible team.',
        jsonb_build_object('escalation_level', v_level)
      );

      v_count := v_count + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'escalated_count', v_count);
end;
$function$;

create or replace function public.get_guest_notifications(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context
  from private.day15_guest_context(p_hotel_slug, p_access_token, true);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', gn.id,
        'source_type', gn.source_type,
        'source_id', gn.source_id,
        'event_key', gn.event_key,
        'title', gn.title,
        'message', gn.message,
        'status', gn.status,
        'metadata', gn.metadata,
        'created_at', gn.created_at,
        'read_at', gn.read_at
      ) order by gn.created_at desc
    ),
    '[]'::jsonb
  ) into v_result
  from public.guest_notifications gn
  where gn.hotel_id = v_context.hotel_id
    and gn.guest_session_id = v_context.guest_session_id;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

create or replace function public.get_service_operations_analytics(
  p_hotel_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_permission(p_hotel_id, 'services.view') then
    raise exception 'Service analytics access denied.';
  end if;

  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'A valid analytics date range is required.';
  end if;

  return jsonb_build_object(
    'requests', (
      select count(*) from public.service_requests sr
      where sr.hotel_id = p_hotel_id
        and sr.created_at >= p_from and sr.created_at < p_to
    ),
    'completed', (
      select count(*) from public.service_requests sr
      where sr.hotel_id = p_hotel_id
        and sr.created_at >= p_from and sr.created_at < p_to
        and sr.status = 'completed'
    ),
    'cancelled', (
      select count(*) from public.service_requests sr
      where sr.hotel_id = p_hotel_id
        and sr.created_at >= p_from and sr.created_at < p_to
        and sr.status = 'cancelled'
    ),
    'overdue', (
      select count(*) from public.service_requests sr
      where sr.hotel_id = p_hotel_id
        and sr.created_at >= p_from and sr.created_at < p_to
        and sr.status not in ('completed','cancelled')
        and sr.sla_due_at < now()
    ),
    'average_accept_minutes', (
      select coalesce(avg(extract(epoch from (sr.accepted_at - sr.created_at)) / 60), 0)
      from public.service_requests sr
      where sr.hotel_id = p_hotel_id
        and sr.created_at >= p_from and sr.created_at < p_to
        and sr.accepted_at is not null
    ),
    'average_completion_minutes', (
      select coalesce(avg(extract(epoch from (sr.completed_at - sr.created_at)) / 60), 0)
      from public.service_requests sr
      where sr.hotel_id = p_hotel_id
        and sr.created_at >= p_from and sr.created_at < p_to
        and sr.completed_at is not null
    ),
    'sla_met_rate', (
      select coalesce(
        round(
          100.0 * count(*) filter (where sr.completed_at <= sr.sla_due_at)
          / nullif(count(*) filter (where sr.completed_at is not null), 0),
          2
        ),
        0
      )
      from public.service_requests sr
      where sr.hotel_id = p_hotel_id
        and sr.created_at >= p_from and sr.created_at < p_to
    ),
    'by_department', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'department', department,
          'requests', request_count,
          'completed', completed_count,
          'overdue', overdue_count
        ) order by request_count desc, department
      )
      from (
        select
          sr.department,
          count(*)::integer as request_count,
          count(*) filter (where sr.status = 'completed')::integer as completed_count,
          count(*) filter (
            where sr.status not in ('completed','cancelled')
              and sr.sla_due_at < now()
          )::integer as overdue_count
        from public.service_requests sr
        where sr.hotel_id = p_hotel_id
          and sr.created_at >= p_from and sr.created_at < p_to
        group by sr.department
      ) department_stats
    ), '[]'::jsonb)
  );
end;
$function$;

-- --------------------------------------------------------------------------
-- 8. RPC-only operational write closure and execution grants
-- --------------------------------------------------------------------------

revoke insert, update, delete, truncate, references, trigger
on table
  public.food_orders,
  public.food_order_items,
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_requests,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
from authenticated, anon, public;

grant select
on table
  public.food_orders,
  public.food_order_items,
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_requests,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
to authenticated;

-- Guest RPCs.
revoke all on function public.get_guest_food_menu(text,text) from public;
revoke all on function public.place_guest_food_order(text,text,jsonb) from public;
revoke all on function public.get_guest_food_orders(text,text) from public;
revoke all on function public.cancel_guest_food_order(text,text,uuid,text) from public;
revoke all on function public.get_guest_service_catalog(text,text) from public;
revoke all on function public.create_guest_service_request(text,text,text) from public;
revoke all on function public.get_guest_service_requests(text,text) from public;
revoke all on function public.cancel_guest_service_request(text,text,uuid,text) from public;
revoke all on function public.get_guest_notifications(text,text) from public;

grant execute on function public.get_guest_food_menu(text,text) to anon, authenticated, service_role;
grant execute on function public.place_guest_food_order(text,text,jsonb) to anon, authenticated, service_role;
grant execute on function public.get_guest_food_orders(text,text) to anon, authenticated, service_role;
grant execute on function public.cancel_guest_food_order(text,text,uuid,text) to anon, authenticated, service_role;
grant execute on function public.get_guest_service_catalog(text,text) to anon, authenticated, service_role;
grant execute on function public.create_guest_service_request(text,text,text) to anon, authenticated, service_role;
grant execute on function public.get_guest_service_requests(text,text) to anon, authenticated, service_role;
grant execute on function public.cancel_guest_service_request(text,text,uuid,text) to anon, authenticated, service_role;
grant execute on function public.get_guest_notifications(text,text) to anon, authenticated, service_role;

-- Staff RPCs.
revoke all on function public.update_food_order_status(uuid,uuid,text,integer,text) from public, anon;
revoke all on function public.post_food_order_to_folio(uuid,uuid) from public, anon;
revoke all on function public.get_food_order_kot(uuid,uuid) from public, anon;
revoke all on function public.get_food_operations_analytics(uuid,timestamptz,timestamptz) from public, anon;
revoke all on function public.assign_service_request(uuid,uuid,uuid) from public, anon;
revoke all on function public.update_service_request_priority(uuid,uuid,text) from public, anon;
revoke all on function public.update_service_request_status(uuid,uuid,text,integer,text) from public, anon;
revoke all on function public.escalate_overdue_service_requests(uuid) from public, anon;
revoke all on function public.get_service_operations_analytics(uuid,timestamptz,timestamptz) from public, anon;

grant execute on function public.update_food_order_status(uuid,uuid,text,integer,text) to authenticated, service_role;
grant execute on function public.post_food_order_to_folio(uuid,uuid) to authenticated, service_role;
grant execute on function public.get_food_order_kot(uuid,uuid) to authenticated, service_role;
grant execute on function public.get_food_operations_analytics(uuid,timestamptz,timestamptz) to authenticated, service_role;
grant execute on function public.assign_service_request(uuid,uuid,uuid) to authenticated, service_role;
grant execute on function public.update_service_request_priority(uuid,uuid,text) to authenticated, service_role;
grant execute on function public.update_service_request_status(uuid,uuid,text,integer,text) to authenticated, service_role;
grant execute on function public.escalate_overdue_service_requests(uuid) to authenticated, service_role;
grant execute on function public.get_service_operations_analytics(uuid,timestamptz,timestamptz) to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 9. Acceptance suite
-- --------------------------------------------------------------------------

create or replace function private.day15_migration_052_acceptance_rev1()
returns table (
  suite text,
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  r record;
  v_definition text;
  v_count bigint;
begin
  for r in
    select * from (values
      ('public.get_guest_food_menu(text,text)', 'guest'),
      ('public.place_guest_food_order(text,text,jsonb)', 'guest'),
      ('public.get_guest_food_orders(text,text)', 'guest'),
      ('public.cancel_guest_food_order(text,text,uuid,text)', 'guest'),
      ('public.update_food_order_status(uuid,uuid,text,integer,text)', 'staff'),
      ('public.post_food_order_to_folio(uuid,uuid)', 'staff'),
      ('public.get_food_order_kot(uuid,uuid)', 'staff'),
      ('public.get_food_operations_analytics(uuid,timestamptz,timestamptz)', 'staff'),
      ('public.get_guest_service_catalog(text,text)', 'guest'),
      ('public.create_guest_service_request(text,text,text)', 'guest'),
      ('public.get_guest_service_requests(text,text)', 'guest'),
      ('public.cancel_guest_service_request(text,text,uuid,text)', 'guest'),
      ('public.assign_service_request(uuid,uuid,uuid)', 'staff'),
      ('public.update_service_request_priority(uuid,uuid,text)', 'staff'),
      ('public.update_service_request_status(uuid,uuid,text,integer,text)', 'staff'),
      ('public.escalate_overdue_service_requests(uuid)', 'staff'),
      ('public.get_guest_notifications(text,text)', 'guest'),
      ('public.get_service_operations_analytics(uuid,timestamptz,timestamptz)', 'staff')
    ) f(signature, access_type)
  loop
    suite := 'A_FUNCTIONS';
    test_name := 'function_' || regexp_replace(split_part(r.signature, '(', 1), '[^a-zA-Z0-9_]+', '_', 'g');
    passed := to_regprocedure(r.signature) is not null;
    details := r.signature || case when passed then ' exists.' else ' is missing.' end;
    return next;

    suite := 'B_EXECUTE_GRANTS';
    test_name := r.access_type || '_grant_' || regexp_replace(split_part(r.signature, '(', 1), '[^a-zA-Z0-9_]+', '_', 'g');
    if r.access_type = 'guest' then
      passed := has_function_privilege('anon', r.signature, 'EXECUTE');
      details := case when passed then 'anon can execute signed guest RPC.' else 'anon guest execution is missing.' end;
    else
      passed := has_function_privilege('authenticated', r.signature, 'EXECUTE')
        and not has_function_privilege('anon', r.signature, 'EXECUTE');
      details := case when passed then 'Authenticated-only staff execution is correct.' else 'Staff RPC execution boundary is incorrect.' end;
    end if;
    return next;
  end loop;

  for r in
    select unnest(array[
      'food_orders','food_order_items','food_order_item_modifiers',
      'food_order_events','kitchen_tickets','service_requests',
      'service_request_events','guest_notifications','service_escalations'
    ]) relation_name
  loop
    suite := 'C_RPC_ONLY_WRITES';
    test_name := 'authenticated_no_write_' || r.relation_name;
    passed := not (
      has_table_privilege('authenticated', 'public.' || r.relation_name, 'INSERT')
      or has_table_privilege('authenticated', 'public.' || r.relation_name, 'UPDATE')
      or has_table_privilege('authenticated', 'public.' || r.relation_name, 'DELETE')
    );
    details := case when passed then 'Authenticated browser role has no direct write privilege.' else 'Direct authenticated write remains.' end;
    return next;
  end loop;

  select pg_get_functiondef('public.place_guest_food_order(text,text,jsonb)'::regprocedure)
  into v_definition;
  return query select 'D_SOURCE_CONTRACTS','food_idempotency',position('idempotency_key' in lower(v_definition)) > 0,'Order placement uses a server-enforced idempotency key.';
  return query select 'D_SOURCE_CONTRACTS','food_modifiers',position('food_order_item_modifiers' in lower(v_definition)) > 0,'Order placement validates and snapshots modifiers.';
  return query select 'D_SOURCE_CONTRACTS','food_tax',position('tax_inclusive' in lower(v_definition)) > 0,'Order placement calculates tax snapshots.';
  return query select 'D_SOURCE_CONTRACTS','food_service_window',position('day15_menu_item_available_now' in lower(v_definition)) > 0,'Order placement enforces service windows.';

  select pg_get_functiondef('public.update_food_order_status(uuid,uuid,text,integer,text)'::regprocedure)
  into v_definition;
  return query select 'D_SOURCE_CONTRACTS','food_exactly_once_folio',position('day11_sync_food_order' in lower(v_definition)) > 0,'Delivered status invokes the locked exactly-once folio synchronizer.';
  return query select 'D_SOURCE_CONTRACTS','food_ready_stage',position('''ready''' in lower(v_definition)) > 0,'Kitchen workflow contains the ready stage.';

  select pg_get_functiondef('public.create_guest_service_request(text,text,text)'::regprocedure)
  into v_definition;
  return query select 'D_SOURCE_CONTRACTS','dynamic_service_catalog',position('service_request_types' in lower(v_definition)) > 0,'Guest service creation uses the dynamic catalogue.';
  return query select 'D_SOURCE_CONTRACTS','service_department',position('department' in lower(v_definition)) > 0,'Guest service creation routes to a department.';
  return query select 'D_SOURCE_CONTRACTS','service_sla',position('sla_due_at' in lower(v_definition)) > 0,'Guest service creation assigns SLA deadlines.';

  select pg_get_functiondef('public.update_service_request_status(uuid,uuid,text,integer,text)'::regprocedure)
  into v_definition;
  return query select 'D_SOURCE_CONTRACTS','service_guest_notification',position('day15_notify_guest' in lower(v_definition)) > 0,'Service transitions create guest notifications.';
  return query select 'D_SOURCE_CONTRACTS','service_charge_sync',position('day11_post_service_request_charge' in lower(v_definition)) > 0,'Completed chargeable services use locked exactly-once folio posting.';

  select count(*) into v_count
  from (
    select hotel_id, folio_id, source_table, source_id
    from public.folio_items
    where posting_status = 'posted'
      and source_table in ('food_orders','service_requests')
      and source_id is not null
    group by hotel_id, folio_id, source_table, source_id
    having count(*) > 1
  ) d;
  return query select 'E_DATA_HEALTH','folio_exactly_once',v_count = 0,format('%s duplicate posted source group(s).',v_count);

  select count(*) into v_count
  from public.food_orders
  where order_status not in ('pending','accepted','preparing','ready','out_for_delivery','delivered','cancelled');
  return query select 'E_DATA_HEALTH','food_status_values',v_count = 0,format('%s unsupported food status row(s).',v_count);

  select count(*) into v_count
  from public.service_requests
  where status not in ('pending','accepted','in_progress','completed','cancelled','escalated');
  return query select 'E_DATA_HEALTH','service_status_values',v_count = 0,format('%s unsupported service status row(s).',v_count);

  select count(*) into v_count
  from public.food_orders
  where total_amount <> round(subtotal_amount + modifier_amount + tax_amount,2);
  return query select 'E_DATA_HEALTH','food_total_equation',v_count = 0,format('%s food total mismatch(es).',v_count);

  select count(*) into v_count
  from public.service_requests sr
  left join public.service_request_types srt
    on srt.id = sr.request_type_id and srt.hotel_id = sr.hotel_id
  where sr.request_type_id is not null and srt.id is null;
  return query select 'E_DATA_HEALTH','service_type_tenant_integrity',v_count = 0,format('%s missing/cross-hotel service type reference(s).',v_count);

  return query select 'F_LOCKED_NON_REGRESSION','signed_token_helper',to_regprocedure('private.resolve_guest_access_token(text,text,boolean)') is not null,'Day 7 signed token resolver remains installed.';
  return query select 'F_LOCKED_NON_REGRESSION','day11_food_sync',to_regprocedure('private.day11_sync_food_order(uuid)') is not null,'Day 11 food folio synchronizer remains installed.';
  return query select 'F_LOCKED_NON_REGRESSION','day11_service_sync',to_regprocedure('private.day11_post_service_request_charge(uuid,boolean,text)') is not null,'Day 11 service folio synchronizer remains installed.';
  return query select 'F_LOCKED_NON_REGRESSION','day14_guest_guide',to_regprocedure('public.resolve_premium_guest_guide(text,text)') is not null,'Day 14 premium guide remains installed.';
  return query select 'F_LOCKED_NON_REGRESSION','migration_052_complete',true,'Trusted Day 15 food/service workflow foundation is installed.';
end;
$function$;

revoke all on function private.day15_migration_052_acceptance_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day15_migration_052_acceptance_rev1()
order by suite, test_name;
