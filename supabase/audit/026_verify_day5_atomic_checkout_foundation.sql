-- ============================================================================
-- StayQR Day 5 — Verify atomic checkout foundation
-- Run after migration 202607240010 and before seeding browser acceptance data.
-- Every row must return passed = true.
-- ============================================================================

with tests(test_name, passed, details) as (
  values
    (
      'checkout_rpc_installed',
      to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is not null,
      'The authenticated checkout RPC is installed with the locked Day 5 signature.'
    ),
    (
      'checkout_event_table_installed',
      to_regclass('public.reservation_checkout_events') is not null,
      'Immutable checkout events are available for idempotency and audit.'
    ),
    (
      'checkout_trace_columns_installed',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'guest_sessions'
          and column_name = 'checked_out_at'
      )
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'guest_sessions'
          and column_name = 'checked_out_by'
      ),
      'Guest sessions carry explicit checkout time and actor fields.'
    ),
    (
      'checkout_event_unique_anchor',
      to_regclass('public.uq_reservation_checkout_events_session') is not null,
      'One guest session can create only one immutable checkout event.'
    ),
    (
      'authenticated_execute_grant',
      has_function_privilege(
        'authenticated',
        'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)',
        'EXECUTE'
      ),
      'Authenticated front-desk users can execute the server checkout transaction.'
    ),
    (
      'checkout_event_rls_enabled',
      coalesce((
        select c.relrowsecurity
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'reservation_checkout_events'
      ), false),
      'Checkout events are protected by tenant-aware row-level security.'
    ),
    (
      'reservation_checkout_sync_preserved',
      exists (
        select 1
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'guest_sessions'
          and t.tgname = 'guest_sessions_sync_reservation_status'
          and not t.tgisinternal
      ),
      'The linked reservation-room/header checkout synchronization trigger remains active.'
    ),
    (
      'checkout_rpc_releases_inventory',
      position(
        'update public.room_inventory_allocations'
        in lower(pg_get_functiondef(
          'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure
        ))
      ) > 0,
      'Checkout releases the active authoritative inventory allocation.'
    )
)
select test_name, passed, details
from tests
order by test_name;
