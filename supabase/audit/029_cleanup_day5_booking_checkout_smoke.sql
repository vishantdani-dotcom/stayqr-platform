-- ============================================================================
-- StayQR Day 5 — Cleanup booking-to-checkout smoke-test data
-- Run only after audit 028 passes every row.
-- ============================================================================

create or replace function private.cleanup_day5_checkout_smoke_20260724()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state jsonb;
  v_target_hotel uuid;
  v_reservation_id uuid;
  v_reservation_room_id uuid;
  v_room_id uuid;
  v_guest_id uuid;
  v_rate_plan_id uuid;
  v_temporary_rate_plan_created boolean;
  v_target_sequence_year integer;
  v_sequence_existed boolean;
  v_sequence_before bigint;
  deleted_checkout_events integer := 0;
  deleted_invoice_items integer := 0;
  deleted_collections integer := 0;
  deleted_transfers integer := 0;
  deleted_checkin_events integer := 0;
  deleted_invoices integer := 0;
  deleted_payments integer := 0;
  deleted_tasks integer := 0;
  deleted_sessions integer := 0;
  deleted_allocations integer := 0;
  deleted_reservations integer := 0;
  deleted_guests integer := 0;
  deleted_rooms integer := 0;
  deleted_rate_plans integer := 0;
begin
  select s.payload into v_state
  from private.day5_checkout_smoke_state_20260724 s
  where s.singleton
  for update;

  if v_state is null then
    raise exception 'Day 5 checkout smoke state is missing or already cleaned.';
  end if;

  v_target_hotel := (v_state->>'hotel_id')::uuid;
  v_reservation_id := (v_state->>'reservation_id')::uuid;
  v_reservation_room_id := (v_state->>'reservation_room_id')::uuid;
  v_room_id := (v_state->>'room_id')::uuid;
  v_guest_id := (v_state->>'guest_id')::uuid;
  v_rate_plan_id := (v_state->>'rate_plan_id')::uuid;
  v_temporary_rate_plan_created := coalesce((v_state->>'temporary_rate_plan_created')::boolean, false);
  v_target_sequence_year := (v_state->>'sequence_year')::integer;
  v_sequence_existed := coalesce((v_state->>'sequence_existed')::boolean, false);
  v_sequence_before := nullif(v_state->>'sequence_before', '')::bigint;

  delete from public.reservation_checkout_events event
  where event.hotel_id = v_target_hotel
    and event.reservation_id = v_reservation_id;
  get diagnostics deleted_checkout_events = row_count;

  delete from public.invoice_items item
  using public.invoices inv
  where item.invoice_id = inv.id
    and inv.hotel_id = v_target_hotel
    and inv.guest_id = v_guest_id
    and inv.room_id = v_room_id;
  get diagnostics deleted_invoice_items = row_count;

  delete from public.reservation_payment_transfers transfer
  where transfer.hotel_id = v_target_hotel
    and transfer.reservation_id = v_reservation_id;
  get diagnostics deleted_transfers = row_count;

  delete from public.payment_collections collection
  where collection.hotel_id = v_target_hotel
    and collection.reservation_id = v_reservation_id;
  get diagnostics deleted_collections = row_count;

  delete from public.reservation_checkin_events event
  where event.hotel_id = v_target_hotel
    and event.reservation_id = v_reservation_id;
  get diagnostics deleted_checkin_events = row_count;

  delete from public.invoices inv
  where inv.hotel_id = v_target_hotel
    and inv.guest_id = v_guest_id
    and inv.room_id = v_room_id;
  get diagnostics deleted_invoices = row_count;

  delete from public.payments payment
  where payment.hotel_id = v_target_hotel
    and payment.reservation_id = v_reservation_id;
  get diagnostics deleted_payments = row_count;

  delete from public.housekeeping_tasks task
  where task.hotel_id = v_target_hotel
    and task.room_id = v_room_id;
  get diagnostics deleted_tasks = row_count;

  delete from public.guest_sessions session
  where session.hotel_id = v_target_hotel
    and session.reservation_id = v_reservation_id;
  get diagnostics deleted_sessions = row_count;

  delete from public.room_inventory_allocations allocation
  where allocation.hotel_id = v_target_hotel
    and allocation.reservation_room_id = v_reservation_room_id;
  get diagnostics deleted_allocations = row_count;

  delete from public.activity_logs log
  where log.hotel_id = v_target_hotel
    and log.entity_type = 'reservation'
    and log.entity_id = v_reservation_id;

  delete from public.reservations reservation
  where reservation.hotel_id = v_target_hotel
    and reservation.id = v_reservation_id;
  get diagnostics deleted_reservations = row_count;

  delete from public.guests guest
  where guest.hotel_id = v_target_hotel
    and guest.id = v_guest_id;
  get diagnostics deleted_guests = row_count;

  delete from public.rooms room
  where room.hotel_id = v_target_hotel
    and room.id = v_room_id;
  get diagnostics deleted_rooms = row_count;

  if v_temporary_rate_plan_created then
    delete from public.rate_plans rate_plan
    where rate_plan.hotel_id = v_target_hotel
      and rate_plan.id = v_rate_plan_id;
    get diagnostics deleted_rate_plans = row_count;
  end if;

  if v_sequence_existed then
    update public.reservation_number_sequences sequence
    set last_number = v_sequence_before
    where sequence.hotel_id = v_target_hotel
      and sequence.sequence_year = v_target_sequence_year;
  else
    delete from public.reservation_number_sequences sequence
    where sequence.hotel_id = v_target_hotel
      and sequence.sequence_year = v_target_sequence_year;
  end if;

  delete from private.day5_checkout_smoke_state_20260724;

  return jsonb_build_object(
    'result', 'DAY 5 BOOKING-TO-CHECKOUT SMOKE DATA CLEANED',
    'deleted_checkout_events', deleted_checkout_events,
    'deleted_invoice_items', deleted_invoice_items,
    'deleted_collections', deleted_collections,
    'deleted_transfers', deleted_transfers,
    'deleted_checkin_events', deleted_checkin_events,
    'deleted_invoices', deleted_invoices,
    'deleted_payments', deleted_payments,
    'deleted_housekeeping_tasks', deleted_tasks,
    'deleted_sessions', deleted_sessions,
    'deleted_allocations', deleted_allocations,
    'deleted_reservations', deleted_reservations,
    'deleted_guests', deleted_guests,
    'deleted_rooms', deleted_rooms,
    'deleted_temporary_rate_plans', deleted_rate_plans
  );
end;
$$;

revoke all on function private.cleanup_day5_checkout_smoke_20260724()
from public;

select jsonb_pretty(
  private.cleanup_day5_checkout_smoke_20260724()
) as stayqr_day5_checkout_smoke_cleanup;
