-- ============================================================================
-- StayQR v1.0
-- Migration: 202607220003_reservation_crud_rate_quote_activity
-- Day 3: Reservation CRUD and Rate Quotation
--
-- PURPOSE
--   1. Add transactional create/edit/cancel/no-show Reservation operations.
--   2. Add secure guest lookup and guest creation inside Reservation workflows.
--   3. Add reservation-aware room availability for modification workflows.
--   4. Calculate base/seasonal rates, occupancy supplements and totals.
--   5. Record reservation deposits without inventing invoice/payment history.
--   6. Add immutable hotel activity logs for reservation actions.
--   7. Expose secure list/detail functions for the Day 3 React UI.
--
-- PREREQUISITE
--   Migration 202607200002_reservation_foundation_and_availability Revision 1
--   must be applied and the Day 2 exit-gate suite must be green.
--
-- SAFETY
--   - Run the COMPLETE file once using role postgres.
--   - The migration is transactional.
--   - Existing PMS records are not changed.
--   - Day 3 supports one room per reservation. Multi-room/group booking is Day 5.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607220003_reservation_crud_rate_quote_activity')
);

-- ============================================================================
-- 0. PREREQUISITE ASSERTIONS
-- ============================================================================

do $$
begin
  if to_regclass('public.reservations') is null
     or to_regclass('public.reservation_rooms') is null
     or to_regclass('public.room_inventory_allocations') is null
     or to_regprocedure(
       'public.get_rate_quote(uuid,uuid,date,date)'
     ) is null
     or to_regprocedure(
       'private.next_reservation_number(uuid,date)'
     ) is null
  then
    raise exception
      'Migration stopped: the Day 2 Reservation foundation is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'room_inventory_no_overlapping_active_allocations'
      and conrelid = 'public.room_inventory_allocations'::regclass
  ) then
    raise exception
      'Migration stopped: database overlap protection is missing.';
  end if;
end
$$;

-- ============================================================================
-- 1. ACTIVITY LOGS
-- ============================================================================

create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  description text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint activity_logs_action_not_blank
    check (length(trim(action)) > 0),
  constraint activity_logs_entity_type_not_blank
    check (length(trim(entity_type)) > 0)
);

create index if not exists idx_activity_logs_hotel_created
on public.activity_logs (hotel_id, created_at desc);

create index if not exists idx_activity_logs_hotel_entity
on public.activity_logs (
  hotel_id,
  entity_type,
  entity_id,
  created_at desc
);

create index if not exists idx_activity_logs_hotel_actor
on public.activity_logs (hotel_id, actor_user_id, created_at desc);

alter table public.activity_logs enable row level security;

drop policy if exists stayqr_activity_logs_select
on public.activity_logs;

create policy stayqr_activity_logs_select
on public.activity_logs
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

-- No direct browser insert/update/delete policy. Trusted functions write logs.

-- ============================================================================
-- 2. RESERVATION DEPOSITS
-- ============================================================================

create table if not exists public.reservation_payments (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  reservation_id uuid not null,
  amount numeric(12,2) not null,
  payment_method text not null default 'cash',
  payment_status text not null default 'collected',
  transaction_reference text,
  notes text,
  collected_by uuid references auth.users(id) on delete set null,
  collected_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  created_at timestamptz not null default now(),
  constraint reservation_payments_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete cascade,
  constraint reservation_payments_amount_check
    check (amount > 0),
  constraint reservation_payments_method_check
    check (
      payment_method in (
        'cash',
        'card',
        'upi',
        'bank_transfer',
        'payment_link',
        'other'
      )
    ),
  constraint reservation_payments_status_check
    check (
      payment_status in (
        'collected',
        'refunded',
        'voided'
      )
    ),
  constraint reservation_payments_void_check
    check (
      payment_status <> 'voided'
      or (
        voided_at is not null
        and length(trim(coalesce(void_reason, ''))) > 0
      )
    )
);

create unique index if not exists uq_reservation_payments_hotel_id_id
on public.reservation_payments (hotel_id, id);

create index if not exists idx_reservation_payments_reservation
on public.reservation_payments (
  hotel_id,
  reservation_id,
  collected_at desc
);

create index if not exists idx_reservation_payments_hotel_status
on public.reservation_payments (
  hotel_id,
  payment_status,
  collected_at desc
);

alter table public.reservation_payments enable row level security;

drop policy if exists stayqr_reservation_payments_select
on public.reservation_payments;

create policy stayqr_reservation_payments_select
on public.reservation_payments
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

-- Deposits are created by trusted Reservation RPCs only.

-- ============================================================================
-- 3. SUPPORTING INDEXES
-- ============================================================================

create index if not exists idx_guests_hotel_phone
on public.guests (hotel_id, phone);

create index if not exists idx_guests_hotel_email_lower
on public.guests (hotel_id, lower(email));

create index if not exists idx_guests_hotel_name_lower
on public.guests (hotel_id, lower(full_name));

create index if not exists idx_reservations_hotel_status_arrival
on public.reservations (
  hotel_id,
  status,
  arrival_date,
  created_at desc
);

create index if not exists idx_reservations_hotel_number_lower
on public.reservations (hotel_id, lower(reservation_number));

-- ============================================================================
-- 4. AUTHORIZATION AND ACTIVITY HELPERS
-- ============================================================================

create or replace function private.assert_reservation_write_access(
  target_hotel_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.user_has_hotel_role(
    target_hotel_id,
    array[
      'owner',
      'manager',
      'reception',
      'front_desk',
      'frontdesk'
    ]
  ) then
    raise exception 'Reservation write access denied.';
  end if;
end;
$$;

create or replace function private.current_hotel_actor_role(
  target_hotel_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.is_platform_admin() then 'platform_admin'
    else coalesce(
      (
        select lower(replace(trim(s.role), ' ', '_'))
        from public.staff s
        where s.hotel_id = target_hotel_id
          and s.auth_user_id = (select auth.uid())
          and lower(s.status) = 'active'
        order by s.created_at
        limit 1
      ),
      (
        select lower(replace(trim(hu.role), ' ', '_'))
        from public.hotel_users hu
        where hu.hotel_id = target_hotel_id
          and hu.user_id = (select auth.uid())
          and lower(hu.status) = 'active'
        order by hu.created_at
        limit 1
      ),
      'authenticated'
    )
  end;
$$;

create or replace function private.write_activity_log(
  target_hotel_id uuid,
  target_action text,
  target_entity_type text,
  target_entity_id uuid,
  target_description text default null,
  target_before_data jsonb default null,
  target_after_data jsonb default null,
  target_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  log_id uuid;
begin
  insert into public.activity_logs (
    hotel_id,
    actor_user_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    description,
    before_data,
    after_data,
    metadata
  )
  values (
    target_hotel_id,
    auth.uid(),
    private.current_hotel_actor_role(target_hotel_id),
    target_action,
    target_entity_type,
    target_entity_id,
    target_description,
    target_before_data,
    target_after_data,
    coalesce(target_metadata, '{}'::jsonb)
  )
  returning id into log_id;

  return log_id;
end;
$$;

-- ============================================================================
-- 5. DEPOSIT TOTAL SYNCHRONIZATION
-- ============================================================================

create or replace function private.sync_reservation_deposit_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_hotel_id uuid;
  target_reservation_id uuid;
  collected_total numeric(12,2);
begin
  target_hotel_id := coalesce(new.hotel_id, old.hotel_id);
  target_reservation_id :=
    coalesce(new.reservation_id, old.reservation_id);

  select coalesce(
    sum(rp.amount) filter (
      where rp.payment_status = 'collected'
    ),
    0
  )::numeric(12,2)
  into collected_total
  from public.reservation_payments rp
  where rp.hotel_id = target_hotel_id
    and rp.reservation_id = target_reservation_id;

  update public.reservations
  set
    deposit_collected = collected_total,
    updated_by = coalesce(auth.uid(), updated_by),
    updated_at = now()
  where hotel_id = target_hotel_id
    and id = target_reservation_id;

  return coalesce(new, old);
end;
$$;

drop trigger if exists reservation_payments_sync_deposit
on public.reservation_payments;

create trigger reservation_payments_sync_deposit
after insert or update of amount, payment_status
or delete
on public.reservation_payments
for each row
execute function private.sync_reservation_deposit_total();

-- ============================================================================
-- 6. RESERVATION-AWARE AVAILABILITY
-- ============================================================================

create or replace function public.get_reservation_available_rooms(
  target_hotel_id uuid,
  target_arrival_date date,
  target_departure_date date,
  target_room_type_id uuid default null,
  exclude_reservation_id uuid default null
)
returns table (
  room_id uuid,
  room_number text,
  room_type_id uuid,
  room_type_name text,
  room_status text,
  max_adults integer,
  max_children integer,
  max_occupancy integer,
  standard_rate numeric,
  active_rate_plan_id uuid,
  active_rate_plan_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  if target_arrival_date is null
     or target_departure_date is null
     or target_departure_date <= target_arrival_date
  then
    raise exception 'Departure date must be after arrival date.';
  end if;

  if target_departure_date - target_arrival_date > 365 then
    raise exception 'Availability searches are limited to 365 nights.';
  end if;

  return query
  select
    r.id,
    r.room_number,
    rt.id,
    rt.name,
    r.status,
    rt.max_adults,
    rt.max_children,
    rt.max_occupancy,
    coalesce(rp.base_rate, rt.base_rate)::numeric,
    rp.id,
    rp.name
  from public.rooms r
  join public.room_types rt
    on rt.id = r.room_type_id
   and rt.hotel_id = r.hotel_id
   and rt.is_active
  left join lateral (
    select candidate.*
    from public.rate_plans candidate
    where candidate.hotel_id = r.hotel_id
      and candidate.room_type_id = r.room_type_id
      and candidate.is_active
    order by candidate.priority asc, candidate.created_at asc
    limit 1
  ) rp on true
  join public.hotels h on h.id = r.hotel_id
  where r.hotel_id = target_hotel_id
    and (
      target_room_type_id is null
      or r.room_type_id = target_room_type_id
    )
    and r.status not in ('maintenance', 'out_of_order')
    and not (
      r.status = 'cleaning'
      and target_arrival_date <=
        (now() at time zone h.timezone)::date
    )
    and not exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.hotel_id = r.hotel_id
        and ria.room_id = r.id
        and ria.status = 'active'
        and ria.stay_dates &&
          daterange(
            target_arrival_date,
            target_departure_date,
            '[)'
          )
        and not (
          exclude_reservation_id is not null
          and ria.allocation_type = 'reservation'
          and exists (
            select 1
            from public.reservation_rooms owned_room
            where owned_room.id = ria.reservation_room_id
              and owned_room.hotel_id = target_hotel_id
              and owned_room.reservation_id =
                exclude_reservation_id
          )
        )
    )
  order by
    rt.sort_order,
    nullif(
      regexp_replace(r.room_number, '[^0-9]', '', 'g'),
      ''
    )::integer nulls last,
    r.room_number;
end;
$$;

-- ============================================================================
-- 7. OCCUPANCY-AWARE RATE QUOTATION
-- ============================================================================

create or replace function public.get_reservation_rate_quote(
  target_hotel_id uuid,
  target_rate_plan_id uuid,
  target_arrival_date date,
  target_departure_date date,
  target_adults integer default 1,
  target_children integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  room_type_row public.room_types%rowtype;
  rate_plan_row public.rate_plans%rowtype;
  quote_lines jsonb;
  number_of_nights integer;
  extra_adults integer;
  room_subtotal numeric(12,2);
  average_nightly numeric(12,2);
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  if target_adults < 1 or target_children < 0 then
    raise exception 'Guest counts are invalid.';
  end if;

  select rp.*
  into rate_plan_row
  from public.rate_plans rp
  where rp.id = target_rate_plan_id
    and rp.hotel_id = target_hotel_id
    and rp.is_active;

  if not found then
    raise exception 'Active rate plan not found for this hotel.';
  end if;

  select rt.*
  into room_type_row
  from public.room_types rt
  where rt.id = rate_plan_row.room_type_id
    and rt.hotel_id = target_hotel_id
    and rt.is_active;

  if not found then
    raise exception 'Active room type not found for this rate plan.';
  end if;

  if target_adults > room_type_row.max_adults
     or target_children > room_type_row.max_children
     or target_adults + target_children >
       room_type_row.max_occupancy
  then
    raise exception 'Guest count exceeds room-type capacity.';
  end if;

  number_of_nights :=
    target_departure_date - target_arrival_date;

  if number_of_nights < 1 or number_of_nights > 365 then
    raise exception 'Stay length must be between 1 and 365 nights.';
  end if;

  extra_adults :=
    greatest(target_adults - room_type_row.base_occupancy, 0);

  with quoted as (
    select
      q.stay_date,
      q.currency_code,
      q.nightly_rate,
      q.extra_adult_rate,
      q.extra_child_rate,
      q.rate_source,
      q.seasonal_rate_id,
      (
        q.nightly_rate
        + q.extra_adult_rate * extra_adults
        + q.extra_child_rate * target_children
      )::numeric(12,2) as effective_nightly_rate
    from public.get_rate_quote(
      target_hotel_id,
      target_rate_plan_id,
      target_arrival_date,
      target_departure_date
    ) q
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'stay_date', quoted.stay_date,
          'nightly_rate', quoted.nightly_rate,
          'extra_adult_rate', quoted.extra_adult_rate,
          'extra_child_rate', quoted.extra_child_rate,
          'extra_adults', extra_adults,
          'children', target_children,
          'effective_nightly_rate',
            quoted.effective_nightly_rate,
          'rate_source', quoted.rate_source,
          'seasonal_rate_id', quoted.seasonal_rate_id
        )
        order by quoted.stay_date
      ),
      '[]'::jsonb
    ),
    coalesce(sum(quoted.effective_nightly_rate), 0)::numeric(12,2)
  into quote_lines, room_subtotal
  from quoted;

  average_nightly :=
    round(room_subtotal / number_of_nights, 2);

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'rate_plan_id', rate_plan_row.id,
    'rate_plan_name', rate_plan_row.name,
    'room_type_id', room_type_row.id,
    'room_type_name', room_type_row.name,
    'currency_code', rate_plan_row.currency_code,
    'arrival_date', target_arrival_date,
    'departure_date', target_departure_date,
    'nights', number_of_nights,
    'adults', target_adults,
    'children', target_children,
    'extra_adults', extra_adults,
    'average_nightly_rate', average_nightly,
    'room_subtotal', room_subtotal,
    'tax_amount', 0,
    'discount_amount', 0,
    'total_amount', room_subtotal,
    'nightly_breakdown', quote_lines
  );
end;
$$;

-- ============================================================================
-- 8. GUEST LOOKUP
-- ============================================================================

create or replace function public.search_reservation_guests(
  target_hotel_id uuid,
  search_text text default null,
  result_limit integer default 20
)
returns table (
  guest_id uuid,
  full_name text,
  phone text,
  email text,
  id_type text,
  id_number text,
  preferred_language text,
  created_at timestamptz,
  reservation_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_search text;
  safe_limit integer;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  normalized_search := lower(trim(coalesce(search_text, '')));
  safe_limit := least(greatest(coalesce(result_limit, 20), 1), 50);

  return query
  select
    g.id,
    g.full_name,
    g.phone,
    g.email,
    g.id_type,
    g.id_number,
    g.preferred_language,
    g.created_at,
    (
      select count(*)
      from public.reservations r
      where r.hotel_id = g.hotel_id
        and r.primary_guest_id = g.id
    )::bigint
  from public.guests g
  where g.hotel_id = target_hotel_id
    and (
      normalized_search = ''
      or lower(g.full_name) like '%' || normalized_search || '%'
      or lower(coalesce(g.phone, '')) like
        '%' || normalized_search || '%'
      or lower(coalesce(g.email, '')) like
        '%' || normalized_search || '%'
      or lower(coalesce(g.id_number, '')) like
        '%' || normalized_search || '%'
    )
  order by
    case
      when lower(g.full_name) = normalized_search then 0
      when lower(coalesce(g.phone, '')) = normalized_search then 0
      else 1
    end,
    g.created_at desc
  limit safe_limit;
end;
$$;

-- ============================================================================
-- 9. PRIVATE RESERVATION JSON BUILDER
-- ============================================================================

create or replace function private.build_reservation_json(
  target_hotel_id uuid,
  target_reservation_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'hotel_id', r.hotel_id,
    'reservation_number', r.reservation_number,
    'status', r.status,
    'booking_source', r.booking_source,
    'source_reference', r.source_reference,
    'arrival_date', r.arrival_date,
    'departure_date', r.departure_date,
    'expected_checkin_time', r.expected_checkin_time,
    'expected_checkout_time', r.expected_checkout_time,
    'adults', r.adults,
    'children', r.children,
    'currency_code', r.currency_code,
    'room_subtotal', r.room_subtotal,
    'tax_amount', r.tax_amount,
    'discount_amount', r.discount_amount,
    'total_amount', r.total_amount,
    'deposit_required', r.deposit_required,
    'deposit_collected', r.deposit_collected,
    'deposit_balance',
      greatest(r.deposit_required - r.deposit_collected, 0),
    'special_requests', r.special_requests,
    'internal_notes', r.internal_notes,
    'cancellation_reason', r.cancellation_reason,
    'cancelled_at', r.cancelled_at,
    'no_show_at', r.no_show_at,
    'created_by', r.created_by,
    'updated_by', r.updated_by,
    'created_at', r.created_at,
    'updated_at', r.updated_at,
    'guest', (
      select jsonb_build_object(
        'id', g.id,
        'full_name', g.full_name,
        'phone', g.phone,
        'email', g.email,
        'id_type', g.id_type,
        'id_number', g.id_number,
        'preferred_language', g.preferred_language,
        'created_at', g.created_at
      )
      from public.guests g
      where g.id = r.primary_guest_id
        and g.hotel_id = r.hotel_id
    ),
    'rooms', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', rr.id,
            'room_type_id', rr.room_type_id,
            'room_type_name', rt.name,
            'room_id', rr.room_id,
            'room_number', room.room_number,
            'rate_plan_id', rr.rate_plan_id,
            'rate_plan_name', rp.name,
            'status', rr.status,
            'adults', rr.adults,
            'children', rr.children,
            'nightly_rate', rr.nightly_rate,
            'room_subtotal', rr.room_subtotal,
            'tax_amount', rr.tax_amount,
            'discount_amount', rr.discount_amount,
            'total_amount', rr.total_amount,
            'notes', rr.notes
          )
          order by rr.created_at
        ),
        '[]'::jsonb
      )
      from public.reservation_rooms rr
      join public.room_types rt
        on rt.id = rr.room_type_id
       and rt.hotel_id = rr.hotel_id
      left join public.rooms room
        on room.id = rr.room_id
       and room.hotel_id = rr.hotel_id
      left join public.rate_plans rp
        on rp.id = rr.rate_plan_id
       and rp.hotel_id = rr.hotel_id
      where rr.hotel_id = r.hotel_id
        and rr.reservation_id = r.id
    ),
    'payments', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', payment.id,
            'amount', payment.amount,
            'payment_method', payment.payment_method,
            'payment_status', payment.payment_status,
            'transaction_reference',
              payment.transaction_reference,
            'notes', payment.notes,
            'collected_by', payment.collected_by,
            'collected_at', payment.collected_at
          )
          order by payment.collected_at desc
        ),
        '[]'::jsonb
      )
      from public.reservation_payments payment
      where payment.hotel_id = r.hotel_id
        and payment.reservation_id = r.id
    ),
    'status_history', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', history.id,
            'old_status', history.old_status,
            'new_status', history.new_status,
            'reason', history.reason,
            'changed_by', history.changed_by,
            'metadata', history.metadata,
            'created_at', history.created_at
          )
          order by history.created_at desc
        ),
        '[]'::jsonb
      )
      from public.reservation_status_history history
      where history.hotel_id = r.hotel_id
        and history.reservation_id = r.id
    )
  )
  from public.reservations r
  where r.hotel_id = target_hotel_id
    and r.id = target_reservation_id;
$$;

-- ============================================================================
-- 10. GUEST RESOLUTION HELPER
-- ============================================================================

create or replace function private.resolve_reservation_guest(
  target_hotel_id uuid,
  guest_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_guest_id uuid;
  new_guest_id uuid;
  guest_name text;
  guest_phone text;
  guest_email text;
begin
  if guest_payload is null then
    raise exception 'Guest information is required.';
  end if;

  if nullif(trim(guest_payload->>'id'), '') is not null then
    existing_guest_id := (guest_payload->>'id')::uuid;

    if not exists (
      select 1
      from public.guests g
      where g.id = existing_guest_id
        and g.hotel_id = target_hotel_id
    ) then
      raise exception 'Selected guest does not belong to this hotel.';
    end if;

    return existing_guest_id;
  end if;

  guest_name := nullif(trim(guest_payload->>'full_name'), '');
  guest_phone := nullif(trim(guest_payload->>'phone'), '');
  guest_email :=
    nullif(lower(trim(guest_payload->>'email')), '');

  if guest_name is null then
    raise exception 'Guest full name is required.';
  end if;

  insert into public.guests (
    hotel_id,
    full_name,
    phone,
    email,
    id_type,
    id_number,
    preferred_language
  )
  values (
    target_hotel_id,
    guest_name,
    guest_phone,
    guest_email,
    nullif(trim(guest_payload->>'id_type'), ''),
    nullif(trim(guest_payload->>'id_number'), ''),
    coalesce(
      nullif(trim(guest_payload->>'preferred_language'), ''),
      'english'
    )
  )
  returning id into new_guest_id;

  return new_guest_id;
end;
$$;

-- ============================================================================
-- 11. CREATE RESERVATION
-- ============================================================================

create or replace function public.create_reservation(
  target_hotel_id uuid,
  reservation_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  hotel_row public.hotels%rowtype;
  room_type_row public.room_types%rowtype;
  selected_room_id uuid;
  selected_room_number text;
  target_room_type_id uuid;
  target_rate_plan_id uuid;
  target_guest_id uuid;
  target_status text;
  target_booking_source text;
  target_arrival_date date;
  target_departure_date date;
  target_adults integer;
  target_children integer;
  target_deposit_required numeric(12,2);
  target_deposit_amount numeric(12,2);
  target_payment_method text;
  quote jsonb;
  target_subtotal numeric(12,2);
  target_total numeric(12,2);
  target_average_rate numeric(12,2);
  generated_number text;
  created_reservation_id uuid;
  created_reservation_room_id uuid;
  reservation_result jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if reservation_payload is null then
    raise exception 'Reservation payload is required.';
  end if;

  select h.*
  into hotel_row
  from public.hotels h
  where h.id = target_hotel_id
    and h.status = 'active';

  if not found then
    raise exception 'Active hotel not found.';
  end if;

  target_status :=
    lower(coalesce(
      nullif(trim(reservation_payload->>'status'), ''),
      'confirmed'
    ));

  if target_status not in ('draft', 'tentative', 'confirmed') then
    raise exception
      'New reservations may be draft, tentative or confirmed.';
  end if;

  target_booking_source :=
    lower(coalesce(
      nullif(trim(reservation_payload->>'booking_source'), ''),
      'walk_in'
    ));

  if target_booking_source not in (
    'walk_in',
    'phone',
    'website',
    'ota_manual',
    'travel_agent',
    'corporate',
    'repeat_guest',
    'other'
  ) then
    raise exception 'Unsupported booking source.';
  end if;

  target_arrival_date :=
    nullif(reservation_payload->>'arrival_date', '')::date;
  target_departure_date :=
    nullif(reservation_payload->>'departure_date', '')::date;

  if target_arrival_date is null
     or target_departure_date is null
     or target_departure_date <= target_arrival_date
  then
    raise exception 'Departure date must be after arrival date.';
  end if;

  if target_departure_date - target_arrival_date > 365 then
    raise exception 'Reservations are limited to 365 nights.';
  end if;

  target_adults :=
    coalesce(
      nullif(reservation_payload->>'adults', '')::integer,
      1
    );
  target_children :=
    coalesce(
      nullif(reservation_payload->>'children', '')::integer,
      0
    );

  target_room_type_id :=
    nullif(reservation_payload->>'room_type_id', '')::uuid;
  target_rate_plan_id :=
    nullif(reservation_payload->>'rate_plan_id', '')::uuid;

  if target_room_type_id is null or target_rate_plan_id is null then
    raise exception 'Room type and rate plan are required.';
  end if;

  select rt.*
  into room_type_row
  from public.room_types rt
  where rt.id = target_room_type_id
    and rt.hotel_id = target_hotel_id
    and rt.is_active;

  if not found then
    raise exception 'Active room type not found.';
  end if;

  if not exists (
    select 1
    from public.rate_plans rp
    where rp.id = target_rate_plan_id
      and rp.hotel_id = target_hotel_id
      and rp.room_type_id = target_room_type_id
      and rp.is_active
  ) then
    raise exception 'Rate plan does not belong to the selected room type.';
  end if;

  quote := public.get_reservation_rate_quote(
    target_hotel_id,
    target_rate_plan_id,
    target_arrival_date,
    target_departure_date,
    target_adults,
    target_children
  );

  target_subtotal := (quote->>'room_subtotal')::numeric(12,2);
  target_total := (quote->>'total_amount')::numeric(12,2);
  target_average_rate :=
    (quote->>'average_nightly_rate')::numeric(12,2);

  if nullif(trim(reservation_payload->>'room_id'), '') is not null then
    selected_room_id :=
      (reservation_payload->>'room_id')::uuid;

    select available.room_number
    into selected_room_number
    from public.get_reservation_available_rooms(
      target_hotel_id,
      target_arrival_date,
      target_departure_date,
      target_room_type_id,
      null
    ) available
    where available.room_id = selected_room_id;

    if not found then
      raise exception
        'Selected room is not available for these dates.';
    end if;
  elsif target_status in ('tentative', 'confirmed') then
    select
      available.room_id,
      available.room_number
    into
      selected_room_id,
      selected_room_number
    from public.get_reservation_available_rooms(
      target_hotel_id,
      target_arrival_date,
      target_departure_date,
      target_room_type_id,
      null
    ) available
    order by available.room_number
    limit 1;

    if selected_room_id is null then
      raise exception
        'No room is available for the selected room type and dates.';
    end if;
  end if;

  target_guest_id := private.resolve_reservation_guest(
    target_hotel_id,
    reservation_payload->'guest'
  );

  target_deposit_amount :=
    coalesce(
      nullif(reservation_payload->>'deposit_amount', '')::numeric,
      0
    )::numeric(12,2);

  target_deposit_required :=
    greatest(
      coalesce(
        nullif(
          reservation_payload->>'deposit_required',
          ''
        )::numeric,
        0
      ),
      target_deposit_amount
    )::numeric(12,2);

  if target_deposit_amount < 0
     or target_deposit_required < 0
     or target_deposit_required > target_total
     or target_deposit_amount > target_total
  then
    raise exception
      'Deposit values must be between zero and the reservation total.';
  end if;

  target_payment_method :=
    lower(coalesce(
      nullif(trim(reservation_payload->>'payment_method'), ''),
      'cash'
    ));

  generated_number := private.next_reservation_number(
    target_hotel_id,
    target_arrival_date
  );

  insert into public.reservations (
    hotel_id,
    reservation_number,
    primary_guest_id,
    status,
    booking_source,
    source_reference,
    arrival_date,
    departure_date,
    expected_checkin_time,
    expected_checkout_time,
    adults,
    children,
    currency_code,
    room_subtotal,
    tax_amount,
    discount_amount,
    total_amount,
    deposit_required,
    deposit_collected,
    special_requests,
    internal_notes,
    created_by,
    updated_by
  )
  values (
    target_hotel_id,
    generated_number,
    target_guest_id,
    target_status,
    target_booking_source,
    nullif(trim(reservation_payload->>'source_reference'), ''),
    target_arrival_date,
    target_departure_date,
    nullif(
      reservation_payload->>'expected_checkin_time',
      ''
    )::time,
    nullif(
      reservation_payload->>'expected_checkout_time',
      ''
    )::time,
    target_adults,
    target_children,
    hotel_row.currency_code,
    target_subtotal,
    0,
    0,
    target_total,
    target_deposit_required,
    0,
    nullif(trim(reservation_payload->>'special_requests'), ''),
    nullif(trim(reservation_payload->>'internal_notes'), ''),
    actor_user_id,
    actor_user_id
  )
  returning id into created_reservation_id;

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
    created_reservation_id,
    target_room_type_id,
    selected_room_id,
    target_rate_plan_id,
    case
      when target_status = 'confirmed' then 'confirmed'
      else 'held'
    end,
    target_adults,
    target_children,
    target_average_rate,
    target_subtotal,
    0,
    0,
    target_total,
    nullif(trim(reservation_payload->>'room_notes'), '')
  )
  returning id into created_reservation_room_id;

  insert into public.reservation_guests (
    hotel_id,
    reservation_id,
    guest_id,
    is_primary
  )
  values (
    target_hotel_id,
    created_reservation_id,
    target_guest_id,
    true
  );

  if target_deposit_amount > 0 then
    insert into public.reservation_payments (
      hotel_id,
      reservation_id,
      amount,
      payment_method,
      payment_status,
      transaction_reference,
      notes,
      collected_by
    )
    values (
      target_hotel_id,
      created_reservation_id,
      target_deposit_amount,
      target_payment_method,
      'collected',
      nullif(
        trim(reservation_payload->>'payment_reference'),
        ''
      ),
      nullif(trim(reservation_payload->>'payment_notes'), ''),
      actor_user_id
    );
  end if;

  reservation_result := private.build_reservation_json(
    target_hotel_id,
    created_reservation_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'reservation.created',
    'reservation',
    created_reservation_id,
    format(
      'Reservation %s created for room %s.',
      generated_number,
      coalesce(selected_room_number, 'unassigned')
    ),
    null,
    reservation_result,
    jsonb_build_object(
      'reservation_room_id', created_reservation_room_id,
      'booking_source', target_booking_source,
      'deposit_amount', target_deposit_amount
    )
  );

  return reservation_result;
end;
$$;

-- ============================================================================
-- 12. UPDATE RESERVATION
-- ============================================================================

create or replace function public.update_reservation(
  target_hotel_id uuid,
  target_reservation_id uuid,
  reservation_payload jsonb,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  current_reservation public.reservations%rowtype;
  current_room public.reservation_rooms%rowtype;
  hotel_row public.hotels%rowtype;
  target_guest_id uuid;
  target_room_type_id uuid;
  target_rate_plan_id uuid;
  target_room_id uuid;
  target_arrival_date date;
  target_departure_date date;
  target_adults integer;
  target_children integer;
  target_deposit_required numeric(12,2);
  additional_deposit numeric(12,2);
  target_payment_method text;
  target_booking_source text;
  quote jsonb;
  target_subtotal numeric(12,2);
  target_total numeric(12,2);
  target_average_rate numeric(12,2);
  before_json jsonb;
  after_json jsonb;
  room_status_after_edit text;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if reservation_payload is null then
    raise exception 'Reservation payload is required.';
  end if;

  select r.*
  into current_reservation
  from public.reservations r
  where r.id = target_reservation_id
    and r.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Reservation not found.';
  end if;

  if current_reservation.status not in (
    'draft',
    'tentative',
    'confirmed'
  ) then
    raise exception
      'Only draft, tentative or confirmed reservations may be edited.';
  end if;

  if expected_updated_at is not null
     and current_reservation.updated_at is distinct from
       expected_updated_at
  then
    raise exception
      'Reservation changed after it was opened. Refresh and try again.';
  end if;

  select rr.*
  into current_room
  from public.reservation_rooms rr
  where rr.hotel_id = target_hotel_id
    and rr.reservation_id = target_reservation_id
  order by rr.created_at
  limit 1
  for update;

  if not found then
    raise exception 'Reservation room record not found.';
  end if;

  select h.*
  into hotel_row
  from public.hotels h
  where h.id = target_hotel_id
    and h.status = 'active';

  before_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  target_arrival_date := coalesce(
    nullif(reservation_payload->>'arrival_date', '')::date,
    current_reservation.arrival_date
  );
  target_departure_date := coalesce(
    nullif(reservation_payload->>'departure_date', '')::date,
    current_reservation.departure_date
  );

  if target_departure_date <= target_arrival_date
     or target_departure_date - target_arrival_date > 365
  then
    raise exception
      'Stay length must be between 1 and 365 nights.';
  end if;

  target_adults := coalesce(
    nullif(reservation_payload->>'adults', '')::integer,
    current_reservation.adults
  );
  target_children := coalesce(
    nullif(reservation_payload->>'children', '')::integer,
    current_reservation.children
  );

  target_room_type_id := coalesce(
    nullif(reservation_payload->>'room_type_id', '')::uuid,
    current_room.room_type_id
  );
  target_rate_plan_id := coalesce(
    nullif(reservation_payload->>'rate_plan_id', '')::uuid,
    current_room.rate_plan_id
  );

  if not exists (
    select 1
    from public.rate_plans rp
    where rp.id = target_rate_plan_id
      and rp.hotel_id = target_hotel_id
      and rp.room_type_id = target_room_type_id
      and rp.is_active
  ) then
    raise exception 'Rate plan does not belong to the selected room type.';
  end if;

  quote := public.get_reservation_rate_quote(
    target_hotel_id,
    target_rate_plan_id,
    target_arrival_date,
    target_departure_date,
    target_adults,
    target_children
  );

  target_subtotal := (quote->>'room_subtotal')::numeric(12,2);
  target_total := (quote->>'total_amount')::numeric(12,2);
  target_average_rate :=
    (quote->>'average_nightly_rate')::numeric(12,2);

  if reservation_payload ? 'room_id' then
    target_room_id :=
      nullif(reservation_payload->>'room_id', '')::uuid;
  else
    target_room_id := current_room.room_id;
  end if;

  if target_room_id is null
     and current_reservation.status in ('tentative', 'confirmed')
  then
    select available.room_id
    into target_room_id
    from public.get_reservation_available_rooms(
      target_hotel_id,
      target_arrival_date,
      target_departure_date,
      target_room_type_id,
      target_reservation_id
    ) available
    order by available.room_number
    limit 1;

    if target_room_id is null then
      raise exception
        'No room is available for the selected room type and dates.';
    end if;
  elsif target_room_id is not null then
    if not exists (
      select 1
      from public.get_reservation_available_rooms(
        target_hotel_id,
        target_arrival_date,
        target_departure_date,
        target_room_type_id,
        target_reservation_id
      ) available
      where available.room_id = target_room_id
    ) then
      raise exception
        'Selected room is not available for these dates.';
    end if;
  end if;

  if reservation_payload ? 'guest' then
    target_guest_id := private.resolve_reservation_guest(
      target_hotel_id,
      reservation_payload->'guest'
    );
  else
    target_guest_id := current_reservation.primary_guest_id;
  end if;

  target_booking_source := lower(coalesce(
    nullif(trim(reservation_payload->>'booking_source'), ''),
    current_reservation.booking_source
  ));

  if target_booking_source not in (
    'walk_in',
    'phone',
    'website',
    'ota_manual',
    'travel_agent',
    'corporate',
    'repeat_guest',
    'other'
  ) then
    raise exception 'Unsupported booking source.';
  end if;

  additional_deposit := coalesce(
    nullif(
      reservation_payload->>'additional_deposit_amount',
      ''
    )::numeric,
    0
  )::numeric(12,2);

  target_deposit_required := coalesce(
    nullif(
      reservation_payload->>'deposit_required',
      ''
    )::numeric,
    current_reservation.deposit_required
  )::numeric(12,2);

  target_deposit_required := greatest(
    target_deposit_required,
    current_reservation.deposit_collected + additional_deposit
  );

  if additional_deposit < 0
     or target_deposit_required < 0
     or target_deposit_required > target_total
     or current_reservation.deposit_collected +
       additional_deposit > target_total
  then
    raise exception
      'Deposit values must be between zero and the reservation total.';
  end if;

  target_payment_method := lower(coalesce(
    nullif(trim(reservation_payload->>'payment_method'), ''),
    'cash'
  ));

  -- Release the old allocation first to avoid a transient overlap while dates
  -- and physical room assignment are changed in the same transaction.
  update public.reservation_rooms
  set status = 'released'
  where id = current_room.id
    and hotel_id = target_hotel_id;

  update public.reservations
  set
    primary_guest_id = target_guest_id,
    booking_source = target_booking_source,
    source_reference = case
      when reservation_payload ? 'source_reference'
        then nullif(trim(reservation_payload->>'source_reference'), '')
      else source_reference
    end,
    arrival_date = target_arrival_date,
    departure_date = target_departure_date,
    expected_checkin_time = case
      when reservation_payload ? 'expected_checkin_time'
        then nullif(
          reservation_payload->>'expected_checkin_time',
          ''
        )::time
      else expected_checkin_time
    end,
    expected_checkout_time = case
      when reservation_payload ? 'expected_checkout_time'
        then nullif(
          reservation_payload->>'expected_checkout_time',
          ''
        )::time
      else expected_checkout_time
    end,
    adults = target_adults,
    children = target_children,
    currency_code = hotel_row.currency_code,
    room_subtotal = target_subtotal,
    tax_amount = 0,
    discount_amount = 0,
    total_amount = target_total,
    deposit_required = target_deposit_required,
    special_requests = case
      when reservation_payload ? 'special_requests'
        then nullif(trim(reservation_payload->>'special_requests'), '')
      else special_requests
    end,
    internal_notes = case
      when reservation_payload ? 'internal_notes'
        then nullif(trim(reservation_payload->>'internal_notes'), '')
      else internal_notes
    end,
    updated_by = actor_user_id,
    updated_at = now()
  where id = target_reservation_id
    and hotel_id = target_hotel_id;

  room_status_after_edit := case
    when current_reservation.status = 'confirmed' then 'confirmed'
    else 'held'
  end;

  update public.reservation_rooms
  set
    room_type_id = target_room_type_id,
    room_id = target_room_id,
    rate_plan_id = target_rate_plan_id,
    status = room_status_after_edit,
    adults = target_adults,
    children = target_children,
    nightly_rate = target_average_rate,
    room_subtotal = target_subtotal,
    tax_amount = 0,
    discount_amount = 0,
    total_amount = target_total,
    notes = case
      when reservation_payload ? 'room_notes'
        then nullif(trim(reservation_payload->>'room_notes'), '')
      else notes
    end,
    updated_at = now()
  where id = current_room.id
    and hotel_id = target_hotel_id;

  if target_guest_id is distinct from
     current_reservation.primary_guest_id
  then
    delete from public.reservation_guests
    where hotel_id = target_hotel_id
      and reservation_id = target_reservation_id
      and is_primary;

    insert into public.reservation_guests (
      hotel_id,
      reservation_id,
      guest_id,
      is_primary
    )
    values (
      target_hotel_id,
      target_reservation_id,
      target_guest_id,
      true
    )
    on conflict (reservation_id, guest_id)
    do update set is_primary = true;
  end if;

  if additional_deposit > 0 then
    insert into public.reservation_payments (
      hotel_id,
      reservation_id,
      amount,
      payment_method,
      payment_status,
      transaction_reference,
      notes,
      collected_by
    )
    values (
      target_hotel_id,
      target_reservation_id,
      additional_deposit,
      target_payment_method,
      'collected',
      nullif(
        trim(reservation_payload->>'payment_reference'),
        ''
      ),
      nullif(trim(reservation_payload->>'payment_notes'), ''),
      actor_user_id
    );
  end if;

  after_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'reservation.updated',
    'reservation',
    target_reservation_id,
    format(
      'Reservation %s was modified.',
      current_reservation.reservation_number
    ),
    before_json,
    after_json,
    jsonb_build_object(
      'additional_deposit', additional_deposit
    )
  );

  return after_json;
end;
$$;

-- ============================================================================
-- 13. CANCEL / NO-SHOW / STATUS CHANGE
-- ============================================================================

create or replace function public.change_reservation_status(
  target_hotel_id uuid,
  target_reservation_id uuid,
  target_status text,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_reservation public.reservations%rowtype;
  normalized_status text;
  before_json jsonb;
  after_json jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  normalized_status := lower(trim(coalesce(target_status, '')));

  if normalized_status not in ('cancelled', 'no_show') then
    raise exception
      'Day 3 status action supports cancelled or no_show.';
  end if;

  select r.*
  into current_reservation
  from public.reservations r
  where r.id = target_reservation_id
    and r.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Reservation not found.';
  end if;

  if normalized_status = 'cancelled'
     and nullif(trim(reason), '') is null
  then
    raise exception 'Cancellation reason is required.';
  end if;

  before_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  update public.reservations
  set
    status = normalized_status,
    cancellation_reason = case
      when normalized_status = 'cancelled'
        then nullif(trim(reason), '')
      else cancellation_reason
    end,
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_reservation_id
    and hotel_id = target_hotel_id;

  update public.reservation_rooms
  set
    status = case
      when normalized_status = 'cancelled'
        then 'cancelled'
      else 'released'
    end,
    updated_at = now()
  where reservation_id = target_reservation_id
    and hotel_id = target_hotel_id;

  after_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'reservation.' || normalized_status,
    'reservation',
    target_reservation_id,
    format(
      'Reservation %s changed to %s.',
      current_reservation.reservation_number,
      normalized_status
    ),
    before_json,
    after_json,
    jsonb_build_object('reason', nullif(trim(reason), ''))
  );

  return after_json;
end;
$$;

-- ============================================================================
-- 14. RESERVATION LIST AND DETAIL
-- ============================================================================

create or replace function public.get_reservations(
  target_hotel_id uuid,
  status_filter text default null,
  search_text text default null,
  arrival_from date default null,
  arrival_to date default null,
  page_limit integer default 50,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_status text;
  normalized_search text;
  safe_limit integer;
  safe_offset integer;
  result_items jsonb;
  result_count bigint;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  normalized_status :=
    nullif(lower(trim(coalesce(status_filter, ''))), '');
  normalized_search :=
    lower(trim(coalesce(search_text, '')));
  safe_limit := least(greatest(coalesce(page_limit, 50), 1), 100);
  safe_offset := greatest(coalesce(page_offset, 0), 0);

  with filtered as (
    select r.*
    from public.reservations r
    left join public.guests g
      on g.id = r.primary_guest_id
     and g.hotel_id = r.hotel_id
    where r.hotel_id = target_hotel_id
      and (
        normalized_status is null
        or r.status = normalized_status
      )
      and (
        arrival_from is null
        or r.departure_date > arrival_from
      )
      and (
        arrival_to is null
        or r.arrival_date <= arrival_to
      )
      and (
        normalized_search = ''
        or lower(r.reservation_number) like
          '%' || normalized_search || '%'
        or lower(coalesce(g.full_name, '')) like
          '%' || normalized_search || '%'
        or lower(coalesce(g.phone, '')) like
          '%' || normalized_search || '%'
        or lower(coalesce(g.email, '')) like
          '%' || normalized_search || '%'
      )
  ),
  page_rows as (
    select *
    from filtered
    order by arrival_date asc, created_at desc
    limit safe_limit
    offset safe_offset
  )
  select
    coalesce(
      jsonb_agg(
        private.build_reservation_json(
          target_hotel_id,
          page_rows.id
        )
        order by page_rows.arrival_date, page_rows.created_at desc
      ),
      '[]'::jsonb
    )
  into result_items
  from page_rows;

  select count(*)
  into result_count
  from public.reservations r
  left join public.guests g
    on g.id = r.primary_guest_id
   and g.hotel_id = r.hotel_id
  where r.hotel_id = target_hotel_id
    and (
      normalized_status is null
      or r.status = normalized_status
    )
    and (
      arrival_from is null
      or r.departure_date > arrival_from
    )
    and (
      arrival_to is null
      or r.arrival_date <= arrival_to
    )
    and (
      normalized_search = ''
      or lower(r.reservation_number) like
        '%' || normalized_search || '%'
      or lower(coalesce(g.full_name, '')) like
        '%' || normalized_search || '%'
      or lower(coalesce(g.phone, '')) like
        '%' || normalized_search || '%'
      or lower(coalesce(g.email, '')) like
        '%' || normalized_search || '%'
    );

  return jsonb_build_object(
    'items', result_items,
    'total_count', result_count,
    'limit', safe_limit,
    'offset', safe_offset
  );
end;
$$;

create or replace function public.get_reservation_details(
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
  result jsonb;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  result := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  if result is null then
    raise exception 'Reservation not found.';
  end if;

  return result;
end;
$$;

-- ============================================================================
-- 15. FUNCTION PERMISSIONS
-- ============================================================================

revoke all on function private.assert_reservation_write_access(uuid)
from public;
revoke all on function private.current_hotel_actor_role(uuid)
from public;
revoke all on function private.write_activity_log(
  uuid,text,text,uuid,text,jsonb,jsonb,jsonb
) from public;
revoke all on function private.sync_reservation_deposit_total()
from public;
revoke all on function private.build_reservation_json(uuid,uuid)
from public;
revoke all on function private.resolve_reservation_guest(uuid,jsonb)
from public;

revoke all on function public.get_reservation_available_rooms(
  uuid,date,date,uuid,uuid
) from public;
revoke all on function public.get_reservation_rate_quote(
  uuid,uuid,date,date,integer,integer
) from public;
revoke all on function public.search_reservation_guests(
  uuid,text,integer
) from public;
revoke all on function public.create_reservation(uuid,jsonb)
from public;
revoke all on function public.update_reservation(
  uuid,uuid,jsonb,timestamptz
) from public;
revoke all on function public.change_reservation_status(
  uuid,uuid,text,text
) from public;
revoke all on function public.get_reservations(
  uuid,text,text,date,date,integer,integer
) from public;
revoke all on function public.get_reservation_details(uuid,uuid)
from public;

grant execute on function public.get_reservation_available_rooms(
  uuid,date,date,uuid,uuid
) to authenticated;
grant execute on function public.get_reservation_rate_quote(
  uuid,uuid,date,date,integer,integer
) to authenticated;
grant execute on function public.search_reservation_guests(
  uuid,text,integer
) to authenticated;
grant execute on function public.create_reservation(uuid,jsonb)
to authenticated;
grant execute on function public.update_reservation(
  uuid,uuid,jsonb,timestamptz
) to authenticated;
grant execute on function public.change_reservation_status(
  uuid,uuid,text,text
) to authenticated;
grant execute on function public.get_reservations(
  uuid,text,text,date,date,integer,integer
) to authenticated;
grant execute on function public.get_reservation_details(uuid,uuid)
to authenticated;

-- ============================================================================
-- 16. FINAL ASSERTIONS
-- ============================================================================

do $$
begin
  if to_regclass('public.activity_logs') is null
     or to_regclass('public.reservation_payments') is null
  then
    raise exception
      'Migration stopped: Day 3 supporting tables are missing.';
  end if;

  if to_regprocedure(
    'public.create_reservation(uuid,jsonb)'
  ) is null
     or to_regprocedure(
       'public.update_reservation(uuid,uuid,jsonb,timestamptz)'
     ) is null
     or to_regprocedure(
       'public.change_reservation_status(uuid,uuid,text,text)'
     ) is null
     or to_regprocedure(
       'public.get_reservation_rate_quote(uuid,uuid,date,date,integer,integer)'
     ) is null
  then
    raise exception
      'Migration stopped: Day 3 Reservation functions are missing.';
  end if;

  if not exists (
    select 1
    from information_schema.triggers
    where trigger_schema = 'public'
      and event_object_table = 'reservation_payments'
      and trigger_name =
        'reservation_payments_sync_deposit'
  ) then
    raise exception
      'Migration stopped: deposit synchronization trigger is missing.';
  end if;
end
$$;

commit;

-- Supabase may display one blank `pg_advisory_xact_lock` row.
-- That is expected and is not an error.
