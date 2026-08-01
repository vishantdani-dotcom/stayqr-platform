-- ============================================================================
-- StayQR v1.0
-- Day 13 Migration 042 REV1 — RPC-Only Operational Write Closure
-- and Checkout-Request Settlement Integration
--
-- WHY THIS CLOSURE EXISTS
-- Audit 060 REV3 returned 229/230. The only failed result was:
--   DAY13_FINAL / 11_rpc_only_operational_writes
--
-- Migration 039 installed authoritative room RPCs but the legacy authenticated
-- INSERT/UPDATE/DELETE grants on public.rooms were still present from the
-- earlier broad Day 7 table grant. The old Service Requests page also attempted
-- a client-side checkout by directly updating rooms/guest_sessions and directly
-- inserting housekeeping_tasks, bypassing the accepted checkout/folio/invoice
-- transaction.
--
-- OUTCOME
-- 1. Rooms, housekeeping and maintenance operational writes become RPC-only.
-- 2. Authenticated staff retain tenant-scoped SELECT access.
-- 3. Approved Day 13 RPC execution remains available to authenticated users.
-- 4. Completing a real guest session automatically closes the matching active
--    "Checkout Request" service request.
-- 5. No production room, stay, financial, housekeeping or maintenance row is
--    created, deleted or otherwise changed merely by installing this migration.
--
-- RUN WITH
-- Supabase SQL Editor role: postgres
--
-- EXPECTED RESULT
-- 24 rows; every passed value = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607310042:day13-rpc-only-operational-write-closure')
);

-- --------------------------------------------------------------------------
-- 0. Preconditions
-- --------------------------------------------------------------------------

do $preflight$
begin
  if to_regclass('public.rooms') is null
     or to_regclass('public.housekeeping_tasks') is null
     or to_regclass('public.maintenance_tasks') is null
     or to_regclass('public.guest_sessions') is null
     or to_regclass('public.service_requests') is null
  then
    raise exception
      'Migration 042 stopped: required Day 13 operational tables are missing.';
  end if;

  if to_regprocedure(
       'public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text)'
     ) is null
     or to_regprocedure(
       'public.transition_room_status(uuid,uuid,text,text,text,text)'
     ) is null
     or to_regprocedure(
       'public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)'
     ) is null
     or to_regprocedure(
       'public.report_maintenance_task(uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text)'
     ) is null
     or to_regprocedure(
       'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'
     ) is null
  then
    raise exception
      'Migration 042 stopped: accepted operational or checkout RPCs are missing.';
  end if;
end;
$preflight$;

-- --------------------------------------------------------------------------
-- 1. Close legacy direct-write grants.
--    RLS alone is not the intended Day 13 write boundary; browser writes must
--    enter through permission-checked, audited RPCs.
-- --------------------------------------------------------------------------

revoke insert, update, delete
on table public.rooms
from authenticated;

revoke insert, update, delete
on table public.housekeeping_tasks
from authenticated;

revoke insert, update, delete
on table public.maintenance_tasks
from authenticated;

grant select
on table public.rooms, public.housekeeping_tasks, public.maintenance_tasks
to authenticated;

-- Reassert the three representative workflow entry points used by Audit 060.
grant execute on function
  public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text)
to authenticated;

grant execute on function
  public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)
to authenticated;

grant execute on function
  public.report_maintenance_task(uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text)
to authenticated;

revoke execute on function
  public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text)
from anon;

revoke execute on function
  public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)
from anon;

revoke execute on function
  public.report_maintenance_task(uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text)
from anon;

-- --------------------------------------------------------------------------
-- 2. Keep checkout requests aligned with the authoritative checkout RPC.
--    The frontend now opens the Guests settlement flow. When that transaction
--    completes the stay, this trigger closes the matching active request.
-- --------------------------------------------------------------------------

create or replace function private.day13_sync_checkout_request_on_stay_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status::text = 'completed'
     and old.status::text is distinct from new.status::text
  then
    update public.service_requests request
    set
      status = 'completed',
      accepted_at = coalesce(request.accepted_at, now()),
      started_at = coalesce(request.started_at, now()),
      completed_at = coalesce(request.completed_at, now())
    where request.hotel_id = new.hotel_id
      and request.room_id = new.room_id
      and request.guest_id = new.guest_id
      and request.request_type = 'Checkout Request'
      and request.status not in ('completed', 'cancelled');
  end if;

  return new;
end;
$function$;

revoke all on function
  private.day13_sync_checkout_request_on_stay_completion()
from public, anon, authenticated;

drop trigger if exists
  guest_sessions_day13_checkout_request_sync
on public.guest_sessions;

create trigger guest_sessions_day13_checkout_request_sync
after update of status
on public.guest_sessions
for each row
when (old.status is distinct from new.status)
execute function private.day13_sync_checkout_request_on_stay_completion();

commit;

-- --------------------------------------------------------------------------
-- 3. Read-only acceptance
-- --------------------------------------------------------------------------

with parameters as (
  select '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid as hotel_id
),
checks(test_order, test_name, passed, details) as (
  select 1, '01_rooms_insert_revoked',
    not has_table_privilege('authenticated','public.rooms','INSERT'),
    'Authenticated browser cannot directly insert rooms.'

  union all select 2, '02_rooms_update_revoked',
    not has_table_privilege('authenticated','public.rooms','UPDATE'),
    'Authenticated browser cannot directly update rooms.'

  union all select 3, '03_rooms_delete_revoked',
    not has_table_privilege('authenticated','public.rooms','DELETE'),
    'Authenticated browser cannot directly delete rooms.'

  union all select 4, '04_housekeeping_insert_revoked',
    not has_table_privilege('authenticated','public.housekeeping_tasks','INSERT'),
    'Housekeeping task creation is RPC-only.'

  union all select 5, '05_housekeeping_update_revoked',
    not has_table_privilege('authenticated','public.housekeeping_tasks','UPDATE'),
    'Housekeeping lifecycle updates are RPC-only.'

  union all select 6, '06_housekeeping_delete_revoked',
    not has_table_privilege('authenticated','public.housekeeping_tasks','DELETE'),
    'Housekeeping task deletion is blocked.'

  union all select 7, '07_maintenance_insert_revoked',
    not has_table_privilege('authenticated','public.maintenance_tasks','INSERT'),
    'Maintenance task creation is RPC-only.'

  union all select 8, '08_maintenance_update_revoked',
    not has_table_privilege('authenticated','public.maintenance_tasks','UPDATE'),
    'Maintenance lifecycle updates are RPC-only.'

  union all select 9, '09_maintenance_delete_revoked',
    not has_table_privilege('authenticated','public.maintenance_tasks','DELETE'),
    'Maintenance task deletion is blocked.'

  union all select 10, '10_rooms_select_retained',
    has_table_privilege('authenticated','public.rooms','SELECT'),
    'Tenant-scoped room reads remain available.'

  union all select 11, '11_housekeeping_select_retained',
    has_table_privilege('authenticated','public.housekeeping_tasks','SELECT'),
    'Tenant-scoped housekeeping reads remain available.'

  union all select 12, '12_maintenance_select_retained',
    has_table_privilege('authenticated','public.maintenance_tasks','SELECT'),
    'Tenant-scoped maintenance reads remain available.'

  union all select 13, '13_room_rpc_execute',
    has_function_privilege(
      'authenticated',
      'public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text)',
      'EXECUTE'
    ),
    'Authenticated staff can invoke the room RPC.'

  union all select 14, '14_housekeeping_rpc_execute',
    has_function_privilege(
      'authenticated',
      'public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)',
      'EXECUTE'
    ),
    'Authenticated staff can invoke the housekeeping RPC.'

  union all select 15, '15_maintenance_rpc_execute',
    has_function_privilege(
      'authenticated',
      'public.report_maintenance_task(uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text)',
      'EXECUTE'
    ),
    'Authenticated staff can invoke the maintenance RPC.'

  union all select 16, '16_anon_operational_rpcs_revoked',
    not has_function_privilege(
      'anon',
      'public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.report_maintenance_task(uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text)',
      'EXECUTE'
    ),
    'Anonymous users cannot invoke operational writes.'

  union all select 17, '17_checkout_sync_function_exists',
    to_regprocedure(
      'private.day13_sync_checkout_request_on_stay_completion()'
    ) is not null,
    'Checkout service-request sync function exists.'

  union all select 18, '18_checkout_sync_trigger_exists',
    exists(
      select 1
      from pg_trigger
      where tgname='guest_sessions_day13_checkout_request_sync'
        and not tgisinternal
    ),
    'Guest-session completion trigger exists.'

  union all select 19, '19_checkout_sync_is_private',
    not has_function_privilege(
      'authenticated',
      'private.day13_sync_checkout_request_on_stay_completion()',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'private.day13_sync_checkout_request_on_stay_completion()',
      'EXECUTE'
    ),
    'Browser roles cannot invoke the private trigger function.'

  union all select 20, '20_room_inventory_preserved',
    (select count(*)=12 from public.rooms r join parameters p on p.hotel_id=r.hotel_id where r.is_active)
    and (select count(*)=7 from public.rooms r join parameters p on p.hotel_id=r.hotel_id where r.status='available')
    and (select count(*)=4 from public.rooms r join parameters p on p.hotel_id=r.hotel_id where r.status='occupied')
    and (select count(*)=1 from public.rooms r join parameters p on p.hotel_id=r.hotel_id where r.status='cleaning'),
    'Locked room baseline remains 12 / 7 / 4 / 1.'

  union all select 21, '21_housekeeping_baseline_preserved',
    (select count(*)=14 from public.housekeeping_tasks t join parameters p on p.hotel_id=t.hotel_id)
    and (select count(*)=13 from public.housekeeping_tasks t join parameters p on p.hotel_id=t.hotel_id where t.status='completed')
    and (select count(*)=1 from public.housekeeping_tasks t join parameters p on p.hotel_id=t.hotel_id where t.status='pending'),
    'Locked housekeeping baseline remains 14 / 13 / 1.'

  union all select 22, '22_maintenance_baseline_preserved',
    (select count(*)=0 from public.maintenance_tasks t join parameters p on p.hotel_id=t.hotel_id),
    'No production maintenance task was created.'

  union all select 23, '23_financial_baseline_preserved',
    (select count(*)=40 from public.folios f join parameters p on p.hotel_id=f.hotel_id)
    and (select coalesce(sum(balance_amount),0)=22785 from public.folios f join parameters p on p.hotel_id=f.hotel_id),
    'Financial baseline remains 40 folios / INR 22,785.'

  union all select 24, '24_day13_rpc_only_closure_exit_gate',
    not has_table_privilege('authenticated','public.rooms','INSERT')
    and not has_table_privilege('authenticated','public.rooms','UPDATE')
    and not has_table_privilege('authenticated','public.rooms','DELETE')
    and not has_table_privilege('authenticated','public.housekeeping_tasks','INSERT')
    and not has_table_privilege('authenticated','public.maintenance_tasks','INSERT')
    and has_function_privilege(
      'authenticated',
      'public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text)',
      'EXECUTE'
    )
    and has_function_privilege(
      'authenticated',
      'public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)',
      'EXECUTE'
    )
    and has_function_privilege(
      'authenticated',
      'public.report_maintenance_task(uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text)',
      'EXECUTE'
    ),
    'Day 13 operational writes are RPC-only.'
)
select test_name, passed, details
from checks
order by test_order;
