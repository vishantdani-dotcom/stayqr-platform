-- StayQR Day 6 final acceptance context seed
-- This creates only a private audit context. It does not create hotel data.
-- Run after Audit 032 passes and after the Day 6 test Reception identity is active.

begin;

select pg_advisory_xact_lock(
  hashtext('stayqr:day6-final-acceptance-context:20260725')
);

create schema if not exists private;

create table if not exists private.day6_final_acceptance_context_20260725 (
  context_key text primary key,
  hotel_id uuid not null,
  other_hotel_id uuid,
  reception_staff_id uuid not null,
  reception_auth_user_id uuid not null,
  platform_admin_user_id uuid not null,
  seeded_at timestamptz not null default now()
);

revoke all on private.day6_final_acceptance_context_20260725
from public, anon, authenticated;

do $$
declare
  target_staff public.staff%rowtype;
  target_auth auth.users%rowtype;
  platform_user_id uuid;
  other_hotel_id uuid;
  target_count integer;
begin
  select count(*)
  into target_count
  from public.staff s
  where lower(s.full_name) = lower('Day 6 Front Desk Test');

  if target_count <> 1 then
    raise exception
      'Day 6 acceptance requires exactly one staff profile named Day 6 Front Desk Test; found %.',
      target_count;
  end if;

  select s.*
  into target_staff
  from public.staff s
  where lower(s.full_name) = lower('Day 6 Front Desk Test')
  limit 1;

  if target_staff.auth_user_id is null
     or target_staff.status <> 'active'
     or lower(replace(trim(target_staff.role), ' ', '_')) <> 'reception'
  then
    raise exception
      'Day 6 test identity must be active, linked and assigned the Reception role.';
  end if;

  select au.*
  into target_auth
  from auth.users au
  where au.id = target_staff.auth_user_id;

  if target_auth.id is null then
    raise exception 'Day 6 test identity does not exist in Supabase Auth.';
  end if;

  if coalesce(target_auth.banned_until, '-infinity'::timestamptz) > now() then
    raise exception 'Day 6 test identity is still banned. Activate it before seeding.';
  end if;

  if target_auth.email_confirmed_at is null then
    raise exception 'Day 6 test identity has not accepted the invitation.';
  end if;

  select pa.user_id
  into platform_user_id
  from public.platform_admins pa
  where pa.status = 'active'
  order by pa.created_at
  limit 1;

  if platform_user_id is null then
    raise exception 'No active Platform Admin exists for the Day 6 acceptance gate.';
  end if;

  select h.id
  into other_hotel_id
  from public.hotels h
  where h.id <> target_staff.hotel_id
  order by
    case when lower(h.hotel_name) = lower('Hotel Apex Stay Inn') then 0 else 1 end,
    h.created_at
  limit 1;

  if exists (
    select 1
    from public.staff s
    where s.auth_user_id = target_staff.auth_user_id
      and s.hotel_id <> target_staff.hotel_id
      and s.status = 'active'
  ) then
    raise exception 'The Day 6 Reception test identity has unexpected cross-hotel staff access.';
  end if;

  insert into private.day6_final_acceptance_context_20260725 (
    context_key,
    hotel_id,
    other_hotel_id,
    reception_staff_id,
    reception_auth_user_id,
    platform_admin_user_id,
    seeded_at
  ) values (
    'day6-final',
    target_staff.hotel_id,
    other_hotel_id,
    target_staff.id,
    target_staff.auth_user_id,
    platform_user_id,
    now()
  )
  on conflict (context_key) do update
  set
    hotel_id = excluded.hotel_id,
    other_hotel_id = excluded.other_hotel_id,
    reception_staff_id = excluded.reception_staff_id,
    reception_auth_user_id = excluded.reception_auth_user_id,
    platform_admin_user_id = excluded.platform_admin_user_id,
    seeded_at = excluded.seeded_at;
end
$$;

commit;

select jsonb_pretty(
  jsonb_build_object(
    'result', 'DAY 6 FINAL ACCEPTANCE CONTEXT READY',
    'hotel', h.hotel_name,
    'other_hotel', other_hotel.hotel_name,
    'reception_staff', s.full_name,
    'reception_role', s.role,
    'reception_status', s.status,
    'auth_email', au.email,
    'auth_banned', coalesce(au.banned_until, '-infinity'::timestamptz) > now(),
    'platform_admin', pa.display_name,
    'seeded_at', context.seeded_at
  )
) as stayqr_day6_final_acceptance_context
from private.day6_final_acceptance_context_20260725 context
join public.hotels h on h.id = context.hotel_id
left join public.hotels other_hotel on other_hotel.id = context.other_hotel_id
join public.staff s on s.id = context.reception_staff_id
join auth.users au on au.id = context.reception_auth_user_id
join public.platform_admins pa on pa.user_id = context.platform_admin_user_id
where context.context_key = 'day6-final';
