-- StayQR Day 6 browser-acceptance cleanup verification
-- Required result: 8 rows, every passed = true.

with latest_cleanup as (
  select *
  from private.day6_browser_acceptance_cleanup_log_20260725
  order by cleanup_id desc
  limit 1
), tests(test_name, passed, details) as (
  values
    (
      '01_cleanup_log_exists',
      exists (select 1 from latest_cleanup),
      'The controlled cleanup snapshot was preserved privately.'
    ),
    (
      '02_test_staff_removed',
      not exists (
        select 1
        from public.staff s
        join latest_cleanup log on log.staff_id = s.id
      )
      and not exists (
        select 1 from public.staff
        where lower(full_name) = lower('Day 6 Front Desk Test')
      ),
      'The Day 6 controlled staff profile was removed.'
    ),
    (
      '03_test_membership_removed',
      not exists (
        select 1
        from public.hotel_users hu
        join latest_cleanup log
          on hu.hotel_id = log.hotel_id
         and (
           hu.user_id = log.auth_user_id
           or lower(hu.email) = lower(log.email)
         )
      ),
      'The mirrored hotel membership was removed.'
    ),
    (
      '04_test_auth_user_removed',
      not exists (
        select 1
        from auth.users au
        join latest_cleanup log on au.id = log.auth_user_id
      ),
      'The temporary Supabase Auth user was removed.'
    ),
    (
      '05_test_identity_events_removed',
      not exists (
        select 1
        from public.staff_identity_events event
        join latest_cleanup log
          on event.staff_id = log.staff_id
          or event.auth_user_id = log.auth_user_id
      ),
      'Temporary acceptance lifecycle events were removed.'
    ),
    (
      '06_acceptance_context_removed',
      not exists (
        select 1
        from private.day6_final_acceptance_context_20260725
        where context_key = 'day6-final'
      ),
      'The temporary final-gate context was removed.'
    ),
    (
      '07_no_active_unlinked_staff',
      not exists (
        select 1 from public.staff
        where status in ('active', 'invited') and auth_user_id is null
      ),
      'Cleanup did not reintroduce an active unlinked staff identity.'
    ),
    (
      '08_platform_admin_preserved',
      exists (
        select 1
        from public.platform_admins pa
        join auth.users au on au.id = pa.user_id
        where pa.status = 'active'
      ),
      'The real Platform Admin identity remains active and linked.'
    )
)
select test_name, passed, details
from tests
order by test_name;
