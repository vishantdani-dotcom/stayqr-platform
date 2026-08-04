-- ============================================================================
-- StayQR v1.0
-- Day 15 Migration 051 REV2 PRIVILEGE FIX
-- Immutable Operational Ledger Write Closure
--
-- BASIS
-- Migration 051 REV1 acceptance:
--   130 checks
--   124 passed
--   6 failed
--
-- All six failures were inherited authenticated INSERT/UPDATE/DELETE
-- privileges on immutable operational ledger tables:
--   food_order_item_modifiers
--   food_order_events
--   kitchen_tickets
--   service_request_events
--   guest_notifications
--   service_escalations
--
-- PURPOSE
-- Remove direct browser-role writes while retaining authenticated SELECT,
-- service-role operational access, RLS, all existing rows and all Day 15
-- schema/backfills.
--
-- BUSINESS DATA CHANGES
-- None.
--
-- EXPECTED RESULT
-- 130 rows
-- 130 passed = true
-- 0 failures
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608040051:day15-privilege-closure-rev2')
);

do $preflight$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'food_order_item_modifiers',
    'food_order_events',
    'kitchen_tickets',
    'service_request_events',
    'guest_notifications',
    'service_escalations'
  ]
  loop
    if to_regclass('public.' || relation_name) is null then
      raise exception
        'Migration 051 REV2 stopped: public.% is missing.',
        relation_name;
    end if;
  end loop;

  if to_regprocedure(
    'private.day15_migration_051_acceptance_rev1()'
  ) is null then
    raise exception
      'Migration 051 REV2 stopped: REV1 acceptance helper is missing.';
  end if;
end;
$preflight$;

-- Remove all inherited/direct browser write capabilities.
revoke insert, update, delete, truncate, references, trigger
on table
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
from authenticated;

revoke all
on table
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
from anon, public;

-- Authenticated hotel users retain read access through RLS.
grant select
on table
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
to authenticated;

-- Trusted server actions retain full operational access.
grant select, insert, update, delete
on table
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
to service_role;

commit;

-- Re-run the authoritative Migration 051 acceptance suite.
select suite, test_name, passed, details
from private.day15_migration_051_acceptance_rev1()
order by suite, test_name;
