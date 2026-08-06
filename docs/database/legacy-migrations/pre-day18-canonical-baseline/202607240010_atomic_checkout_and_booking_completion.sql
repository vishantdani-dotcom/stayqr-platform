-- ============================================================================
-- StayQR v1.0
-- Migration: 202607240010_atomic_checkout_and_booking_completion
-- Day 5 closure: atomic booking-to-checkout transaction
--
-- PURPOSE
--   1. Replace the browser-side multi-request checkout with one transaction.
--   2. Create the paid invoice, line items and remaining collection exactly once.
--   3. Complete the guest session, expire guest access, advance linked
--      reservation/room status, send the room to cleaning and create one task.
--   4. Preserve an immutable checkout event for idempotency and audit.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607240010_atomic_checkout_and_booking_completion')
);

-- --------------------------------------------------------------------------
-- 0. Prerequisite assertions
-- --------------------------------------------------------------------------

do $$
begin
  if to_regclass('public.guest_sessions') is null
     or to_regclass('public.invoices') is null
     or to_regclass('public.invoice_items') is null
     or to_regclass('public.payments') is null
     or to_regclass('public.payment_collections') is null
     or to_regclass('public.housekeeping_tasks') is null
     or to_regprocedure('private.assert_reservation_write_access(uuid)') is null
     or to_regprocedure('private.build_reservation_json(uuid,uuid)') is null
     or to_regprocedure('private.write_activity_log(uuid,text,text,uuid,text,jsonb,jsonb,jsonb)') is null
  then
    raise exception 'Day 5 checkout migration stopped: the Day 1-5 foundation is incomplete.';
  end if;
end
$$;

-- --------------------------------------------------------------------------
-- 1. Checkout trace fields and immutable event
-- --------------------------------------------------------------------------

alter table public.guest_sessions
  add column if not exists checked_out_at timestamptz,
  add column if not exists checked_out_by uuid references auth.users(id) on delete set null;

create table if not exists public.reservation_checkout_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  guest_session_id uuid not null,
  reservation_id uuid,
  reservation_room_id uuid,
  room_id uuid not null,
  guest_id uuid not null,
  invoice_id uuid not null,
  checked_out_by uuid references auth.users(id) on delete set null,
  checked_out_at timestamptz not null default now(),
  settlement_snapshot jsonb not null,
  metadata jsonb not null default '{}'::jsonb,
  constraint reservation_checkout_events_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete restrict,
  constraint reservation_checkout_events_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete restrict,
  constraint reservation_checkout_events_reservation_room_fkey
    foreign key (hotel_id, reservation_room_id)
    references public.reservation_rooms(hotel_id, id)
    on delete restrict,
  constraint reservation_checkout_events_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,
  constraint reservation_checkout_events_invoice_fkey
    foreign key (invoice_id)
    references public.invoices(id)
    on delete restrict
);

create unique index if not exists uq_reservation_checkout_events_session
on public.reservation_checkout_events (guest_session_id);

create index if not exists idx_reservation_checkout_events_hotel_created
on public.reservation_checkout_events (hotel_id, checked_out_at desc);

alter table public.reservation_checkout_events enable row level security;

drop policy if exists stayqr_reservation_checkout_events_select
on public.reservation_checkout_events;

create policy stayqr_reservation_checkout_events_select
on public.reservation_checkout_events
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

-- No browser write policy. The atomic RPC owns checkout-event writes.

-- --------------------------------------------------------------------------
-- 2. Server-side atomic checkout
-- --------------------------------------------------------------------------

create or replace function public.checkout_guest_session(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  tax_percent numeric default 0,
  discount_type text default 'fixed',
  discount_value numeric default 0,
  remaining_payment_collected boolean default false,
  settlement_payment_method text default 'cash',
  settlement_transaction_reference text default null,
  invoice_notes text default null,
  allow_excess_paid boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_row public.guest_sessions%rowtype;
  room_row public.rooms%rowtype;
  guest_row public.guests%rowtype;
  existing_event public.reservation_checkout_events%rowtype;
  existing_invoice public.invoices%rowtype;
  payment_row public.payments%rowtype;
  stay_end timestamptz := now();
  stay_hours integer;
  stay_nights integer;
  safe_tax_percent numeric(12,2);
  safe_discount_value numeric(12,2);
  room_amount numeric(12,2) := 0;
  food_amount numeric(12,2) := 0;
  manual_amount numeric(12,2) := 0;
  service_amount numeric(12,2) := 0;
  subtotal numeric(12,2) := 0;
  tax_amount numeric(12,2) := 0;
  discount_amount numeric(12,2) := 0;
  grand_total numeric(12,2) := 0;
  previously_paid numeric(12,2) := 0;
  amount_to_collect numeric(12,2) := 0;
  excess_paid numeric(12,2) := 0;
  amount_remaining numeric(12,2) := 0;
  payment_collected numeric(12,2) := 0;
  payment_balance numeric(12,2) := 0;
  collection_amount numeric(12,2) := 0;
  created_invoice_id uuid;
  created_invoice_number text;
  settlement_payment_id uuid;
  housekeeping_task_id uuid;
  reservation_snapshot jsonb;
  checkout_snapshot jsonb;
  open_food_count integer := 0;
  food_order_count integer := 0;
  food_item_count integer := 0;
  actor_id uuid := auth.uid();
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if target_guest_session_id is null then
    raise exception 'Guest session is required.';
  end if;

  safe_tax_percent := round(coalesce(tax_percent, 0)::numeric, 2);
  safe_discount_value := round(coalesce(discount_value, 0)::numeric, 2);
  discount_type := lower(trim(coalesce(discount_type, 'fixed')));
  settlement_payment_method := lower(trim(coalesce(settlement_payment_method, 'cash')));

  if safe_tax_percent < 0 or safe_tax_percent > 100 then
    raise exception 'Tax percentage must be between 0 and 100.';
  end if;

  if discount_type not in ('fixed', 'percentage') then
    raise exception 'Discount type must be fixed or percentage.';
  end if;

  if safe_discount_value < 0 then
    raise exception 'Discount value cannot be negative.';
  end if;

  if discount_type = 'percentage' and safe_discount_value > 100 then
    raise exception 'Discount percentage cannot exceed 100%%.';
  end if;

  if settlement_payment_method not in ('cash', 'upi', 'card', 'bank_transfer', 'other') then
    raise exception 'Unsupported settlement payment method.';
  end if;

  if settlement_payment_method in ('upi', 'card', 'bank_transfer')
     and length(trim(coalesce(settlement_transaction_reference, ''))) = 0
  then
    raise exception 'A transaction/reference number is required for this payment method.';
  end if;

  select gs.*
  into session_row
  from public.guest_sessions gs
  where gs.hotel_id = target_hotel_id
    and gs.id = target_guest_session_id
  for update;

  if not found then
    raise exception 'Guest stay not found.';
  end if;

  select event.*
  into existing_event
  from public.reservation_checkout_events event
  where event.hotel_id = target_hotel_id
    and event.guest_session_id = target_guest_session_id
  limit 1;

  if existing_event.id is not null then
    select inv.* into existing_invoice
    from public.invoices inv
    where inv.id = existing_event.invoice_id;

    raise exception 'This stay is already checked out. Invoice: %',
      coalesce(existing_invoice.invoice_number, existing_event.invoice_id::text);
  end if;

  if session_row.status <> 'active' then
    raise exception 'Only an active guest stay can be checked out.';
  end if;

  if session_row.checkin_time is null then
    raise exception 'Guest check-in time is missing.';
  end if;

  select rm.* into room_row
  from public.rooms rm
  where rm.hotel_id = target_hotel_id
    and rm.id = session_row.room_id
  for update;

  if not found then raise exception 'Stay room not found.'; end if;

  select g.* into guest_row
  from public.guests g
  where g.hotel_id = target_hotel_id
    and g.id = session_row.guest_id
  for update;

  if not found then raise exception 'Stay guest not found.'; end if;

  select inv.* into existing_invoice
  from public.invoices inv
  where inv.hotel_id = target_hotel_id
    and inv.guest_session_id = target_guest_session_id
  order by inv.created_at
  limit 1
  for update;

  if existing_invoice.id is not null then
    raise exception 'Invoice already exists for this stay: %',
      coalesce(existing_invoice.invoice_number, existing_invoice.id::text);
  end if;

  select count(*)::integer
  into open_food_count
  from public.food_orders fo
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.created_at >= session_row.checkin_time
    and fo.order_status in ('pending', 'accepted', 'preparing', 'out_for_delivery');

  if open_food_count > 0 then
    raise exception '% food order(s) are still active. Complete or cancel them before checkout.', open_food_count;
  end if;

  stay_hours := greatest(
    1,
    ceil(extract(epoch from (stay_end - session_row.checkin_time)) / 3600.0)::integer
  );
  stay_nights := greatest(1, ceil(stay_hours / 24.0)::integer);

  -- Reservation-linked payments are exact. Legacy/direct stays fall back to
  -- same hotel + guest + room + stay window.
  select coalesce(sum(p.amount), 0)::numeric(12,2)
  into room_amount
  from public.payments p
  where p.hotel_id = target_hotel_id
    and p.guest_id = session_row.guest_id
    and p.room_id = session_row.room_id
    and p.payment_type = 'room_charge'
    and (
      p.guest_session_id = target_guest_session_id
      or (
        p.guest_session_id is null
        and p.created_at >= session_row.checkin_time
      )
    );

  select
    coalesce(sum(fo.total_amount), 0)::numeric(12,2),
    count(*)::integer
  into food_amount, food_order_count
  from public.food_orders fo
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.order_status = 'delivered'
    and fo.created_at >= session_row.checkin_time;

  select coalesce(sum(foi.quantity), 0)::integer
  into food_item_count
  from public.food_orders fo
  join public.food_order_items foi
    on foi.order_id = fo.id
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.order_status = 'delivered'
    and fo.created_at >= session_row.checkin_time;

  select coalesce(sum(mc.charge_amount), 0)::numeric(12,2)
  into manual_amount
  from public.manual_charges mc
  where mc.hotel_id = target_hotel_id
    and mc.guest_id = session_row.guest_id
    and mc.room_id = session_row.room_id
    and mc.created_at >= session_row.checkin_time;

  -- service_requests currently has no mandatory monetary column. Reading via
  -- to_jsonb preserves compatibility if a charge field is added later.
  select coalesce(sum(
    coalesce(
      nullif(to_jsonb(sr)->>'service_amount', '')::numeric,
      nullif(to_jsonb(sr)->>'charge_amount', '')::numeric,
      nullif(to_jsonb(sr)->>'amount', '')::numeric,
      0
    )
  ), 0)::numeric(12,2)
  into service_amount
  from public.service_requests sr
  where sr.hotel_id = target_hotel_id
    and sr.guest_id = session_row.guest_id
    and sr.room_id = session_row.room_id
    and sr.status = 'completed'
    and sr.created_at >= session_row.checkin_time;

  subtotal := round(room_amount + food_amount + manual_amount + service_amount, 2);
  tax_amount := round(subtotal * safe_tax_percent / 100.0, 2);

  if discount_type = 'percentage' then
    discount_amount := round((subtotal + tax_amount) * safe_discount_value / 100.0, 2);
  else
    discount_amount := safe_discount_value;
  end if;

  discount_amount := least(subtotal + tax_amount, discount_amount);
  grand_total := greatest(round(subtotal + tax_amount - discount_amount, 2), 0);

  select coalesce(sum(paid_amount_value), 0)::numeric(12,2)
  into previously_paid
  from (
    select pc.amount as paid_amount_value
    from public.payment_collections pc
    join public.payments p
      on p.hotel_id = pc.hotel_id
     and p.id = pc.payment_id
    where pc.hotel_id = target_hotel_id
      and p.guest_id = session_row.guest_id
      and p.room_id = session_row.room_id
      and (
        p.guest_session_id = target_guest_session_id
        or (
          p.guest_session_id is null
          and p.created_at >= session_row.checkin_time
        )
      )

    union all

    select p.amount
    from public.payments p
    where p.hotel_id = target_hotel_id
      and p.guest_id = session_row.guest_id
      and p.room_id = session_row.room_id
      and p.payment_status = 'paid'
      and (
        p.guest_session_id = target_guest_session_id
        or (
          p.guest_session_id is null
          and p.created_at >= session_row.checkin_time
        )
      )
      and not exists (
        select 1
        from public.payment_collections pc
        where pc.hotel_id = p.hotel_id
          and pc.payment_id = p.id
      )
  ) paid_rows;

  amount_to_collect := greatest(round(grand_total - previously_paid, 2), 0);
  excess_paid := greatest(round(previously_paid - grand_total, 2), 0);

  if amount_to_collect > 0 and not coalesce(remaining_payment_collected, false) then
    raise exception 'Confirm collection of the remaining amount before checkout.';
  end if;

  if excess_paid > 0 and not coalesce(allow_excess_paid, false) then
    raise exception 'Previous payments exceed the final bill by %. Verify refund/adjustment before checkout.', excess_paid;
  end if;

  created_invoice_number := format(
    'INV-%s-%s',
    to_char(stay_end at time zone 'UTC', 'YYYYMMDD'),
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
  );

  insert into public.invoices (
    hotel_id,
    guest_session_id,
    room_id,
    guest_id,
    invoice_number,
    room_amount,
    food_amount,
    manual_amount,
    service_amount,
    subtotal_amount,
    tax_percent,
    tax_amount,
    discount_type,
    discount_value,
    discount_amount,
    previous_paid_amount,
    amount_to_collect,
    total_amount,
    payment_status,
    invoice_status,
    paid_amount,
    pending_amount,
    settled_at,
    checkin_time,
    checkout_time,
    stay_hours,
    stay_nights,
    food_order_count,
    food_item_count,
    invoice_notes
  ) values (
    target_hotel_id,
    target_guest_session_id,
    session_row.room_id,
    session_row.guest_id,
    created_invoice_number,
    room_amount,
    food_amount,
    manual_amount,
    service_amount,
    subtotal,
    safe_tax_percent,
    tax_amount,
    discount_type,
    safe_discount_value,
    discount_amount,
    previously_paid,
    amount_to_collect,
    grand_total,
    'paid',
    'paid',
    grand_total,
    0,
    stay_end,
    session_row.checkin_time,
    stay_end,
    stay_hours,
    stay_nights,
    food_order_count,
    food_item_count,
    nullif(trim(coalesce(invoice_notes, '')), '')
  ) returning id into created_invoice_id;

  if room_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'room',
      format('%s · %s night(s)', coalesce(room_row.room_type, 'Hotel Room'), stay_nights),
      stay_nights,
      case when stay_nights > 0 then round(room_amount / stay_nights, 2) else room_amount end,
      room_amount,
      target_guest_session_id
    );
  end if;

  insert into public.invoice_items (
    invoice_id, hotel_id, guest_id, room_id,
    item_type, description, quantity, unit_price, amount, source_id
  )
  select
    created_invoice_id,
    target_hotel_id,
    session_row.guest_id,
    session_row.room_id,
    'food',
    coalesce(mi.item_name, 'Food Item'),
    foi.quantity,
    foi.price,
    round(foi.quantity * foi.price, 2),
    fo.id
  from public.food_orders fo
  join public.food_order_items foi
    on foi.order_id = fo.id
  left join public.menu_items mi
    on mi.id = foi.menu_item_id
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.order_status = 'delivered'
    and fo.created_at >= session_row.checkin_time
    and foi.quantity > 0
    and foi.price > 0;

  insert into public.invoice_items (
    invoice_id, hotel_id, guest_id, room_id,
    item_type, description, quantity, unit_price, amount, source_id
  )
  select
    created_invoice_id,
    target_hotel_id,
    session_row.guest_id,
    session_row.room_id,
    'manual_charge',
    coalesce(mc.charge_name, 'Additional Charge'),
    1,
    mc.charge_amount,
    mc.charge_amount,
    mc.id
  from public.manual_charges mc
  where mc.hotel_id = target_hotel_id
    and mc.guest_id = session_row.guest_id
    and mc.room_id = session_row.room_id
    and mc.created_at >= session_row.checkin_time
    and mc.charge_amount > 0;

  if service_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'service',
      'Completed hotel services',
      1,
      service_amount,
      service_amount,
      null
    );
  end if;

  if tax_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'tax',
      format('Tax %s%%', safe_tax_percent),
      1,
      tax_amount,
      tax_amount,
      null
    );
  end if;

  if discount_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'discount',
      case
        when discount_type = 'percentage' then format('Discount %s%%', safe_discount_value)
        else 'Fixed Discount'
      end,
      1,
      -discount_amount,
      -discount_amount,
      null
    );
  end if;

  -- Record the newly collected balance against existing payment demands first.
  amount_remaining := amount_to_collect;

  for payment_row in
    select p.*
    from public.payments p
    where p.hotel_id = target_hotel_id
      and p.guest_id = session_row.guest_id
      and p.room_id = session_row.room_id
      and (
        p.guest_session_id = target_guest_session_id
        or (
          p.guest_session_id is null
          and p.created_at >= session_row.checkin_time
        )
      )
    order by p.created_at, p.id
    for update
  loop
    select coalesce(sum(pc.amount), 0)::numeric(12,2)
    into payment_collected
    from public.payment_collections pc
    where pc.hotel_id = target_hotel_id
      and pc.payment_id = payment_row.id;

    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);
    collection_amount := least(amount_remaining, payment_balance);

    if collection_amount > 0 then
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
        invoice_id
      ) values (
        target_hotel_id,
        payment_row.id,
        session_row.guest_id,
        session_row.room_id,
        collection_amount,
        settlement_payment_method,
        nullif(trim(coalesce(settlement_transaction_reference, '')), ''),
        'Final checkout settlement collected by StayQR',
        actor_id,
        stay_end,
        target_guest_session_id,
        session_row.reservation_id,
        created_invoice_id
      );

      amount_remaining := round(amount_remaining - collection_amount, 2);
      payment_collected := round(payment_collected + collection_amount, 2);
    end if;

    update public.payments
    set
      invoice_id = created_invoice_id,
      payment_status = case
        when payment_collected >= payment_row.amount then 'paid'
        when payment_collected > 0 then 'partial'
        else payment_row.payment_status
      end,
      payment_method = case
        when collection_amount > 0 then settlement_payment_method
        else payment_method
      end,
      transaction_reference = case
        when collection_amount > 0 then nullif(trim(coalesce(settlement_transaction_reference, '')), '')
        else transaction_reference
      end,
      paid_at = case
        when payment_collected >= payment_row.amount then stay_end
        else paid_at
      end
    where hotel_id = target_hotel_id
      and id = payment_row.id;
  end loop;

  -- Charges without an existing demand receive one exact settlement demand.
  if amount_remaining > 0 then
    insert into public.payments (
      hotel_id,
      guest_id,
      room_id,
      amount,
      payment_type,
      payment_status,
      notes,
      payment_method,
      transaction_reference,
      paid_at,
      collected_by,
      payment_notes,
      invoice_id,
      guest_session_id,
      reservation_id,
      reservation_room_id
    ) values (
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      amount_remaining,
      'checkout_settlement',
      'paid',
      format('Final checkout settlement for %s', created_invoice_number),
      settlement_payment_method,
      nullif(trim(coalesce(settlement_transaction_reference, '')), ''),
      stay_end,
      actor_id,
      'Created atomically during final checkout',
      created_invoice_id,
      target_guest_session_id,
      session_row.reservation_id,
      session_row.reservation_room_id
    ) returning id into settlement_payment_id;

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
      invoice_id
    ) values (
      target_hotel_id,
      settlement_payment_id,
      session_row.guest_id,
      session_row.room_id,
      amount_remaining,
      settlement_payment_method,
      nullif(trim(coalesce(settlement_transaction_reference, '')), ''),
      'Final checkout settlement collected by StayQR',
      actor_id,
      stay_end,
      target_guest_session_id,
      session_row.reservation_id,
      created_invoice_id
    );

    amount_remaining := 0;
  end if;

  update public.payment_collections pc
  set invoice_id = created_invoice_id
  from public.payments p
  where p.hotel_id = target_hotel_id
    and p.id = pc.payment_id
    and pc.hotel_id = target_hotel_id
    and p.guest_id = session_row.guest_id
    and p.room_id = session_row.room_id
    and (
      p.guest_session_id = target_guest_session_id
      or (
        p.guest_session_id is null
        and p.created_at >= session_row.checkin_time
      )
    );

  update public.food_orders
  set payment_status = 'paid'
  where hotel_id = target_hotel_id
    and guest_id = session_row.guest_id
    and room_id = session_row.room_id
    and order_status = 'delivered'
    and created_at >= session_row.checkin_time;

  update public.manual_charges
  set payment_status = 'paid'
  where hotel_id = target_hotel_id
    and guest_id = session_row.guest_id
    and room_id = session_row.room_id
    and created_at >= session_row.checkin_time;

  update public.guest_sessions
  set
    status = 'completed',
    expired_at = stay_end,
    checked_out_at = stay_end,
    checked_out_by = actor_id
  where hotel_id = target_hotel_id
    and id = target_guest_session_id
    and status = 'active';

  if not found then
    raise exception 'Checkout lost its active-stay lock. Refresh and try again.';
  end if;

  -- Release the active inventory ledger entry so an early checkout does not
  -- keep the room unavailable until the original departure date.
  update public.room_inventory_allocations
  set
    status = 'released',
    released_at = stay_end,
    updated_at = stay_end
  where hotel_id = target_hotel_id
    and status = 'active'
    and (
      reservation_room_id = session_row.reservation_room_id
      or guest_session_id = target_guest_session_id
    );

  -- The Day 5 guest-session trigger advances linked reservation records and
  -- changes occupied rooms to cleaning. Direct stays are handled here too.
  update public.rooms
  set status = 'cleaning'
  where hotel_id = target_hotel_id
    and id = session_row.room_id
    and status = 'occupied';

  select task.id into housekeeping_task_id
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.room_id = session_row.room_id
    and task.task_type = 'room_cleaning'
    and task.status in ('pending', 'in_progress')
  order by task.created_at
  limit 1
  for update;

  if housekeeping_task_id is null then
    insert into public.housekeeping_tasks (
      hotel_id,
      room_id,
      room_number,
      task_type,
      status,
      notes
    ) values (
      target_hotel_id,
      session_row.room_id,
      room_row.room_number,
      'room_cleaning',
      'pending',
      format('Checkout cleaning task for invoice %s', created_invoice_number)
    ) returning id into housekeeping_task_id;
  end if;

  if session_row.reservation_id is not null then
    reservation_snapshot := private.build_reservation_json(
      target_hotel_id,
      session_row.reservation_id
    );
  end if;

  checkout_snapshot := jsonb_build_object(
    'invoice_id', created_invoice_id,
    'invoice_number', created_invoice_number,
    'hotel_id', target_hotel_id,
    'guest_session_id', target_guest_session_id,
    'reservation_id', session_row.reservation_id,
    'reservation_room_id', session_row.reservation_room_id,
    'room_id', session_row.room_id,
    'room_number', room_row.room_number,
    'guest_id', session_row.guest_id,
    'guest_name', guest_row.full_name,
    'checkin_time', session_row.checkin_time,
    'checkout_time', stay_end,
    'stay_hours', stay_hours,
    'stay_nights', stay_nights,
    'room_amount', room_amount,
    'food_amount', food_amount,
    'manual_amount', manual_amount,
    'service_amount', service_amount,
    'subtotal', subtotal,
    'tax_percent', safe_tax_percent,
    'tax_amount', tax_amount,
    'discount_type', discount_type,
    'discount_value', safe_discount_value,
    'discount_amount', discount_amount,
    'grand_total', grand_total,
    'previously_paid', previously_paid,
    'amount_collected_at_checkout', amount_to_collect,
    'excess_paid', excess_paid,
    'housekeeping_task_id', housekeeping_task_id,
    'reservation', reservation_snapshot
  );

  insert into public.reservation_checkout_events (
    hotel_id,
    guest_session_id,
    reservation_id,
    reservation_room_id,
    room_id,
    guest_id,
    invoice_id,
    checked_out_by,
    checked_out_at,
    settlement_snapshot,
    metadata
  ) values (
    target_hotel_id,
    target_guest_session_id,
    session_row.reservation_id,
    session_row.reservation_room_id,
    session_row.room_id,
    session_row.guest_id,
    created_invoice_id,
    actor_id,
    stay_end,
    checkout_snapshot,
    jsonb_build_object(
      'payment_method', settlement_payment_method,
      'transaction_reference', nullif(trim(coalesce(settlement_transaction_reference, '')), '')
    )
  );

  if session_row.reservation_id is not null then
    perform private.write_activity_log(
      target_hotel_id,
      'reservation.room_checkout_completed',
      'reservation',
      session_row.reservation_id,
      format('Room %s checkout completed with invoice %s.', room_row.room_number, created_invoice_number),
      null,
      reservation_snapshot,
      jsonb_build_object(
        'reservation_room_id', session_row.reservation_room_id,
        'guest_session_id', target_guest_session_id,
        'invoice_id', created_invoice_id,
        'housekeeping_task_id', housekeeping_task_id,
        'grand_total', grand_total,
        'amount_collected_at_checkout', amount_to_collect
      )
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'invoice_id', created_invoice_id,
    'invoice_number', created_invoice_number,
    'guest_session_id', target_guest_session_id,
    'reservation_id', session_row.reservation_id,
    'reservation_room_id', session_row.reservation_room_id,
    'room_id', session_row.room_id,
    'room_number', room_row.room_number,
    'housekeeping_task_id', housekeeping_task_id,
    'grand_total', grand_total,
    'previously_paid', previously_paid,
    'amount_collected_at_checkout', amount_to_collect,
    'room_status', 'cleaning',
    'stay_status', 'completed',
    'reservation', reservation_snapshot
  );
end;
$$;

revoke all on function public.checkout_guest_session(
  uuid, uuid, numeric, text, numeric, boolean, text, text, text, boolean
) from public;

grant execute on function public.checkout_guest_session(
  uuid, uuid, numeric, text, numeric, boolean, text, text, text, boolean
) to authenticated;

commit;

-- Supabase may show one blank pg_advisory_xact_lock row. That is expected.
