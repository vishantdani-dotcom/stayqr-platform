-- ============================================================================
-- StayQR v1.0
-- Day 8 Migration 018 — Atomic Hotel Onboarding and Trial RPC Foundation
--
-- PRIMARY OUTCOME
-- Replaces separate browser-side hotel/subscription inserts with secure,
-- transactional server workflows for:
--   - fresh authenticated owner self-onboarding;
--   - atomic hotel + owner + profile + settings + floor + invoice + trial setup;
--   - collision-safe hotel_slug generation;
--   - idempotent bootstrap requests;
--   - dedicated one-time trial activation;
--   - resumable onboarding step persistence;
--   - server-computed operational-readiness checks.
--
-- SCOPE BOUNDARY
-- This migration does not yet create room-type, bulk-room, amenities,
-- request-category or menu-default configuration RPCs. The readiness engine
-- intentionally reports those items as incomplete until the next Day 8
-- package configures them.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - Does not create a new hotel while the migration itself is running.
-- - No existing hotel, room, guest, reservation, payment or subscription row
--   is deleted.
-- - Browser roles receive EXECUTE only on the approved public RPCs.
--
-- EXPECTED RESULT
-- 18 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607270018:atomic-hotel-onboarding-rpcs')
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
begin
  if to_regclass('public.hotel_settings') is null
     or to_regclass('public.hotel_onboarding') is null
     or to_regclass('public.floors') is null
     or to_regclass('public.invoice_number_sequences') is null
  then
    raise exception
      'Migration 018 stopped: Migration 017 foundation tables are missing.';
  end if;

  if to_regprocedure('private.is_platform_admin()') is null
     or to_regprocedure('private.user_has_hotel_access(uuid)') is null
     or to_regprocedure('private.user_has_permission(uuid,text)') is null
  then
    raise exception
      'Migration 018 stopped: locked authorization helpers are missing.';
  end if;

  if to_regprocedure('private.set_updated_at()') is null then
    raise exception
      'Migration 018 stopped: private.set_updated_at() is missing.';
  end if;

  if not exists (
    select 1
    from public.subscription_plans sp
    where sp.status = 'active'
  ) then
    raise exception
      'Migration 018 stopped: no active subscription plan is available.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. BOOTSTRAP IDEMPOTENCY
-- ============================================================================

alter table public.hotel_onboarding
  add column if not exists bootstrap_request_id uuid,
  add column if not exists onboarding_source text not null default 'legacy';

alter table public.hotel_onboarding
  drop constraint if exists hotel_onboarding_source_check;

alter table public.hotel_onboarding
  add constraint hotel_onboarding_source_check
  check (
    onboarding_source in (
      'legacy',
      'self_service',
      'platform_admin',
      'assisted'
    )
  )
  not valid;

alter table public.hotel_onboarding
  validate constraint hotel_onboarding_source_check;

create unique index if not exists uq_hotel_onboarding_bootstrap_request
on public.hotel_onboarding (bootstrap_request_id)
where bootstrap_request_id is not null;

-- ============================================================================
-- 2. PRIVATE NORMALIZATION AND READINESS HELPERS
-- ============================================================================

create or replace function private.normalize_hotel_slug(raw_value text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(
      left(
        trim(
          both '-'
          from regexp_replace(
            lower(coalesce(raw_value, '')),
            '[^a-z0-9]+',
            '-',
            'g'
          )
        ),
        48
      ),
      ''
    ),
    'hotel'
  );
$$;

revoke all on function private.normalize_hotel_slug(text)
from public, anon, authenticated;

create or replace function private.onboarding_next_step(current_step text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case current_step
    when 'account' then 'hotel_details'
    when 'hotel_details' then 'policies'
    when 'policies' then 'room_types'
    when 'room_types' then 'floors_rooms'
    when 'floors_rooms' then 'amenities'
    when 'amenities' then 'request_categories'
    when 'request_categories' then 'menu'
    when 'menu' then 'invoice'
    when 'invoice' then 'subscription'
    when 'subscription' then 'review'
    when 'review' then 'complete'
    else 'complete'
  end;
$$;

revoke all on function private.onboarding_next_step(text)
from public, anon, authenticated;

create or replace function private.compute_hotel_onboarding_readiness(
  target_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $readiness$
declare
  hotel_details_ready boolean := false;
  owner_ready boolean := false;
  settings_ready boolean := false;
  room_types_ready boolean := false;
  floors_ready boolean := false;
  rooms_ready boolean := false;
  rates_ready boolean := false;
  amenities_ready boolean := false;
  request_categories_ready boolean := false;
  menu_ready boolean := false;
  invoice_ready boolean := false;
  subscription_ready boolean := false;
  qr_ready boolean := false;
  all_ready boolean := false;
  missing_items text[];
begin
  if target_hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = target_hotel_id
     )
  then
    raise exception 'Unknown hotel.';
  end if;

  select
    nullif(trim(h.hotel_name), '') is not null
    and nullif(trim(h.slug), '') is not null
    and nullif(trim(h.timezone), '') is not null
    and h.currency_code ~ '^[A-Z]{3}$'
    and exists (
      select 1
      from public.hotel_info hi
      where hi.hotel_id = h.id
    )
  into hotel_details_ready
  from public.hotels h
  where h.id = target_hotel_id;

  select exists (
    select 1
    from public.staff s
    where s.hotel_id = target_hotel_id
      and s.status = 'active'
      and s.auth_user_id is not null
      and lower(replace(trim(s.role::text), ' ', '_')) = 'owner'
  )
  into owner_ready;

  select exists (
    select 1
    from public.hotel_settings hs
    where hs.hotel_id = target_hotel_id
  )
  into settings_ready;

  select exists (
    select 1
    from public.room_types rt
    where rt.hotel_id = target_hotel_id
      and rt.is_active
  )
  into room_types_ready;

  select exists (
    select 1
    from public.floors f
    where f.hotel_id = target_hotel_id
      and f.is_active
  )
  into floors_ready;

  select
    exists (
      select 1
      from public.rooms r
      where r.hotel_id = target_hotel_id
    )
    and not exists (
      select 1
      from public.rooms r
      where r.hotel_id = target_hotel_id
        and (r.room_type_id is null or r.floor_id is null)
    )
  into rooms_ready;

  select
    room_types_ready
    and not exists (
      select 1
      from public.room_types rt
      where rt.hotel_id = target_hotel_id
        and rt.is_active
        and not exists (
          select 1
          from public.rate_plans rp
          where rp.hotel_id = rt.hotel_id
            and rp.room_type_id = rt.id
            and rp.is_active
        )
    )
  into rates_ready;

  if to_regclass('public.amenities') is not null then
    execute
      'select exists (
         select 1
         from public.amenities a
         where a.hotel_id = $1
           and a.is_active
       )'
    into amenities_ready
    using target_hotel_id;
  end if;

  if to_regclass('public.service_request_types') is not null then
    execute
      'select exists (
         select 1
         from public.service_request_types srt
         where srt.hotel_id = $1
           and srt.is_active
       )'
    into request_categories_ready
    using target_hotel_id;
  end if;

  select
    exists (
      select 1
      from public.menu_categories mc
      where mc.hotel_id = target_hotel_id
    )
    and exists (
      select 1
      from public.menu_items mi
      where mi.hotel_id = target_hotel_id
    )
  into menu_ready;

  select exists (
    select 1
    from public.invoice_number_sequences ins
    where ins.hotel_id = target_hotel_id
      and ins.sequence_year = extract(year from now())::integer
  )
  into invoice_ready;

  select exists (
    select 1
    from public.hotel_subscriptions hsub
    where hsub.hotel_id = target_hotel_id
      and hsub.status in ('trial', 'trialing', 'active', 'past_due')
      and (
        hsub.end_date is null
        or hsub.end_date > now()
        or hsub.status = 'past_due'
      )
  )
  into subscription_ready;

  qr_ready :=
    rooms_ready
    and to_regclass('public.guest_access_tokens') is not null
    and to_regprocedure('public.get_guest_access_links(uuid)') is not null
    and to_regprocedure('public.resolve_guest_portal(text,text)') is not null;

  missing_items := array_remove(array[
    case when not hotel_details_ready then 'hotel_details' end,
    case when not owner_ready then 'owner_identity' end,
    case when not settings_ready then 'hotel_settings' end,
    case when not room_types_ready then 'room_types' end,
    case when not floors_ready then 'floors' end,
    case when not rooms_ready then 'rooms' end,
    case when not rates_ready then 'rates' end,
    case when not amenities_ready then 'amenities' end,
    case when not request_categories_ready then 'request_categories' end,
    case when not menu_ready then 'menu' end,
    case when not invoice_ready then 'invoice_numbering' end,
    case when not subscription_ready then 'subscription' end,
    case when not qr_ready then 'qr_readiness' end
  ], null);

  all_ready := coalesce(cardinality(missing_items), 0) = 0;

  return jsonb_build_object(
    'ready', all_ready,
    'checklist', jsonb_build_object(
      'hotel_details', hotel_details_ready,
      'owner_identity', owner_ready,
      'settings', settings_ready,
      'room_types', room_types_ready,
      'floors', floors_ready,
      'rooms', rooms_ready,
      'rates', rates_ready,
      'amenities', amenities_ready,
      'request_categories', request_categories_ready,
      'menu', menu_ready,
      'invoice', invoice_ready,
      'subscription', subscription_ready,
      'qr_ready', qr_ready
    ),
    'missing', to_jsonb(coalesce(missing_items, '{}'::text[])),
    'generated_at', now()
  );
end;
$readiness$;

revoke all on function private.compute_hotel_onboarding_readiness(uuid)
from public, anon, authenticated;

-- ============================================================================
-- 3. READINESS RPCs
-- ============================================================================

create or replace function public.get_hotel_onboarding_readiness(
  target_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_hotel_access(target_hotel_id)
    or exists (
      select 1
      from public.hotel_onboarding ho
      where ho.hotel_id = target_hotel_id
        and ho.owner_user_id = actor_user_id
    )
  ) then
    raise exception 'Hotel access denied.';
  end if;

  return private.compute_hotel_onboarding_readiness(target_hotel_id);
end;
$$;

revoke all on function public.get_hotel_onboarding_readiness(uuid)
from public, anon, authenticated;

grant execute on function public.get_hotel_onboarding_readiness(uuid)
to authenticated;

create or replace function public.refresh_hotel_onboarding_readiness(
  target_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  readiness jsonb;
  is_ready boolean;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
    or exists (
      select 1
      from public.hotel_onboarding ho
      where ho.hotel_id = target_hotel_id
        and ho.owner_user_id = actor_user_id
    )
  ) then
    raise exception 'Hotel configuration access denied.';
  end if;

  readiness := private.compute_hotel_onboarding_readiness(target_hotel_id);
  is_ready := coalesce((readiness ->> 'ready')::boolean, false);

  update public.hotel_onboarding ho
  set
    readiness_state = readiness,
    status = case when is_ready then 'complete' else 'in_progress' end,
    current_step = case when is_ready then 'complete' else ho.current_step end,
    completed_at = case when is_ready then coalesce(ho.completed_at, now()) else null end,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id;

  if not found then
    raise exception 'Hotel onboarding state is missing.';
  end if;

  return readiness;
end;
$$;

revoke all on function public.refresh_hotel_onboarding_readiness(uuid)
from public, anon, authenticated;

grant execute on function public.refresh_hotel_onboarding_readiness(uuid)
to authenticated;

-- ============================================================================
-- 4. DEDICATED ONE-TIME TRIAL ACTIVATION
-- ============================================================================

create or replace function public.activate_hotel_trial(
  target_hotel_id uuid,
  target_plan_id uuid,
  trial_days integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  plan_row public.subscription_plans%rowtype;
  existing_row public.hotel_subscriptions%rowtype;
  created_row public.hotel_subscriptions%rowtype;
  start_at timestamptz := now();
  finish_at timestamptz;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if target_hotel_id is null or target_plan_id is null then
    raise exception 'Hotel and subscription plan are required.';
  end if;

  if trial_days is null or trial_days < 1 or trial_days > 30 then
    raise exception 'Trial duration must be between 1 and 30 days.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('stayqr:hotel-trial:' || target_hotel_id::text)
  );

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
    or exists (
      select 1
      from public.hotel_onboarding ho
      where ho.hotel_id = target_hotel_id
        and ho.owner_user_id = actor_user_id
    )
  ) then
    raise exception 'Trial activation access denied.';
  end if;

  select sp.*
  into plan_row
  from public.subscription_plans sp
  where sp.id = target_plan_id
    and sp.status = 'active'
  for share;

  if not found then
    raise exception 'The selected subscription plan is not active.';
  end if;

  select hsub.*
  into existing_row
  from public.hotel_subscriptions hsub
  where hsub.hotel_id = target_hotel_id
    and hsub.status in (
      'trial',
      'trialing',
      'active',
      'past_due',
      'suspended'
    )
  order by hsub.created_at desc
  limit 1
  for update;

  if found then
    if existing_row.status in ('trial', 'trialing')
       and existing_row.plan_id = target_plan_id
       and coalesce(existing_row.trial_ends_at, existing_row.end_date) > now()
    then
      return jsonb_build_object(
        'hotel_id', target_hotel_id,
        'subscription_id', existing_row.id,
        'plan_id', existing_row.plan_id,
        'status', existing_row.status,
        'trial_started_at', coalesce(
          existing_row.trial_started_at,
          existing_row.start_date
        ),
        'trial_ends_at', coalesce(
          existing_row.trial_ends_at,
          existing_row.end_date
        ),
        'idempotent', true
      );
    end if;

    raise exception
      'This hotel already has a current subscription with status %.',
      existing_row.status;
  end if;

  if exists (
    select 1
    from public.hotel_subscriptions history
    where history.hotel_id = target_hotel_id
      and (
        history.trial_started_at is not null
        or history.status in ('trial', 'trialing')
      )
  ) then
    raise exception 'The one-time hotel trial has already been used.';
  end if;

  finish_at := start_at + make_interval(days => trial_days);

  insert into public.hotel_subscriptions (
    hotel_id,
    plan_id,
    status,
    start_date,
    end_date,
    created_at,
    trial_started_at,
    trial_ends_at,
    activated_at,
    metadata,
    updated_at
  ) values (
    target_hotel_id,
    target_plan_id,
    'trialing',
    start_at,
    finish_at,
    start_at,
    start_at,
    finish_at,
    null,
    jsonb_build_object(
      'source', 'day8_onboarding',
      'trial_days', trial_days,
      'activated_by', actor_user_id
    ),
    start_at
  )
  returning * into created_row;

  update public.hotels h
  set
    subscription_status = 'trialing',
    updated_at = now()
  where h.id = target_hotel_id;

  update public.hotel_onboarding ho
  set
    completed_steps = array(
      select distinct completed_step
      from unnest(
        coalesce(ho.completed_steps, '{}'::text[])
        || array['subscription']::text[]
      ) completed_step
      order by completed_step
    ),
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id;

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', created_row.id,
    'plan_id', created_row.plan_id,
    'status', created_row.status,
    'trial_started_at', created_row.trial_started_at,
    'trial_ends_at', created_row.trial_ends_at,
    'idempotent', false
  );
end;
$$;

revoke all on function public.activate_hotel_trial(uuid,uuid,integer)
from public, anon, authenticated;

grant execute on function public.activate_hotel_trial(uuid,uuid,integer)
to authenticated;

-- ============================================================================
-- 5. ATOMIC FRESH-HOTEL BOOTSTRAP
-- ============================================================================

create or replace function public.bootstrap_hotel_onboarding(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $bootstrap$
declare
  actor_user_id uuid := (select auth.uid());
  actor_email text;
  actor_is_platform_admin boolean := false;

  request_id uuid;
  existing_hotel_id uuid;
  existing_slug text;

  hotel_name_value text;
  owner_name_value text;
  contact_email_value text;
  phone_value text;
  address_value text;
  city_value text;
  state_value text;
  location_value text;
  website_value text;
  gst_value text;
  timezone_value text;
  currency_value text;
  requested_slug text;
  slug_base text;
  slug_candidate text;
  slug_suffix integer := 1;

  plan_id_value uuid;
  trial_days_value integer := 14;

  default_tax_percent_value numeric(6,3) := 0;
  prices_include_tax_value boolean := false;
  checkin_time_value time := '14:00';
  checkout_time_value time := '11:00';
  cancellation_policy_value text;
  house_rules_value text;
  terms_value text;
  invoice_notes_value text;

  new_hotel_id uuid := gen_random_uuid();
  owner_staff_id uuid;
  default_floor_id uuid;
  invoice_prefix text;
  trial_result jsonb;
  readiness jsonb;
  source_value text;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Onboarding payload must be a JSON object.';
  end if;

  select lower(au.email)
  into actor_email
  from auth.users au
  where au.id = actor_user_id
    and au.email is not null;

  if actor_email is null then
    raise exception 'The authenticated account must have an email address.';
  end if;

  actor_is_platform_admin := private.is_platform_admin();

  begin
    request_id := coalesce(
      nullif(trim(payload ->> 'request_id'), '')::uuid,
      gen_random_uuid()
    );
  exception when invalid_text_representation then
    raise exception 'request_id must be a valid UUID.';
  end;

  perform pg_advisory_xact_lock(
    hashtext('stayqr:bootstrap-request:' || request_id::text)
  );

  select ho.hotel_id, h.slug
  into existing_hotel_id, existing_slug
  from public.hotel_onboarding ho
  join public.hotels h on h.id = ho.hotel_id
  where ho.bootstrap_request_id = request_id
  limit 1;

  if existing_hotel_id is not null then
    if not (
      actor_is_platform_admin
      or exists (
        select 1
        from public.hotel_onboarding ho
        where ho.hotel_id = existing_hotel_id
          and ho.owner_user_id = actor_user_id
      )
    ) then
      raise exception 'The bootstrap request belongs to another account.';
    end if;

    return jsonb_build_object(
      'hotel_id', existing_hotel_id,
      'hotel_slug', existing_slug,
      'request_id', request_id,
      'onboarding', (
        select to_jsonb(ho)
        from public.hotel_onboarding ho
        where ho.hotel_id = existing_hotel_id
      ),
      'readiness',
        private.compute_hotel_onboarding_readiness(existing_hotel_id),
      'idempotent', true
    );
  end if;

  if not actor_is_platform_admin
     and exists (
       select 1
       from public.staff s
       where s.auth_user_id = actor_user_id
         and s.status in ('active', 'invited')
     )
  then
    raise exception
      'Self-service bootstrap is limited to accounts without existing active hotel access.';
  end if;

  hotel_name_value := nullif(trim(payload ->> 'hotel_name'), '');
  owner_name_value := nullif(trim(payload ->> 'owner_name'), '');

  if hotel_name_value is null then
    raise exception 'hotel_name is required.';
  end if;

  if owner_name_value is null then
    raise exception 'owner_name is required.';
  end if;

  contact_email_value := lower(
    coalesce(
      nullif(trim(payload ->> 'contact_email'), ''),
      actor_email
    )
  );

  if contact_email_value !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'contact_email is invalid.';
  end if;

  phone_value := nullif(trim(payload ->> 'phone'), '');
  address_value := nullif(trim(payload ->> 'address'), '');
  city_value := nullif(trim(payload ->> 'city'), '');
  state_value := nullif(trim(payload ->> 'state'), '');
  location_value := coalesce(
    nullif(trim(payload ->> 'location'), ''),
    nullif(trim(concat_ws(', ', city_value, state_value)), '')
  );
  website_value := nullif(trim(payload ->> 'website'), '');
  gst_value := nullif(trim(payload ->> 'tax_registration_number'), '');
  timezone_value := coalesce(
    nullif(trim(payload ->> 'timezone'), ''),
    'Asia/Kolkata'
  );
  currency_value := upper(
    coalesce(
      nullif(trim(payload ->> 'currency_code'), ''),
      'INR'
    )
  );

  if not exists (
    select 1
    from pg_catalog.pg_timezone_names tzn
    where tzn.name = timezone_value
  ) then
    raise exception 'Unknown timezone: %.', timezone_value;
  end if;

  if currency_value !~ '^[A-Z]{3}$' then
    raise exception 'currency_code must contain exactly three letters.';
  end if;

  begin
    plan_id_value := nullif(trim(payload ->> 'plan_id'), '')::uuid;
  exception when invalid_text_representation then
    raise exception 'plan_id must be a valid UUID.';
  end;

  if plan_id_value is null then
    raise exception 'plan_id is required.';
  end if;

  if not exists (
    select 1
    from public.subscription_plans sp
    where sp.id = plan_id_value
      and sp.status = 'active'
  ) then
    raise exception 'The selected subscription plan is not active.';
  end if;

  begin
    trial_days_value := coalesce(
      nullif(trim(payload ->> 'trial_days'), '')::integer,
      14
    );
  exception when invalid_text_representation then
    raise exception 'trial_days must be an integer.';
  end;

  if trial_days_value < 1 or trial_days_value > 30 then
    raise exception 'trial_days must be between 1 and 30.';
  end if;

  begin
    default_tax_percent_value := coalesce(
      nullif(trim(payload ->> 'default_tax_percent'), '')::numeric,
      0
    );
  exception when invalid_text_representation then
    raise exception 'default_tax_percent must be numeric.';
  end;

  if default_tax_percent_value < 0
     or default_tax_percent_value > 100
  then
    raise exception 'default_tax_percent must be between 0 and 100.';
  end if;

  begin
    prices_include_tax_value := coalesce(
      nullif(trim(payload ->> 'prices_include_tax'), '')::boolean,
      false
    );
  exception when invalid_text_representation then
    raise exception 'prices_include_tax must be true or false.';
  end;

  begin
    checkin_time_value := coalesce(
      nullif(trim(payload ->> 'checkin_time'), '')::time,
      '14:00'::time
    );
    checkout_time_value := coalesce(
      nullif(trim(payload ->> 'checkout_time'), '')::time,
      '11:00'::time
    );
  exception when invalid_datetime_format then
    raise exception 'Check-in and checkout values must be valid times.';
  end;

  cancellation_policy_value :=
    nullif(trim(payload ->> 'cancellation_policy'), '');
  house_rules_value := nullif(trim(payload ->> 'house_rules'), '');
  terms_value := nullif(trim(payload ->> 'terms_and_conditions'), '');
  invoice_notes_value := nullif(trim(payload ->> 'invoice_notes'), '');

  requested_slug := nullif(trim(payload ->> 'hotel_slug'), '');
  slug_base := private.normalize_hotel_slug(
    coalesce(requested_slug, hotel_name_value)
  );

  perform pg_advisory_xact_lock(
    hashtext('stayqr:hotel-slug:' || slug_base)
  );

  loop
    slug_candidate := case
      when slug_suffix = 1 then slug_base
      else left(
        slug_base,
        greatest(1, 48 - length(slug_suffix::text) - 1)
      ) || '-' || slug_suffix::text
    end;

    exit when not exists (
      select 1
      from public.hotels h
      where lower(h.slug) = lower(slug_candidate)
    );

    slug_suffix := slug_suffix + 1;

    if slug_suffix > 9999 then
      raise exception 'A unique hotel slug could not be generated.';
    end if;
  end loop;

  source_value := case
    when actor_is_platform_admin then 'platform_admin'
    else 'self_service'
  end;

  insert into public.hotels (
    id,
    hotel_name,
    owner_name,
    email,
    phone,
    address,
    city,
    state,
    location,
    status,
    subscription_status,
    website,
    gst_number,
    slug,
    timezone,
    currency_code,
    created_at,
    updated_at
  ) values (
    new_hotel_id,
    hotel_name_value,
    owner_name_value,
    contact_email_value,
    phone_value,
    address_value,
    city_value,
    state_value,
    location_value,
    'active',
    'trialing',
    website_value,
    gst_value,
    slug_candidate,
    timezone_value,
    currency_value,
    now(),
    now()
  );

  insert into public.staff (
    hotel_id,
    full_name,
    email,
    phone,
    role,
    status,
    auth_user_id,
    created_at,
    updated_at,
    invited_at,
    accepted_at,
    disabled_at,
    created_by,
    updated_by,
    identity_reconciliation_status,
    identity_reconciliation_note,
    identity_reconciled_at
  ) values (
    new_hotel_id,
    owner_name_value,
    actor_email,
    phone_value,
    'owner',
    'active',
    actor_user_id,
    now(),
    now(),
    now(),
    now(),
    null,
    actor_user_id,
    actor_user_id,
    'linked',
    'Owner identity created atomically by Day 8 hotel onboarding.',
    now()
  )
  returning id into owner_staff_id;

  insert into public.hotel_info (
    hotel_id,
    hotel_name,
    address,
    reception_phone,
    emergency_phone,
    checkin_time,
    checkout_time,
    breakfast_time,
    wifi_name,
    wifi_password,
    hotel_rules,
    about,
    created_at,
    google_review_url,
    reward_title,
    reward_description,
    reward_enabled
  ) values (
    new_hotel_id,
    hotel_name_value,
    coalesce(address_value, location_value),
    phone_value,
    phone_value,
    to_char(checkin_time_value, 'HH12:MI AM'),
    to_char(checkout_time_value, 'HH12:MI AM'),
    null,
    null,
    null,
    house_rules_value,
    hotel_name_value ||
      ' uses StayQR for a smarter and more convenient guest experience.',
    now(),
    null,
    'Guest Reward',
    'Contact reception to learn about available guest rewards.',
    false
  );

  insert into public.hotel_settings (
    hotel_id,
    legal_name,
    tax_registration_number,
    default_tax_percent,
    prices_include_tax,
    tax_label,
    checkin_time,
    checkout_time,
    cancellation_policy,
    house_rules,
    terms_and_conditions,
    invoice_notes,
    locale,
    date_format,
    created_by,
    updated_by,
    created_at,
    updated_at
  ) values (
    new_hotel_id,
    hotel_name_value,
    gst_value,
    default_tax_percent_value,
    prices_include_tax_value,
    'Tax',
    checkin_time_value,
    checkout_time_value,
    cancellation_policy_value,
    house_rules_value,
    terms_value,
    invoice_notes_value,
    'en-IN',
    'DD/MM/YYYY',
    actor_user_id,
    actor_user_id,
    now(),
    now()
  );

  insert into public.hotel_onboarding (
    hotel_id,
    owner_user_id,
    status,
    current_step,
    completed_steps,
    form_state,
    readiness_state,
    last_error,
    version,
    started_at,
    last_saved_at,
    completed_at,
    created_by,
    updated_by,
    created_at,
    updated_at,
    bootstrap_request_id,
    onboarding_source
  ) values (
    new_hotel_id,
    actor_user_id,
    'in_progress',
    'subscription',
    array['account', 'hotel_details', 'policies']::text[],
    jsonb_build_object(
      'account', jsonb_build_object(
        'owner_name', owner_name_value,
        'owner_email', actor_email
      ),
      'hotel_details', jsonb_build_object(
        'hotel_name', hotel_name_value,
        'hotel_slug', slug_candidate,
        'contact_email', contact_email_value,
        'phone', phone_value,
        'address', address_value,
        'city', city_value,
        'state', state_value,
        'location', location_value,
        'website', website_value,
        'timezone', timezone_value,
        'currency_code', currency_value
      ),
      'policies', jsonb_build_object(
        'default_tax_percent', default_tax_percent_value,
        'prices_include_tax', prices_include_tax_value,
        'checkin_time', checkin_time_value,
        'checkout_time', checkout_time_value
      )
    ),
    '{}'::jsonb,
    null,
    1,
    now(),
    now(),
    null,
    actor_user_id,
    actor_user_id,
    now(),
    now(),
    request_id,
    source_value
  );

  insert into public.floors (
    hotel_id,
    name,
    code,
    floor_number,
    description,
    sort_order,
    is_active,
    created_by,
    updated_by,
    created_at,
    updated_at
  ) values (
    new_hotel_id,
    'Default Floor',
    'DEFAULT',
    0,
    'Initial floor created during hotel onboarding.',
    0,
    true,
    actor_user_id,
    actor_user_id,
    now(),
    now()
  )
  returning id into default_floor_id;

  invoice_prefix :=
    coalesce(
      nullif(
        upper(
          left(
            regexp_replace(slug_candidate, '[^a-z0-9]', '', 'g'),
            4
          )
        ),
        ''
      ),
      'INV'
    ) || '-INV';

  insert into public.invoice_number_sequences (
    hotel_id,
    sequence_year,
    prefix,
    last_number,
    padding,
    reset_annually,
    updated_by,
    created_at,
    updated_at
  ) values (
    new_hotel_id,
    extract(year from now())::integer,
    invoice_prefix,
    0,
    6,
    true,
    actor_user_id,
    now(),
    now()
  );

  trial_result := public.activate_hotel_trial(
    new_hotel_id,
    plan_id_value,
    trial_days_value
  );

  update public.hotel_onboarding ho
  set
    current_step = 'room_types',
    completed_steps = array[
      'account',
      'hotel_details',
      'policies',
      'subscription'
    ]::text[],
    form_state = jsonb_set(
      ho.form_state,
      '{subscription}',
      jsonb_build_object(
        'plan_id', plan_id_value,
        'trial_days', trial_days_value,
        'trial', trial_result
      ),
      true
    ),
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = new_hotel_id;

  readiness := private.compute_hotel_onboarding_readiness(new_hotel_id);

  update public.hotel_onboarding ho
  set
    readiness_state = readiness,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = new_hotel_id;

  return jsonb_build_object(
    'hotel_id', new_hotel_id,
    'hotel_slug', slug_candidate,
    'owner_staff_id', owner_staff_id,
    'default_floor_id', default_floor_id,
    'request_id', request_id,
    'trial', trial_result,
    'onboarding', (
      select to_jsonb(ho)
      from public.hotel_onboarding ho
      where ho.hotel_id = new_hotel_id
    ),
    'readiness', readiness,
    'idempotent', false
  );
exception
  when unique_violation then
    raise exception
      'Hotel onboarding could not be completed because a unique hotel, email, slug or request value is already in use.';
end;
$bootstrap$;

revoke all on function public.bootstrap_hotel_onboarding(jsonb)
from public, anon, authenticated;

grant execute on function public.bootstrap_hotel_onboarding(jsonb)
to authenticated;

-- ============================================================================
-- 6. RESUMABLE STEP PERSISTENCE
-- ============================================================================

create or replace function public.save_hotel_onboarding_step(
  target_hotel_id uuid,
  target_step text,
  step_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  onboarding_row public.hotel_onboarding%rowtype;
  readiness jsonb;
  checklist_key text;
  step_ready boolean := false;
  complete_requested boolean := false;
  sanitized_payload jsonb;
  next_step text;
  updated_onboarding jsonb;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if target_hotel_id is null then
    raise exception 'Hotel is required.';
  end if;

  if target_step not in (
    'hotel_details',
    'policies',
    'room_types',
    'floors_rooms',
    'amenities',
    'request_categories',
    'menu',
    'invoice',
    'subscription',
    'review'
  ) then
    raise exception 'Unsupported onboarding step: %.', target_step;
  end if;

  if step_payload is null or jsonb_typeof(step_payload) <> 'object' then
    raise exception 'Step payload must be a JSON object.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
    or exists (
      select 1
      from public.hotel_onboarding ho
      where ho.hotel_id = target_hotel_id
        and ho.owner_user_id = actor_user_id
    )
  ) then
    raise exception 'Onboarding update access denied.';
  end if;

  select ho.*
  into onboarding_row
  from public.hotel_onboarding ho
  where ho.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Hotel onboarding state is missing.';
  end if;

  begin
    complete_requested := coalesce(
      (step_payload ->> 'complete')::boolean,
      false
    );
  exception when invalid_text_representation then
    raise exception 'complete must be true or false.';
  end;

  sanitized_payload := step_payload - 'complete';
  readiness := private.compute_hotel_onboarding_readiness(target_hotel_id);

  checklist_key := case target_step
    when 'hotel_details' then 'hotel_details'
    when 'policies' then 'settings'
    when 'room_types' then 'room_types'
    when 'floors_rooms' then 'rooms'
    when 'amenities' then 'amenities'
    when 'request_categories' then 'request_categories'
    when 'menu' then 'menu'
    when 'invoice' then 'invoice'
    when 'subscription' then 'subscription'
    when 'review' then 'ready'
  end;

  if target_step = 'review' then
    step_ready := coalesce((readiness ->> 'ready')::boolean, false);
  else
    step_ready := coalesce(
      (readiness -> 'checklist' ->> checklist_key)::boolean,
      false
    );
  end if;

  if complete_requested and not step_ready then
    raise exception
      'Step % cannot be completed because its server readiness check is false.',
      target_step;
  end if;

  next_step := case
    when complete_requested
      then private.onboarding_next_step(target_step)
    else onboarding_row.current_step
  end;

  update public.hotel_onboarding ho
  set
    form_state = jsonb_set(
      coalesce(ho.form_state, '{}'::jsonb),
      array[target_step],
      sanitized_payload,
      true
    ),
    completed_steps = case
      when complete_requested then array(
        select distinct completed_step
        from unnest(
          coalesce(ho.completed_steps, '{}'::text[])
          || array[target_step]::text[]
        ) completed_step
        order by completed_step
      )
      else ho.completed_steps
    end,
    current_step = case
      when complete_requested then next_step
      else ho.current_step
    end,
    readiness_state = readiness,
    status = case
      when target_step = 'review'
       and complete_requested
       and step_ready
        then 'complete'
      else 'in_progress'
    end,
    completed_at = case
      when target_step = 'review'
       and complete_requested
       and step_ready
        then coalesce(ho.completed_at, now())
      else null
    end,
    last_error = null,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id
  returning to_jsonb(ho) into updated_onboarding;

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'step', target_step,
    'step_ready', step_ready,
    'complete_requested', complete_requested,
    'next_step', next_step,
    'onboarding', updated_onboarding,
    'readiness', readiness
  );
end;
$$;

revoke all on function public.save_hotel_onboarding_step(uuid,text,jsonb)
from public, anon, authenticated;

grant execute on function public.save_hotel_onboarding_step(uuid,text,jsonb)
to authenticated;

-- ============================================================================
-- 7. REFRESH READINESS FOR EXISTING HOTELS
-- ============================================================================

update public.hotel_onboarding ho
set
  readiness_state =
    private.compute_hotel_onboarding_readiness(ho.hotel_id),
  last_saved_at = now(),
  version = ho.version + 1,
  updated_at = now();

-- Audit 043 is no longer needed after the foundation and RPC package exist.
drop function if exists
  private.run_day8_onboarding_preflight_20260727();

-- ============================================================================
-- 8. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
declare
  function_row record;
begin
  if to_regprocedure('public.bootstrap_hotel_onboarding(jsonb)') is null
     or to_regprocedure(
       'public.save_hotel_onboarding_step(uuid,text,jsonb)'
     ) is null
     or to_regprocedure(
       'public.activate_hotel_trial(uuid,uuid,integer)'
     ) is null
     or to_regprocedure(
       'public.get_hotel_onboarding_readiness(uuid)'
     ) is null
     or to_regprocedure(
       'public.refresh_hotel_onboarding_readiness(uuid)'
     ) is null
  then
    raise exception
      'Migration 018 failed: one or more public onboarding RPCs are missing.';
  end if;

  if has_function_privilege(
    'anon',
    'public.bootstrap_hotel_onboarding(jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.save_hotel_onboarding_step(uuid,text,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.activate_hotel_trial(uuid,uuid,integer)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 018 failed: anon can execute a protected onboarding RPC.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.bootstrap_hotel_onboarding(jsonb)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.save_hotel_onboarding_step(uuid,text,jsonb)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.activate_hotel_trial(uuid,uuid,integer)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 018 failed: authenticated cannot execute onboarding RPCs.';
  end if;

  for function_row in
    select p.oid::regprocedure::text as function_name,
           p.prosecdef,
           p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'bootstrap_hotel_onboarding',
        'save_hotel_onboarding_step',
        'activate_hotel_trial',
        'get_hotel_onboarding_readiness',
        'refresh_hotel_onboarding_readiness'
      )
  loop
    if not function_row.prosecdef then
      raise exception
        'Migration 018 failed: % is not SECURITY DEFINER.',
        function_row.function_name;
    end if;

    if not (
      function_row.proconfig
      @> array['search_path=""']::text[]
      or function_row.proconfig
      @> array['search_path=']::text[]
    ) then
      raise exception
        'Migration 018 failed: % does not lock search_path.',
        function_row.function_name;
    end if;
  end loop;
end;
$verify$;

commit;

-- ============================================================================
-- 9. ACCEPTANCE RESULT
-- ============================================================================

with first_hotel as (
  select h.id
  from public.hotels h
  order by h.created_at
  limit 1
),
sample_readiness as (
  select private.compute_hotel_onboarding_readiness(fh.id) as readiness
  from first_hotel fh
),
checks(test_name, passed, details) as (
  values
    (
      '01_bootstrap_request_id_column',
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'hotel_onboarding'
          and column_name = 'bootstrap_request_id'
      ),
      'hotel_onboarding stores an idempotent bootstrap request UUID.'
    ),
    (
      '02_bootstrap_request_unique_index',
      to_regclass(
        'public.uq_hotel_onboarding_bootstrap_request'
      ) is not null,
      'Duplicate onboarding bootstrap requests cannot create duplicate hotels.'
    ),
    (
      '03_slug_normalization_helper',
      private.normalize_hotel_slug('  Hotel Apex & Spa  ')
        = 'hotel-apex-spa',
      'Hotel names are converted to safe hotel_slug candidates.'
    ),
    (
      '04_atomic_bootstrap_rpc',
      to_regprocedure(
        'public.bootstrap_hotel_onboarding(jsonb)'
      ) is not null,
      'Atomic authenticated hotel bootstrap RPC exists.'
    ),
    (
      '05_resumable_step_rpc',
      to_regprocedure(
        'public.save_hotel_onboarding_step(uuid,text,jsonb)'
      ) is not null,
      'Server-validated resumable onboarding step RPC exists.'
    ),
    (
      '06_trial_activation_rpc',
      to_regprocedure(
        'public.activate_hotel_trial(uuid,uuid,integer)'
      ) is not null,
      'Dedicated one-time hotel trial activation RPC exists.'
    ),
    (
      '07_readiness_get_rpc',
      to_regprocedure(
        'public.get_hotel_onboarding_readiness(uuid)'
      ) is not null,
      'Authorized callers can retrieve the server readiness checklist.'
    ),
    (
      '08_readiness_refresh_rpc',
      to_regprocedure(
        'public.refresh_hotel_onboarding_readiness(uuid)'
      ) is not null,
      'Authorized callers can refresh persisted onboarding readiness.'
    ),
    (
      '09_readiness_checklist_shape',
      (
        select
          readiness ? 'ready'
          and readiness ? 'checklist'
          and readiness ? 'missing'
          and (readiness -> 'checklist') ? 'hotel_details'
          and (readiness -> 'checklist') ? 'rooms'
          and (readiness -> 'checklist') ? 'amenities'
          and (readiness -> 'checklist') ? 'subscription'
          and (readiness -> 'checklist') ? 'qr_ready'
        from sample_readiness
      ),
      'Readiness includes every major Day 8 operational category.'
    ),
    (
      '10_existing_readiness_persisted',
      not exists (
        select 1
        from public.hotel_onboarding ho
        where ho.readiness_state = '{}'::jsonb
           or not (ho.readiness_state ? 'checklist')
      ),
      'Every existing hotel has a server-generated readiness snapshot.'
    ),
    (
      '11_authenticated_bootstrap_execute',
      has_function_privilege(
        'authenticated',
        'public.bootstrap_hotel_onboarding(jsonb)',
        'EXECUTE'
      ),
      'Authenticated users can invoke the approved bootstrap RPC.'
    ),
    (
      '12_anon_bootstrap_blocked',
      not has_function_privilege(
        'anon',
        'public.bootstrap_hotel_onboarding(jsonb)',
        'EXECUTE'
      ),
      'Anonymous users cannot invoke hotel bootstrap.'
    ),
    (
      '13_anon_trial_blocked',
      not has_function_privilege(
        'anon',
        'public.activate_hotel_trial(uuid,uuid,integer)',
        'EXECUTE'
      ),
      'Anonymous users cannot activate subscriptions or trials.'
    ),
    (
      '14_private_readiness_not_exposed',
      not has_function_privilege(
        'authenticated',
        'private.compute_hotel_onboarding_readiness(uuid)',
        'EXECUTE'
      ),
      'Browser roles cannot bypass the authorized public readiness RPC.'
    ),
    (
      '15_preflight_helper_removed',
      to_regprocedure(
        'private.run_day8_onboarding_preflight_20260727()'
      ) is null,
      'Temporary Audit 043 helper has been removed.'
    ),
    (
      '16_current_subscriptions_remain_unique',
      not exists (
        select 1
        from (
          select hsub.hotel_id
          from public.hotel_subscriptions hsub
          where hsub.status in (
            'trial',
            'trialing',
            'active',
            'past_due'
          )
          group by hsub.hotel_id
          having count(*) > 1
        ) duplicate_current
      ),
      'No hotel has multiple current trial/active subscriptions.'
    ),
    (
      '17_no_existing_hotel_was_created',
      true,
      'Migration 018 installed RPCs only; it did not invoke hotel bootstrap.'
    ),
    (
      '18_day8_atomic_onboarding_ready',
      to_regprocedure(
        'public.bootstrap_hotel_onboarding(jsonb)'
      ) is not null
      and to_regprocedure(
        'public.save_hotel_onboarding_step(uuid,text,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.activate_hotel_trial(uuid,uuid,integer)'
      ) is not null,
      'Atomic hotel onboarding RPC foundation is ready for controlled acceptance testing.'
    )
)
select test_name, passed, details
from checks
order by test_name;
