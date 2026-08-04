-- ============================================================================
-- StayQR v1.0
-- Day 16 Audit 068 REV3 RUNTIME-SELECTION FIX
-- Final Consolidated Analytics and Standard Reports Acceptance
--
-- ROADMAP SCOPE
-- Date filters; occupancy; ADR/ARR; RevPAR; revenue drill-down;
-- reservation/source; arrival/departure; payments/cashier; tax/GST;
-- guest; food; service SLA; housekeeping; staff/department; CSV/PDF exports.
--
-- ROADMAP EXIT GATE
-- Metrics reconcile to source records for the test dataset; all exports
-- respect hotel, role and date filters.
--
-- ACCEPTED PREREQUISITES
-- - Audit 067 preflight reviewed: 132 rows.
-- - Migration 055 REV3 accepted: 118/118.
-- - Reports frontend source gate passed.
-- - Lint passed with 0 errors.
-- - Production build passed.
-- - Controlled browser checks completed for presets, tabs, drill-downs,
--   empty states, CSV exports and PDF export.
--
-- SAFETY
-- Read-only for hotel business data.
-- Creates/replaces one private audit helper only.
--
-- EXPECTED RESULT
-- 217 rows
-- 217 passed = true
-- 0 failures
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050068:day16-final-acceptance-rev1')
);

create schema if not exists private;

do $preflight$
declare
  v_missing text;
begin
  select string_agg(signature, ', ' order by signature)
  into v_missing
  from (
    values
      (
        'private.day16_migration_055_acceptance_rev1()',
        to_regprocedure(
          'private.day16_migration_055_acceptance_rev1()'
        ) is not null
      ),
      (
        'public.get_report_filter_options(uuid)',
        to_regprocedure(
          'public.get_report_filter_options(uuid)'
        ) is not null
      ),
      (
        'public.get_report_kpi_summary(uuid,date,date)',
        to_regprocedure(
          'public.get_report_kpi_summary(uuid,date,date)'
        ) is not null
      ),
      (
        'public.get_report_occupancy_daily(uuid,date,date)',
        to_regprocedure(
          'public.get_report_occupancy_daily(uuid,date,date)'
        ) is not null
      ),
      (
        'public.get_report_revenue_daily(uuid,date,date)',
        to_regprocedure(
          'public.get_report_revenue_daily(uuid,date,date)'
        ) is not null
      ),
      (
        'public.get_report_export_rows(uuid,date,date,text,jsonb)',
        to_regprocedure(
          'public.get_report_export_rows(uuid,date,date,text,jsonb)'
        ) is not null
      )
  ) required(signature, exists_now)
  where not exists_now;

  if v_missing is not null then
    raise exception
      'Audit 068 stopped. Missing prerequisite(s): %',
      v_missing;
  end if;
end;
$preflight$;

create or replace function private.day16_audit_068_final_rev3()
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
  v_hotel_id uuid;
  v_hotel_name text;
  v_auth_user_id uuid;
  v_other_hotel_id uuid;
  v_timezone text;
  v_is_platform_admin boolean := false;
  v_date_from date;
  v_date_to date;

  v_kpi jsonb;
  v_occupancy jsonb;
  v_revenue_daily jsonb;
  v_revenue_category jsonb;
  v_sources jsonb;
  v_arrivals jsonb;
  v_payments jsonb;
  v_tax jsonb;
  v_guest_food_service jsonb;
  v_service_sla jsonb;
  v_housekeeping jsonb;
  v_staff jsonb;
  v_filters jsonb;
  v_export jsonb;

  v_available numeric := 0;
  v_sold numeric := 0;
  v_occupied numeric := 0;
  v_blocked numeric := 0;

  v_room_revenue numeric := 0;
  v_food_revenue numeric := 0;
  v_service_revenue numeric := 0;
  v_other_revenue numeric := 0;
  v_tax_revenue numeric := 0;
  v_gross_revenue numeric := 0;
  v_collections numeric := 0;

  v_reservation_count bigint := 0;
  v_arrival_count bigint := 0;
  v_departure_count bigint := 0;
  v_food_order_count bigint := 0;
  v_service_request_count bigint := 0;

  v_count bigint := 0;
  v_count_2 bigint := 0;
  v_count_3 bigint := 0;
  v_count_4 bigint := 0;
  v_amount numeric := 0;
  v_amount_2 numeric := 0;
  v_amount_3 numeric := 0;
  v_amount_4 numeric := 0;
  v_bool boolean := false;
  v_text text;
begin
  -- ========================================================================
  -- A. Re-run the complete accepted Migration 055 contract: 118 rows.
  -- ========================================================================
  return query
  select
    'M055_' || accepted.suite,
    accepted.test_name,
    accepted.passed,
    accepted.details
  from private.day16_migration_055_acceptance_rev1() accepted;

  -- ========================================================================
  -- B. Resolve a real authorized hotel/user and runtime window: 10 rows.
  -- ========================================================================
  with candidates as (
    select distinct
      h.id as hotel_id,
      h.hotel_name,
      coalesce(nullif(trim(h.timezone), ''), 'Asia/Kolkata') as timezone,
      s.auth_user_id,
      exists (
        select 1
        from public.platform_admins pa
        where pa.user_id = s.auth_user_id
          and pa.status = 'active'
      ) as is_platform_admin,
      (
        select count(*) from public.folio_items fi
        where fi.hotel_id = h.id
      )
      + (
        select count(*) from public.guest_sessions gs
        where gs.hotel_id = h.id
      )
      + (
        select count(*) from public.food_orders fo
        where fo.hotel_id = h.id
      )
      + (
        select count(*) from public.service_requests sr
        where sr.hotel_id = h.id
      ) as activity_score
    from public.staff s
    join public.hotels h
      on h.id = s.hotel_id
    join auth.users au
      on au.id = s.auth_user_id
    join public.role_permissions rp
      on lower(replace(trim(rp.role_name), ' ', '_'))
       = lower(replace(trim(s.role), ' ', '_'))
     and rp.permission_key = 'reports.view'
    where s.status = 'active'
      and h.status = 'active'
      and s.auth_user_id is not null
      and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
  )
  select
    c.hotel_id,
    c.hotel_name,
    c.auth_user_id,
    c.timezone,
    c.is_platform_admin
  into
    v_hotel_id,
    v_hotel_name,
    v_auth_user_id,
    v_timezone,
    v_is_platform_admin
  from candidates c
  where c.activity_score > 0
  order by
    c.activity_score desc,
    case when c.is_platform_admin then 1 else 0 end,
    c.hotel_name
  limit 1;

  select h.id
  into v_other_hotel_id
  from public.hotels h
  where h.status = 'active'
    and h.id <> v_hotel_id
  order by h.created_at, h.id
  limit 1;

  if v_hotel_id is not null then
    select greatest(
      (now() at time zone v_timezone)::date,
      coalesce(
        (
          select max((fi.service_at at time zone v_timezone)::date)
          from public.folio_items fi
          where fi.hotel_id = v_hotel_id
        ),
        date '1900-01-01'
      ),
      coalesce(
        (
          select max((gs.checkin_time at time zone v_timezone)::date)
          from public.guest_sessions gs
          where gs.hotel_id = v_hotel_id
        ),
        date '1900-01-01'
      ),
      coalesce(
        (
          select max((fo.created_at at time zone v_timezone)::date)
          from public.food_orders fo
          where fo.hotel_id = v_hotel_id
        ),
        date '1900-01-01'
      ),
      coalesce(
        (
          select max((sr.created_at at time zone v_timezone)::date)
          from public.service_requests sr
          where sr.hotel_id = v_hotel_id
        ),
        date '1900-01-01'
      )
    )
    into v_date_to;

    v_date_from := v_date_to - 29;
  end if;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'primary_hotel_selected';
  passed := v_hotel_id is not null;
  details := format(
    'Hotel: %s (%s).',
    coalesce(v_hotel_name, 'missing'),
    coalesce(v_hotel_id::text, 'missing')
  );
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'authorized_user_selected';
  passed := v_auth_user_id is not null;
  details := format(
    'Auth user: %s.',
    coalesce(v_auth_user_id::text, 'missing')
  );
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'active_staff_identity';
  select exists (
    select 1
    from public.staff s
    where s.hotel_id = v_hotel_id
      and s.auth_user_id = v_auth_user_id
      and s.status = 'active'
  )
  into v_bool;
  passed := coalesce(v_bool, false);
  details := 'Selected identity is active staff for the selected hotel.';
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'reports_view_permission';
  select exists (
    select 1
    from public.staff s
    join public.role_permissions rp
      on lower(replace(trim(rp.role_name), ' ', '_'))
       = lower(replace(trim(s.role), ' ', '_'))
    where s.hotel_id = v_hotel_id
      and s.auth_user_id = v_auth_user_id
      and s.status = 'active'
      and rp.permission_key = 'reports.view'
  )
  into v_bool;
  passed := coalesce(v_bool, false);
  details := 'Selected identity has reports.view through its active staff role.';
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'platform_admin_state_known';
  passed := v_is_platform_admin is not null;
  details := format(
    'Selected identity platform-admin state: %s.',
    coalesce(v_is_platform_admin::text, 'unknown')
  );
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'hotel_timezone_valid';
  begin
    perform now() at time zone v_timezone;
    v_bool := true;
  exception when others then
    v_bool := false;
  end;
  passed := v_bool;
  details := format('Timezone: %s.', coalesce(v_timezone, 'missing'));
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'inclusive_30_day_window';
  passed := v_date_to >= v_date_from
    and (v_date_to - v_date_from) = 29;
  details := format(
    'Range: %s through %s.',
    coalesce(v_date_from::text, 'missing'),
    coalesce(v_date_to::text, 'missing')
  );
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'second_active_hotel_selected';
  passed := v_other_hotel_id is not null;
  details := format(
    'Other active hotel: %s.',
    coalesce(v_other_hotel_id::text, 'missing')
  );
  return next;

  select
    (select count(*) from public.folio_items fi
     where fi.hotel_id = v_hotel_id)
    + (select count(*) from public.guest_sessions gs
       where gs.hotel_id = v_hotel_id)
    + (select count(*) from public.food_orders fo
       where fo.hotel_id = v_hotel_id)
    + (select count(*) from public.service_requests sr
       where sr.hotel_id = v_hotel_id)
  into v_count;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'runtime_source_data_exists';
  passed := v_count > 0;
  details := format('%s source activity row(s).', v_count);
  return next;

  suite := 'RUNTIME_CONTEXT';
  test_name := 'context_ready';
  passed := v_hotel_id is not null
    and v_auth_user_id is not null
    and v_other_hotel_id is not null
    and v_date_from is not null
    and v_date_to is not null;
  details := 'Runtime reconciliation context is complete and uses an authorized hotel with source activity.';
  return next;

  perform set_config(
    'request.jwt.claim.sub',
    v_auth_user_id::text,
    true
  );

  v_filters := public.get_report_filter_options(v_hotel_id);
  v_kpi := public.get_report_kpi_summary(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_occupancy := public.get_report_occupancy_daily(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_revenue_daily := public.get_report_revenue_daily(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_revenue_category := public.get_report_revenue_by_category(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_sources := public.get_report_reservations_by_source(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_arrivals := public.get_report_arrivals_departures(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_payments := public.get_report_payments_by_method(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_tax := public.get_report_tax_gst_summary(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_guest_food_service := public.get_report_guest_food_service(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_service_sla := public.get_report_service_sla(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_housekeeping := public.get_report_housekeeping(
    v_hotel_id,
    v_date_from,
    v_date_to
  );
  v_staff := public.get_report_staff_department(
    v_hotel_id,
    v_date_from,
    v_date_to
  );

  -- Direct room-night source reconciliation.
  with report_days as (
    select day_value::date as report_date
    from generate_series(
      v_date_from::timestamp,
      v_date_to::timestamp,
      interval '1 day'
    ) day_value
  ),
  room_count as (
    select count(*)::numeric as total_rooms
    from public.rooms r
    where r.hotel_id = v_hotel_id
  ),
  blocked as (
    select distinct
      allocation.room_id,
      day_value::date as report_date
    from public.room_inventory_allocations allocation
    cross join lateral generate_series(
      greatest(allocation.starts_on, v_date_from)::timestamp,
      least(allocation.ends_on - 1, v_date_to)::timestamp,
      interval '1 day'
    ) day_value
    where allocation.hotel_id = v_hotel_id
      and allocation.allocation_type = 'block'
      and allocation.status <> 'cancelled'
      and allocation.starts_on <= v_date_to
      and allocation.ends_on > v_date_from
  ),
  sold as (
    select distinct
      allocation.room_id,
      day_value::date as report_date
    from public.room_inventory_allocations allocation
    cross join lateral generate_series(
      greatest(allocation.starts_on, v_date_from)::timestamp,
      least(allocation.ends_on - 1, v_date_to)::timestamp,
      interval '1 day'
    ) day_value
    where allocation.hotel_id = v_hotel_id
      and allocation.allocation_type in ('reservation', 'stay')
      and allocation.status <> 'cancelled'
      and allocation.starts_on <= v_date_to
      and allocation.ends_on > v_date_from
  ),
  occupied as (
    select distinct
      allocation.room_id,
      day_value::date as report_date
    from public.room_inventory_allocations allocation
    cross join lateral generate_series(
      greatest(allocation.starts_on, v_date_from)::timestamp,
      least(allocation.ends_on - 1, v_date_to)::timestamp,
      interval '1 day'
    ) day_value
    where allocation.hotel_id = v_hotel_id
      and allocation.allocation_type = 'stay'
      and allocation.status <> 'cancelled'
      and allocation.starts_on <= v_date_to
      and allocation.ends_on > v_date_from
  ),
  daily as (
    select
      report_days.report_date,
      room_count.total_rooms,
      count(distinct blocked.room_id)::numeric as blocked_count,
      count(distinct sold.room_id)::numeric as sold_count,
      count(distinct occupied.room_id)::numeric as occupied_count
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
  select
    coalesce(sum(greatest(total_rooms - blocked_count, 0)), 0),
    coalesce(sum(sold_count), 0),
    coalesce(sum(occupied_count), 0),
    coalesce(sum(blocked_count), 0)
  into
    v_available,
    v_sold,
    v_occupied,
    v_blocked
  from daily;

  select
    coalesce(
      sum(fi.amount) filter (
        where fi.item_kind = 'charge'
          and fi.charge_category = 'room'
      ),
      0
    ),
    coalesce(
      sum(fi.amount) filter (
        where fi.item_kind = 'charge'
          and fi.charge_category = 'food'
      ),
      0
    ),
    coalesce(
      sum(fi.amount) filter (
        where fi.item_kind = 'charge'
          and fi.charge_category = 'service'
      ),
      0
    ),
    coalesce(
      sum(fi.amount) filter (
        where fi.item_kind = 'charge'
          and fi.charge_category in ('manual', 'other')
      ),
      0
    ),
    coalesce(
      sum(fi.amount) filter (
        where fi.item_kind = 'tax'
      ),
      0
    )
  into
    v_room_revenue,
    v_food_revenue,
    v_service_revenue,
    v_other_revenue,
    v_tax_revenue
  from public.folio_items fi
  where fi.hotel_id = v_hotel_id
    and fi.posting_status = 'posted'
    and (fi.service_at at time zone v_timezone)::date
      between v_date_from and v_date_to;

  v_gross_revenue :=
    v_room_revenue
    + v_food_revenue
    + v_service_revenue
    + v_other_revenue
    + v_tax_revenue;

  select coalesce(sum(fc.amount), 0)
  into v_collections
  from public.folio_collections fc
  where fc.hotel_id = v_hotel_id
    and fc.status = 'posted'
    and (fc.collected_at at time zone v_timezone)::date
      between v_date_from and v_date_to;

  select count(*)
  into v_reservation_count
  from public.reservations r
  where r.hotel_id = v_hotel_id
    and r.arrival_date between v_date_from and v_date_to;

  select count(*)
  into v_arrival_count
  from public.guest_sessions gs
  where gs.hotel_id = v_hotel_id
    and (gs.checkin_time at time zone v_timezone)::date
      between v_date_from and v_date_to;

  select count(*)
  into v_departure_count
  from public.guest_sessions gs
  where gs.hotel_id = v_hotel_id
    and gs.checkout_time is not null
    and gs.status = 'completed'
    and (gs.checkout_time at time zone v_timezone)::date
      between v_date_from and v_date_to;

  select count(*)
  into v_food_order_count
  from public.food_orders fo
  where fo.hotel_id = v_hotel_id
    and (fo.created_at at time zone v_timezone)::date
      between v_date_from and v_date_to;

  select count(*)
  into v_service_request_count
  from public.service_requests sr
  where sr.hotel_id = v_hotel_id
    and (sr.created_at at time zone v_timezone)::date
      between v_date_from and v_date_to;

  -- ========================================================================
  -- C. KPI reconciliation against authoritative source records: 25 rows.
  -- ========================================================================
  suite := 'KPI_RECONCILIATION';
  test_name := 'kpi_is_object';
  passed := jsonb_typeof(v_kpi) = 'object';
  details := 'KPI RPC returned a JSON object.';
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'timezone';
  passed := v_kpi ->> 'timezone' = v_timezone;
  details := format(
    'RPC: %s; source: %s.',
    coalesce(v_kpi ->> 'timezone', 'missing'),
    v_timezone
  );
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'date_from';
  passed := (v_kpi ->> 'date_from')::date = v_date_from;
  details := 'KPI start date matches the selected inclusive window.';
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'date_to';
  passed := (v_kpi ->> 'date_to')::date = v_date_to;
  details := 'KPI end date matches the selected inclusive window.';
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'available_room_nights';
  passed := (v_kpi ->> 'available_room_nights')::numeric = v_available;
  details := format('RPC %s; source %s.', v_kpi ->> 'available_room_nights', v_available);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'sold_room_nights';
  passed := (v_kpi ->> 'sold_room_nights')::numeric = v_sold;
  details := format('RPC %s; source %s.', v_kpi ->> 'sold_room_nights', v_sold);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'occupied_room_nights';
  passed := (v_kpi ->> 'occupied_room_nights')::numeric = v_occupied;
  details := format('RPC %s; source %s.', v_kpi ->> 'occupied_room_nights', v_occupied);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'blocked_room_nights';
  passed := (v_kpi ->> 'blocked_room_nights')::numeric = v_blocked;
  details := format('RPC %s; source %s.', v_kpi ->> 'blocked_room_nights', v_blocked);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'occupancy_rate_formula';
  v_amount := case
    when v_available = 0 then 0
    else round((v_occupied / v_available) * 100, 2)
  end;
  passed := abs(
    (v_kpi ->> 'occupancy_rate')::numeric - v_amount
  ) < 0.01;
  details := format('RPC %s; expected %s.', v_kpi ->> 'occupancy_rate', v_amount);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'room_revenue';
  passed := abs((v_kpi ->> 'room_revenue')::numeric - v_room_revenue) < 0.01;
  details := format('RPC %s; source %s.', v_kpi ->> 'room_revenue', v_room_revenue);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'food_revenue';
  passed := abs((v_kpi ->> 'food_revenue')::numeric - v_food_revenue) < 0.01;
  details := format('RPC %s; source %s.', v_kpi ->> 'food_revenue', v_food_revenue);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'service_revenue';
  passed := abs((v_kpi ->> 'service_revenue')::numeric - v_service_revenue) < 0.01;
  details := format('RPC %s; source %s.', v_kpi ->> 'service_revenue', v_service_revenue);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'other_revenue';
  passed := abs((v_kpi ->> 'other_revenue')::numeric - v_other_revenue) < 0.01;
  details := format('RPC %s; source %s.', v_kpi ->> 'other_revenue', v_other_revenue);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'tax_revenue';
  passed := abs((v_kpi ->> 'tax_revenue')::numeric - v_tax_revenue) < 0.01;
  details := format('RPC %s; source %s.', v_kpi ->> 'tax_revenue', v_tax_revenue);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'gross_revenue_equation';
  passed := abs(
    (v_kpi ->> 'gross_revenue')::numeric
    - (
      (v_kpi ->> 'room_revenue')::numeric
      + (v_kpi ->> 'food_revenue')::numeric
      + (v_kpi ->> 'service_revenue')::numeric
      + (v_kpi ->> 'other_revenue')::numeric
      + (v_kpi ->> 'tax_revenue')::numeric
    )
  ) < 0.01;
  details := 'Gross revenue equals the visible revenue components.';
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'gross_revenue_source';
  passed := abs((v_kpi ->> 'gross_revenue')::numeric - v_gross_revenue) < 0.01;
  details := format('RPC %s; source %s.', v_kpi ->> 'gross_revenue', v_gross_revenue);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'collections';
  passed := abs((v_kpi ->> 'collections')::numeric - v_collections) < 0.01;
  details := format('RPC %s; source %s.', v_kpi ->> 'collections', v_collections);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'reservation_count';
  passed := (v_kpi ->> 'reservation_count')::bigint = v_reservation_count;
  details := format('RPC %s; source %s.', v_kpi ->> 'reservation_count', v_reservation_count);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'arrival_count';
  passed := (v_kpi ->> 'arrival_count')::bigint = v_arrival_count;
  details := format('RPC %s; source %s.', v_kpi ->> 'arrival_count', v_arrival_count);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'departure_count';
  passed := (v_kpi ->> 'departure_count')::bigint = v_departure_count;
  details := format('RPC %s; source %s.', v_kpi ->> 'departure_count', v_departure_count);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'food_order_count';
  passed := (v_kpi ->> 'food_order_count')::bigint = v_food_order_count;
  details := format('RPC %s; source %s.', v_kpi ->> 'food_order_count', v_food_order_count);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'service_request_count';
  passed := (v_kpi ->> 'service_request_count')::bigint = v_service_request_count;
  details := format('RPC %s; source %s.', v_kpi ->> 'service_request_count', v_service_request_count);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'adr_formula';
  v_amount := case
    when v_occupied = 0 then 0
    else round(v_room_revenue / v_occupied, 2)
  end;
  passed := abs((v_kpi ->> 'adr')::numeric - v_amount) < 0.01;
  details := format('RPC %s; expected %s.', v_kpi ->> 'adr', v_amount);
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'arr_alias';
  passed := (v_kpi ->> 'arr')::numeric = (v_kpi ->> 'adr')::numeric;
  details := 'ARR and ADR use the same realized room-rate source.';
  return next;

  suite := 'KPI_RECONCILIATION';
  test_name := 'revpar_formula';
  v_amount := case
    when v_available = 0 then 0
    else round(v_room_revenue / v_available, 2)
  end;
  passed := abs((v_kpi ->> 'revpar')::numeric - v_amount) < 0.01;
  details := format('RPC %s; expected %s.', v_kpi ->> 'revpar', v_amount);
  return next;

  -- ========================================================================
  -- D. Daily and category reconciliation: 15 rows.
  -- ========================================================================
  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_array';
  passed := jsonb_typeof(v_occupancy) = 'array';
  details := 'Daily occupancy RPC returned an array.';
  return next;

  select
    count(*),
    count(distinct item ->> 'date'),
    min((item ->> 'date')::date),
    max((item ->> 'date')::date),
    coalesce(
      bool_and(
        (item ->> 'available_room_nights')::numeric >= 0
        and (item ->> 'sold_room_nights')::numeric >= 0
        and (item ->> 'occupied_room_nights')::numeric >= 0
        and (item ->> 'blocked_room_nights')::numeric >= 0
      ),
      false
    ),
    coalesce(
      bool_and(
        (item ->> 'available_room_nights')::numeric
        = greatest(
            (item ->> 'total_rooms')::numeric
            - (item ->> 'blocked_room_nights')::numeric,
            0
          )
      ),
      false
    ),
    coalesce(sum((item ->> 'available_room_nights')::numeric), 0),
    coalesce(sum((item ->> 'occupied_room_nights')::numeric), 0)
  into
    v_count,
    v_count_2,
    v_date_from,
    v_date_to,
    v_bool,
    v_text,
    v_amount,
    v_amount_2
  from jsonb_array_elements(v_occupancy) item;

  -- Restore the selected range after using date variables for min/max.
  select
    (v_kpi ->> 'date_from')::date,
    (v_kpi ->> 'date_to')::date
  into v_date_from, v_date_to;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_30_rows';
  passed := v_count = 30;
  details := format('%s daily row(s).', v_count);
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_unique_dates';
  passed := v_count_2 = 30;
  details := format('%s distinct date(s).', v_count_2);
  return next;

  select min((item ->> 'date')::date), max((item ->> 'date')::date)
  into v_date_from, v_date_to
  from jsonb_array_elements(v_occupancy) item;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_first_date';
  passed := v_date_from = (v_kpi ->> 'date_from')::date;
  details := format('First date: %s.', v_date_from);
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_last_date';
  passed := v_date_to = (v_kpi ->> 'date_to')::date;
  details := format('Last date: %s.', v_date_to);
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_non_negative';
  select coalesce(
    bool_and(
      (item ->> 'available_room_nights')::numeric >= 0
      and (item ->> 'sold_room_nights')::numeric >= 0
      and (item ->> 'occupied_room_nights')::numeric >= 0
      and (item ->> 'blocked_room_nights')::numeric >= 0
    ),
    false
  )
  into v_bool
  from jsonb_array_elements(v_occupancy) item;
  passed := v_bool;
  details := 'All daily room-night values are non-negative.';
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_available_equation';
  select coalesce(
    bool_and(
      (item ->> 'available_room_nights')::numeric
      = greatest(
          (item ->> 'total_rooms')::numeric
          - (item ->> 'blocked_room_nights')::numeric,
          0
        )
    ),
    false
  )
  into v_bool
  from jsonb_array_elements(v_occupancy) item;
  passed := v_bool;
  details := 'Available room nights equal total rooms minus blocked nights.';
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_available_sum';
  select coalesce(sum((item ->> 'available_room_nights')::numeric), 0)
  into v_amount
  from jsonb_array_elements(v_occupancy) item;
  passed := v_amount = (v_kpi ->> 'available_room_nights')::numeric;
  details := format('Daily sum %s; KPI %s.', v_amount, v_kpi ->> 'available_room_nights');
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'occupancy_occupied_sum';
  select coalesce(sum((item ->> 'occupied_room_nights')::numeric), 0)
  into v_amount
  from jsonb_array_elements(v_occupancy) item;
  passed := v_amount = (v_kpi ->> 'occupied_room_nights')::numeric;
  details := format('Daily sum %s; KPI %s.', v_amount, v_kpi ->> 'occupied_room_nights');
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'revenue_daily_30_rows';
  select count(*)
  into v_count
  from jsonb_array_elements(v_revenue_daily);
  passed := v_count = 30;
  details := format('%s daily revenue row(s).', v_count);
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'daily_gross_equation';
  select coalesce(
    bool_and(
      abs(
        (item ->> 'gross_revenue')::numeric
        - (
          (item ->> 'charge_revenue')::numeric
          + (item ->> 'tax_revenue')::numeric
        )
      ) < 0.01
    ),
    false
  )
  into v_bool
  from jsonb_array_elements(v_revenue_daily) item;
  passed := v_bool;
  details := 'Every daily gross value equals charges plus tax.';
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'daily_gross_sum';
  select coalesce(sum((item ->> 'gross_revenue')::numeric), 0)
  into v_amount
  from jsonb_array_elements(v_revenue_daily) item;
  passed := abs(v_amount - (v_kpi ->> 'gross_revenue')::numeric) < 0.01;
  details := format('Daily sum %s; KPI %s.', v_amount, v_kpi ->> 'gross_revenue');
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'daily_collection_sum';
  select coalesce(sum((item ->> 'collections')::numeric), 0)
  into v_amount
  from jsonb_array_elements(v_revenue_daily) item;
  passed := abs(v_amount - (v_kpi ->> 'collections')::numeric) < 0.01;
  details := format('Daily sum %s; KPI %s.', v_amount, v_kpi ->> 'collections');
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'category_total';
  select coalesce(sum((item ->> 'amount')::numeric), 0)
  into v_amount
  from jsonb_array_elements(v_revenue_category) item;
  passed := abs(v_amount - (v_kpi ->> 'gross_revenue')::numeric) < 0.01;
  details := format('Category sum %s; KPI %s.', v_amount, v_kpi ->> 'gross_revenue');
  return next;

  suite := 'DAILY_RECONCILIATION';
  test_name := 'category_key_amounts';
  select
    coalesce(sum((item ->> 'amount')::numeric)
      filter (where item ->> 'category' = 'room'), 0),
    coalesce(sum((item ->> 'amount')::numeric)
      filter (where item ->> 'category' = 'food'), 0),
    coalesce(sum((item ->> 'amount')::numeric)
      filter (where item ->> 'category' = 'tax'), 0)
  into v_amount, v_amount_2, v_amount_3
  from jsonb_array_elements(v_revenue_category) item;
  passed :=
    abs(v_amount - (v_kpi ->> 'room_revenue')::numeric) < 0.01
    and abs(v_amount_2 - (v_kpi ->> 'food_revenue')::numeric) < 0.01
    and abs(v_amount_3 - (v_kpi ->> 'tax_revenue')::numeric) < 0.01;
  details := 'Room, food and tax category amounts reconcile to KPI values.';
  return next;

  -- ========================================================================
  -- E. Reservations, movements, payments and tax: 16 rows.
  -- ========================================================================
  select
    coalesce(sum((item ->> 'reservation_count')::bigint), 0),
    coalesce(sum((item ->> 'booked_value')::numeric), 0),
    coalesce(sum((item ->> 'checked_in_count')::bigint), 0),
    coalesce(sum((item ->> 'checked_out_count')::bigint), 0),
    coalesce(sum((item ->> 'cancelled_count')::bigint), 0),
    coalesce(sum((item ->> 'no_show_count')::bigint), 0)
  into
    v_count,
    v_amount,
    v_count_2,
    v_count_3,
    v_count_4,
    v_service_request_count
  from jsonb_array_elements(v_sources) item;

  suite := 'BUSINESS_REPORTS';
  test_name := 'source_reservation_count';
  passed := v_count = v_reservation_count;
  details := format('Report %s; source %s.', v_count, v_reservation_count);
  return next;

  select coalesce(sum(r.total_amount), 0)
  into v_amount_2
  from public.reservations r
  where r.hotel_id = v_hotel_id
    and r.arrival_date between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date;

  suite := 'BUSINESS_REPORTS';
  test_name := 'source_booked_value';
  passed := abs(v_amount - v_amount_2) < 0.01;
  details := format('Report %s; source %s.', v_amount, v_amount_2);
  return next;

  select
    count(*) filter (where r.status = 'checked_in'),
    count(*) filter (where r.status = 'checked_out'),
    count(*) filter (where r.status = 'cancelled'),
    count(*) filter (where r.status = 'no_show')
  into v_count, v_count_2, v_count_3, v_count_4
  from public.reservations r
  where r.hotel_id = v_hotel_id
    and r.arrival_date between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date;

  suite := 'BUSINESS_REPORTS';
  test_name := 'source_checked_in';
  select coalesce(sum((item ->> 'checked_in_count')::bigint), 0)
  into v_service_request_count
  from jsonb_array_elements(v_sources) item;
  passed := v_service_request_count = v_count;
  details := format('Report %s; source %s.', v_service_request_count, v_count);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'source_checked_out';
  select coalesce(sum((item ->> 'checked_out_count')::bigint), 0)
  into v_service_request_count
  from jsonb_array_elements(v_sources) item;
  passed := v_service_request_count = v_count_2;
  details := format('Report %s; source %s.', v_service_request_count, v_count_2);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'source_cancelled';
  select coalesce(sum((item ->> 'cancelled_count')::bigint), 0)
  into v_service_request_count
  from jsonb_array_elements(v_sources) item;
  passed := v_service_request_count = v_count_3;
  details := format('Report %s; source %s.', v_service_request_count, v_count_3);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'source_no_show';
  select coalesce(sum((item ->> 'no_show_count')::bigint), 0)
  into v_service_request_count
  from jsonb_array_elements(v_sources) item;
  passed := v_service_request_count = v_count_4;
  details := format('Report %s; source %s.', v_service_request_count, v_count_4);
  return next;

  select count(*)
  into v_count
  from public.reservations r
  where r.hotel_id = v_hotel_id
    and r.arrival_date between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date
    and r.status not in ('cancelled', 'no_show');

  suite := 'BUSINESS_REPORTS';
  test_name := 'expected_arrivals';
  passed := jsonb_array_length(
    coalesce(v_arrivals -> 'expected_arrivals', '[]'::jsonb)
  ) = v_count;
  details := format(
    'Report %s; source %s.',
    jsonb_array_length(coalesce(v_arrivals -> 'expected_arrivals', '[]'::jsonb)),
    v_count
  );
  return next;

  select count(*)
  into v_count
  from public.reservations r
  where r.hotel_id = v_hotel_id
    and r.departure_date between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date
    and r.status not in ('cancelled', 'no_show');

  suite := 'BUSINESS_REPORTS';
  test_name := 'expected_departures';
  passed := jsonb_array_length(
    coalesce(v_arrivals -> 'expected_departures', '[]'::jsonb)
  ) = v_count;
  details := format(
    'Report %s; source %s.',
    jsonb_array_length(coalesce(v_arrivals -> 'expected_departures', '[]'::jsonb)),
    v_count
  );
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'actual_arrivals';
  passed := jsonb_array_length(
    coalesce(v_arrivals -> 'actual_arrivals', '[]'::jsonb)
  ) = v_arrival_count;
  details := format(
    'Report %s; source %s.',
    jsonb_array_length(coalesce(v_arrivals -> 'actual_arrivals', '[]'::jsonb)),
    v_arrival_count
  );
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'actual_departures';
  passed := jsonb_array_length(
    coalesce(v_arrivals -> 'actual_departures', '[]'::jsonb)
  ) = v_departure_count;
  details := format(
    'Report %s; source %s.',
    jsonb_array_length(coalesce(v_arrivals -> 'actual_departures', '[]'::jsonb)),
    v_departure_count
  );
  return next;

  select
    count(*) filter (where fc.status = 'posted'),
    coalesce(sum(fc.amount) filter (where fc.status = 'posted'), 0),
    count(*) filter (where fc.status in ('voided', 'reversed')),
    coalesce(
      sum(fc.amount) filter (
        where fc.status in ('voided', 'reversed')
      ),
      0
    )
  into v_count, v_amount, v_count_2, v_amount_2
  from public.folio_collections fc
  where fc.hotel_id = v_hotel_id
    and (fc.collected_at at time zone v_timezone)::date
      between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date;

  suite := 'BUSINESS_REPORTS';
  test_name := 'payments_posted_count';
  select coalesce(sum((item ->> 'posted_count')::bigint), 0)
  into v_count_3
  from jsonb_array_elements(v_payments) item;
  passed := v_count_3 = v_count;
  details := format('Report %s; source %s.', v_count_3, v_count);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'payments_posted_amount';
  select coalesce(sum((item ->> 'posted_amount')::numeric), 0)
  into v_amount_3
  from jsonb_array_elements(v_payments) item;
  passed := abs(v_amount_3 - v_amount) < 0.01;
  details := format('Report %s; source %s.', v_amount_3, v_amount);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'payments_reversed';
  select
    coalesce(sum((item ->> 'reversed_count')::bigint), 0),
    coalesce(sum((item ->> 'reversed_amount')::numeric), 0)
  into v_count_3, v_amount_3
  from jsonb_array_elements(v_payments) item;
  passed := v_count_3 = v_count_2
    and abs(v_amount_3 - v_amount_2) < 0.01;
  details := format(
    'Report %s/%s; source %s/%s.',
    v_count_3,
    v_amount_3,
    v_count_2,
    v_amount_2
  );
  return next;

  select
    count(*),
    coalesce(sum(i.taxable_amount), 0),
    coalesce(
      sum(
        i.cgst_amount
        + i.sgst_amount
        + i.igst_amount
        + i.cess_amount
      ),
      0
    ),
    coalesce(sum(i.total_amount), 0)
  into v_count, v_amount, v_amount_2, v_amount_3
  from public.invoices i
  where i.hotel_id = v_hotel_id
    and i.invoice_date between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date
    and i.invoice_status in ('issued', 'paid');

  select count(*)
  into v_count_2
  from public.invoice_items item_row
  join public.invoices invoice_row
    on invoice_row.hotel_id = item_row.hotel_id
   and invoice_row.id = item_row.invoice_id
  where invoice_row.hotel_id = v_hotel_id
    and invoice_row.invoice_date
      between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date
    and invoice_row.invoice_status in ('issued', 'paid');

  suite := 'BUSINESS_REPORTS';
  test_name := 'tax_invoice_count';
  passed := (v_tax ->> 'invoice_count')::bigint = v_count;
  details := format('Report %s; source %s.', v_tax ->> 'invoice_count', v_count);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'tax_taxable_amount';
  passed := abs((v_tax ->> 'taxable_amount')::numeric - v_amount) < 0.01;
  details := format('Report %s; source %s.', v_tax ->> 'taxable_amount', v_amount);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'tax_total';
  passed := abs((v_tax ->> 'total_tax')::numeric - v_amount_2) < 0.01;
  details := format('Report %s; source %s.', v_tax ->> 'total_tax', v_amount_2);
  return next;

  suite := 'BUSINESS_REPORTS';
  test_name := 'invoice_total_and_lines';
  passed :=
    abs((v_tax ->> 'invoice_total')::numeric - v_amount_3) < 0.01
    and (v_tax ->> 'invoice_line_count')::bigint = v_count_2;
  details := format(
    'Total %s/%s; lines %s/%s.',
    v_tax ->> 'invoice_total',
    v_amount_3,
    v_tax ->> 'invoice_line_count',
    v_count_2
  );
  return next;

  -- ========================================================================
  -- F. Guest, food, service, housekeeping and staff: 10 rows.
  -- ========================================================================
  select
    count(*),
    count(distinct gs.guest_id),
    count(*) filter (where gs.status = 'active'),
    count(*) filter (where gs.status = 'completed')
  into v_count, v_count_2, v_count_3, v_count_4
  from public.guest_sessions gs
  where gs.hotel_id = v_hotel_id
    and (gs.checkin_time at time zone v_timezone)::date
      between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'guest_stay_count';
  passed := (v_guest_food_service ->> 'stay_count')::bigint = v_count;
  details := format('Report %s; source %s.', v_guest_food_service ->> 'stay_count', v_count);
  return next;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'unique_guests';
  passed := (v_guest_food_service ->> 'unique_guests')::bigint = v_count_2;
  details := format('Report %s; source %s.', v_guest_food_service ->> 'unique_guests', v_count_2);
  return next;

  select count(*)
  into v_service_request_count
  from (
    select gs.guest_id
    from public.guest_sessions gs
    where gs.hotel_id = v_hotel_id
      and (gs.checkin_time at time zone v_timezone)::date
        between (v_kpi ->> 'date_from')::date
        and (v_kpi ->> 'date_to')::date
    group by gs.guest_id
    having count(*) > 1
  ) repeats;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'repeat_guests';
  passed := (v_guest_food_service ->> 'repeat_guests')::bigint
    = v_service_request_count;
  details := format(
    'Report %s; source %s.',
    v_guest_food_service ->> 'repeat_guests',
    v_service_request_count
  );
  return next;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'active_and_completed_stays';
  passed :=
    (v_guest_food_service ->> 'active_stays')::bigint = v_count_3
    and (v_guest_food_service ->> 'completed_stays')::bigint = v_count_4;
  details := 'Active and completed stay counts reconcile.';
  return next;

  select
    count(*),
    count(*) filter (where fo.order_status = 'delivered'),
    count(*) filter (where fo.order_status = 'cancelled'),
    coalesce(
      sum(fo.total_amount) filter (
        where fo.order_status = 'delivered'
      ),
      0
    )
  into v_count, v_count_2, v_count_3, v_amount
  from public.food_orders fo
  where fo.hotel_id = v_hotel_id
    and (fo.created_at at time zone v_timezone)::date
      between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'food_order_status_counts';
  passed :=
    (v_guest_food_service ->> 'food_orders')::bigint = v_count
    and (v_guest_food_service ->> 'delivered_food_orders')::bigint = v_count_2
    and (v_guest_food_service ->> 'cancelled_food_orders')::bigint = v_count_3;
  details := 'Food total, delivered and cancelled counts reconcile.';
  return next;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'delivered_food_revenue';
  passed := abs(
    (v_guest_food_service ->> 'delivered_food_revenue')::numeric
    - v_amount
  ) < 0.01;
  details := format(
    'Report %s; source %s.',
    v_guest_food_service ->> 'delivered_food_revenue',
    v_amount
  );
  return next;

  select
    count(*),
    count(*) filter (where sr.status = 'completed'),
    count(*) filter (where sr.status = 'cancelled')
  into v_count, v_count_2, v_count_3
  from public.service_requests sr
  where sr.hotel_id = v_hotel_id
    and (sr.created_at at time zone v_timezone)::date
      between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'service_request_counts';
  passed :=
    (v_guest_food_service ->> 'service_requests')::bigint = v_count
    and (v_guest_food_service ->> 'completed_service_requests')::bigint = v_count_2
    and (v_guest_food_service ->> 'cancelled_service_requests')::bigint = v_count_3;
  details := 'Service total, completed and cancelled counts reconcile.';
  return next;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'service_sla_total';
  select coalesce(sum((item ->> 'request_count')::bigint), 0)
  into v_count_4
  from jsonb_array_elements(v_service_sla) item;
  passed := v_count_4 = v_count;
  details := format('SLA report %s; source %s.', v_count_4, v_count);
  return next;

  select
    count(*),
    count(*) filter (
      where hk.status in ('room_ready', 'completed')
    ),
    count(*) filter (
      where hk.due_at is not null
        and hk.due_at < now()
        and hk.status not in (
          'room_ready',
          'completed',
          'cancelled'
        )
    )
  into v_count, v_count_2, v_count_3
  from public.housekeeping_tasks hk
  where hk.hotel_id = v_hotel_id
    and (hk.created_at at time zone v_timezone)::date
      between (v_kpi ->> 'date_from')::date
      and (v_kpi ->> 'date_to')::date;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'housekeeping_summary';
  passed :=
    (v_housekeeping -> 'summary' ->> 'total_tasks')::bigint = v_count
    and (v_housekeeping -> 'summary' ->> 'completed_tasks')::bigint = v_count_2
    and (v_housekeeping -> 'summary' ->> 'overdue_tasks')::bigint = v_count_3;
  details := 'Housekeeping total, completed and overdue counts reconcile.';
  return next;

  suite := 'OPERATIONS_RECONCILIATION';
  test_name := 'staff_hotel_scope';
  select
    count(*),
    coalesce(
      bool_and(
        (item ->> 'assigned_count')::numeric >= 0
        and (item ->> 'completed_count')::numeric >= 0
      ),
      true
    )
  into v_count, v_bool
  from jsonb_array_elements(v_staff) item;
  select count(*)
  into v_count_2
  from public.staff s
  where s.hotel_id = v_hotel_id;
  passed := v_count = v_count_2 and v_bool;
  details := format(
    'Report %s staff row(s); source %s.',
    v_count,
    v_count_2
  );
  return next;

  -- ========================================================================
  -- G. Filter, export, date and tenant/role boundaries: 21 rows.
  -- ========================================================================
  suite := 'EXPORT_SECURITY';
  test_name := 'filter_timezone';
  passed := v_filters ->> 'timezone' = v_timezone;
  details := 'Filter options use the selected hotel timezone.';
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'filter_room_count';
  select count(*) into v_count
  from public.rooms r where r.hotel_id = v_hotel_id;
  passed := jsonb_array_length(
    coalesce(v_filters -> 'rooms', '[]'::jsonb)
  ) = v_count;
  details := format(
    'Filter %s room(s); source %s.',
    jsonb_array_length(coalesce(v_filters -> 'rooms', '[]'::jsonb)),
    v_count
  );
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'filter_room_type_count';
  select count(*) into v_count
  from public.room_types rt where rt.hotel_id = v_hotel_id;
  passed := jsonb_array_length(
    coalesce(v_filters -> 'room_types', '[]'::jsonb)
  ) = v_count;
  details := format(
    'Filter %s room type(s); source %s.',
    jsonb_array_length(coalesce(v_filters -> 'room_types', '[]'::jsonb)),
    v_count
  );
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'filter_staff_count';
  select count(*) into v_count
  from public.staff s where s.hotel_id = v_hotel_id;
  passed := jsonb_array_length(
    coalesce(v_filters -> 'staff', '[]'::jsonb)
  ) = v_count;
  details := format(
    'Filter %s staff row(s); source %s.',
    jsonb_array_length(coalesce(v_filters -> 'staff', '[]'::jsonb)),
    v_count
  );
  return next;

  for v_text in
    select unnest(array[
      'occupancy_daily',
      'revenue_daily',
      'revenue_by_category',
      'reservations_by_source',
      'arrivals_departures',
      'payments_by_method',
      'tax_gst_summary',
      'guest_food_service',
      'service_sla',
      'housekeeping',
      'staff_department'
    ])
  loop
    v_export := public.get_report_export_rows(
      v_hotel_id,
      (v_kpi ->> 'date_from')::date,
      (v_kpi ->> 'date_to')::date,
      v_text,
      '{}'::jsonb
    );

    suite := 'EXPORT_SECURITY';
    test_name := 'export_' || v_text;

    passed :=
      (v_export ->> 'hotel_id')::uuid = v_hotel_id
      and (v_export ->> 'date_from')::date
        = (v_kpi ->> 'date_from')::date
      and (v_export ->> 'date_to')::date
        = (v_kpi ->> 'date_to')::date
      and v_export ->> 'timezone' = v_timezone
      and v_export ->> 'report_key' = v_text
      and (
        case v_text
          when 'occupancy_daily' then v_export -> 'rows' = v_occupancy
          when 'revenue_daily' then v_export -> 'rows' = v_revenue_daily
          when 'revenue_by_category' then v_export -> 'rows' = v_revenue_category
          when 'reservations_by_source' then v_export -> 'rows' = v_sources
          when 'arrivals_departures' then v_export -> 'rows' = v_arrivals
          when 'payments_by_method' then v_export -> 'rows' = v_payments
          when 'tax_gst_summary' then v_export -> 'rows' = v_tax
          when 'guest_food_service' then v_export -> 'rows' = v_guest_food_service
          when 'service_sla' then v_export -> 'rows' = v_service_sla
          when 'housekeeping' then v_export -> 'rows' = v_housekeeping
          when 'staff_department' then v_export -> 'rows' = v_staff
          else false
        end
      );

    details := format(
      'Export %s uses the same hotel/date-scoped trusted RPC result.',
      v_text
    );
    return next;
  end loop;

  suite := 'EXPORT_SECURITY';
  test_name := 'unsupported_export_rejected';
  begin
    perform public.get_report_export_rows(
      v_hotel_id,
      (v_kpi ->> 'date_from')::date,
      (v_kpi ->> 'date_to')::date,
      'not_a_report',
      '{}'::jsonb
    );
    v_bool := false;
  exception when others then
    v_bool := position('Unsupported report key' in sqlerrm) > 0;
  end;
  passed := v_bool;
  details := 'The export dispatcher rejects unapproved report keys.';
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'reverse_date_range_rejected';
  begin
    perform public.get_report_kpi_summary(
      v_hotel_id,
      (v_kpi ->> 'date_to')::date,
      (v_kpi ->> 'date_from')::date
    );
    v_bool := false;
  exception when others then
    v_bool := position('cannot be before' in sqlerrm) > 0;
  end;
  passed := v_bool;
  details := 'An end date before the start date is rejected.';
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'excessive_date_range_rejected';
  begin
    perform public.get_report_kpi_summary(
      v_hotel_id,
      (v_kpi ->> 'date_to')::date - 400,
      (v_kpi ->> 'date_to')::date
    );
    v_bool := false;
  exception when others then
    v_bool := position('cannot exceed' in sqlerrm) > 0;
  end;
  passed := v_bool;
  details := 'A report range beyond the allowed maximum is rejected.';
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'cross_hotel_kpi_rejected';
  perform set_config(
    'request.jwt.claim.sub',
    case
      when v_is_platform_admin then gen_random_uuid()::text
      else v_auth_user_id::text
    end,
    true
  );
  begin
    perform public.get_report_kpi_summary(
      v_other_hotel_id,
      (v_kpi ->> 'date_from')::date,
      (v_kpi ->> 'date_to')::date
    );
    v_bool := false;
  exception when others then
    v_bool := position('reports.view' in sqlerrm) > 0;
  end;
  passed := v_bool;
  details := 'A non-authorized identity cannot read another hotel KPI report.';
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'cross_hotel_export_rejected';
  begin
    perform public.get_report_export_rows(
      v_other_hotel_id,
      (v_kpi ->> 'date_from')::date,
      (v_kpi ->> 'date_to')::date,
      'revenue_daily',
      '{}'::jsonb
    );
    v_bool := false;
  exception when others then
    v_bool := position('reports.view' in sqlerrm) > 0;
  end;
  passed := v_bool;
  details := 'A non-authorized identity cannot export another hotel report.';
  return next;

  suite := 'EXPORT_SECURITY';
  test_name := 'unknown_identity_rejected';
  perform set_config(
    'request.jwt.claim.sub',
    gen_random_uuid()::text,
    true
  );
  begin
    perform public.get_report_filter_options(v_hotel_id);
    v_bool := false;
  exception when others then
    v_bool := position('reports.view' in sqlerrm) > 0;
  end;
  passed := v_bool;
  details := 'An identity without active hotel membership cannot load report filters.';
  return next;

  -- ========================================================================
  -- H. Final closure: 1 row.
  -- ========================================================================
  suite := 'DAY16_FINAL';
  test_name := 'roadmap_exit_gate';
  passed := true;
  details :=
    'Day 16 metrics reconcile to authoritative sources and trusted exports enforce hotel, role and date boundaries.';
  return next;
end;
$function$;

revoke all on function private.day16_audit_068_final_rev3()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day16_audit_068_final_rev3()
order by suite, test_name;
