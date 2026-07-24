-- StayQR Day 5 foundation verification. Run after migration 202607240007.

with checks as (
  select 'reservation_checkin_events_table' as test_name,
         to_regclass('public.reservation_checkin_events') is not null as passed,
         'Immutable check-in event table exists.' as details
  union all
  select 'reservation_payment_transfers_table',
         to_regclass('public.reservation_payment_transfers') is not null,
         'Deposit transfer ledger exists.'
  union all
  select 'checkin_rpc',
         to_regprocedure('public.check_in_reservation_room(uuid,uuid,uuid,timestamp with time zone)') is not null,
         'Atomic reservation room check-in RPC exists.'
  union all
  select 'group_add_rpc',
         to_regprocedure('public.add_reservation_room(uuid,uuid,jsonb,timestamp with time zone)') is not null,
         'Group reservation room-add RPC exists.'
  union all
  select 'group_remove_rpc',
         to_regprocedure('public.remove_reservation_room(uuid,uuid,uuid,timestamp with time zone)') is not null,
         'Group reservation room-remove RPC exists.'
  union all
  select 'operations_read_model',
         to_regprocedure('public.get_reservation_operations(uuid,date,integer)') is not null,
         'Arrivals/departures read model exists.'
  union all
  select 'confirmation_read_model',
         to_regprocedure('public.get_reservation_confirmation(uuid,uuid)') is not null,
         'Authoritative confirmation snapshot RPC exists.'
  union all
  select 'checkout_sync_trigger',
         exists (
           select 1 from pg_trigger
           where tgname = 'guest_sessions_sync_reservation_status'
             and tgrelid = 'public.guest_sessions'::regclass
             and not tgisinternal
         ),
         'Reservation-linked stay checkout synchronization is installed.'
  union all
  select 'guest_session_idempotency',
         to_regclass('public.uq_guest_sessions_reservation_room') is not null,
         'One guest session per reservation room is enforced.'
  union all
  select 'room_charge_idempotency',
         to_regclass('public.uq_payments_reservation_room_charge') is not null,
         'One room charge per reservation room is enforced.'
)
select test_name, passed, details
from checks
order by test_name;
