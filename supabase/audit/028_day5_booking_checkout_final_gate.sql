-- ============================================================================
-- StayQR Day 5 — Booking-to-checkout final acceptance gate
--
-- Run only after the controlled reservation from audit 027 has been checked in
-- and completed through Guests > Final Bill & Checkout.
-- Every row must return passed = true before cleanup audit 029.
-- ============================================================================

create or replace function private.run_day5_checkout_final_gate_20260724()
returns table(test_name text, passed boolean, details text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state jsonb;
  v_actor_user uuid;
  v_target_hotel uuid;
  v_other_hotel uuid;
  v_reservation_id uuid;
  v_reservation_room_id uuid;
  v_room_id uuid;
  v_guest_id uuid;
  v_session_id uuid;
  v_invoice_id uuid;
  v_expected_total numeric(12,2);
  v_expected_deposit numeric(12,2);
  v_duplicate_rejected boolean := false;
  v_duplicate_reason text := '';
  v_operations_today jsonb;
  v_operations_departure jsonb;
begin
  select s.payload into v_state
  from private.day5_checkout_smoke_state_20260724 s
  where s.singleton;

  if v_state is null then
    raise exception 'Day 5 checkout smoke state is missing. Run audit 027 first.';
  end if;

  v_actor_user := (v_state->>'actor_user')::uuid;
  v_target_hotel := (v_state->>'hotel_id')::uuid;
  v_other_hotel := nullif(v_state->>'other_hotel_id', '')::uuid;
  v_reservation_id := (v_state->>'reservation_id')::uuid;
  v_reservation_room_id := (v_state->>'reservation_room_id')::uuid;
  v_room_id := (v_state->>'room_id')::uuid;
  v_guest_id := (v_state->>'guest_id')::uuid;
  v_expected_total := (v_state->>'expected_total')::numeric(12,2);
  v_expected_deposit := (v_state->>'deposit_amount')::numeric(12,2);

  select gs.id into v_session_id
  from public.guest_sessions gs
  where gs.hotel_id = v_target_hotel
    and gs.reservation_room_id = v_reservation_room_id
  limit 1;

  select inv.id into v_invoice_id
  from public.invoices inv
  where inv.hotel_id = v_target_hotel
    and inv.guest_session_id = v_session_id
  limit 1;

  perform set_config('request.jwt.claim.sub', v_actor_user::text, true);

  begin
    perform public.checkout_guest_session(
      v_target_hotel,
      v_session_id,
      0,
      'fixed',
      0,
      true,
      'cash',
      'D5CO-DUPLICATE-RETRY',
      'Duplicate checkout rejection test',
      false
    );
  exception when others then
    v_duplicate_reason := sqlerrm;
    v_duplicate_rejected :=
      position('already checked out' in lower(sqlerrm)) > 0
      or position('invoice already exists' in lower(sqlerrm)) > 0
      or position('only an active guest stay' in lower(sqlerrm)) > 0;
  end;

  v_operations_today := public.get_reservation_operations(
    v_target_hotel,
    (v_state->>'business_date')::date,
    7
  );

  v_operations_departure := public.get_reservation_operations(
    v_target_hotel,
    (v_state->>'departure_test_date')::date,
    7
  );

  return query
  with checks(test_name, passed, details) as (
    values
      (
        '01_controlled_state_present',
        v_state is not null and v_session_id is not null and v_invoice_id is not null,
        'The controlled reservation, stay and final invoice are present.'
      ),
      (
        '02_reservation_and_room_checked_out',
        exists (
          select 1
          from public.reservations r
          join public.reservation_rooms rr
            on rr.hotel_id = r.hotel_id
           and rr.reservation_id = r.id
          where r.hotel_id = v_target_hotel
            and r.id = v_reservation_id
            and r.status = 'checked_out'
            and rr.id = v_reservation_room_id
            and rr.status = 'checked_out'
        ),
        'The linked booking header and physical reservation room are checked out.'
      ),
      (
        '03_guest_session_completed_and_qr_expired',
        exists (
          select 1
          from public.guest_sessions gs
          where gs.hotel_id = v_target_hotel
            and gs.id = v_session_id
            and gs.status = 'completed'
            and gs.expired_at is not null
            and gs.checked_out_at is not null
        ),
        'The stay is completed and guest/QR access has been expired.'
      ),
      (
        '04_invoice_created_once_and_paid',
        (
          select count(*) = 1
          from public.invoices inv
          where inv.hotel_id = v_target_hotel
            and inv.guest_session_id = v_session_id
            and inv.payment_status = 'paid'
            and inv.invoice_status = 'paid'
            and inv.pending_amount = 0
            and inv.total_amount = v_expected_total
            and inv.paid_amount = v_expected_total
            and inv.previous_paid_amount = v_expected_deposit
            and inv.amount_to_collect = v_expected_total - v_expected_deposit
        ),
        'Exactly one paid invoice carries the correct total, deposit and remaining settlement.'
      ),
      (
        '05_invoice_items_match_final_total',
        coalesce((
          select round(sum(ii.amount), 2) = v_expected_total
          from public.invoice_items ii
          where ii.hotel_id = v_target_hotel
            and ii.invoice_id = v_invoice_id
        ), false),
        'The itemised invoice rows reconcile exactly to the final invoice total.'
      ),
      (
        '06_deposit_and_final_collection_exactly_once',
        coalesce((
          select round(sum(pc.amount), 2) = v_expected_total
          from public.payment_collections pc
          where pc.hotel_id = v_target_hotel
            and pc.guest_session_id = v_session_id
            and pc.invoice_id = v_invoice_id
        ), false)
        and (
          select count(*) = 1
          from public.reservation_payment_transfers transfer
          where transfer.hotel_id = v_target_hotel
            and transfer.reservation_room_id = v_reservation_room_id
            and transfer.amount = v_expected_deposit
        ),
        'The ₹500 reservation deposit and the remaining checkout collection total the invoice exactly once.'
      ),
      (
        '07_room_cleaning_and_inventory_released',
        exists (
          select 1 from public.rooms room
          where room.hotel_id = v_target_hotel
            and room.id = v_room_id
            and room.status = 'cleaning'
        )
        and not exists (
          select 1 from public.room_inventory_allocations allocation
          where allocation.hotel_id = v_target_hotel
            and allocation.reservation_room_id = v_reservation_room_id
            and allocation.status = 'active'
        )
        and exists (
          select 1 from public.room_inventory_allocations allocation
          where allocation.hotel_id = v_target_hotel
            and allocation.reservation_room_id = v_reservation_room_id
            and allocation.status = 'released'
            and allocation.released_at is not null
        ),
        'Checkout sends the room to cleaning and releases the authoritative inventory allocation.'
      ),
      (
        '08_one_housekeeping_task',
        (
          select count(*) = 1
          from public.housekeeping_tasks task
          where task.hotel_id = v_target_hotel
            and task.room_id = v_room_id
            and task.task_type = 'room_cleaning'
            and task.status in ('pending', 'in_progress')
        ),
        'Exactly one active room-cleaning task exists for the checked-out room.'
      ),
      (
        '09_checkout_event_created_once',
        (
          select count(*) = 1
          from public.reservation_checkout_events event
          where event.hotel_id = v_target_hotel
            and event.guest_session_id = v_session_id
            and event.invoice_id = v_invoice_id
        ),
        'Exactly one immutable checkout event anchors the transaction.'
      ),
      (
        '10_duplicate_checkout_rejected',
        v_duplicate_rejected,
        coalesce(nullif(v_duplicate_reason, ''), 'The duplicate call did not return the required rejection.')
      ),
      (
        '11_operational_queues_refreshed',
        not exists (
          select 1
          from jsonb_array_elements(coalesce(v_operations_today->'in_house', '[]'::jsonb)) item
          where item->>'reservation_id' = v_reservation_id::text
        )
        and not exists (
          select 1
          from jsonb_array_elements(coalesce(v_operations_today->'today_arrivals', '[]'::jsonb)) item
          where item->>'reservation_id' = v_reservation_id::text
        )
        and not exists (
          select 1
          from jsonb_array_elements(coalesce(v_operations_departure->'today_departures', '[]'::jsonb)) item
          where item->>'reservation_id' = v_reservation_id::text
        ),
        'The checked-out room no longer appears in arrivals, in-house or pending-departure queues.'
      ),
      (
        '12_no_active_guest_or_duplicate_financial_records',
        not exists (
          select 1 from public.guest_sessions gs
          where gs.hotel_id = v_target_hotel
            and gs.id = v_session_id
            and gs.status = 'active'
        )
        and (
          select count(*) = 1
          from public.reservation_checkin_events event
          where event.hotel_id = v_target_hotel
            and event.reservation_room_id = v_reservation_room_id
        )
        and (
          select count(*) = 1
          from public.reservation_checkout_events event
          where event.hotel_id = v_target_hotel
            and event.guest_session_id = v_session_id
        ),
        'No active stay, duplicate check-in event or duplicate checkout event remains.'
      ),
      (
        '13_tenant_isolation',
        v_other_hotel is null
        or (
          not exists (
            select 1 from public.reservations r
            where r.hotel_id = v_other_hotel
              and r.source_reference = 'DAY5-CHECKOUT-SMOKE'
          )
          and not exists (
            select 1 from public.rooms room
            where room.hotel_id = v_other_hotel
              and room.room_number like (v_state->>'room_prefix') || '%'
          )
          and not exists (
            select 1 from public.invoices inv
            where inv.hotel_id = v_other_hotel
              and inv.guest_id = v_guest_id
          )
        ),
        'No controlled reservation, room or invoice leaked into the second hotel.'
      )
  )
  select checks.test_name, checks.passed, checks.details
  from checks
  order by checks.test_name;
end;
$$;

revoke all on function private.run_day5_checkout_final_gate_20260724()
from public;

select *
from private.run_day5_checkout_final_gate_20260724()
order by test_name;
