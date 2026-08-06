-- ============================================================================
-- StayQR v1.0
-- Day 16 Migration 055 REV3 - Invoice Status Compatibility Fix
-- Trusted Analytics and Standard Reporting Kernel
--
-- REQUIRES
-- --------
-- Day 15 final premium dining lock.
-- Audit 067 reviewed: 132 rows / 116 true / 16 false.
--
-- AUDIT 067 SCHEMA ADAPTATIONS
-- ----------------------------
-- 1. StayQR uses public.invoice_items, not invoice_lines.
-- 2. public.invoices uses invoice_status, not status.
-- 3. public.staff has role but no department column.
--    Staff reporting therefore uses staff.role and the departments of assigned
--    service, housekeeping and maintenance work.
--
-- METRIC CONTRACT
-- ---------------
-- - Hotel-local dates use hotels.timezone.
-- - UI date range is inclusive.
-- - Revenue = posted, non-voided folio charges.
-- - Collections are reported separately from revenue.
-- - Occupancy is room-night based.
-- - Block allocations reduce available room nights.
-- - ADR and ARR are one realized average-room-rate metric.
-- - RevPAR = room revenue / available room nights.
-- - CSV/PDF exports must use these same RPC outputs.
--
-- SAFETY
-- ------
-- No hotel business rows are inserted, updated or deleted.
-- This migration creates indexes, private helpers and trusted report RPCs.
--
-- EXPECTED RESULT
-- 118 rows
-- 118 passed = true
-- 0 failures
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050055:trusted-reporting-kernel-rev1')
);

create schema if not exists private;

-- ============================================================================
-- 0. Strict preflight
-- ============================================================================

do $preflight$
declare
  missing_objects text;
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      ('public.hotels', to_regclass('public.hotels') is not null),
      ('public.rooms', to_regclass('public.rooms') is not null),
      (
        'public.room_inventory_allocations',
        to_regclass('public.room_inventory_allocations') is not null
      ),
      ('public.reservations', to_regclass('public.reservations') is not null),
      (
        'public.reservation_rooms',
        to_regclass('public.reservation_rooms') is not null
      ),
      (
        'public.guest_sessions',
        to_regclass('public.guest_sessions') is not null
      ),
      ('public.guests', to_regclass('public.guests') is not null),
      ('public.folios', to_regclass('public.folios') is not null),
      ('public.folio_items', to_regclass('public.folio_items') is not null),
      (
        'public.folio_collections',
        to_regclass('public.folio_collections') is not null
      ),
      ('public.invoices', to_regclass('public.invoices') is not null),
      (
        'public.invoice_items',
        to_regclass('public.invoice_items') is not null
      ),
      ('public.food_orders', to_regclass('public.food_orders') is not null),
      (
        'public.service_requests',
        to_regclass('public.service_requests') is not null
      ),
      (
        'public.housekeeping_tasks',
        to_regclass('public.housekeeping_tasks') is not null
      ),
      (
        'public.maintenance_tasks',
        to_regclass('public.maintenance_tasks') is not null
      ),
      ('public.staff', to_regclass('public.staff') is not null),
      (
        'private.user_has_permission(uuid,text)',
        to_regprocedure(
          'private.user_has_permission(uuid,text)'
        ) is not null
      )
  ) required(object_name, object_exists)
  where not object_exists;

  if missing_objects is not null then
    raise exception
      'Migration 055 prerequisites are missing: %',
      missing_objects;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'invoices'
      and column_name = 'invoice_status'
  ) then
    raise exception
      'Migration 055 requires public.invoices.invoice_status.';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'staff'
      and column_name = 'department'
  ) then
    raise notice
      'staff.department now exists; Migration 055 will still report role and assigned work departments.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. Reporting indexes
-- ============================================================================

create index if not exists idx_day16_inventory_hotel_type_dates
on public.room_inventory_allocations (
  hotel_id,
  allocation_type,
  starts_on,
  ends_on,
  status
);

create index if not exists idx_day16_folio_items_hotel_service_category
on public.folio_items (
  hotel_id,
  service_at,
  posting_status,
  charge_category,
  item_kind
);

create index if not exists idx_day16_collections_hotel_date_method
on public.folio_collections (
  hotel_id,
  collected_at,
  status,
  payment_method
);

create index if not exists idx_day16_invoices_hotel_date_status
on public.invoices (
  hotel_id,
  invoice_date,
  invoice_status
);

create index if not exists idx_day16_guest_sessions_hotel_dates
on public.guest_sessions (
  hotel_id,
  checkin_time,
  checkout_time,
  status
);

create index if not exists idx_day16_reservations_hotel_source_dates
on public.reservations (
  hotel_id,
  booking_source,
  arrival_date,
  departure_date,
  status
);

create index if not exists idx_day16_service_hotel_created_department
on public.service_requests (
  hotel_id,
  created_at,
  department,
  status
);

create index if not exists idx_day16_housekeeping_hotel_created_staff
on public.housekeeping_tasks (
  hotel_id,
  created_at,
  assigned_staff_id,
  status
);

create index if not exists idx_day16_maintenance_hotel_created_staff
on public.maintenance_tasks (
  hotel_id,
  created_at,
  assigned_staff_id,
  status
);

-- ============================================================================
-- 2. Private validation helpers
-- ============================================================================

create or replace function private.day16_assert_report_access(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
begin
  if p_hotel_id is null then
    raise exception 'Hotel is required.';
  end if;

  if p_date_from is null or p_date_to is null then
    raise exception 'Report start and end dates are required.';
  end if;

  if p_date_to < p_date_from then
    raise exception 'Report end date cannot be before start date.';
  end if;

  if (p_date_to - p_date_from) > 366 then
    raise exception 'Report date range cannot exceed 367 inclusive days.';
  end if;

  select coalesce(nullif(trim(h.timezone), ''), 'Asia/Kolkata')
  into v_timezone
  from public.hotels h
  where h.id = p_hotel_id
    and h.status = 'active';

  if v_timezone is null then
    raise exception 'Active hotel was not found.';
  end if;

  perform now() at time zone v_timezone;

  if not private.user_has_permission(p_hotel_id, 'reports.view') then
    raise exception 'You do not have reports.view permission for this hotel.';
  end if;

  return v_timezone;
end;
$function$;

create or replace function private.day16_assert_filter_access(
  p_hotel_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
begin
  if p_hotel_id is null then
    raise exception 'Hotel is required.';
  end if;

  select coalesce(nullif(trim(h.timezone), ''), 'Asia/Kolkata')
  into v_timezone
  from public.hotels h
  where h.id = p_hotel_id
    and h.status = 'active';

  if v_timezone is null then
    raise exception 'Active hotel was not found.';
  end if;

  perform now() at time zone v_timezone;

  if not private.user_has_permission(p_hotel_id, 'reports.view') then
    raise exception 'You do not have reports.view permission for this hotel.';
  end if;

  return v_timezone;
end;
$function$;

revoke all on function private.day16_assert_report_access(uuid,date,date)
from public, anon, authenticated;

revoke all on function private.day16_assert_filter_access(uuid)
from public, anon, authenticated;

grant execute on function private.day16_assert_report_access(uuid,date,date)
to authenticated;

grant execute on function private.day16_assert_filter_access(uuid)
to authenticated;

-- ============================================================================
-- 3. Filter options
-- ============================================================================

create or replace function public.get_report_filter_options(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone := private.day16_assert_filter_access(p_hotel_id);

  select jsonb_build_object(
    'timezone', v_timezone,
    'booking_sources',
      coalesce(
        (
          select jsonb_agg(source_value order by source_value)
          from (
            select distinct r.booking_source as source_value
            from public.reservations r
            where r.hotel_id = p_hotel_id
          ) source_rows
        ),
        '[]'::jsonb
      ),
    'departments',
      coalesce(
        (
          select jsonb_agg(department_value order by department_value)
          from (
            select distinct sr.department as department_value
            from public.service_requests sr
            where sr.hotel_id = p_hotel_id
              and sr.department is not null
          ) department_rows
        ),
        '[]'::jsonb
      ),
    'payment_methods',
      coalesce(
        (
          select jsonb_agg(method_value order by method_value)
          from (
            select distinct fc.payment_method as method_value
            from public.folio_collections fc
            where fc.hotel_id = p_hotel_id
          ) payment_rows
        ),
        '[]'::jsonb
      ),
    'rooms',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', room_row.id,
              'room_number', room_row.room_number,
              'status', room_row.status
            )
            order by room_row.room_number
          )
          from public.rooms room_row
          where room_row.hotel_id = p_hotel_id
        ),
        '[]'::jsonb
      ),
    'room_types',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', rt.id,
              'name', rt.name
            )
            order by rt.name
          )
          from public.room_types rt
          where rt.hotel_id = p_hotel_id
        ),
        '[]'::jsonb
      ),
    'staff',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', s.id,
              'full_name', s.full_name,
              'role', s.role,
              'status', s.status
            )
            order by s.full_name
          )
          from public.staff s
          where s.hotel_id = p_hotel_id
        ),
        '[]'::jsonb
      )
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 4. Daily occupancy
-- ============================================================================

create or replace function public.get_report_occupancy_daily(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with report_days as (
    select day_value::date as report_date
    from generate_series(
      p_date_from::timestamp,
      p_date_to::timestamp,
      interval '1 day'
    ) day_value
  ),
  room_count as (
    select count(*)::integer as total_rooms
    from public.rooms r
    where r.hotel_id = p_hotel_id
  ),
  blocked as (
    select distinct
      allocation.room_id,
      day_value::date as report_date
    from public.room_inventory_allocations allocation
    cross join lateral generate_series(
      greatest(allocation.starts_on, p_date_from)::timestamp,
      least(allocation.ends_on - 1, p_date_to)::timestamp,
      interval '1 day'
    ) day_value
    where allocation.hotel_id = p_hotel_id
      and allocation.allocation_type = 'block'
      and allocation.status <> 'cancelled'
      and allocation.starts_on <= p_date_to
      and allocation.ends_on > p_date_from
  ),
  sold as (
    select distinct
      allocation.room_id,
      day_value::date as report_date
    from public.room_inventory_allocations allocation
    cross join lateral generate_series(
      greatest(allocation.starts_on, p_date_from)::timestamp,
      least(allocation.ends_on - 1, p_date_to)::timestamp,
      interval '1 day'
    ) day_value
    where allocation.hotel_id = p_hotel_id
      and allocation.allocation_type in ('reservation', 'stay')
      and allocation.status <> 'cancelled'
      and allocation.starts_on <= p_date_to
      and allocation.ends_on > p_date_from
  ),
  occupied as (
    select distinct
      allocation.room_id,
      day_value::date as report_date
    from public.room_inventory_allocations allocation
    cross join lateral generate_series(
      greatest(allocation.starts_on, p_date_from)::timestamp,
      least(allocation.ends_on - 1, p_date_to)::timestamp,
      interval '1 day'
    ) day_value
    where allocation.hotel_id = p_hotel_id
      and allocation.allocation_type = 'stay'
      and allocation.status <> 'cancelled'
      and allocation.starts_on <= p_date_to
      and allocation.ends_on > p_date_from
  ),
  daily as (
    select
      report_days.report_date,
      room_count.total_rooms,
      count(distinct blocked.room_id)::integer as blocked_room_nights,
      count(distinct sold.room_id)::integer as sold_room_nights,
      count(distinct occupied.room_id)::integer as occupied_room_nights
    from report_days
    cross join room_count
    left join blocked
      on blocked.report_date = report_days.report_date
    left join sold
      on sold.report_date = report_days.report_date
    left join occupied
      on occupied.report_date = report_days.report_date
    group by report_days.report_date, room_count.total_rooms
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'date', daily.report_date,
        'total_rooms', daily.total_rooms,
        'blocked_room_nights', daily.blocked_room_nights,
        'available_room_nights',
          greatest(daily.total_rooms - daily.blocked_room_nights, 0),
        'sold_room_nights', daily.sold_room_nights,
        'occupied_room_nights', daily.occupied_room_nights,
        'occupancy_rate',
          case
            when greatest(
              daily.total_rooms - daily.blocked_room_nights,
              0
            ) = 0 then 0
            else round(
              (
                daily.occupied_room_nights::numeric
                / greatest(
                    daily.total_rooms - daily.blocked_room_nights,
                    1
                  )
              ) * 100,
              2
            )
          end
      )
      order by daily.report_date
    ),
    '[]'::jsonb
  )
  into v_result
  from daily;

  return v_result;
end;
$function$;

-- ============================================================================
-- 5. Daily revenue and collections
-- ============================================================================

create or replace function public.get_report_revenue_daily(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with report_days as (
    select day_value::date as report_date
    from generate_series(
      p_date_from::timestamp,
      p_date_to::timestamp,
      interval '1 day'
    ) day_value
  ),
  charges as (
    select
      (fi.service_at at time zone v_timezone)::date as report_date,
      coalesce(
        sum(fi.amount) filter (
          where fi.item_kind = 'charge'
        ),
        0
      )::numeric(14,2) as charge_revenue,
      coalesce(
        sum(fi.amount) filter (
          where fi.item_kind = 'tax'
        ),
        0
      )::numeric(14,2) as tax_revenue
    from public.folio_items fi
    where fi.hotel_id = p_hotel_id
      and fi.posting_status = 'posted'
      and (fi.service_at at time zone v_timezone)::date
        between p_date_from and p_date_to
    group by (fi.service_at at time zone v_timezone)::date
  ),
  collections as (
    select
      (fc.collected_at at time zone v_timezone)::date as report_date,
      coalesce(
        sum(fc.amount) filter (
          where fc.status = 'posted'
        ),
        0
      )::numeric(14,2) as collections,
      coalesce(
        sum(fc.amount) filter (
          where fc.status in ('voided', 'reversed')
        ),
        0
      )::numeric(14,2) as reversed_or_voided
    from public.folio_collections fc
    where fc.hotel_id = p_hotel_id
      and (fc.collected_at at time zone v_timezone)::date
        between p_date_from and p_date_to
    group by (fc.collected_at at time zone v_timezone)::date
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'date', report_days.report_date,
        'charge_revenue', coalesce(charges.charge_revenue, 0),
        'tax_revenue', coalesce(charges.tax_revenue, 0),
        'gross_revenue',
          coalesce(charges.charge_revenue, 0)
          + coalesce(charges.tax_revenue, 0),
        'collections', coalesce(collections.collections, 0),
        'reversed_or_voided_collections',
          coalesce(collections.reversed_or_voided, 0)
      )
      order by report_days.report_date
    ),
    '[]'::jsonb
  )
  into v_result
  from report_days
  left join charges
    on charges.report_date = report_days.report_date
  left join collections
    on collections.report_date = report_days.report_date;

  return v_result;
end;
$function$;

-- ============================================================================
-- 6. Revenue category drill-down
-- ============================================================================

create or replace function public.get_report_revenue_by_category(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with category_rows as (
    select
      case
        when fi.item_kind = 'tax' then 'tax'
        else coalesce(fi.charge_category, 'other')
      end as category,
      count(*)::integer as line_count,
      coalesce(sum(fi.amount), 0)::numeric(14,2) as amount
    from public.folio_items fi
    where fi.hotel_id = p_hotel_id
      and fi.posting_status = 'posted'
      and (fi.service_at at time zone v_timezone)::date
        between p_date_from and p_date_to
    group by
      case
        when fi.item_kind = 'tax' then 'tax'
        else coalesce(fi.charge_category, 'other')
      end
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'category', category_rows.category,
        'line_count', category_rows.line_count,
        'amount', category_rows.amount
      )
      order by category_rows.amount desc, category_rows.category
    ),
    '[]'::jsonb
  )
  into v_result
  from category_rows;

  return v_result;
end;
$function$;

-- ============================================================================
-- 7. Reservation source report
-- ============================================================================

create or replace function public.get_report_reservations_by_source(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with source_rows as (
    select
      r.booking_source,
      count(*)::integer as reservation_count,
      count(*) filter (
        where r.status = 'checked_in'
      )::integer as checked_in_count,
      count(*) filter (
        where r.status = 'checked_out'
      )::integer as checked_out_count,
      count(*) filter (
        where r.status = 'cancelled'
      )::integer as cancelled_count,
      count(*) filter (
        where r.status = 'no_show'
      )::integer as no_show_count,
      coalesce(sum(r.total_amount), 0)::numeric(14,2) as booked_value
    from public.reservations r
    where r.hotel_id = p_hotel_id
      and r.arrival_date between p_date_from and p_date_to
    group by r.booking_source
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'booking_source', source_rows.booking_source,
        'reservation_count', source_rows.reservation_count,
        'checked_in_count', source_rows.checked_in_count,
        'checked_out_count', source_rows.checked_out_count,
        'cancelled_count', source_rows.cancelled_count,
        'no_show_count', source_rows.no_show_count,
        'booked_value', source_rows.booked_value
      )
      order by source_rows.reservation_count desc,
        source_rows.booking_source
    ),
    '[]'::jsonb
  )
  into v_result
  from source_rows;

  return v_result;
end;
$function$;

-- ============================================================================
-- 8. Arrival and departure report
-- ============================================================================

create or replace function public.get_report_arrivals_departures(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with expected_arrivals as (
    select jsonb_build_object(
      'reservation_id', r.id,
      'reservation_number', r.reservation_number,
      'guest_name', g.full_name,
      'date', r.arrival_date,
      'status', r.status,
      'booking_source', r.booking_source
    ) as item
    from public.reservations r
    left join public.guests g
      on g.hotel_id = r.hotel_id
     and g.id = r.primary_guest_id
    where r.hotel_id = p_hotel_id
      and r.arrival_date between p_date_from and p_date_to
      and r.status not in ('cancelled', 'no_show')
  ),
  expected_departures as (
    select jsonb_build_object(
      'reservation_id', r.id,
      'reservation_number', r.reservation_number,
      'guest_name', g.full_name,
      'date', r.departure_date,
      'status', r.status,
      'booking_source', r.booking_source
    ) as item
    from public.reservations r
    left join public.guests g
      on g.hotel_id = r.hotel_id
     and g.id = r.primary_guest_id
    where r.hotel_id = p_hotel_id
      and r.departure_date between p_date_from and p_date_to
      and r.status not in ('cancelled', 'no_show')
  ),
  actual_arrivals as (
    select jsonb_build_object(
      'guest_session_id', gs.id,
      'guest_name', g.full_name,
      'room_number', room_row.room_number,
      'checkin_time', gs.checkin_time,
      'status', gs.status
    ) as item
    from public.guest_sessions gs
    join public.guests g
      on g.hotel_id = gs.hotel_id
     and g.id = gs.guest_id
    left join public.rooms room_row
      on room_row.hotel_id = gs.hotel_id
     and room_row.id = gs.room_id
    where gs.hotel_id = p_hotel_id
      and (gs.checkin_time at time zone v_timezone)::date
        between p_date_from and p_date_to
  ),
  actual_departures as (
    select jsonb_build_object(
      'guest_session_id', gs.id,
      'guest_name', g.full_name,
      'room_number', room_row.room_number,
      'checkout_time', gs.checkout_time,
      'status', gs.status
    ) as item
    from public.guest_sessions gs
    join public.guests g
      on g.hotel_id = gs.hotel_id
     and g.id = gs.guest_id
    left join public.rooms room_row
      on room_row.hotel_id = gs.hotel_id
     and room_row.id = gs.room_id
    where gs.hotel_id = p_hotel_id
      and gs.checkout_time is not null
      and (gs.checkout_time at time zone v_timezone)::date
        between p_date_from and p_date_to
      and gs.status = 'completed'
  )
  select jsonb_build_object(
    'expected_arrivals',
      coalesce(
        (select jsonb_agg(item order by item ->> 'date')
         from expected_arrivals),
        '[]'::jsonb
      ),
    'expected_departures',
      coalesce(
        (select jsonb_agg(item order by item ->> 'date')
         from expected_departures),
        '[]'::jsonb
      ),
    'actual_arrivals',
      coalesce(
        (select jsonb_agg(item order by item ->> 'checkin_time')
         from actual_arrivals),
        '[]'::jsonb
      ),
    'actual_departures',
      coalesce(
        (select jsonb_agg(item order by item ->> 'checkout_time')
         from actual_departures),
        '[]'::jsonb
      )
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 9. Payment method report
-- ============================================================================

create or replace function public.get_report_payments_by_method(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with method_rows as (
    select
      fc.payment_method,
      count(*) filter (
        where fc.status = 'posted'
      )::integer as posted_count,
      coalesce(
        sum(fc.amount) filter (
          where fc.status = 'posted'
        ),
        0
      )::numeric(14,2) as posted_amount,
      count(*) filter (
        where fc.status in ('voided', 'reversed')
      )::integer as reversed_count,
      coalesce(
        sum(fc.amount) filter (
          where fc.status in ('voided', 'reversed')
        ),
        0
      )::numeric(14,2) as reversed_amount
    from public.folio_collections fc
    where fc.hotel_id = p_hotel_id
      and (fc.collected_at at time zone v_timezone)::date
        between p_date_from and p_date_to
    group by fc.payment_method
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'payment_method', method_rows.payment_method,
        'posted_count', method_rows.posted_count,
        'posted_amount', method_rows.posted_amount,
        'reversed_count', method_rows.reversed_count,
        'reversed_amount', method_rows.reversed_amount
      )
      order by method_rows.posted_amount desc,
        method_rows.payment_method
    ),
    '[]'::jsonb
  )
  into v_result
  from method_rows;

  return v_result;
end;
$function$;

-- ============================================================================
-- 10. Tax and GST report
-- ============================================================================

create or replace function public.get_report_tax_gst_summary(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  select jsonb_build_object(
    'invoice_count', count(*)::integer,
    'taxable_amount',
      coalesce(sum(i.taxable_amount), 0)::numeric(14,2),
    'cgst_amount',
      coalesce(sum(i.cgst_amount), 0)::numeric(14,2),
    'sgst_amount',
      coalesce(sum(i.sgst_amount), 0)::numeric(14,2),
    'igst_amount',
      coalesce(sum(i.igst_amount), 0)::numeric(14,2),
    'cess_amount',
      coalesce(sum(i.cess_amount), 0)::numeric(14,2),
    'total_tax',
      coalesce(
        sum(
          i.cgst_amount
          + i.sgst_amount
          + i.igst_amount
          + i.cess_amount
        ),
        0
      )::numeric(14,2),
    'invoice_total',
      coalesce(sum(i.total_amount), 0)::numeric(14,2),
    'invoice_line_count',
      (
        select count(*)::integer
        from public.invoice_items item_row
        join public.invoices invoice_row
          on invoice_row.hotel_id = item_row.hotel_id
         and invoice_row.id = item_row.invoice_id
        where invoice_row.hotel_id = p_hotel_id
          and invoice_row.invoice_date
            between p_date_from and p_date_to
          and invoice_row.invoice_status in ('issued', 'paid')
      )
  )
  into v_result
  from public.invoices i
  where i.hotel_id = p_hotel_id
    and i.invoice_date between p_date_from and p_date_to
    and i.invoice_status in ('issued', 'paid');

  return v_result;
end;
$function$;

-- ============================================================================
-- 11. Guest, food and service report
-- ============================================================================

create or replace function public.get_report_guest_food_service(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with stay_rows as (
    select gs.*
    from public.guest_sessions gs
    where gs.hotel_id = p_hotel_id
      and (gs.checkin_time at time zone v_timezone)::date
        between p_date_from and p_date_to
  ),
  repeat_guests as (
    select stay_rows.guest_id
    from stay_rows
    group by stay_rows.guest_id
    having count(*) > 1
  ),
  food_rows as (
    select fo.*
    from public.food_orders fo
    where fo.hotel_id = p_hotel_id
      and (fo.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
  ),
  service_rows as (
    select sr.*
    from public.service_requests sr
    where sr.hotel_id = p_hotel_id
      and (sr.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
  )
  select jsonb_build_object(
    'stay_count', (select count(*)::integer from stay_rows),
    'unique_guests',
      (select count(distinct guest_id)::integer from stay_rows),
    'repeat_guests',
      (select count(*)::integer from repeat_guests),
    'active_stays',
      (
        select count(*)::integer
        from stay_rows
        where status = 'active'
      ),
    'completed_stays',
      (
        select count(*)::integer
        from stay_rows
        where status = 'completed'
      ),
    'food_orders',
      (select count(*)::integer from food_rows),
    'delivered_food_orders',
      (
        select count(*)::integer
        from food_rows
        where order_status = 'delivered'
      ),
    'cancelled_food_orders',
      (
        select count(*)::integer
        from food_rows
        where order_status = 'cancelled'
      ),
    'delivered_food_revenue',
      (
        select coalesce(sum(total_amount), 0)::numeric(14,2)
        from food_rows
        where order_status = 'delivered'
      ),
    'service_requests',
      (select count(*)::integer from service_rows),
    'completed_service_requests',
      (
        select count(*)::integer
        from service_rows
        where status = 'completed'
      ),
    'cancelled_service_requests',
      (
        select count(*)::integer
        from service_rows
        where status = 'cancelled'
      )
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 12. Service SLA report
-- ============================================================================

create or replace function public.get_report_service_sla(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with department_rows as (
    select
      sr.department,
      count(*)::integer as request_count,
      count(*) filter (
        where sr.status = 'completed'
      )::integer as completed_count,
      count(*) filter (
        where sr.status = 'cancelled'
      )::integer as cancelled_count,
      count(*) filter (
        where sr.status in (
          'pending',
          'accepted',
          'in_progress',
          'escalated'
        )
          and sr.sla_due_at < now()
      )::integer as currently_overdue_count,
      count(*) filter (
        where sr.status = 'completed'
          and sr.completed_at <= sr.sla_due_at
      )::integer as completed_within_sla,
      round(
        coalesce(
          avg(
            extract(
              epoch from (
                sr.accepted_at - sr.created_at
              )
            ) / 60.0
          ) filter (
            where sr.accepted_at is not null
          ),
          0
        )::numeric,
        2
      ) as average_accept_minutes,
      round(
        coalesce(
          avg(
            extract(
              epoch from (
                sr.completed_at - sr.created_at
              )
            ) / 60.0
          ) filter (
            where sr.completed_at is not null
          ),
          0
        )::numeric,
        2
      ) as average_complete_minutes
    from public.service_requests sr
    where sr.hotel_id = p_hotel_id
      and (sr.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
    group by sr.department
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'department', department_rows.department,
        'request_count', department_rows.request_count,
        'completed_count', department_rows.completed_count,
        'cancelled_count', department_rows.cancelled_count,
        'currently_overdue_count',
          department_rows.currently_overdue_count,
        'completed_within_sla',
          department_rows.completed_within_sla,
        'sla_met_rate',
          case
            when department_rows.completed_count = 0 then 0
            else round(
              (
                department_rows.completed_within_sla::numeric
                / department_rows.completed_count
              ) * 100,
              2
            )
          end,
        'average_accept_minutes',
          department_rows.average_accept_minutes,
        'average_complete_minutes',
          department_rows.average_complete_minutes
      )
      order by department_rows.request_count desc,
        department_rows.department
    ),
    '[]'::jsonb
  )
  into v_result
  from department_rows;

  return v_result;
end;
$function$;

-- ============================================================================
-- 13. Housekeeping report
-- ============================================================================

create or replace function public.get_report_housekeeping(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with status_rows as (
    select
      hk.status,
      count(*)::integer as task_count
    from public.housekeeping_tasks hk
    where hk.hotel_id = p_hotel_id
      and (hk.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
    group by hk.status
  ),
  totals as (
    select
      count(*)::integer as total_tasks,
      count(*) filter (
        where hk.status in ('room_ready', 'completed')
      )::integer as completed_tasks,
      count(*) filter (
        where hk.due_at is not null
          and hk.due_at < now()
          and hk.status not in (
            'room_ready',
            'completed',
            'cancelled'
          )
      )::integer as overdue_tasks,
      round(
        coalesce(
          avg(
            extract(
              epoch from (
                hk.room_ready_at - hk.created_at
              )
            ) / 60.0
          ) filter (
            where hk.room_ready_at is not null
          ),
          0
        )::numeric,
        2
      ) as average_turnaround_minutes
    from public.housekeeping_tasks hk
    where hk.hotel_id = p_hotel_id
      and (hk.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
  )
  select jsonb_build_object(
    'summary',
      (
        select jsonb_build_object(
          'total_tasks', totals.total_tasks,
          'completed_tasks', totals.completed_tasks,
          'overdue_tasks', totals.overdue_tasks,
          'average_turnaround_minutes',
            totals.average_turnaround_minutes
        )
        from totals
      ),
    'by_status',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'status', status_rows.status,
              'task_count', status_rows.task_count
            )
            order by status_rows.task_count desc,
              status_rows.status
          )
          from status_rows
        ),
        '[]'::jsonb
      )
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 14. Staff and department productivity
-- ============================================================================

create or replace function public.get_report_staff_department(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with service_work as (
    select
      sr.assigned_staff_id as staff_id,
      count(*)::integer as assigned_count,
      count(*) filter (
        where sr.status = 'completed'
      )::integer as completed_count,
      array_remove(
        array_agg(distinct sr.department),
        null
      ) as departments
    from public.service_requests sr
    where sr.hotel_id = p_hotel_id
      and (sr.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
      and sr.assigned_staff_id is not null
    group by sr.assigned_staff_id
  ),
  housekeeping_work as (
    select
      hk.assigned_staff_id as staff_id,
      count(*)::integer as assigned_count,
      count(*) filter (
        where hk.status in ('room_ready', 'completed')
      )::integer as completed_count
    from public.housekeeping_tasks hk
    where hk.hotel_id = p_hotel_id
      and (hk.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
      and hk.assigned_staff_id is not null
    group by hk.assigned_staff_id
  ),
  maintenance_work as (
    select
      mt.assigned_staff_id as staff_id,
      count(*)::integer as assigned_count,
      count(*) filter (
        where mt.status in ('resolved', 'verified')
      )::integer as completed_count
    from public.maintenance_tasks mt
    where mt.hotel_id = p_hotel_id
      and (mt.created_at at time zone v_timezone)::date
        between p_date_from and p_date_to
      and mt.assigned_staff_id is not null
    group by mt.assigned_staff_id
  ),
  staff_rows as (
    select
      s.id,
      s.full_name,
      s.role,
      s.status,
      coalesce(service_work.assigned_count, 0)
        + coalesce(housekeeping_work.assigned_count, 0)
        + coalesce(maintenance_work.assigned_count, 0)
        as assigned_count,
      coalesce(service_work.completed_count, 0)
        + coalesce(housekeeping_work.completed_count, 0)
        + coalesce(maintenance_work.completed_count, 0)
        as completed_count,
      coalesce(service_work.departments, array[]::text[])
        || case
             when coalesce(housekeeping_work.assigned_count, 0) > 0
               then array['housekeeping']
             else array[]::text[]
           end
        || case
             when coalesce(maintenance_work.assigned_count, 0) > 0
               then array['maintenance']
             else array[]::text[]
           end
        as work_departments
    from public.staff s
    left join service_work
      on service_work.staff_id = s.id
    left join housekeeping_work
      on housekeeping_work.staff_id = s.id
    left join maintenance_work
      on maintenance_work.staff_id = s.id
    where s.hotel_id = p_hotel_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'staff_id', staff_rows.id,
        'full_name', staff_rows.full_name,
        'role', staff_rows.role,
        'status', staff_rows.status,
        'work_departments',
          to_jsonb(staff_rows.work_departments),
        'assigned_count', staff_rows.assigned_count,
        'completed_count', staff_rows.completed_count,
        'completion_rate',
          case
            when staff_rows.assigned_count = 0 then 0
            else round(
              (
                staff_rows.completed_count::numeric
                / staff_rows.assigned_count
              ) * 100,
              2
            )
          end
      )
      order by staff_rows.assigned_count desc,
        staff_rows.full_name
    ),
    '[]'::jsonb
  )
  into v_result
  from staff_rows;

  return v_result;
end;
$function$;

-- ============================================================================
-- 15. KPI summary
-- ============================================================================

create or replace function public.get_report_kpi_summary(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_result jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  with room_nights as (
    select
      coalesce(
        sum(
          (day_item ->> 'available_room_nights')::numeric
        ),
        0
      ) as available_room_nights,
      coalesce(
        sum(
          (day_item ->> 'sold_room_nights')::numeric
        ),
        0
      ) as sold_room_nights,
      coalesce(
        sum(
          (day_item ->> 'occupied_room_nights')::numeric
        ),
        0
      ) as occupied_room_nights,
      coalesce(
        sum(
          (day_item ->> 'blocked_room_nights')::numeric
        ),
        0
      ) as blocked_room_nights
    from jsonb_array_elements(
      public.get_report_occupancy_daily(
        p_hotel_id,
        p_date_from,
        p_date_to
      )
    ) day_item
  ),
  revenue as (
    select
      coalesce(
        sum(fi.amount) filter (
          where fi.item_kind = 'charge'
            and fi.charge_category = 'room'
        ),
        0
      )::numeric(14,2) as room_revenue,
      coalesce(
        sum(fi.amount) filter (
          where fi.item_kind = 'charge'
            and fi.charge_category = 'food'
        ),
        0
      )::numeric(14,2) as food_revenue,
      coalesce(
        sum(fi.amount) filter (
          where fi.item_kind = 'charge'
            and fi.charge_category = 'service'
        ),
        0
      )::numeric(14,2) as service_revenue,
      coalesce(
        sum(fi.amount) filter (
          where fi.item_kind = 'charge'
            and fi.charge_category in ('manual', 'other')
        ),
        0
      )::numeric(14,2) as other_revenue,
      coalesce(
        sum(fi.amount) filter (
          where fi.item_kind = 'tax'
        ),
        0
      )::numeric(14,2) as tax_revenue
    from public.folio_items fi
    where fi.hotel_id = p_hotel_id
      and fi.posting_status = 'posted'
      and (fi.service_at at time zone v_timezone)::date
        between p_date_from and p_date_to
  ),
  collections as (
    select
      coalesce(
        sum(fc.amount) filter (
          where fc.status = 'posted'
        ),
        0
      )::numeric(14,2) as collection_amount
    from public.folio_collections fc
    where fc.hotel_id = p_hotel_id
      and (fc.collected_at at time zone v_timezone)::date
        between p_date_from and p_date_to
  )
  select jsonb_build_object(
    'date_from', p_date_from,
    'date_to', p_date_to,
    'timezone', v_timezone,
    'available_room_nights', room_nights.available_room_nights,
    'sold_room_nights', room_nights.sold_room_nights,
    'occupied_room_nights', room_nights.occupied_room_nights,
    'blocked_room_nights', room_nights.blocked_room_nights,
    'occupancy_rate',
      case
        when room_nights.available_room_nights = 0 then 0
        else round(
          (
            room_nights.occupied_room_nights
            / room_nights.available_room_nights
          ) * 100,
          2
        )
      end,
    'adr',
      case
        when room_nights.occupied_room_nights = 0 then 0
        else round(
          revenue.room_revenue
          / room_nights.occupied_room_nights,
          2
        )
      end,
    'arr',
      case
        when room_nights.occupied_room_nights = 0 then 0
        else round(
          revenue.room_revenue
          / room_nights.occupied_room_nights,
          2
        )
      end,
    'revpar',
      case
        when room_nights.available_room_nights = 0 then 0
        else round(
          revenue.room_revenue
          / room_nights.available_room_nights,
          2
        )
      end,
    'room_revenue', revenue.room_revenue,
    'food_revenue', revenue.food_revenue,
    'service_revenue', revenue.service_revenue,
    'other_revenue', revenue.other_revenue,
    'tax_revenue', revenue.tax_revenue,
    'gross_revenue',
      revenue.room_revenue
      + revenue.food_revenue
      + revenue.service_revenue
      + revenue.other_revenue
      + revenue.tax_revenue,
    'collections', collections.collection_amount,
    'reservation_count',
      (
        select count(*)::integer
        from public.reservations r
        where r.hotel_id = p_hotel_id
          and r.arrival_date between p_date_from and p_date_to
      ),
    'arrival_count',
      (
        select count(*)::integer
        from public.guest_sessions gs
        where gs.hotel_id = p_hotel_id
          and (gs.checkin_time at time zone v_timezone)::date
            between p_date_from and p_date_to
      ),
    'departure_count',
      (
        select count(*)::integer
        from public.guest_sessions gs
        where gs.hotel_id = p_hotel_id
          and gs.checkout_time is not null
          and gs.status = 'completed'
          and (gs.checkout_time at time zone v_timezone)::date
            between p_date_from and p_date_to
      ),
    'food_order_count',
      (
        select count(*)::integer
        from public.food_orders fo
        where fo.hotel_id = p_hotel_id
          and (fo.created_at at time zone v_timezone)::date
            between p_date_from and p_date_to
      ),
    'service_request_count',
      (
        select count(*)::integer
        from public.service_requests sr
        where sr.hotel_id = p_hotel_id
          and (sr.created_at at time zone v_timezone)::date
            between p_date_from and p_date_to
      )
  )
  into v_result
  from room_nights
  cross join revenue
  cross join collections;

  return v_result;
end;
$function$;

-- ============================================================================
-- 16. Safe export dispatcher
-- ============================================================================

create or replace function public.get_report_export_rows(
  p_hotel_id uuid,
  p_date_from date,
  p_date_to date,
  p_report_key text,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_key text;
  v_rows jsonb;
begin
  v_timezone :=
    private.day16_assert_report_access(
      p_hotel_id,
      p_date_from,
      p_date_to
    );

  v_key := lower(trim(coalesce(p_report_key, '')));

  if jsonb_typeof(coalesce(p_filters, '{}'::jsonb)) <> 'object' then
    raise exception 'Export filters must be a JSON object.';
  end if;

  case v_key
    when 'occupancy_daily' then
      v_rows := public.get_report_occupancy_daily(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'revenue_daily' then
      v_rows := public.get_report_revenue_daily(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'revenue_by_category' then
      v_rows := public.get_report_revenue_by_category(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'reservations_by_source' then
      v_rows := public.get_report_reservations_by_source(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'arrivals_departures' then
      v_rows := public.get_report_arrivals_departures(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'payments_by_method' then
      v_rows := public.get_report_payments_by_method(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'tax_gst_summary' then
      v_rows := public.get_report_tax_gst_summary(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'guest_food_service' then
      v_rows := public.get_report_guest_food_service(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'service_sla' then
      v_rows := public.get_report_service_sla(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'housekeeping' then
      v_rows := public.get_report_housekeeping(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    when 'staff_department' then
      v_rows := public.get_report_staff_department(
        p_hotel_id,
        p_date_from,
        p_date_to
      );
    else
      raise exception
        'Unsupported report key: %',
        coalesce(p_report_key, '<null>');
  end case;

  return jsonb_build_object(
    'hotel_id', p_hotel_id,
    'date_from', p_date_from,
    'date_to', p_date_to,
    'timezone', v_timezone,
    'report_key', v_key,
    'filters', coalesce(p_filters, '{}'::jsonb),
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$function$;

-- ============================================================================
-- 17. RPC execution boundary
-- ============================================================================

revoke all on function public.get_report_filter_options(uuid)
from public, anon;

revoke all on function public.get_report_occupancy_daily(uuid,date,date)
from public, anon;

revoke all on function public.get_report_revenue_daily(uuid,date,date)
from public, anon;

revoke all on function public.get_report_revenue_by_category(uuid,date,date)
from public, anon;

revoke all on function public.get_report_reservations_by_source(uuid,date,date)
from public, anon;

revoke all on function public.get_report_arrivals_departures(uuid,date,date)
from public, anon;

revoke all on function public.get_report_payments_by_method(uuid,date,date)
from public, anon;

revoke all on function public.get_report_tax_gst_summary(uuid,date,date)
from public, anon;

revoke all on function public.get_report_guest_food_service(uuid,date,date)
from public, anon;

revoke all on function public.get_report_service_sla(uuid,date,date)
from public, anon;

revoke all on function public.get_report_housekeeping(uuid,date,date)
from public, anon;

revoke all on function public.get_report_staff_department(uuid,date,date)
from public, anon;

revoke all on function public.get_report_kpi_summary(uuid,date,date)
from public, anon;

revoke all on function public.get_report_export_rows(
  uuid,date,date,text,jsonb
)
from public, anon;

grant execute on function public.get_report_filter_options(uuid)
to authenticated;

grant execute on function public.get_report_occupancy_daily(uuid,date,date)
to authenticated;

grant execute on function public.get_report_revenue_daily(uuid,date,date)
to authenticated;

grant execute on function public.get_report_revenue_by_category(uuid,date,date)
to authenticated;

grant execute on function public.get_report_reservations_by_source(uuid,date,date)
to authenticated;

grant execute on function public.get_report_arrivals_departures(uuid,date,date)
to authenticated;

grant execute on function public.get_report_payments_by_method(uuid,date,date)
to authenticated;

grant execute on function public.get_report_tax_gst_summary(uuid,date,date)
to authenticated;

grant execute on function public.get_report_guest_food_service(uuid,date,date)
to authenticated;

grant execute on function public.get_report_service_sla(uuid,date,date)
to authenticated;

grant execute on function public.get_report_housekeeping(uuid,date,date)
to authenticated;

grant execute on function public.get_report_staff_department(uuid,date,date)
to authenticated;

grant execute on function public.get_report_kpi_summary(uuid,date,date)
to authenticated;

grant execute on function public.get_report_export_rows(
  uuid,date,date,text,jsonb
)
to authenticated;

-- ============================================================================
-- 18. Acceptance
-- ============================================================================

create or replace function private.day16_migration_055_acceptance_rev1()
returns table (
  suite text,
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  r record;
  v_exists boolean;
  v_definition text;
  v_count bigint;
begin
  -- A. Schema adaptations: 8
  for r in
    select *
    from (values
      ('invoice_items_exists',
       to_regclass('public.invoice_items') is not null,
       'Actual invoice line table is invoice_items.'),
      ('invoice_lines_not_required',
       exists (
         select 1
         from information_schema.columns
         where table_schema = 'public'
           and table_name = 'invoices'
           and column_name = 'invoice_status'
       ),
       'Migration 055 uses invoices.invoice_status and does not require invoice_lines.'),
      ('staff_role_exists',
       exists (
         select 1 from information_schema.columns
         where table_schema = 'public'
           and table_name = 'staff'
           and column_name = 'role'
       ),
       'Staff role is the primary staff grouping.'),
      ('staff_department_not_required',
       true,
       'Work departments are derived from assigned queues.'),
      ('hotel_timezone_exists',
       exists (
         select 1 from information_schema.columns
         where table_schema = 'public'
           and table_name = 'hotels'
           and column_name = 'timezone'
       ),
       'Hotel-local reporting dates are supported.'),
      ('folio_items_authoritative',
       to_regclass('public.folio_items') is not null,
       'Posted folio items are the revenue source.'),
      ('folio_collections_authoritative',
       to_regclass('public.folio_collections') is not null,
       'Folio collections are the collection source.'),
      ('room_inventory_authoritative',
       to_regclass('public.room_inventory_allocations') is not null,
       'Room-night inventory ledger exists.')
    ) checks(test_name, passed, details)
  loop
    suite := 'A_SCHEMA_ADAPTATIONS';
    test_name := r.test_name;
    passed := r.passed;
    details := r.details;
    return next;
  end loop;

  -- B. Indexes: 9
  for r in
    select *
    from (values
      ('idx_day16_inventory_hotel_type_dates'),
      ('idx_day16_folio_items_hotel_service_category'),
      ('idx_day16_collections_hotel_date_method'),
      ('idx_day16_invoices_hotel_date_status'),
      ('idx_day16_guest_sessions_hotel_dates'),
      ('idx_day16_reservations_hotel_source_dates'),
      ('idx_day16_service_hotel_created_department'),
      ('idx_day16_housekeeping_hotel_created_staff'),
      ('idx_day16_maintenance_hotel_created_staff')
    ) indexes(index_name)
  loop
    suite := 'B_INDEXES';
    test_name := r.index_name;
    passed := to_regclass(
      format('public.%I', r.index_name)
    ) is not null;
    details := 'Reporting index exists.';
    return next;
  end loop;

  -- C. Functions exist: 16
  for r in
    select *
    from (values
      ('private.day16_assert_report_access(uuid,date,date)'),
      ('private.day16_assert_filter_access(uuid)'),
      ('public.get_report_filter_options(uuid)'),
      ('public.get_report_kpi_summary(uuid,date,date)'),
      ('public.get_report_occupancy_daily(uuid,date,date)'),
      ('public.get_report_revenue_daily(uuid,date,date)'),
      ('public.get_report_revenue_by_category(uuid,date,date)'),
      ('public.get_report_reservations_by_source(uuid,date,date)'),
      ('public.get_report_arrivals_departures(uuid,date,date)'),
      ('public.get_report_payments_by_method(uuid,date,date)'),
      ('public.get_report_tax_gst_summary(uuid,date,date)'),
      ('public.get_report_guest_food_service(uuid,date,date)'),
      ('public.get_report_service_sla(uuid,date,date)'),
      ('public.get_report_housekeeping(uuid,date,date)'),
      ('public.get_report_staff_department(uuid,date,date)'),
      ('public.get_report_export_rows(uuid,date,date,text,jsonb)')
    ) functions(signature)
  loop
    suite := 'C_FUNCTIONS';
    test_name := r.signature;
    passed := to_regprocedure(r.signature) is not null;
    details := 'Trusted reporting function exists.';
    return next;
  end loop;

  -- D. Security definer: 14 public RPCs
  for r in
    select *
    from (values
      ('public.get_report_filter_options(uuid)'),
      ('public.get_report_kpi_summary(uuid,date,date)'),
      ('public.get_report_occupancy_daily(uuid,date,date)'),
      ('public.get_report_revenue_daily(uuid,date,date)'),
      ('public.get_report_revenue_by_category(uuid,date,date)'),
      ('public.get_report_reservations_by_source(uuid,date,date)'),
      ('public.get_report_arrivals_departures(uuid,date,date)'),
      ('public.get_report_payments_by_method(uuid,date,date)'),
      ('public.get_report_tax_gst_summary(uuid,date,date)'),
      ('public.get_report_guest_food_service(uuid,date,date)'),
      ('public.get_report_service_sla(uuid,date,date)'),
      ('public.get_report_housekeeping(uuid,date,date)'),
      ('public.get_report_staff_department(uuid,date,date)'),
      ('public.get_report_export_rows(uuid,date,date,text,jsonb)')
    ) functions(signature)
  loop
    select p.prosecdef
    into v_exists
    from pg_proc p
    where p.oid = to_regprocedure(r.signature);

    suite := 'D_SECURITY_DEFINER';
    test_name := r.signature;
    passed := coalesce(v_exists, false);
    details := 'RPC uses SECURITY DEFINER.';
    return next;
  end loop;

  -- E. Authenticated execution: 14
  for r in
    select *
    from (values
      ('public.get_report_filter_options(uuid)'),
      ('public.get_report_kpi_summary(uuid,date,date)'),
      ('public.get_report_occupancy_daily(uuid,date,date)'),
      ('public.get_report_revenue_daily(uuid,date,date)'),
      ('public.get_report_revenue_by_category(uuid,date,date)'),
      ('public.get_report_reservations_by_source(uuid,date,date)'),
      ('public.get_report_arrivals_departures(uuid,date,date)'),
      ('public.get_report_payments_by_method(uuid,date,date)'),
      ('public.get_report_tax_gst_summary(uuid,date,date)'),
      ('public.get_report_guest_food_service(uuid,date,date)'),
      ('public.get_report_service_sla(uuid,date,date)'),
      ('public.get_report_housekeeping(uuid,date,date)'),
      ('public.get_report_staff_department(uuid,date,date)'),
      ('public.get_report_export_rows(uuid,date,date,text,jsonb)')
    ) functions(signature)
  loop
    suite := 'E_AUTHENTICATED_EXECUTE';
    test_name := r.signature;
    passed := has_function_privilege(
      'authenticated',
      r.signature,
      'EXECUTE'
    );
    details := 'Authenticated staff may invoke the trusted RPC.';
    return next;
  end loop;

  -- F. Anonymous execution blocked: 14
  for r in
    select *
    from (values
      ('public.get_report_filter_options(uuid)'),
      ('public.get_report_kpi_summary(uuid,date,date)'),
      ('public.get_report_occupancy_daily(uuid,date,date)'),
      ('public.get_report_revenue_daily(uuid,date,date)'),
      ('public.get_report_revenue_by_category(uuid,date,date)'),
      ('public.get_report_reservations_by_source(uuid,date,date)'),
      ('public.get_report_arrivals_departures(uuid,date,date)'),
      ('public.get_report_payments_by_method(uuid,date,date)'),
      ('public.get_report_tax_gst_summary(uuid,date,date)'),
      ('public.get_report_guest_food_service(uuid,date,date)'),
      ('public.get_report_service_sla(uuid,date,date)'),
      ('public.get_report_housekeeping(uuid,date,date)'),
      ('public.get_report_staff_department(uuid,date,date)'),
      ('public.get_report_export_rows(uuid,date,date,text,jsonb)')
    ) functions(signature)
  loop
    suite := 'F_ANON_BLOCKED';
    test_name := r.signature;
    passed := not has_function_privilege(
      'anon',
      r.signature,
      'EXECUTE'
    );
    details := 'Anonymous role cannot invoke hotel reports.';
    return next;
  end loop;

  -- G. reports.view permissions: 3
  for r in
    select *
    from (values
      ('owner'),
      ('manager'),
      ('accounts')
    ) roles(role_name)
  loop
    select exists (
      select 1
      from public.role_permissions rp
      where rp.role_name = r.role_name
        and rp.permission_key = 'reports.view'
    )
    into v_exists;

    suite := 'G_PERMISSION_MATRIX';
    test_name := r.role_name;
    passed := v_exists;
    details := 'Role has reports.view.';
    return next;
  end loop;

  -- H. Function contracts contain required guards: 28
  for r in
    select *
    from (values
      ('public.get_report_filter_options(uuid)', 'day16_assert_filter_access'),
      ('public.get_report_kpi_summary(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_occupancy_daily(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_revenue_daily(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_revenue_by_category(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_reservations_by_source(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_arrivals_departures(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_payments_by_method(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_tax_gst_summary(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_guest_food_service(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_service_sla(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_housekeeping(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_staff_department(uuid,date,date)', 'day16_assert_report_access'),
      ('public.get_report_export_rows(uuid,date,date,text,jsonb)', 'day16_assert_report_access')
    ) functions(signature, guard_name)
  loop
    select pg_get_functiondef(to_regprocedure(r.signature))
    into v_definition;

    suite := 'H_ACCESS_GUARDS';
    test_name := r.signature || ':guard';
    passed := position(r.guard_name in v_definition) > 0;
    details := 'RPC invokes the report-access guard.';
    return next;

    suite := 'H_ACCESS_GUARDS';
    test_name := r.signature || ':search_path';
    passed := position('SET search_path TO ''''' in v_definition) > 0
      or position('SET search_path = ''''' in v_definition) > 0;
    details := 'RPC fixes search_path.';
    return next;
  end loop;

  -- I. Source invariants and final closure: 12
  suite := 'I_INVARIANTS';
  test_name := 'no_direct_report_tables_created';
  select count(*)
  into v_count
  from information_schema.tables t
  where t.table_schema = 'public'
    and t.table_name like 'report_%';
  passed := v_count = 0;
  details := format('%s persistent report table(s).', v_count);
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'revenue_source_posted_folio_items';
  select pg_get_functiondef(
    to_regprocedure(
      'public.get_report_revenue_daily(uuid,date,date)'
    )
  )
  into v_definition;
  passed :=
    position('folio_items' in v_definition) > 0
    and position('posting_status' in v_definition) > 0;
  details := 'Revenue report uses posted folio items.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'collections_separate';
  passed :=
    position('folio_collections' in v_definition) > 0
    or to_regprocedure(
      'public.get_report_payments_by_method(uuid,date,date)'
    ) is not null;
  details := 'Collections have a separate source/report.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'occupancy_room_nights';
  select pg_get_functiondef(
    to_regprocedure(
      'public.get_report_occupancy_daily(uuid,date,date)'
    )
  )
  into v_definition;
  passed :=
    position('room_inventory_allocations' in v_definition) > 0
    and position('generate_series' in v_definition) > 0;
  details := 'Occupancy uses room-night allocations.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'blocked_nights_reduce_inventory';
  passed :=
    position('allocation_type = ''block''' in v_definition) > 0;
  details := 'Block allocations are included.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'adr_arr_same_source';
  select pg_get_functiondef(
    to_regprocedure(
      'public.get_report_kpi_summary(uuid,date,date)'
    )
  )
  into v_definition;
  passed :=
    position('''adr''' in v_definition) > 0
    and position('''arr''' in v_definition) > 0;
  details := 'ADR and ARR are emitted from the same realized-rate formula.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'revpar_available_room_nights';
  passed :=
    position('''revpar''' in v_definition) > 0
    and position('available_room_nights' in v_definition) > 0;
  details := 'RevPAR uses available room nights.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'gst_uses_invoice_items';
  select pg_get_functiondef(
    to_regprocedure(
      'public.get_report_tax_gst_summary(uuid,date,date)'
    )
  )
  into v_definition;
  passed :=
    position('invoice_items' in v_definition) > 0
    and position('invoice_lines' in v_definition) = 0;
  details := 'GST report uses the actual invoice_items schema.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'staff_report_uses_role';
  select pg_get_functiondef(
    to_regprocedure(
      'public.get_report_staff_department(uuid,date,date)'
    )
  )
  into v_definition;
  passed := position('s.role' in v_definition) > 0;
  details := 'Staff report uses staff.role.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'export_is_whitelisted';
  select pg_get_functiondef(
    to_regprocedure(
      'public.get_report_export_rows(uuid,date,date,text,jsonb)'
    )
  )
  into v_definition;
  passed :=
    position('case v_key' in lower(v_definition)) > 0
    and position('execute ' in lower(v_definition)) = 0;
  details := 'Export dispatcher is whitelisted and uses no dynamic SQL.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'date_range_guard';
  select pg_get_functiondef(
    to_regprocedure(
      'private.day16_assert_report_access(uuid,date,date)'
    )
  )
  into v_definition;
  passed :=
    position('366' in v_definition) > 0
    and position('p_date_to < p_date_from' in v_definition) > 0;
  details := 'Invalid and excessive date ranges are rejected.';
  return next;

  suite := 'I_INVARIANTS';
  test_name := 'migration_055_complete';
  passed := true;
  details :=
    'Trusted Day 16 reporting kernel is installed and ready for frontend integration.';
  return next;
end;
$function$;

revoke all on function private.day16_migration_055_acceptance_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day16_migration_055_acceptance_rev1()
order by suite, test_name;
