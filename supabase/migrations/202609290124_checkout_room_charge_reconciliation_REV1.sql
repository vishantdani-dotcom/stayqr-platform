begin;

-- StayQR Checkout Room-Charge Reconciliation REV1 / Migration 124
-- Purpose:
-- * Make the final checkout bill reconcile the posted room charge against the
--   actual elapsed stay before invoice issuance.
-- * Preserve the hotel's confirmed final amount; never silently overwrite it.
-- * Keep the legacy payments room-charge source and authoritative folio in sync
--   through the existing payments_day11_folio_sync trigger.
-- * Record an immutable audit event for every room-charge change.

create table if not exists public.guest_session_room_charge_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid not null,
  payment_id uuid not null,
  idempotency_key text not null,
  previous_room_charge numeric(12,2) not null,
  suggested_room_charge numeric(12,2) not null,
  final_room_charge numeric(12,2) not null,
  agreed_nightly_rate numeric(12,2) not null default 0,
  billable_nights integer not null,
  stay_hours integer not null,
  adjustment_reason text,
  result_snapshot jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now(),
  constraint guest_session_room_charge_events_hotel_request_unique
    unique (hotel_id, idempotency_key),
  constraint guest_session_room_charge_events_amounts_check check (
    previous_room_charge >= 0
    and suggested_room_charge >= 0
    and final_room_charge >= 0
    and agreed_nightly_rate >= 0
  ),
  constraint guest_session_room_charge_events_duration_check check (
    billable_nights >= 1 and stay_hours >= 1
  ),
  constraint guest_session_room_charge_events_request_check check (
    length(trim(idempotency_key)) >= 8
  ),
  constraint guest_session_room_charge_events_reason_check check (
    adjustment_reason is null
    or (length(trim(adjustment_reason)) >= 3 and length(trim(adjustment_reason)) <= 240)
  ),
  constraint guest_session_room_charge_events_hotel_fkey
    foreign key (hotel_id) references public.hotels(id) on delete restrict,
  constraint guest_session_room_charge_events_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id) on delete cascade,
  constraint guest_session_room_charge_events_payment_fkey
    foreign key (payment_id) references public.payments(id) on delete restrict,
  constraint guest_session_room_charge_events_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete set null
);

create index if not exists idx_guest_session_room_charge_events_session_created
  on public.guest_session_room_charge_events (hotel_id, guest_session_id, created_at desc);

alter table public.guest_session_room_charge_events enable row level security;

drop policy if exists stayqr_checkout_room_charge_events_select
  on public.guest_session_room_charge_events;

create policy stayqr_checkout_room_charge_events_select
  on public.guest_session_room_charge_events
  for select
  to authenticated
  using (
    private.user_has_any_permission(
      hotel_id,
      array[
        'guests.view'::text,
        'guests.manage'::text,
        'payments.view'::text,
        'payments.manage'::text,
        'checkout.manage'::text
      ]
    )
  );

revoke all on table public.guest_session_room_charge_events from public, anon, authenticated;
grant select on table public.guest_session_room_charge_events to authenticated;
grant all on table public.guest_session_room_charge_events to service_role;

create or replace function public.reconcile_active_stay_room_charge(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  session_row public.guest_sessions%rowtype;
  payment_row public.payments%rowtype;
  existing_event public.guest_session_room_charge_events%rowtype;
  request_id_value text;
  adjustment_reason_value text;
  expected_current_room_charge_value numeric(12,2);
  suggested_room_charge_value numeric(12,2);
  final_room_charge_value numeric(12,2);
  agreed_nightly_rate_value numeric(12,2);
  billable_nights_value integer;
  stay_hours_value integer;
  room_charge_changed boolean;
  folio_charges_amount_value numeric(14,2) := 0;
  folio_balance_amount_value numeric(14,2) := 0;
  result_value jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if target_guest_session_id is null then
    raise exception 'Guest session is required.';
  end if;

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Room-charge reconciliation payload must be a JSON object.';
  end if;

  request_id_value := nullif(trim(payload ->> 'request_id'), '');
  adjustment_reason_value := nullif(trim(payload ->> 'adjustment_reason'), '');

  if request_id_value is null or length(request_id_value) < 8 then
    raise exception 'A stable request_id of at least 8 characters is required.';
  end if;

  if adjustment_reason_value is not null and length(adjustment_reason_value) > 240 then
    raise exception 'Room-charge adjustment reason is too long.';
  end if;

  begin
    expected_current_room_charge_value := round(coalesce((payload ->> 'expected_current_room_charge')::numeric, 0), 2);
    suggested_room_charge_value := round(coalesce((payload ->> 'suggested_room_charge')::numeric, 0), 2);
    final_room_charge_value := round(coalesce((payload ->> 'final_room_charge')::numeric, 0), 2);
    agreed_nightly_rate_value := round(coalesce((payload ->> 'agreed_nightly_rate')::numeric, 0), 2);
    billable_nights_value := greatest(coalesce((payload ->> 'billable_nights')::integer, 1), 1);
    stay_hours_value := greatest(coalesce((payload ->> 'stay_hours')::integer, 1), 1);
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Room-charge reconciliation values are invalid.';
  end;

  if expected_current_room_charge_value < 0
     or suggested_room_charge_value < 0
     or final_room_charge_value < 0
     or agreed_nightly_rate_value < 0
  then
    raise exception 'Room-charge values cannot be negative.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:checkout-room-charge:'
      || target_hotel_id::text
      || ':'
      || target_guest_session_id::text,
      0
    )
  );

  select event.*
  into existing_event
  from public.guest_session_room_charge_events event
  where event.hotel_id = target_hotel_id
    and event.idempotency_key = request_id_value
  limit 1;

  if existing_event.id is not null then
    return coalesce(existing_event.result_snapshot, '{}'::jsonb)
      || jsonb_build_object('idempotent', true);
  end if;

  select session.*
  into session_row
  from public.guest_sessions session
  where session.hotel_id = target_hotel_id
    and session.id = target_guest_session_id
  for update;

  if not found then
    raise exception 'Guest stay not found.';
  end if;

  if session_row.status <> 'active' then
    raise exception 'Only an active guest stay can have its room charge reconciled.';
  end if;

  if exists (
    select 1
    from public.invoices invoice
    where invoice.hotel_id = target_hotel_id
      and invoice.guest_session_id = target_guest_session_id
  ) then
    raise exception 'An invoice already exists for this stay. Adjust the issued bill through Guest Bills.';
  end if;

  select payment.*
  into payment_row
  from public.payments payment
  where payment.hotel_id = target_hotel_id
    and payment.guest_session_id = target_guest_session_id
    and payment.payment_type = 'room_charge'
  order by payment.created_at, payment.id
  limit 1
  for update;

  if not found then
    raise exception 'The active stay does not have an authoritative room-charge record.';
  end if;

  if abs(round(coalesce(payment_row.amount, 0)::numeric, 2) - expected_current_room_charge_value) >= 0.01 then
    raise exception 'The room charge changed after checkout was opened. Reopen checkout and review the latest bill.';
  end if;

  room_charge_changed :=
    abs(final_room_charge_value - expected_current_room_charge_value) >= 0.01;

  if room_charge_changed and adjustment_reason_value is null then
    raise exception 'A room-charge adjustment reason is required when the final amount changes.';
  end if;

  if room_charge_changed then
    update public.payments
    set amount = final_room_charge_value
    where id = payment_row.id
      and hotel_id = target_hotel_id;
  end if;

  -- The existing payments_day11_folio_sync AFTER trigger updates the matching
  -- folio item and recalculates the folio before these values are read.
  select
    coalesce(folio.charges_amount, 0),
    coalesce(folio.balance_amount, 0)
  into folio_charges_amount_value, folio_balance_amount_value
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and folio.guest_session_id = target_guest_session_id
  limit 1;

  result_value := jsonb_build_object(
    'success', true,
    'idempotent', false,
    'hotel_id', target_hotel_id,
    'guest_session_id', target_guest_session_id,
    'payment_id', payment_row.id,
    'previous_room_charge', expected_current_room_charge_value,
    'suggested_room_charge', suggested_room_charge_value,
    'current_room_charge', final_room_charge_value,
    'agreed_nightly_rate', agreed_nightly_rate_value,
    'billable_nights', billable_nights_value,
    'stay_hours', stay_hours_value,
    'room_charge_changed', room_charge_changed,
    'adjustment_reason', adjustment_reason_value,
    'folio_charges_amount', folio_charges_amount_value,
    'folio_balance_amount', folio_balance_amount_value
  );

  insert into public.guest_session_room_charge_events (
    hotel_id,
    guest_session_id,
    payment_id,
    idempotency_key,
    previous_room_charge,
    suggested_room_charge,
    final_room_charge,
    agreed_nightly_rate,
    billable_nights,
    stay_hours,
    adjustment_reason,
    result_snapshot,
    created_by
  )
  values (
    target_hotel_id,
    target_guest_session_id,
    payment_row.id,
    request_id_value,
    expected_current_room_charge_value,
    suggested_room_charge_value,
    final_room_charge_value,
    agreed_nightly_rate_value,
    billable_nights_value,
    stay_hours_value,
    adjustment_reason_value,
    result_value,
    auth.uid()
  );

  perform private.write_activity_log(
    target_hotel_id,
    'checkout.room_charge_reconciled',
    'guest_session',
    target_guest_session_id,
    case
      when room_charge_changed then
        format(
          'Room charge adjusted from INR %s to INR %s before checkout.',
          expected_current_room_charge_value,
          final_room_charge_value
        )
      else
        format('Room charge INR %s confirmed before checkout.', final_room_charge_value)
    end,
    jsonb_build_object(
      'room_charge', expected_current_room_charge_value
    ),
    jsonb_build_object(
      'room_charge', final_room_charge_value
    ),
    jsonb_build_object(
      'request_id', request_id_value,
      'suggested_room_charge', suggested_room_charge_value,
      'agreed_nightly_rate', agreed_nightly_rate_value,
      'billable_nights', billable_nights_value,
      'stay_hours', stay_hours_value,
      'adjustment_reason', adjustment_reason_value
    )
  );

  return result_value;
end;
$function$;

revoke all on function public.reconcile_active_stay_room_charge(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.reconcile_active_stay_room_charge(uuid, uuid, jsonb)
  to authenticated, service_role;

comment on function public.reconcile_active_stay_room_charge(uuid, uuid, jsonb) is
  'Atomically confirms or adjusts the active stay room charge before invoice issuance, synchronizing the legacy payment into the authoritative folio and preserving an immutable audit event.';

commit;
