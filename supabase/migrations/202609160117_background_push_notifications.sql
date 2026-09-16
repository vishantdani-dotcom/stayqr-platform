-- StayQR background push notifications — additive post-launch enhancement.
-- Does not alter foreground notification routing, ringtone playback, QR, billing or tenant permissions.
-- The Database Webhook trigger is installed by the production closure script with a runtime-only secret; the secret is intentionally not committed.

create table if not exists public.background_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  user_id uuid not null,
  endpoint text not null,
  p256dh text not null,
  auth_secret text not null,
  expiration_time timestamptz,
  user_agent text,
  platform text,
  is_active boolean not null default true,
  failure_count integer not null default 0 check (failure_count >= 0),
  last_seen_at timestamptz not null default now(),
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint background_push_endpoint_length check (length(endpoint) between 16 and 2048),
  constraint background_push_p256dh_length check (length(p256dh) between 16 and 512),
  constraint background_push_auth_length check (length(auth_secret) between 8 and 256),
  constraint background_push_subscription_unique unique (hotel_id, user_id, endpoint)
);

create index if not exists background_push_subscriptions_user_idx
  on public.background_push_subscriptions (user_id, hotel_id, is_active);

create index if not exists background_push_subscriptions_active_idx
  on public.background_push_subscriptions (hotel_id, user_id, updated_at desc)
  where is_active;

alter table public.background_push_subscriptions enable row level security;

create table if not exists public.background_push_deliveries (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.notification_recipients(id) on delete cascade,
  subscription_id uuid not null references public.background_push_subscriptions(id) on delete cascade,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  user_id uuid not null,
  status text not null default 'prepared'
    check (status in ('prepared','sent','failed','skipped')),
  http_status integer,
  error_code text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint background_push_delivery_unique unique (recipient_id, subscription_id)
);

create index if not exists background_push_deliveries_hotel_idx
  on public.background_push_deliveries (hotel_id, created_at desc);

create index if not exists background_push_deliveries_user_idx
  on public.background_push_deliveries (user_id, created_at desc);

alter table public.background_push_deliveries enable row level security;

revoke all on table public.background_push_subscriptions from anon, authenticated;
revoke all on table public.background_push_deliveries from anon, authenticated;
grant select, insert, update, delete on table public.background_push_subscriptions to service_role;
grant select, insert, update, delete on table public.background_push_deliveries to service_role;

create or replace function public.register_background_push_subscription(
  p_hotel_id uuid,
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_expiration_time timestamptz default null,
  p_user_agent text default null,
  p_platform text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.background_push_subscriptions%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if p_hotel_id is null or not exists (
    select 1
    from public.staff s
    where s.hotel_id = p_hotel_id
      and s.auth_user_id = v_user_id
      and s.status = 'active'
  ) then
    raise exception 'Active hotel staff access required.';
  end if;

  if length(coalesce(trim(p_endpoint), '')) not between 16 and 2048
     or length(coalesce(trim(p_p256dh), '')) not between 16 and 512
     or length(coalesce(trim(p_auth), '')) not between 8 and 256 then
    raise exception 'Push subscription data is incomplete.';
  end if;

  -- A browser push endpoint is origin/device scoped. If another StayQR user
  -- enables this same browser, deactivate the previous user's binding first.
  update public.background_push_subscriptions
  set is_active = false,
      updated_at = now(),
      last_error_code = 'device_reassigned'
  where endpoint = trim(p_endpoint)
    and user_id <> v_user_id
    and is_active;

  insert into public.background_push_subscriptions (
    hotel_id,
    user_id,
    endpoint,
    p256dh,
    auth_secret,
    expiration_time,
    user_agent,
    platform,
    is_active,
    failure_count,
    last_seen_at,
    last_error_code,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    v_user_id,
    trim(p_endpoint),
    trim(p_p256dh),
    trim(p_auth),
    p_expiration_time,
    nullif(left(coalesce(p_user_agent, ''), 1000), ''),
    nullif(left(coalesce(p_platform, ''), 120), ''),
    true,
    0,
    now(),
    null,
    now(),
    now()
  )
  on conflict (hotel_id, user_id, endpoint)
  do update set
    p256dh = excluded.p256dh,
    auth_secret = excluded.auth_secret,
    expiration_time = excluded.expiration_time,
    user_agent = excluded.user_agent,
    platform = excluded.platform,
    is_active = true,
    failure_count = 0,
    last_seen_at = now(),
    last_error_code = null,
    updated_at = now()
  returning * into v_row;

  -- Keep a practical device ceiling per staff/hotel identity. Older devices
  -- remain in audit history but stop receiving background pushes.
  update public.background_push_subscriptions s
  set is_active = false,
      last_error_code = 'device_limit',
      updated_at = now()
  where s.id in (
    select ranked.id
    from (
      select id,
             row_number() over (order by last_seen_at desc, created_at desc) as rn
      from public.background_push_subscriptions
      where hotel_id = p_hotel_id
        and user_id = v_user_id
        and is_active
    ) ranked
    where ranked.rn > 10
  );

  return jsonb_build_object(
    'enabled', true,
    'subscription_id', v_row.id,
    'hotel_id', p_hotel_id
  );
end;
$$;

create or replace function public.disable_background_push_subscription(
  p_hotel_id uuid,
  p_endpoint text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not exists (
    select 1
    from public.staff s
    where s.hotel_id = p_hotel_id
      and s.auth_user_id = v_user_id
      and s.status = 'active'
  ) then
    raise exception 'Active hotel staff access required.';
  end if;

  update public.background_push_subscriptions
  set is_active = false,
      updated_at = now(),
      last_error_code = 'disabled_by_user'
  where hotel_id = p_hotel_id
    and user_id = v_user_id
    and endpoint = trim(p_endpoint)
    and is_active;

  get diagnostics v_count = row_count;
  return jsonb_build_object('enabled', false, 'disabled', v_count);
end;
$$;

create or replace function public.disable_my_background_push_endpoint(
  p_endpoint text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  update public.background_push_subscriptions
  set is_active = false,
      updated_at = now(),
      last_error_code = 'logout'
  where user_id = v_user_id
    and endpoint = trim(p_endpoint)
    and is_active;

  get diagnostics v_count = row_count;
  return jsonb_build_object('disabled', v_count);
end;
$$;

create or replace function public.get_background_push_status(
  p_hotel_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not exists (
    select 1
    from public.staff s
    where s.hotel_id = p_hotel_id
      and s.auth_user_id = v_user_id
      and s.status = 'active'
  ) then
    raise exception 'Active hotel staff access required.';
  end if;

  select count(*)
  into v_count
  from public.background_push_subscriptions s
  where s.hotel_id = p_hotel_id
    and s.user_id = v_user_id
    and s.is_active;

  return jsonb_build_object(
    'enabled', v_count > 0,
    'active_devices', v_count
  );
end;
$$;

revoke all on function public.register_background_push_subscription(uuid,text,text,text,timestamptz,text,text) from public, anon;
revoke all on function public.disable_background_push_subscription(uuid,text) from public, anon;
revoke all on function public.disable_my_background_push_endpoint(text) from public, anon;
revoke all on function public.get_background_push_status(uuid) from public, anon;

grant execute on function public.register_background_push_subscription(uuid,text,text,text,timestamptz,text,text) to authenticated;
grant execute on function public.disable_background_push_subscription(uuid,text) to authenticated;
grant execute on function public.disable_my_background_push_endpoint(text) to authenticated;
grant execute on function public.get_background_push_status(uuid) to authenticated;

-- SQL Editor / migration acceptance row.
select
  to_regclass('public.background_push_subscriptions') is not null as subscriptions_table,
  to_regclass('public.background_push_deliveries') is not null as deliveries_table,
  to_regprocedure('public.register_background_push_subscription(uuid,text,text,text,timestamp with time zone,text,text)') is not null as register_rpc,
  to_regprocedure('public.disable_background_push_subscription(uuid,text)') is not null as disable_rpc,
  to_regprocedure('public.disable_my_background_push_endpoint(text)') is not null as logout_rpc,
  to_regprocedure('public.get_background_push_status(uuid)') is not null as status_rpc,
  has_function_privilege('authenticated','public.register_background_push_subscription(uuid,text,text,text,timestamp with time zone,text,text)','EXECUTE') as authenticated_register,
  not has_function_privilege('anon','public.register_background_push_subscription(uuid,text,text,text,timestamp with time zone,text,text)','EXECUTE') as anon_register_blocked;
