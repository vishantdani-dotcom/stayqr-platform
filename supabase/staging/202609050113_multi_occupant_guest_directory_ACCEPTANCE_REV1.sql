-- StayQR Multi-Occupant Guest Directory REV7
-- Staging acceptance after Migration 113 is applied directly in SQL Editor.
-- Read-only verifier: no data mutations.

with defs as (
  select
    pg_get_functiondef('public.get_guest_360_directory(uuid)'::regprocedure) as directory_def,
    pg_get_functiondef('public.get_guest_communication_audience(uuid)'::regprocedure) as audience_def,
    pg_get_functiondef('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)'::regprocedure) as export_def
), target_hotel as (
  select id
  from public.hotels
  where slug = '20e-test-hotel'
  limit 1
), active_session_members as (
  select gs.id as guest_session_id, gs.guest_id
  from public.guest_sessions gs
  join target_hotel h on h.id = gs.hotel_id
  where gs.status = 'active'

  union

  select gs.id as guest_session_id, gc.guest_id
  from public.guest_companions gc
  join public.guest_sessions gs
    on gs.hotel_id = gc.hotel_id
   and gs.id = gc.guest_session_id
  join target_hotel h on h.id = gs.hotel_id
  where gs.status = 'active'
), checks as (
  select '01_GUEST_360_COMPANION_MEMBERSHIP' as check_name,
    directory_def ilike '%from public.guest_companions gc%'
      and directory_def ilike '%gs.id = gc.guest_session_id%'
      and directory_def ilike '%gs.hotel_id = gc.hotel_id%' as ok
  from defs

  union all
  select '02_GUEST_360_UNION_DEDUPES_STAYS',
    directory_def ilike '%with stay_memberships as%'
      and directory_def ilike '%union%'
      and directory_def ilike '%from stay_memberships sm%'
  from defs

  union all
  select '03_GUEST_360_ACTIVE_STATUS_COMPANION_AWARE',
    directory_def ilike '%active_stay as%'
      and directory_def ilike '%sm.status = ''active''%'
  from defs

  union all
  select '04_GUEST_360_TOTAL_STAYS_COMPANION_AWARE',
    directory_def ilike '%count(*)::bigint as total_stays%'
      and directory_def ilike '%group by sm.guest_id%'
  from defs

  union all
  select '05_COMMUNICATION_ACTIVE_ROOM_COMPANION_AWARE',
    audience_def ilike '%from public.guest_companions gc%'
      and audience_def ilike '%active_room_by_guest%'
  from defs

  union all
  select '06_EXPORT_USES_GUEST_360_SUMMARY',
    export_def ilike '%public.get_guest_360_directory(target_hotel_id)%'
  from defs

  union all
  select '07_DIRECTORY_ANON_DENIED',
    not has_function_privilege('anon','public.get_guest_360_directory(uuid)','EXECUTE')

  union all
  select '08_DIRECTORY_AUTHENTICATED_ALLOWED',
    has_function_privilege('authenticated','public.get_guest_360_directory(uuid)','EXECUTE')

  union all
  select '09_AUDIENCE_ANON_DENIED',
    not has_function_privilege('anon','public.get_guest_communication_audience(uuid)','EXECUTE')

  union all
  select '10_AUDIENCE_AUTHENTICATED_ALLOWED',
    has_function_privilege('authenticated','public.get_guest_communication_audience(uuid)','EXECUTE')

  union all
  select '11_20E_HAS_ACTIVE_COMPANION_FIXTURE',
    exists (
      select 1
      from public.guest_companions gc
      join public.guest_sessions gs
        on gs.hotel_id = gc.hotel_id
       and gs.id = gc.guest_session_id
      join target_hotel h on h.id = gs.hotel_id
      where gs.status = 'active'
    )

  union all
  select '12_20E_ACTIVE_MEMBERSHIP_SET_DEDUPED',
    (select count(*) from active_session_members)
      = (select count(distinct guest_session_id::text || ':' || guest_id::text) from active_session_members)
)
select
  check_name,
  case when ok then 'PASS' else 'FAIL' end as status
from checks
order by check_name;
