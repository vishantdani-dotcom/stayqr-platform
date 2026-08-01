-- ============================================================================
-- StayQR v1.0
-- Migration: 202607240007_reservation_checkin_folio_operations
-- Day 5: Reservation Integration and Completion Gate — Foundation
--
-- PURPOSE
--   1. Convert a confirmed reservation room into an active guest stay through
--      one server-controlled transaction.
--   2. Create one room-charge demand and transfer reservation deposits into
--      payment collections exactly once and with full source traceability.
--   3. Add room-level group booking operations.
--   4. Expose hotel-scoped arrivals/departures and confirmation read models.
--   5. Synchronize reservation/room status when a linked stay is checked out.
--
-- PREREQUISITES
--   Migrations 202607200001 through 202607230006 must be applied.
--
-- SAFETY
--   Run this complete file once with role postgres. It is transactional.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607240007_reservation_checkin_folio_operations')
);

-- ============================================================================
-- 0. PREREQUISITE ASSERTIONS
-- ============================================================================

do $$
begin
  if to_regclass('public.reservations') is null
     or to_regclass('public.reservation_rooms') is null
     or to_regclass('public.reservation_payments') is null
     or to_regclass('public.room_inventory_allocations') is null
     or to_regclass('public.guest_sessions') is null
     or to_regclass('public.payments') is null
     or to_regclass('public.payment_collections') is null
     or to_regprocedure('private.assert_reservation_write_access(uuid)') is null
     or to_regprocedure('private.build_reservation_json(uuid,uuid)') is null
  then
    raise exception 'Day 5 migration stopped: Day 1–4 foundation is incomplete.';
  end if;
end
$$;

-- ============================================================================
-- 1. TRACEABLE RESERVATION → STAY / PAYMENT LINKS
-- ============================================================================

alter table public.guest_sessions
  add column if not exists checked_in_by uuid references auth.users(id) on delete set null;

alter table public.payments
  add column if not exists guest_session_id uuid,
  add column if not exists reservation_id uuid,
  add column if not exists reservation_room_id uuid;

alter table public.payment_collections
  add column if not exists guest_session_id uuid,
  add column if not exists reservation_id uuid,
  add column if not exists reservation_payment_id uuid;

create unique index if not exists uq_payments_hotel_id_id
on public.payments (hotel_id, id);

create unique index if not exists uq_payment_collections_hotel_id_id
on public.payment_collections (hotel_id, id);

-- Composite keys are already present on reservation and guest-session parents.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_guest_session_hotel_fkey'
      and conrelid = 'public.payments'::regclass
  ) then
    alter table public.payments
      add constraint payments_guest_session_hotel_fkey
      foreign key (hotel_id, guest_session_id)
      references public.guest_sessions(hotel_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_reservation_hotel_fkey'
      and conrelid = 'public.payments'::regclass
  ) then
    alter table public.payments
      add constraint payments_reservation_hotel_fkey
      foreign key (hotel_id, reservation_id)
      references public.reservations(hotel_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_reservation_room_hotel_fkey'
      and conrelid = 'public.payments'::regclass
  ) then
    alter table public.payments
      add constraint payments_reservation_room_hotel_fkey
      foreign key (hotel_id, reservation_room_id)
      references public.reservation_rooms(hotel_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'payment_collections_guest_session_hotel_fkey'
      and conrelid = 'public.payment_collections'::regclass
  ) then
    alter table public.payment_collections
      add constraint payment_collections_guest_session_hotel_fkey
      foreign key (hotel_id, guest_session_id)
      references public.guest_sessions(hotel_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'payment_collections_reservation_hotel_fkey'
      and conrelid = 'public.payment_collections'::regclass
  ) then
    alter table public.payment_collections
      add constraint payment_collections_reservation_hotel_fkey
      foreign key (hotel_id, reservation_id)
      references public.reservations(hotel_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'payment_collections_reservation_payment_hotel_fkey'
      and conrelid = 'public.payment_collections'::regclass
  ) then
    alter table public.payment_collections
      add constraint payment_collections_reservation_payment_hotel_fkey
      foreign key (hotel_id, reservation_payment_id)
      references public.reservation_payments(hotel_id, id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists uq_guest_sessions_reservation_room
on public.guest_sessions (reservation_room_id)
where reservation_room_id is not null;

create unique index if not exists uq_payments_reservation_room_charge
on public.payments (reservation_room_id)
where reservation_room_id is not null
  and payment_type = 'room_charge';

create index if not exists idx_payments_hotel_guest_session
on public.payments (hotel_id, guest_session_id, created_at);

create index if not exists idx_payment_collections_reservation_payment
on public.payment_collections (
  hotel_id,
  reservation_payment_id,
  collected_at
);

-- Each transfer is an immutable, auditable portion of one reservation deposit.
create table if not exists public.reservation_payment_transfers (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  reservation_id uuid not null,
  reservation_payment_id uuid not null,
  reservation_room_id uuid not null,
  guest_session_id uuid not null,
  payment_id uuid not null,
  payment_collection_id uuid,
  amount numeric(12,2) not null,
  transferred_by uuid references auth.users(id) on delete set null,
  transferred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint reservation_payment_transfers_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete restrict,
  constraint reservation_payment_transfers_source_fkey
    foreign key (hotel_id, reservation_payment_id)
    references public.reservation_payments(hotel_id, id)
    on delete restrict,
  constraint reservation_payment_transfers_room_fkey
    foreign key (hotel_id, reservation_room_id)
    references public.reservation_rooms(hotel_id, id)
    on delete restrict,
  constraint reservation_payment_transfers_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete restrict,
  constraint reservation_payment_transfers_payment_fkey
    foreign key (hotel_id, payment_id)
    references public.payments(hotel_id, id)
    on delete restrict,
  constraint reservation_payment_transfers_collection_fkey
    foreign key (hotel_id, payment_collection_id)
    references public.payment_collections(hotel_id, id)
    on delete restrict,
  constraint reservation_payment_transfers_amount_check
    check (amount > 0)
);

create unique index if not exists uq_reservation_payment_transfer_room
on public.reservation_payment_transfers (
  reservation_payment_id,
  reservation_room_id
);

create index if not exists idx_reservation_payment_transfers_reservation
on public.reservation_payment_transfers (
  hotel_id,
  reservation_id,
  transferred_at
);

alter table public.reservation_payment_transfers enable row level security;

drop policy if exists stayqr_reservation_payment_transfers_select
on public.reservation_payment_transfers;

create policy stayqr_reservation_payment_transfers_select
on public.reservation_payment_transfers
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

-- No browser write policy. Trusted RPCs own all transfer writes.

-- Immutable check-in event gives an idempotency and audit anchor.
create table if not exists public.reservation_checkin_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  reservation_id uuid not null,
  reservation_room_id uuid not null,
  guest_session_id uuid not null,
  room_id uuid not null,
  payment_id uuid,
  checked_in_by uuid references auth.users(id) on delete set null,
  checked_in_at timestamptz not null default now(),
  reservation_snapshot jsonb not null,
  metadata jsonb not null default '{}'::jsonb,
  constraint reservation_checkin_events_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete restrict,
  constraint reservation_checkin_events_room_record_fkey
    foreign key (hotel_id, reservation_room_id)
    references public.reservation_rooms(hotel_id, id)
    on delete restrict,
  constraint reservation_checkin_events_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete restrict,
  constraint reservation_checkin_events_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,
  constraint reservation_checkin_events_payment_fkey
    foreign key (hotel_id, payment_id)
    references public.payments(hotel_id, id)
    on delete restrict
);

create unique index if not exists uq_reservation_checkin_event_room_record
on public.reservation_checkin_events (reservation_room_id);

create unique index if not exists uq_reservation_checkin_event_session
on public.reservation_checkin_events (guest_session_id);

create index if not exists idx_reservation_checkin_events_hotel_date
on public.reservation_checkin_events (hotel_id, checked_in_at desc);

alter table public.reservation_checkin_events enable row level security;

drop policy if exists stayqr_reservation_checkin_events_select
on public.reservation_checkin_events;

create policy stayqr_reservation_checkin_events_select
on public.reservation_checkin_events
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

-- ============================================================================
-- 2. GROUP / MULTI-ROOM OPERATIONS
-- ============================================================================

create or replace function public.add_reservation_room(
  target_hotel_id uuid,
  target_reservation_id uuid,
  room_payload jsonb,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  reservation_row public.reservations%rowtype;
  room_type_row public.room_types%rowtype;
  target_room_type_id uuid;
  target_rate_plan_id uuid;
  target_room_id uuid;
  target_adults integer;
  target_children integer;
  quote jsonb;
  created_room_id uuid;
  before_json jsonb;
  after_json jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if room_payload is null then
    raise exception 'Room payload is required.';
  end if;

  select r.*
  into reservation_row
  from public.reservations r
  where r.hotel_id = target_hotel_id
    and r.id = target_reservation_id
  for update;

  if not found then raise exception 'Reservation not found.'; end if;

  if reservation_row.status not in ('draft', 'tentative', 'confirmed') then
    raise exception 'Rooms may only be added before check-in.';
  end if;

  if expected_updated_at is not null
     and reservation_row.updated_at is distinct from expected_updated_at
  then
    raise exception 'Reservation changed after it was opened. Refresh and try again.';
  end if;

  before_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  target_room_type_id := nullif(room_payload->>'room_type_id', '')::uuid;
  target_rate_plan_id := nullif(room_payload->>'rate_plan_id', '')::uuid;
  target_room_id := nullif(room_payload->>'room_id', '')::uuid;
  target_adults := coalesce(nullif(room_payload->>'adults', '')::integer, 1);
  target_children := coalesce(nullif(room_payload->>'children', '')::integer, 0);

  select rt.* into room_type_row
  from public.room_types rt
  where rt.hotel_id = target_hotel_id
    and rt.id = target_room_type_id
    and rt.is_active;

  if not found then raise exception 'Active room type not found.'; end if;

  if target_adults < 1
     or target_children < 0
     or target_adults > room_type_row.max_adults
     or target_children > room_type_row.max_children
     or target_adults + target_children > room_type_row.max_occupancy
  then
    raise exception 'Guest count exceeds the selected room capacity.';
  end if;

  if not exists (
    select 1 from public.rate_plans rp
    where rp.hotel_id = target_hotel_id
      and rp.id = target_rate_plan_id
      and rp.room_type_id = target_room_type_id
      and rp.is_active
  ) then
    raise exception 'Rate plan does not belong to the selected room type.';
  end if;

  quote := public.get_reservation_rate_quote(
    target_hotel_id,
    target_rate_plan_id,
    reservation_row.arrival_date,
    reservation_row.departure_date,
    target_adults,
    target_children
  );

  if target_room_id is not null and not exists (
    select 1
    from public.get_reservation_available_rooms(
      target_hotel_id,
      reservation_row.arrival_date,
      reservation_row.departure_date,
      target_room_type_id,
      target_reservation_id
    ) available
    where available.room_id = target_room_id
  ) then
    raise exception 'Selected room is unavailable for the reservation dates.';
  end if;

  if reservation_row.status = 'confirmed' and target_room_id is null then
    raise exception 'Confirmed reservation rooms require a physical room assignment.';
  end if;

  insert into public.reservation_rooms (
    hotel_id,
    reservation_id,
    room_type_id,
    room_id,
    rate_plan_id,
    status,
    adults,
    children,
    nightly_rate,
    room_subtotal,
    tax_amount,
    discount_amount,
    total_amount,
    notes
  )
  values (
    target_hotel_id,
    target_reservation_id,
    target_room_type_id,
    target_room_id,
    target_rate_plan_id,
    case when reservation_row.status = 'confirmed' then 'confirmed' else 'held' end,
    target_adults,
    target_children,
    (quote->>'average_nightly_rate')::numeric(12,2),
    (quote->>'room_subtotal')::numeric(12,2),
    0,
    0,
    (quote->>'total_amount')::numeric(12,2),
    nullif(trim(room_payload->>'notes'), '')
  )
  returning id into created_room_id;

  update public.reservations r
  set
    adults = totals.total_adults,
    children = totals.total_children,
    room_subtotal = totals.room_subtotal,
    tax_amount = totals.tax_amount,
    discount_amount = totals.discount_amount,
    total_amount = greatest(
      totals.room_subtotal + totals.tax_amount - totals.discount_amount,
      0
    ),
    deposit_required = least(
      r.deposit_required,
      greatest(
        totals.room_subtotal + totals.tax_amount - totals.discount_amount,
        0
      )
    ),
    updated_by = auth.uid()
  from (
    select
      sum(rr.adults)::integer as total_adults,
      sum(rr.children)::integer as total_children,
      sum(rr.room_subtotal)::numeric(12,2) as room_subtotal,
      sum(rr.tax_amount)::numeric(12,2) as tax_amount,
      sum(rr.discount_amount)::numeric(12,2) as discount_amount
    from public.reservation_rooms rr
    where rr.hotel_id = target_hotel_id
      and rr.reservation_id = target_reservation_id
      and rr.status not in ('cancelled', 'released')
  ) totals
  where r.hotel_id = target_hotel_id
    and r.id = target_reservation_id;

  after_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'reservation.room_added',
    'reservation',
    target_reservation_id,
    'A room was added to the reservation.',
    before_json,
    after_json,
    jsonb_build_object('reservation_room_id', created_room_id)
  );

  return after_json;
end;
$$;

create or replace function public.remove_reservation_room(
  target_hotel_id uuid,
  target_reservation_id uuid,
  target_reservation_room_id uuid,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  reservation_row public.reservations%rowtype;
  room_row public.reservation_rooms%rowtype;
  before_json jsonb;
  after_json jsonb;
  remaining_count integer;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  select r.* into reservation_row
  from public.reservations r
  where r.hotel_id = target_hotel_id
    and r.id = target_reservation_id
  for update;

  if not found then raise exception 'Reservation not found.'; end if;

  if reservation_row.status not in ('draft', 'tentative', 'confirmed') then
    raise exception 'Checked-in reservation rooms cannot be removed.';
  end if;

  if expected_updated_at is not null
     and reservation_row.updated_at is distinct from expected_updated_at
  then
    raise exception 'Reservation changed after it was opened. Refresh and try again.';
  end if;

  select rr.* into room_row
  from public.reservation_rooms rr
  where rr.hotel_id = target_hotel_id
    and rr.reservation_id = target_reservation_id
    and rr.id = target_reservation_room_id
  for update;

  if not found then raise exception 'Reservation room not found.'; end if;

  if room_row.status in ('checked_in', 'checked_out') then
    raise exception 'A checked-in or checked-out room cannot be removed.';
  end if;

  select count(*) into remaining_count
  from public.reservation_rooms rr
  where rr.hotel_id = target_hotel_id
    and rr.reservation_id = target_reservation_id
    and rr.id <> target_reservation_room_id
    and rr.status not in ('cancelled', 'released');

  if remaining_count < 1 then
    raise exception 'A reservation must retain at least one room.';
  end if;

  before_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  update public.reservation_rooms
  set status = 'released'
  where hotel_id = target_hotel_id
    and id = target_reservation_room_id;

  update public.reservations r
  set
    adults = totals.total_adults,
    children = totals.total_children,
    room_subtotal = totals.room_subtotal,
    tax_amount = totals.tax_amount,
    discount_amount = totals.discount_amount,
    total_amount = greatest(
      totals.room_subtotal + totals.tax_amount - totals.discount_amount,
      0
    ),
    deposit_required = least(
      r.deposit_required,
      greatest(
        totals.room_subtotal + totals.tax_amount - totals.discount_amount,
        0
      )
    ),
    updated_by = auth.uid()
  from (
    select
      sum(rr.adults)::integer as total_adults,
      sum(rr.children)::integer as total_children,
      sum(rr.room_subtotal)::numeric(12,2) as room_subtotal,
      sum(rr.tax_amount)::numeric(12,2) as tax_amount,
      sum(rr.discount_amount)::numeric(12,2) as discount_amount
    from public.reservation_rooms rr
    where rr.hotel_id = target_hotel_id
      and rr.reservation_id = target_reservation_id
      and rr.status not in ('cancelled', 'released')
  ) totals
  where r.hotel_id = target_hotel_id
    and r.id = target_reservation_id;

  after_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'reservation.room_removed',
    'reservation',
    target_reservation_id,
    'A room was released from the reservation.',
    before_json,
    after_json,
    jsonb_build_object('reservation_room_id', target_reservation_room_id)
  );

  return after_json;
end;
$$;

-- ============================================================================
-- 3. ATOMIC RESERVATION ROOM CHECK-IN
-- ============================================================================

create or replace function public.check_in_reservation_room(
  target_hotel_id uuid,
  target_reservation_id uuid,
  target_reservation_room_id uuid,
  expected_reservation_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  reservation_row public.reservations%rowtype;
  reservation_room_row public.reservation_rooms%rowtype;
  room_row public.rooms%rowtype;
  room_type_row public.room_types%rowtype;
  guest_row public.guests%rowtype;
  hotel_timezone text;
  hotel_today date;
  target_checkin_time timestamptz := now();
  target_checkout_time timestamptz;
  created_session_id uuid;
  created_payment_id uuid;
  created_collection_id uuid;
  created_transfer_id uuid;
  payment_row public.reservation_payments%rowtype;
  already_transferred numeric(12,2);
  transfer_amount numeric(12,2);
  room_credit_remaining numeric(12,2);
  transferred_total numeric(12,2) := 0;
  snapshot jsonb;
  room_count integer;
  checked_in_count integer;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  select r.* into reservation_row
  from public.reservations r
  where r.hotel_id = target_hotel_id
    and r.id = target_reservation_id
  for update;

  if not found then raise exception 'Reservation not found.'; end if;

  if expected_reservation_updated_at is not null
     and reservation_row.updated_at is distinct from expected_reservation_updated_at
  then
    raise exception 'Reservation changed after it was opened. Refresh and try again.';
  end if;

  if reservation_row.status not in ('confirmed', 'checked_in') then
    raise exception 'Only confirmed reservations may be checked in.';
  end if;

  select rr.* into reservation_room_row
  from public.reservation_rooms rr
  where rr.hotel_id = target_hotel_id
    and rr.reservation_id = target_reservation_id
    and rr.id = target_reservation_room_id
  for update;

  if not found then raise exception 'Reservation room not found.'; end if;

  if reservation_room_row.status = 'checked_in'
     or exists (
       select 1 from public.reservation_checkin_events e
       where e.hotel_id = target_hotel_id
         and e.reservation_room_id = target_reservation_room_id
     )
  then
    raise exception 'This reservation room is already checked in.';
  end if;

  if reservation_room_row.status <> 'confirmed' then
    raise exception 'The selected reservation room is not confirmed.';
  end if;

  if reservation_room_row.room_id is null then
    raise exception 'Assign a physical room before check-in.';
  end if;

  select h.timezone into hotel_timezone
  from public.hotels h
  where h.id = target_hotel_id
    and h.status = 'active';

  if hotel_timezone is null then raise exception 'Hotel timezone is missing.'; end if;

  hotel_today := (now() at time zone hotel_timezone)::date;

  if hotel_today < reservation_row.arrival_date then
    raise exception 'This reservation has not reached its arrival date.';
  end if;

  if hotel_today >= reservation_row.departure_date then
    raise exception 'This reservation is past its departure date.';
  end if;

  select rt.* into room_type_row
  from public.room_types rt
  where rt.hotel_id = target_hotel_id
    and rt.id = reservation_room_row.room_type_id;

  if not found then raise exception 'Reservation room type not found.'; end if;

  if reservation_room_row.adults > room_type_row.max_adults
     or reservation_room_row.children > room_type_row.max_children
     or reservation_room_row.adults + reservation_room_row.children > room_type_row.max_occupancy
  then
    raise exception 'Guest count exceeds room capacity.';
  end if;

  select rm.* into room_row
  from public.rooms rm
  where rm.hotel_id = target_hotel_id
    and rm.id = reservation_room_row.room_id
  for update;

  if not found then raise exception 'Assigned room not found.'; end if;

  if room_row.room_type_id <> reservation_room_row.room_type_id then
    raise exception 'Assigned room does not match the reservation room type.';
  end if;

  if room_row.status <> 'available' then
    raise exception 'Assigned room is not currently available.';
  end if;

  if not exists (
    select 1
    from public.room_inventory_allocations allocation
    where allocation.hotel_id = target_hotel_id
      and allocation.reservation_room_id = target_reservation_room_id
      and allocation.room_id = reservation_room_row.room_id
      and allocation.status = 'active'
      and allocation.starts_on = reservation_row.arrival_date
      and allocation.ends_on = reservation_row.departure_date
  ) then
    raise exception 'Authoritative room allocation is missing or stale.';
  end if;

  if exists (
    select 1 from public.guest_sessions session
    where session.hotel_id = target_hotel_id
      and session.room_id = reservation_room_row.room_id
      and session.status = 'active'
  ) then
    raise exception 'The assigned room already has an active guest stay.';
  end if;

  select g.* into guest_row
  from public.guests g
  where g.hotel_id = target_hotel_id
    and g.id = reservation_row.primary_guest_id;

  if not found then raise exception 'Primary guest profile not found.'; end if;

  target_checkout_time := (
    reservation_row.departure_date::timestamp
      + coalesce(reservation_row.expected_checkout_time, time '11:00')
  ) at time zone hotel_timezone;

  if target_checkout_time <= target_checkin_time then
    raise exception 'Calculated checkout time must be after check-in.';
  end if;

  insert into public.guest_sessions (
    hotel_id,
    room_id,
    guest_id,
    checkin_time,
    checkout_time,
    status,
    reservation_id,
    reservation_room_id,
    checked_in_by
  )
  values (
    target_hotel_id,
    reservation_room_row.room_id,
    reservation_row.primary_guest_id,
    target_checkin_time,
    target_checkout_time,
    'active',
    target_reservation_id,
    target_reservation_room_id,
    auth.uid()
  )
  returning id into created_session_id;

  insert into public.payments (
    hotel_id,
    guest_id,
    room_id,
    amount,
    payment_type,
    payment_status,
    notes,
    payment_method,
    guest_session_id,
    reservation_id,
    reservation_room_id
  )
  values (
    target_hotel_id,
    reservation_row.primary_guest_id,
    reservation_room_row.room_id,
    reservation_room_row.total_amount,
    'room_charge',
    'pending',
    format('Reservation %s · Room %s charge', reservation_row.reservation_number, room_row.room_number),
    'cash',
    created_session_id,
    target_reservation_id,
    target_reservation_room_id
  )
  returning id into created_payment_id;

  room_credit_remaining := reservation_room_row.total_amount;

  for payment_row in
    select rp.*
    from public.reservation_payments rp
    where rp.hotel_id = target_hotel_id
      and rp.reservation_id = target_reservation_id
      and rp.payment_status = 'collected'
    order by rp.collected_at, rp.id
    for update
  loop
    exit when room_credit_remaining <= 0;

    select coalesce(sum(t.amount), 0)::numeric(12,2)
    into already_transferred
    from public.reservation_payment_transfers t
    where t.hotel_id = target_hotel_id
      and t.reservation_payment_id = payment_row.id;

    transfer_amount := least(
      greatest(payment_row.amount - already_transferred, 0),
      room_credit_remaining
    )::numeric(12,2);

    if transfer_amount > 0 then
      insert into public.reservation_payment_transfers (
        hotel_id,
        reservation_id,
        reservation_payment_id,
        reservation_room_id,
        guest_session_id,
        payment_id,
        amount,
        transferred_by,
        metadata
      )
      values (
        target_hotel_id,
        target_reservation_id,
        payment_row.id,
        target_reservation_room_id,
        created_session_id,
        created_payment_id,
        transfer_amount,
        auth.uid(),
        jsonb_build_object(
          'payment_method', payment_row.payment_method,
          'transaction_reference', payment_row.transaction_reference,
          'collected_at', payment_row.collected_at
        )
      )
      returning id into created_transfer_id;

      insert into public.payment_collections (
        hotel_id,
        payment_id,
        guest_id,
        room_id,
        amount,
        payment_method,
        transaction_reference,
        notes,
        collected_by,
        collected_at,
        guest_session_id,
        reservation_id,
        reservation_payment_id
      )
      values (
        target_hotel_id,
        created_payment_id,
        reservation_row.primary_guest_id,
        reservation_room_row.room_id,
        transfer_amount,
        payment_row.payment_method,
        payment_row.transaction_reference,
        coalesce(payment_row.notes, 'Reservation deposit transferred at check-in'),
        coalesce(payment_row.collected_by, auth.uid()),
        payment_row.collected_at,
        created_session_id,
        target_reservation_id,
        payment_row.id
      )
      returning id into created_collection_id;

      update public.reservation_payment_transfers
      set payment_collection_id = created_collection_id
      where hotel_id = target_hotel_id
        and id = created_transfer_id;

      room_credit_remaining := room_credit_remaining - transfer_amount;
      transferred_total := transferred_total + transfer_amount;
    end if;
  end loop;

  update public.reservation_rooms
  set status = 'checked_in'
  where hotel_id = target_hotel_id
    and id = target_reservation_room_id;

  if reservation_row.status = 'confirmed' then
    update public.reservations
    set
      status = 'checked_in',
      updated_by = auth.uid()
    where hotel_id = target_hotel_id
      and id = target_reservation_id;
  end if;

  update public.rooms
  set status = 'occupied'
  where hotel_id = target_hotel_id
    and id = reservation_room_row.room_id;

  snapshot := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  insert into public.reservation_checkin_events (
    hotel_id,
    reservation_id,
    reservation_room_id,
    guest_session_id,
    room_id,
    payment_id,
    checked_in_by,
    reservation_snapshot,
    metadata
  )
  values (
    target_hotel_id,
    target_reservation_id,
    target_reservation_room_id,
    created_session_id,
    reservation_room_row.room_id,
    created_payment_id,
    auth.uid(),
    snapshot,
    jsonb_build_object(
      'deposit_transferred', transferred_total,
      'room_charge', reservation_room_row.total_amount
    )
  );

  perform private.write_activity_log(
    target_hotel_id,
    'reservation.room_checked_in',
    'reservation',
    target_reservation_id,
    format(
      'Reservation %s checked in to Room %s.',
      reservation_row.reservation_number,
      room_row.room_number
    ),
    null,
    snapshot,
    jsonb_build_object(
      'reservation_room_id', target_reservation_room_id,
      'guest_session_id', created_session_id,
      'payment_id', created_payment_id,
      'deposit_transferred', transferred_total
    )
  );

  select count(*)::integer,
         count(*) filter (where rr.status in ('checked_in', 'checked_out'))::integer
  into room_count, checked_in_count
  from public.reservation_rooms rr
  where rr.hotel_id = target_hotel_id
    and rr.reservation_id = target_reservation_id
    and rr.status not in ('cancelled', 'released');

  return jsonb_build_object(
    'success', true,
    'reservation_id', target_reservation_id,
    'reservation_room_id', target_reservation_room_id,
    'guest_session_id', created_session_id,
    'payment_id', created_payment_id,
    'room_id', reservation_room_row.room_id,
    'room_number', room_row.room_number,
    'deposit_transferred', transferred_total,
    'checked_in_rooms', checked_in_count,
    'total_rooms', room_count,
    'reservation', snapshot
  );
end;
$$;

-- ============================================================================
-- 4. CHECKOUT SYNCHRONIZATION FOR RESERVATION-LINKED STAYS
-- ============================================================================

create or replace function private.sync_reservation_from_guest_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  active_room_count integer;
  unfinished_room_count integer;
begin
  if new.reservation_room_id is null then return new; end if;

  if new.status = 'active' then
    update public.reservation_rooms
    set status = 'checked_in'
    where hotel_id = new.hotel_id
      and id = new.reservation_room_id
      and status = 'confirmed';

    update public.reservations
    set status = 'checked_in'
    where hotel_id = new.hotel_id
      and id = new.reservation_id
      and status = 'confirmed';

    update public.rooms
    set status = 'occupied'
    where hotel_id = new.hotel_id
      and id = new.room_id;

    return new;
  end if;

  if old.status = 'active' and new.status in ('completed', 'checked_out', 'expired') then
    update public.reservation_rooms
    set status = 'checked_out'
    where hotel_id = new.hotel_id
      and id = new.reservation_room_id
      and status = 'checked_in';

    update public.rooms
    set status = 'cleaning'
    where hotel_id = new.hotel_id
      and id = new.room_id
      and status = 'occupied';

    select
      count(*) filter (where rr.status = 'checked_in')::integer,
      count(*) filter (where rr.status not in ('checked_out', 'cancelled', 'released'))::integer
    into active_room_count, unfinished_room_count
    from public.reservation_rooms rr
    where rr.hotel_id = new.hotel_id
      and rr.reservation_id = new.reservation_id;

    if active_room_count = 0 and unfinished_room_count = 0 then
      update public.reservations
      set status = 'checked_out'
      where hotel_id = new.hotel_id
        and id = new.reservation_id
        and status = 'checked_in';
    end if;

    perform private.write_activity_log(
      new.hotel_id,
      'reservation.room_checked_out',
      'reservation',
      new.reservation_id,
      'A reservation room completed checkout.',
      jsonb_build_object('guest_session_status', old.status),
      jsonb_build_object('guest_session_status', new.status),
      jsonb_build_object(
        'reservation_room_id', new.reservation_room_id,
        'guest_session_id', new.id,
        'room_id', new.room_id
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists guest_sessions_sync_reservation_status
on public.guest_sessions;

create trigger guest_sessions_sync_reservation_status
after insert or update of status
on public.guest_sessions
for each row
execute function private.sync_reservation_from_guest_session();

-- ============================================================================
-- 5. OPERATIONAL READ MODELS
-- ============================================================================

create or replace function public.get_reservation_operations(
  target_hotel_id uuid,
  target_date date default current_date,
  upcoming_days integer default 7
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Reservation operations access denied.';
  end if;

  if target_date is null then target_date := current_date; end if;
  upcoming_days := greatest(1, least(coalesce(upcoming_days, 7), 31));

  with room_rows as (
    select
      r.id as reservation_id,
      r.reservation_number,
      r.status as reservation_status,
      r.arrival_date,
      r.departure_date,
      r.expected_checkin_time,
      r.expected_checkout_time,
      r.primary_guest_id,
      g.full_name as guest_name,
      g.phone as guest_phone,
      rr.id as reservation_room_id,
      rr.status as room_status,
      rr.room_id,
      rm.room_number,
      rt.name as room_type,
      rr.adults,
      rr.children,
      rr.total_amount,
      r.deposit_collected,
      r.updated_at,
      gs.id as guest_session_id,
      gs.status as guest_session_status,
      gs.checkin_time,
      gs.checkout_time
    from public.reservations r
    join public.reservation_rooms rr
      on rr.hotel_id = r.hotel_id
     and rr.reservation_id = r.id
     and rr.status not in ('cancelled', 'released')
    left join public.guests g
      on g.hotel_id = r.hotel_id
     and g.id = r.primary_guest_id
    left join public.rooms rm
      on rm.hotel_id = rr.hotel_id
     and rm.id = rr.room_id
    join public.room_types rt
      on rt.hotel_id = rr.hotel_id
     and rt.id = rr.room_type_id
    left join public.guest_sessions gs
      on gs.hotel_id = rr.hotel_id
     and gs.reservation_room_id = rr.id
    where r.hotel_id = target_hotel_id
  ), item_rows as (
    select jsonb_build_object(
      'reservation_id', reservation_id,
      'reservation_number', reservation_number,
      'reservation_status', reservation_status,
      'arrival_date', arrival_date,
      'departure_date', departure_date,
      'expected_checkin_time', expected_checkin_time,
      'expected_checkout_time', expected_checkout_time,
      'guest_id', primary_guest_id,
      'guest_name', guest_name,
      'guest_phone', guest_phone,
      'reservation_room_id', reservation_room_id,
      'room_status', room_status,
      'room_id', room_id,
      'room_number', room_number,
      'room_type', room_type,
      'adults', adults,
      'children', children,
      'total_amount', total_amount,
      'deposit_collected', deposit_collected,
      'updated_at', updated_at,
      'guest_session_id', guest_session_id,
      'guest_session_status', guest_session_status,
      'checkin_time', checkin_time,
      'checkout_time', checkout_time
    ) as item,
    *
    from room_rows
  )
  select jsonb_build_object(
    'hotel_id', target_hotel_id,
    'business_date', target_date,
    'today_arrivals', coalesce((
      select jsonb_agg(item order by expected_checkin_time nulls last, reservation_number)
      from item_rows
      where arrival_date = target_date
        and reservation_status = 'confirmed'
        and room_status = 'confirmed'
    ), '[]'::jsonb),
    'upcoming_arrivals', coalesce((
      select jsonb_agg(item order by arrival_date, expected_checkin_time nulls last)
      from item_rows
      where arrival_date > target_date
        and arrival_date <= target_date + upcoming_days
        and reservation_status = 'confirmed'
        and room_status = 'confirmed'
    ), '[]'::jsonb),
    'today_departures', coalesce((
      select jsonb_agg(item order by expected_checkout_time nulls last, room_number)
      from item_rows
      where departure_date = target_date
        and room_status = 'checked_in'
    ), '[]'::jsonb),
    'in_house', coalesce((
      select jsonb_agg(item order by room_number)
      from item_rows
      where room_status = 'checked_in'
        and guest_session_status = 'active'
    ), '[]'::jsonb),
    'unallocated_arrivals', coalesce((
      select jsonb_agg(item order by arrival_date, reservation_number)
      from item_rows
      where room_id is null
        and arrival_date <= target_date + upcoming_days
        and reservation_status in ('tentative', 'confirmed')
    ), '[]'::jsonb),
    'overdue_arrivals', coalesce((
      select jsonb_agg(item order by arrival_date, reservation_number)
      from item_rows
      where arrival_date < target_date
        and reservation_status = 'confirmed'
        and room_status = 'confirmed'
        and guest_session_id is null
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

create or replace function public.get_reservation_confirmation(
  target_hotel_id uuid,
  target_reservation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  hotel_json jsonb;
  reservation_json jsonb;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Reservation confirmation access denied.';
  end if;

  select jsonb_build_object(
    'id', h.id,
    'hotel_name', h.hotel_name,
    'email', h.email,
    'phone', h.phone,
    'address', h.address,
    'city', h.city,
    'state', h.state,
    'location', h.location,
    'logo_url', h.logo_url,
    'website', h.website,
    'gst_number', h.gst_number,
    'currency_code', h.currency_code,
    'timezone', h.timezone,
    'invoice_terms', h.invoice_terms,
    'invoice_footer', h.invoice_footer
  ) into hotel_json
  from public.hotels h
  where h.id = target_hotel_id;

  if hotel_json is null then raise exception 'Hotel not found.'; end if;

  reservation_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  if reservation_json is null then raise exception 'Reservation not found.'; end if;

  return jsonb_build_object(
    'generated_at', now(),
    'hotel', hotel_json,
    'reservation', reservation_json
  );
end;
$$;

-- ============================================================================
-- 6. PRIVILEGES
-- ============================================================================

revoke all on function public.add_reservation_room(uuid,uuid,jsonb,timestamptz)
from public;
grant execute on function public.add_reservation_room(uuid,uuid,jsonb,timestamptz)
to authenticated;

revoke all on function public.remove_reservation_room(uuid,uuid,uuid,timestamptz)
from public;
grant execute on function public.remove_reservation_room(uuid,uuid,uuid,timestamptz)
to authenticated;

revoke all on function public.check_in_reservation_room(uuid,uuid,uuid,timestamptz)
from public;
grant execute on function public.check_in_reservation_room(uuid,uuid,uuid,timestamptz)
to authenticated;

revoke all on function public.get_reservation_operations(uuid,date,integer)
from public;
grant execute on function public.get_reservation_operations(uuid,date,integer)
to authenticated;

revoke all on function public.get_reservation_confirmation(uuid,uuid)
from public;
grant execute on function public.get_reservation_confirmation(uuid,uuid)
to authenticated;

revoke all on function private.sync_reservation_from_guest_session()
from public;

commit;

-- Supabase may show one blank pg_advisory_xact_lock row. That is expected.
