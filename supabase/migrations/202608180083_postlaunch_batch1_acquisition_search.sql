-- StayQR post-launch Batch 1: market-ready acquisition and global search.
-- Additive only. The locked v1.0 / Day 20 release migrations remain unchanged.

begin;

create table if not exists public.self_service_acquisition_intents (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,
  hotel_id uuid references public.hotels(id) on delete restrict,
  subscription_id uuid references public.hotel_subscriptions(id) on delete set null,
  acquisition_mode text not null default 'paid',
  billing_cycle text not null default 'monthly',
  status text not null default 'creating',
  provider text not null default 'cashfree',
  provider_link_id text,
  reference_id text not null,
  provider_url text,
  provider_payment_id text,
  amount_minor bigint not null default 0,
  currency_code text not null default 'INR',
  hotel_name text not null,
  owner_name text not null,
  contact_email text not null,
  customer_phone text not null,
  expires_at timestamptz,
  paid_at timestamptz,
  completed_at timestamptz,
  failure_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint self_service_acquisition_mode_check
    check (acquisition_mode in ('paid', 'trial')),
  constraint self_service_acquisition_cycle_check
    check (billing_cycle in ('monthly', 'annual')),
  constraint self_service_acquisition_status_check
    check (status in (
      'creating', 'issued', 'partially_paid', 'paid', 'provisioning',
      'completed', 'expired', 'cancelled', 'failed'
    )),
  constraint self_service_acquisition_amount_check check (amount_minor >= 0),
  constraint self_service_acquisition_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint self_service_acquisition_names_check
    check (
      length(trim(hotel_name)) between 2 and 160
      and length(trim(owner_name)) between 2 and 120
    ),
  constraint self_service_acquisition_email_check
    check (contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  constraint self_service_acquisition_phone_check
    check (customer_phone ~ '^[0-9]{10}$'),
  constraint self_service_acquisition_reference_check
    check (length(trim(reference_id)) between 8 and 120),
  constraint self_service_acquisition_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists uq_self_service_acquisition_provider_link
  on public.self_service_acquisition_intents(provider, provider_link_id)
  where provider_link_id is not null;

create unique index if not exists uq_self_service_acquisition_reference
  on public.self_service_acquisition_intents(provider, reference_id);

create index if not exists idx_self_service_acquisition_owner_recent
  on public.self_service_acquisition_intents(owner_user_id, created_at desc);

create index if not exists idx_self_service_acquisition_status
  on public.self_service_acquisition_intents(status, updated_at desc);

alter table public.self_service_acquisition_intents enable row level security;

drop policy if exists stayqr_self_service_acquisition_select
  on public.self_service_acquisition_intents;
create policy stayqr_self_service_acquisition_select
  on public.self_service_acquisition_intents
  for select
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    or private.is_platform_admin()
  );

revoke all on table public.self_service_acquisition_intents from public, anon, authenticated;
grant select on table public.self_service_acquisition_intents to authenticated;
grant all on table public.self_service_acquisition_intents to service_role;

create or replace function public.get_public_subscription_plans()
returns table (
  id uuid,
  plan_code text,
  plan_name text,
  price_monthly numeric,
  price_annual numeric,
  currency_code text,
  trial_days integer,
  max_rooms integer,
  max_properties integer,
  features jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sp.id,
    sp.plan_code,
    sp.plan_name,
    sp.price_monthly,
    sp.price_annual,
    sp.currency_code,
    sp.trial_days,
    sp.max_rooms,
    sp.max_properties,
    sp.features
  from public.subscription_plans sp
  where sp.status = 'active'
    and sp.is_public = true
  order by sp.price_monthly, sp.plan_name;
$$;

revoke all on function public.get_public_subscription_plans() from public;
grant execute on function public.get_public_subscription_plans() to anon, authenticated, service_role;

create or replace function public.get_my_acquisition_intent(
  target_intent_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  intent_row public.self_service_acquisition_intents%rowtype;
  plan_row public.subscription_plans%rowtype;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  select intent.*
  into intent_row
  from public.self_service_acquisition_intents intent
  where intent.owner_user_id = actor_user_id
    and (target_intent_id is null or intent.id = target_intent_id)
  order by intent.created_at desc
  limit 1;

  if not found then
    return null;
  end if;

  select sp.* into plan_row
  from public.subscription_plans sp
  where sp.id = intent_row.plan_id;

  return jsonb_build_object(
    'id', intent_row.id,
    'status', intent_row.status,
    'acquisition_mode', intent_row.acquisition_mode,
    'billing_cycle', intent_row.billing_cycle,
    'amount_minor', intent_row.amount_minor,
    'currency_code', intent_row.currency_code,
    'hotel_name', intent_row.hotel_name,
    'hotel_id', intent_row.hotel_id,
    'subscription_id', intent_row.subscription_id,
    'provider', intent_row.provider,
    'provider_url', intent_row.provider_url,
    'expires_at', intent_row.expires_at,
    'paid_at', intent_row.paid_at,
    'completed_at', intent_row.completed_at,
    'failure_reason', intent_row.failure_reason,
    'created_at', intent_row.created_at,
    'updated_at', intent_row.updated_at,
    'plan', jsonb_build_object(
      'id', plan_row.id,
      'plan_code', plan_row.plan_code,
      'plan_name', plan_row.plan_name,
      'trial_days', plan_row.trial_days,
      'max_rooms', plan_row.max_rooms
    )
  );
end;
$$;

revoke all on function public.get_my_acquisition_intent(uuid) from public;
grant execute on function public.get_my_acquisition_intent(uuid) to authenticated, service_role;

create or replace function public.start_self_service_trial(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_email text;
  request_id_value uuid;
  plan_id_value uuid;
  plan_row public.subscription_plans%rowtype;
  hotel_name_value text;
  owner_name_value text;
  phone_value text;
  bootstrap_result jsonb;
  hotel_id_value uuid;
  subscription_id_value uuid;
  intent_owner_id uuid;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Trial payload must be a JSON object.';
  end if;

  begin
    request_id_value := nullif(trim(payload ->> 'request_id'), '')::uuid;
    plan_id_value := nullif(trim(payload ->> 'plan_id'), '')::uuid;
  exception when invalid_text_representation then
    raise exception 'request_id and plan_id must be valid UUID values.';
  end;

  if request_id_value is null or plan_id_value is null then
    raise exception 'request_id and plan_id are required.';
  end if;

  select lower(au.email) into actor_email
  from auth.users au
  where au.id = actor_user_id;

  select sp.* into plan_row
  from public.subscription_plans sp
  where sp.id = plan_id_value
    and sp.status = 'active'
    and sp.is_public = true
    and sp.trial_days > 0;

  if not found then
    raise exception 'The selected public trial plan is unavailable.';
  end if;

  hotel_name_value := nullif(trim(payload ->> 'hotel_name'), '');
  owner_name_value := nullif(trim(payload ->> 'owner_name'), '');
  phone_value := regexp_replace(coalesce(payload ->> 'phone', ''), '\D', '', 'g');
  if length(phone_value) = 12 and left(phone_value, 2) = '91' then
    phone_value := right(phone_value, 10);
  end if;

  if hotel_name_value is null or length(hotel_name_value) < 2 or length(hotel_name_value) > 160 then
    raise exception 'Hotel name must contain between 2 and 160 characters.';
  end if;
  if owner_name_value is null or length(owner_name_value) < 2 or length(owner_name_value) > 120 then
    raise exception 'Owner name must contain between 2 and 120 characters.';
  end if;
  if phone_value !~ '^[0-9]{10}$' then
    raise exception 'A valid 10-digit Indian mobile number is required.';
  end if;

  insert into public.self_service_acquisition_intents (
    id, owner_user_id, plan_id, acquisition_mode, billing_cycle,
    status, provider, reference_id, amount_minor, currency_code,
    hotel_name, owner_name, contact_email, customer_phone, metadata
  ) values (
    request_id_value, actor_user_id, plan_row.id, 'trial',
    case when payload ->> 'billing_cycle' = 'annual' then 'annual' else 'monthly' end,
    'provisioning', 'none', 'stayqr_trial_' || replace(request_id_value::text, '-', ''),
    0, plan_row.currency_code, hotel_name_value, owner_name_value,
    actor_email, phone_value,
    jsonb_build_object('source', 'public-self-service-trial')
  )
  on conflict (id) do nothing;

  select intent.owner_user_id into intent_owner_id
  from public.self_service_acquisition_intents intent
  where intent.id = request_id_value;

  if intent_owner_id is distinct from actor_user_id then
    raise exception 'The trial request belongs to another account.';
  end if;

  if exists (
    select 1 from public.self_service_acquisition_intents intent
    where intent.id = request_id_value and intent.status = 'completed'
  ) then
    return public.get_my_acquisition_intent(request_id_value)
      || jsonb_build_object('idempotent', true);
  end if;

  bootstrap_result := public.bootstrap_hotel_onboarding(
    payload
    || jsonb_build_object(
      'request_id', request_id_value,
      'plan_id', plan_row.id,
      'trial_days', least(plan_row.trial_days, 30),
      'hotel_name', hotel_name_value,
      'owner_name', owner_name_value,
      'contact_email', actor_email,
      'phone', phone_value
    )
  );

  hotel_id_value := (bootstrap_result ->> 'hotel_id')::uuid;

  select hs.id into subscription_id_value
  from public.hotel_subscriptions hs
  where hs.hotel_id = hotel_id_value
    and hs.status in ('trial', 'trialing')
  order by hs.updated_at desc
  limit 1;

  update public.hotel_onboarding ho
  set form_state = jsonb_set(
        ho.form_state,
        '{subscription,acquisition}',
        jsonb_build_object(
          'mode', 'trial',
          'billing_cycle', case when payload ->> 'billing_cycle' = 'annual' then 'annual' else 'monthly' end,
          'intent_id', request_id_value
        ),
        true
      ),
      updated_at = now(),
      last_saved_at = now(),
      version = ho.version + 1
  where ho.hotel_id = hotel_id_value;

  update public.self_service_acquisition_intents intent
  set status = 'completed',
      hotel_id = hotel_id_value,
      subscription_id = subscription_id_value,
      completed_at = now(),
      updated_at = now(),
      failure_reason = null
  where intent.id = request_id_value;

  return public.get_my_acquisition_intent(request_id_value)
    || jsonb_build_object('idempotent', coalesce((bootstrap_result ->> 'idempotent')::boolean, false));
end;
$$;

revoke all on function public.start_self_service_trial(jsonb) from public;
grant execute on function public.start_self_service_trial(jsonb) to authenticated, service_role;

create or replace function public.finalize_self_service_acquisition(
  target_intent_id uuid,
  provider_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text := current_setting('request.jwt.claim.role', true);
  intent_row public.self_service_acquisition_intents%rowtype;
  bootstrap_result jsonb;
  activation_result jsonb;
  hotel_id_value uuid;
  subscription_id_value uuid;
  provider_payment_id_value text;
  period_start_value timestamptz;
  period_end_value timestamptz;
  previous_sub text := current_setting('request.jwt.claim.sub', true);
  previous_claims text := current_setting('request.jwt.claims', true);
begin
  if caller_role <> 'service_role' then
    raise exception 'Service-role access required.';
  end if;

  if target_intent_id is null
     or provider_payload is null
     or jsonb_typeof(provider_payload) <> 'object'
  then
    raise exception 'Acquisition intent and provider payload are required.';
  end if;

  select intent.* into intent_row
  from public.self_service_acquisition_intents intent
  where intent.id = target_intent_id
  for update;

  if not found then
    raise exception 'Self-service acquisition intent was not found.';
  end if;

  if intent_row.status = 'completed' then
    return jsonb_build_object(
      'intent_id', intent_row.id,
      'hotel_id', intent_row.hotel_id,
      'subscription_id', intent_row.subscription_id,
      'status', intent_row.status,
      'idempotent', true
    );
  end if;

  if intent_row.acquisition_mode <> 'paid'
     or intent_row.status not in ('paid', 'provisioning')
  then
    raise exception 'Only a paid acquisition intent can be finalized.';
  end if;

  provider_payment_id_value := nullif(trim(provider_payload ->> 'provider_payment_id'), '');
  period_start_value := nullif(trim(provider_payload ->> 'current_period_start'), '')::timestamptz;
  period_end_value := nullif(trim(provider_payload ->> 'current_period_end'), '')::timestamptz;

  if provider_payment_id_value is null
     or period_start_value is null
     or period_end_value is null
     or period_end_value <= period_start_value
  then
    raise exception 'Verified payment identity and a valid paid period are required.';
  end if;

  update public.self_service_acquisition_intents
  set status = 'provisioning', updated_at = now()
  where id = intent_row.id;

  perform set_config('request.jwt.claim.sub', intent_row.owner_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', intent_row.owner_user_id, 'role', 'authenticated')::text,
    true
  );

  bootstrap_result := public.bootstrap_hotel_onboarding(
    jsonb_build_object(
      'request_id', intent_row.id,
      'hotel_name', intent_row.hotel_name,
      'owner_name', intent_row.owner_name,
      'contact_email', intent_row.contact_email,
      'phone', intent_row.customer_phone,
      'plan_id', intent_row.plan_id,
      'trial_days', 1,
      'timezone', 'Asia/Kolkata',
      'currency_code', intent_row.currency_code
    )
  );

  hotel_id_value := (bootstrap_result ->> 'hotel_id')::uuid;

  perform set_config('request.jwt.claim.sub', coalesce(previous_sub, ''), true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config(
    'request.jwt.claims',
    case
      when nullif(previous_claims, '') is null then '{"role":"service_role"}'
      else previous_claims
    end,
    true
  );

  activation_result := public.activate_paid_subscription(
    hotel_id_value,
    jsonb_build_object(
      'plan_id', intent_row.plan_id,
      'billing_cycle', intent_row.billing_cycle,
      'currency_code', intent_row.currency_code,
      'amount_minor', intent_row.amount_minor,
      'provider', 'cashfree',
      'provider_status', 'PAID',
      'provider_payment_link_id', intent_row.provider_link_id,
      'current_period_start', period_start_value,
      'current_period_end', period_end_value,
      'last_payment_at', coalesce(intent_row.paid_at, period_start_value),
      'idempotency_key', 'cashfree:acquisition:' || intent_row.id::text,
      'provider_event_id', nullif(trim(provider_payload ->> 'provider_event_id'), ''),
      'provider_metadata', coalesce(provider_payload -> 'provider_metadata', '{}'::jsonb),
      'metadata', jsonb_build_object(
        'source', 'self_service_acquisition',
        'acquisition_intent_id', intent_row.id
      )
    )
  );

  subscription_id_value := (activation_result ->> 'subscription_id')::uuid;

  insert into public.subscription_payment_links (
    hotel_id, plan_id, subscription_id, provider, provider_link_id,
    reference_id, idempotency_key, status, billing_cycle, currency_code,
    amount_minor, provider_url, provider_payment_id, customer_name,
    customer_email, customer_phone, expires_at, paid_at, metadata,
    created_by, updated_by
  ) values (
    hotel_id_value, intent_row.plan_id, subscription_id_value, 'cashfree',
    intent_row.provider_link_id, intent_row.reference_id,
    'acquisition:' || intent_row.id::text, 'paid', intent_row.billing_cycle,
    intent_row.currency_code, intent_row.amount_minor, intent_row.provider_url,
    provider_payment_id_value, intent_row.owner_name, intent_row.contact_email,
    intent_row.customer_phone, intent_row.expires_at,
    coalesce(intent_row.paid_at, period_start_value),
    jsonb_build_object(
      'source', 'self_service_acquisition',
      'acquisition_intent_id', intent_row.id,
      'provider_event_id', nullif(trim(provider_payload ->> 'provider_event_id'), '')
    ),
    intent_row.owner_user_id, intent_row.owner_user_id
  )
  on conflict do nothing;

  update public.hotel_onboarding ho
  set form_state = jsonb_set(
        ho.form_state,
        '{subscription,acquisition}',
        jsonb_build_object(
          'mode', 'paid',
          'billing_cycle', intent_row.billing_cycle,
          'intent_id', intent_row.id,
          'paid_at', coalesce(intent_row.paid_at, period_start_value)
        ),
        true
      ),
      updated_at = now(),
      last_saved_at = now(),
      version = ho.version + 1
  where ho.hotel_id = hotel_id_value;

  update public.self_service_acquisition_intents intent
  set status = 'completed',
      hotel_id = hotel_id_value,
      subscription_id = subscription_id_value,
      provider_payment_id = provider_payment_id_value,
      completed_at = now(),
      updated_at = now(),
      failure_reason = null
  where intent.id = intent_row.id;

  return jsonb_build_object(
    'intent_id', intent_row.id,
    'hotel_id', hotel_id_value,
    'subscription_id', subscription_id_value,
    'status', 'completed',
    'idempotent', false
  );
end;
$$;

revoke all on function public.finalize_self_service_acquisition(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.finalize_self_service_acquisition(uuid, jsonb) to service_role;

-- Repair a pre-existing Day 10 browser-write regression discovered by the
-- inherited security gate. KYC metadata deletion remains tenant-authorized,
-- server-owned and activity-audited; the locked Day 10 migration is untouched.
create or replace function public.soft_delete_guest_document(
  target_hotel_id uuid,
  target_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  document_before public.guest_documents%rowtype;
  guest_next_status text;
  activity_id uuid;
begin
  if actor_id is null then
    raise exception 'Authentication is required.';
  end if;

  if target_hotel_id is null
     or target_document_id is null
     or not private.user_has_permission(target_hotel_id, 'guests.manage')
  then
    raise exception 'Only authorized guest managers can delete KYC documents.';
  end if;

  select gd.* into document_before
  from public.guest_documents gd
  where gd.hotel_id = target_hotel_id
    and gd.id = target_document_id
    and gd.deleted_at is null
  for update;

  if not found then
    raise exception 'Guest document was not found.';
  end if;

  update public.guest_documents gd
  set deleted_at = now(),
      updated_at = now(),
      metadata = coalesce(gd.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'soft_deleted_by', actor_id,
          'soft_deleted_at', now()
        )
  where gd.hotel_id = target_hotel_id
    and gd.id = target_document_id;

  guest_next_status := case
    when exists (
      select 1 from public.guest_documents gd
      where gd.hotel_id = target_hotel_id
        and gd.guest_id = document_before.guest_id
        and gd.deleted_at is null
        and gd.verification_status = 'verified'
    ) then 'verified'
    when exists (
      select 1 from public.guest_documents gd
      where gd.hotel_id = target_hotel_id
        and gd.guest_id = document_before.guest_id
        and gd.deleted_at is null
        and gd.verification_status = 'pending'
    ) then 'pending'
    when exists (
      select 1 from public.guest_documents gd
      where gd.hotel_id = target_hotel_id
        and gd.guest_id = document_before.guest_id
        and gd.deleted_at is null
        and gd.verification_status = 'rejected'
    ) then 'rejected'
    else 'unverified'
  end;

  update public.guests g
  set identity_verification_status = guest_next_status,
      updated_at = now()
  where g.hotel_id = target_hotel_id
    and g.id = document_before.guest_id;

  activity_id := private.write_activity_log(
    target_hotel_id,
    'front_office.guest_document_deleted',
    'guest_document',
    document_before.id,
    'Private guest document was soft-deleted.',
    jsonb_build_object(
      'verification_status', document_before.verification_status,
      'storage_bucket', document_before.storage_bucket,
      'storage_path', document_before.storage_path
    ),
    jsonb_build_object(
      'deleted_at', now(),
      'guest_identity_status', guest_next_status
    ),
    jsonb_build_object('guest_id', document_before.guest_id)
  );

  return jsonb_build_object(
    'ok', true,
    'activity_id', activity_id,
    'guest_id', document_before.guest_id,
    'guest_identity_status', guest_next_status,
    'storage_bucket', document_before.storage_bucket,
    'storage_path', document_before.storage_path
  );
end;
$$;

revoke all on function public.soft_delete_guest_document(uuid, uuid) from public, anon;
grant execute on function public.soft_delete_guest_document(uuid, uuid) to authenticated, service_role;

create or replace function public.search_hotel_workspace(
  target_hotel_id uuid,
  search_query text,
  result_limit integer default 30
)
returns table (
  entity_type text,
  entity_id uuid,
  title text,
  subtitle text,
  section text,
  sort_rank integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_query text := lower(trim(coalesce(search_query, '')));
  query_pattern text;
  safe_limit integer := greatest(5, least(coalesce(result_limit, 30), 50));
begin
  if target_hotel_id is null or not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  if length(normalized_query) < 2 or length(normalized_query) > 80 then
    raise exception 'Search text must contain between 2 and 80 characters.';
  end if;

  query_pattern := '%'
    || replace(replace(replace(normalized_query, '\', '\\'), '%', '\%'), '_', '\_')
    || '%';

  return query
  select results.entity_type, results.entity_id, results.title,
         results.subtitle, results.section, results.sort_rank
  from (
    select
      'room'::text,
      r.id,
      'Room ' || r.room_number,
      concat_ws(' · ', nullif(r.room_type, ''), initcap(replace(r.status, '_', ' '))),
      'rooms'::text,
      case when lower(r.room_number) = normalized_query then 0 else 10 end
    from public.rooms r
    where r.hotel_id = target_hotel_id
      and private.user_has_permission(target_hotel_id, 'rooms.view')
      and (
        lower(r.room_number) like query_pattern escape '\'
        or lower(coalesce(r.room_type, '')) like query_pattern escape '\'
        or lower(coalesce(r.status, '')) like query_pattern escape '\'
      )

    union all

    select
      'guest'::text,
      g.id,
      g.full_name,
      concat_ws(
        ' · ',
        case when nullif(g.room_number, '') is not null then 'Room ' || g.room_number end,
        case when length(coalesce(g.normalized_phone, g.phone, '')) >= 4
          then 'Phone ••••' || right(coalesce(g.normalized_phone, g.phone), 4) end
      ),
      'guests'::text,
      case when lower(g.full_name) = normalized_query then 0 else 20 end
    from public.guests g
    where g.hotel_id = target_hotel_id
      and private.user_has_permission(target_hotel_id, 'guests.view')
      and (
        lower(g.full_name) like query_pattern escape '\'
        or lower(coalesce(g.phone, '')) like query_pattern escape '\'
        or lower(coalesce(g.email, '')) like query_pattern escape '\'
        or lower(coalesce(g.room_number, '')) like query_pattern escape '\'
      )

    union all

    select
      'reservation'::text,
      reservation.id,
      reservation.reservation_number,
      concat_ws(
        ' · ',
        guest.full_name,
        initcap(replace(reservation.status, '_', ' ')),
        to_char(reservation.arrival_date, 'DD Mon') || '–' || to_char(reservation.departure_date, 'DD Mon YYYY')
      ),
      'reservations'::text,
      case when lower(reservation.reservation_number) = normalized_query then 0 else 30 end
    from public.reservations reservation
    left join public.guests guest on guest.id = reservation.primary_guest_id
    where reservation.hotel_id = target_hotel_id
      and private.user_has_permission(target_hotel_id, 'reservations.view')
      and (
        lower(reservation.reservation_number) like query_pattern escape '\'
        or lower(coalesce(reservation.source_reference, '')) like query_pattern escape '\'
        or lower(coalesce(guest.full_name, '')) like query_pattern escape '\'
      )

    union all

    select
      'service_request'::text,
      request.id,
      initcap(replace(request.request_type, '_', ' ')),
      concat_ws(
        ' · ',
        case when room.room_number is not null then 'Room ' || room.room_number end,
        initcap(replace(request.status, '_', ' ')),
        initcap(request.priority)
      ),
      'services'::text,
      40
    from public.service_requests request
    left join public.rooms room on room.id = request.room_id
    where request.hotel_id = target_hotel_id
      and private.user_has_permission(target_hotel_id, 'services.view')
      and (
        lower(request.request_type) like query_pattern escape '\'
        or lower(coalesce(request.request_details, '')) like query_pattern escape '\'
        or lower(coalesce(room.room_number, '')) like query_pattern escape '\'
      )

    union all

    select
      'invoice'::text,
      invoice.id,
      coalesce(invoice.invoice_number, 'Draft invoice'),
      concat_ws(
        ' · ',
        initcap(replace(invoice.invoice_status, '_', ' ')),
        invoice.currency_code || ' ' || to_char(invoice.total_amount, 'FM999999990.00')
      ),
      'invoices'::text,
      case when lower(coalesce(invoice.invoice_number, '')) = normalized_query then 0 else 50 end
    from public.invoices invoice
    where invoice.hotel_id = target_hotel_id
      and private.user_has_permission(target_hotel_id, 'invoices.view')
      and lower(coalesce(invoice.invoice_number, '')) like query_pattern escape '\'
  ) results(entity_type, entity_id, title, subtitle, section, sort_rank)
  order by results.sort_rank, results.title
  limit safe_limit;
end;
$$;

revoke all on function public.search_hotel_workspace(uuid, text, integer) from public;
grant execute on function public.search_hotel_workspace(uuid, text, integer) to authenticated, service_role;

commit;
