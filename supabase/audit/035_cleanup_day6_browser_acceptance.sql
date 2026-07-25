-- StayQR Day 6 controlled browser-acceptance cleanup
-- Run only after Audit 034 returns 20/20 passed.
-- Removes only the exact "Day 6 Front Desk Test" identity and its Auth user.

begin;

select pg_advisory_xact_lock(
  hashtext('stayqr:day6-browser-acceptance-cleanup:20260725')
);

create schema if not exists private;

create table if not exists private.day6_browser_acceptance_cleanup_log_20260725 (
  cleanup_id bigint generated always as identity primary key,
  staff_id uuid not null,
  auth_user_id uuid not null,
  hotel_id uuid not null,
  email text not null,
  staff_snapshot jsonb not null,
  membership_snapshot jsonb,
  auth_snapshot jsonb not null,
  cleaned_at timestamptz not null default now(),
  unique (staff_id, auth_user_id)
);

revoke all on private.day6_browser_acceptance_cleanup_log_20260725
from public, anon, authenticated;

do $$
declare
  context_row private.day6_final_acceptance_context_20260725%rowtype;
  target_staff public.staff%rowtype;
  target_auth auth.users%rowtype;
  target_membership jsonb;
begin
  select *
  into context_row
  from private.day6_final_acceptance_context_20260725
  where context_key = 'day6-final';

  if context_row.context_key is null then
    raise exception 'Day 6 cleanup stopped: final acceptance context is missing.';
  end if;

  select s.*
  into target_staff
  from public.staff s
  where s.id = context_row.reception_staff_id
    and s.auth_user_id = context_row.reception_auth_user_id
    and s.hotel_id = context_row.hotel_id
    and lower(s.full_name) = lower('Day 6 Front Desk Test');

  if target_staff.id is null then
    raise exception 'Day 6 cleanup stopped: exact controlled staff identity not found.';
  end if;

  if exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = target_staff.auth_user_id
  ) then
    raise exception 'Day 6 cleanup stopped: test identity is a Platform Admin.';
  end if;

  if exists (
    select 1
    from public.staff s
    where s.auth_user_id = target_staff.auth_user_id
      and s.id <> target_staff.id
  ) then
    raise exception 'Day 6 cleanup stopped: Auth user has another staff profile.';
  end if;

  if exists (
    select 1
    from public.hotel_users hu
    where hu.user_id = target_staff.auth_user_id
      and hu.hotel_id <> target_staff.hotel_id
  ) then
    raise exception 'Day 6 cleanup stopped: Auth user has another hotel membership.';
  end if;

  select au.*
  into target_auth
  from auth.users au
  where au.id = target_staff.auth_user_id;

  if target_auth.id is null then
    raise exception 'Day 6 cleanup stopped: controlled Auth user not found.';
  end if;

  select to_jsonb(hu)
  into target_membership
  from public.hotel_users hu
  where hu.hotel_id = target_staff.hotel_id
    and hu.user_id = target_staff.auth_user_id
  limit 1;

  insert into private.day6_browser_acceptance_cleanup_log_20260725 (
    staff_id,
    auth_user_id,
    hotel_id,
    email,
    staff_snapshot,
    membership_snapshot,
    auth_snapshot,
    cleaned_at
  ) values (
    target_staff.id,
    target_staff.auth_user_id,
    target_staff.hotel_id,
    target_staff.email,
    to_jsonb(target_staff),
    target_membership,
    jsonb_build_object(
      'id', target_auth.id,
      'email', target_auth.email,
      'email_confirmed_at', target_auth.email_confirmed_at,
      'created_at', target_auth.created_at,
      'updated_at', target_auth.updated_at,
      'raw_app_meta_data', target_auth.raw_app_meta_data,
      'raw_user_meta_data', target_auth.raw_user_meta_data
    ),
    now()
  )
  on conflict (staff_id, auth_user_id) do nothing;

  delete from public.staff_identity_events event
  where event.staff_id = target_staff.id
     or event.auth_user_id = target_staff.auth_user_id;

  delete from public.hotel_users hu
  where hu.hotel_id = target_staff.hotel_id
    and (
      hu.user_id = target_staff.auth_user_id
      or lower(hu.email) = lower(target_staff.email)
    );

  delete from public.staff s
  where s.id = target_staff.id
    and s.auth_user_id = target_staff.auth_user_id
    and lower(s.full_name) = lower('Day 6 Front Desk Test');

  delete from auth.users au
  where au.id = target_staff.auth_user_id
    and lower(coalesce(au.email, '')) = lower(target_staff.email);

  delete from private.day6_final_acceptance_context_20260725
  where context_key = 'day6-final';
end
$$;

commit;

select jsonb_pretty(
  jsonb_build_object(
    'result', 'DAY 6 BROWSER ACCEPTANCE IDENTITY CLEANED',
    'staff_id', log.staff_id,
    'auth_user_id', log.auth_user_id,
    'hotel_id', log.hotel_id,
    'email', log.email,
    'cleaned_at', log.cleaned_at,
    'next_step', 'Run Audit 036.'
  )
) as stayqr_day6_browser_acceptance_cleanup
from private.day6_browser_acceptance_cleanup_log_20260725 log
order by log.cleanup_id desc
limit 1;
