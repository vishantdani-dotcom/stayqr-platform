-- ============================================================================
-- StayQR v1.0
-- Day 18 Migration 058 REV1
-- Indexes, query-plan hardening and trusted pagination foundation
--
-- ACCEPTED BASELINE
-- Audit 072 preflight: 160/160
-- Public tables: 133
-- Public indexes: 508
-- Invalid indexes: 0
-- RLS tables: 133/133
-- Tables without primary keys: 0
--
-- PURPOSE
-- 1. Add deterministic keyset-pagination indexes for real StayQR query paths.
-- 2. Add bounded, opaque cursor helpers.
-- 3. Add tenant-authorized pagination RPCs for heavy operational datasets.
-- 4. Improve planner statistics for frequently filtered columns.
-- 5. Add manager-only query-health diagnostics.
--
-- SAFETY
-- - No hotel business data is inserted, updated or deleted.
-- - No direct authenticated table-write grant is added.
-- - Page limits are clamped to 1–100.
-- - All public functions are SECURITY DEFINER with locked search_path.
-- - Every paginated read filters by the authorized hotel_id.
--
-- EXPECTED RESULT
-- 100 rows
-- 100 passed = true
-- 0 failures
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '10min';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050058:day18-pagination-rev1')
);

create schema if not exists private;

do $preflight$
declare
  v_missing text;
begin
  select string_agg(object_name, ', ' order by object_name)
  into v_missing
  from (
    values
      ('public.reservations', to_regclass('public.reservations') is not null),
      ('public.guests', to_regclass('public.guests') is not null),
      ('public.guest_sessions', to_regclass('public.guest_sessions') is not null),
      ('public.service_requests', to_regclass('public.service_requests') is not null),
      ('public.food_orders', to_regclass('public.food_orders') is not null),
      ('public.activity_logs', to_regclass('public.activity_logs') is not null),
      ('public.notification_deliveries', to_regclass('public.notification_deliveries') is not null),
      ('public.folios', to_regclass('public.folios') is not null),
      ('public.invoices', to_regclass('public.invoices') is not null),
      ('public.payments', to_regclass('public.payments') is not null),
      ('private.user_has_hotel_access(uuid)', to_regprocedure('private.user_has_hotel_access(uuid)') is not null),
      ('private.day17_can_manage_hotel(uuid)', to_regprocedure('private.day17_can_manage_hotel(uuid)') is not null)
  ) required(object_name, present)
  where not present;

  if v_missing is not null then
    raise exception
      'Migration 058 stopped. Missing prerequisite(s): %',
      v_missing;
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. Stable cursor indexes for high-volume operational paths
-- ============================================================================

create index if not exists idx_d18_reservations_cursor
on public.reservations (hotel_id, created_at desc, id desc);

create index if not exists idx_d18_reservations_status_cursor
on public.reservations (hotel_id, status, created_at desc, id desc);

create index if not exists idx_d18_reservations_source_cursor
on public.reservations (hotel_id, booking_source, created_at desc, id desc);

create index if not exists idx_d18_guests_updated_cursor
on public.guests (hotel_id, updated_at desc, id desc);

create index if not exists idx_d18_guests_name_prefix
on public.guests (hotel_id, lower(full_name) text_pattern_ops, id);

create index if not exists idx_d18_guests_phone_prefix
on public.guests (hotel_id, normalized_phone text_pattern_ops, id);

create index if not exists idx_d18_guests_email_prefix
on public.guests (hotel_id, normalized_email text_pattern_ops, id);

create index if not exists idx_d18_guest_sessions_cursor
on public.guest_sessions (hotel_id, created_at desc, id desc);

create index if not exists idx_d18_guest_sessions_status_cursor
on public.guest_sessions (hotel_id, status, created_at desc, id desc);

create index if not exists idx_d18_service_requests_status_cursor
on public.service_requests (hotel_id, status, created_at desc, id desc);

create index if not exists idx_d18_service_requests_department_cursor
on public.service_requests (hotel_id, department, status, created_at desc, id desc);

create index if not exists idx_d18_food_orders_status_cursor
on public.food_orders (hotel_id, order_status, created_at desc, id desc);

create index if not exists idx_d18_activity_logs_cursor
on public.activity_logs (hotel_id, created_at desc, id desc);

create index if not exists idx_d18_activity_logs_entity_cursor
on public.activity_logs (hotel_id, entity_type, created_at desc, id desc);

create index if not exists idx_d18_notification_deliveries_status_cursor
on public.notification_deliveries (hotel_id, status, created_at desc, id desc);

create index if not exists idx_d18_folios_status_cursor
on public.folios (hotel_id, status, updated_at desc, id desc);

create index if not exists idx_d18_invoices_cursor
on public.invoices (hotel_id, created_at desc, id desc);

create index if not exists idx_d18_payments_cursor
on public.payments (hotel_id, created_at desc, id desc);

create index if not exists idx_d18_housekeeping_status_cursor
on public.housekeeping_tasks (hotel_id, status, created_at desc, id desc);

create index if not exists idx_d18_maintenance_status_cursor
on public.maintenance_tasks (hotel_id, status, created_at desc, id desc);

-- ============================================================================
-- 2. Planner statistics for frequently filtered/sorted columns
-- ============================================================================

alter table public.reservations
  alter column hotel_id set statistics 250,
  alter column status set statistics 250,
  alter column booking_source set statistics 250,
  alter column created_at set statistics 250;

alter table public.guests
  alter column hotel_id set statistics 250,
  alter column full_name set statistics 250,
  alter column normalized_phone set statistics 250,
  alter column normalized_email set statistics 250,
  alter column updated_at set statistics 250;

alter table public.guest_sessions
  alter column hotel_id set statistics 250,
  alter column status set statistics 250,
  alter column created_at set statistics 250;

alter table public.service_requests
  alter column hotel_id set statistics 250,
  alter column status set statistics 250,
  alter column department set statistics 250,
  alter column created_at set statistics 250;

alter table public.food_orders
  alter column hotel_id set statistics 250,
  alter column order_status set statistics 250,
  alter column created_at set statistics 250;

alter table public.activity_logs
  alter column hotel_id set statistics 250,
  alter column entity_type set statistics 250,
  alter column action set statistics 250,
  alter column created_at set statistics 250;

alter table public.notification_deliveries
  alter column hotel_id set statistics 250,
  alter column status set statistics 250,
  alter column channel set statistics 250,
  alter column created_at set statistics 250;

analyze public.reservations;
analyze public.guests;
analyze public.guest_sessions;
analyze public.service_requests;
analyze public.food_orders;
analyze public.activity_logs;
analyze public.notification_deliveries;
analyze public.folios;
analyze public.invoices;
analyze public.payments;
analyze public.housekeeping_tasks;
analyze public.maintenance_tasks;

-- ============================================================================
-- 3. Opaque cursor and page-bound helpers
-- ============================================================================

create or replace function private.day18_page_limit(
  p_requested integer
)
returns integer
language sql
immutable
set search_path = ''
as $function$
  select least(greatest(coalesce(p_requested, 50), 1), 100);
$function$;

create or replace function private.day18_encode_cursor(
  p_cursor_at timestamptz,
  p_cursor_id uuid
)
returns text
language sql
immutable
strict
set search_path = ''
as $function$
  select encode(
    convert_to(
      jsonb_build_object(
        'at', p_cursor_at,
        'id', p_cursor_id
      )::text,
      'UTF8'
    ),
    'hex'
  );
$function$;

create or replace function private.day18_decode_cursor(
  p_cursor text
)
returns table (
  cursor_at timestamptz,
  cursor_id uuid
)
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_payload jsonb;
begin
  if nullif(trim(p_cursor), '') is null then
    return query
    select null::timestamptz, null::uuid;
    return;
  end if;

  begin
    v_payload :=
      convert_from(decode(trim(p_cursor), 'hex'), 'UTF8')::jsonb;

    return query
    select
      nullif(v_payload ->> 'at', '')::timestamptz,
      nullif(v_payload ->> 'id', '')::uuid;
  exception
    when others then
      raise exception 'Invalid pagination cursor.'
        using errcode = '22023';
  end;
end;
$function$;

create or replace function private.day18_assert_page_access(
  p_hotel_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_hotel_id is null
     or not private.user_has_hotel_access(p_hotel_id)
  then
    raise exception 'Hotel access denied.'
      using errcode = '42501';
  end if;
end;
$function$;

revoke all on function private.day18_page_limit(integer)
from public, anon, authenticated;

revoke all on function private.day18_encode_cursor(timestamptz,uuid)
from public, anon, authenticated;

revoke all on function private.day18_decode_cursor(text)
from public, anon, authenticated;

revoke all on function private.day18_assert_page_access(uuid)
from public, anon, authenticated;

-- ============================================================================
-- 4. Trusted reservation pagination
-- ============================================================================

create or replace function public.get_reservations_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_status text default null,
  p_booking_source text default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
  v_search text := nullif(lower(trim(p_search)), '');
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      r.*,
      g.full_name as primary_guest_name,
      row_number() over (
        order by r.created_at desc, r.id desc
      ) as rn
    from public.reservations r
    left join public.guests g
      on g.hotel_id = r.hotel_id
     and g.id = r.primary_guest_id
    where r.hotel_id = p_hotel_id
      and (p_status is null or r.status = p_status)
      and (
        p_booking_source is null
        or r.booking_source = p_booking_source
      )
      and (
        v_search is null
        or lower(r.reservation_number) like v_search || '%'
        or lower(coalesce(g.full_name, '')) like v_search || '%'
      )
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (r.created_at, r.id) < (v_cursor_at, v_cursor_id)
      )
    order by r.created_at desc, r.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.created_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.created_at, v.id)
          from visible v
          order by v.created_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 5. Trusted guest pagination
-- ============================================================================

create or replace function public.get_guests_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
  v_search text := nullif(lower(trim(p_search)), '');
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      g.*,
      row_number() over (
        order by g.updated_at desc, g.id desc
      ) as rn
    from public.guests g
    where g.hotel_id = p_hotel_id
      and (
        v_search is null
        or lower(g.full_name) like v_search || '%'
        or coalesce(g.normalized_phone, '') like v_search || '%'
        or coalesce(g.normalized_email, '') like v_search || '%'
      )
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (g.updated_at, g.id) < (v_cursor_at, v_cursor_id)
      )
    order by g.updated_at desc, g.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.updated_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.updated_at, v.id)
          from visible v
          order by v.updated_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 6. Trusted guest-session pagination
-- ============================================================================

create or replace function public.get_guest_sessions_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      gs.*,
      g.full_name as guest_name,
      r.room_number,
      row_number() over (
        order by gs.created_at desc, gs.id desc
      ) as rn
    from public.guest_sessions gs
    left join public.guests g
      on g.hotel_id = gs.hotel_id
     and g.id = gs.guest_id
    left join public.rooms r
      on r.hotel_id = gs.hotel_id
     and r.id = gs.room_id
    where gs.hotel_id = p_hotel_id
      and (p_status is null or gs.status = p_status)
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (gs.created_at, gs.id) < (v_cursor_at, v_cursor_id)
      )
    order by gs.created_at desc, gs.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.created_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.created_at, v.id)
          from visible v
          order by v.created_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 7. Trusted service-request pagination
-- ============================================================================

create or replace function public.get_service_requests_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_status text default null,
  p_department text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      sr.*,
      g.full_name as guest_name,
      r.room_number,
      row_number() over (
        order by sr.created_at desc, sr.id desc
      ) as rn
    from public.service_requests sr
    left join public.guests g
      on g.hotel_id = sr.hotel_id
     and g.id = sr.guest_id
    left join public.rooms r
      on r.hotel_id = sr.hotel_id
     and r.id = sr.room_id
    where sr.hotel_id = p_hotel_id
      and (p_status is null or sr.status = p_status)
      and (
        p_department is null
        or sr.department = p_department
      )
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (sr.created_at, sr.id) < (v_cursor_at, v_cursor_id)
      )
    order by sr.created_at desc, sr.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.created_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.created_at, v.id)
          from visible v
          order by v.created_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 8. Trusted food-order pagination
-- ============================================================================

create or replace function public.get_food_orders_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      fo.*,
      g.full_name as guest_name,
      r.room_number,
      row_number() over (
        order by fo.created_at desc, fo.id desc
      ) as rn
    from public.food_orders fo
    left join public.guests g
      on g.hotel_id = fo.hotel_id
     and g.id = fo.guest_id
    left join public.rooms r
      on r.hotel_id = fo.hotel_id
     and r.id = fo.room_id
    where fo.hotel_id = p_hotel_id
      and (p_status is null or fo.order_status = p_status)
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (fo.created_at, fo.id) < (v_cursor_at, v_cursor_id)
      )
    order by fo.created_at desc, fo.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.created_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.created_at, v.id)
          from visible v
          order by v.created_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 9. Trusted activity-log pagination
-- ============================================================================

create or replace function public.get_activity_logs_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_entity_type text default null,
  p_action text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      al.*,
      row_number() over (
        order by al.created_at desc, al.id desc
      ) as rn
    from public.activity_logs al
    where al.hotel_id = p_hotel_id
      and (
        p_entity_type is null
        or al.entity_type = p_entity_type
      )
      and (p_action is null or al.action = p_action)
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (al.created_at, al.id) < (v_cursor_at, v_cursor_id)
      )
    order by al.created_at desc, al.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.created_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.created_at, v.id)
          from visible v
          order by v.created_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 10. Trusted delivery pagination
-- ============================================================================

create or replace function public.get_notification_deliveries_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_status text default null,
  p_channel text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      nd.*,
      row_number() over (
        order by nd.created_at desc, nd.id desc
      ) as rn
    from public.notification_deliveries nd
    where nd.hotel_id = p_hotel_id
      and (p_status is null or nd.status = p_status)
      and (p_channel is null or nd.channel = p_channel)
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (nd.created_at, nd.id) < (v_cursor_at, v_cursor_id)
      )
    order by nd.created_at desc, nd.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.created_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.created_at, v.id)
          from visible v
          order by v.created_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 11. Trusted folio pagination
-- ============================================================================

create or replace function public.get_folios_page(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_cursor text default null,
  p_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := private.day18_page_limit(p_limit);
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_result jsonb;
begin
  perform private.day18_assert_page_access(p_hotel_id);

  select cursor_at, cursor_id
  into v_cursor_at, v_cursor_id
  from private.day18_decode_cursor(p_cursor);

  with candidates as (
    select
      f.*,
      g.full_name as guest_name,
      r.room_number,
      row_number() over (
        order by f.updated_at desc, f.id desc
      ) as rn
    from public.folios f
    left join public.guests g
      on g.hotel_id = f.hotel_id
     and g.id = f.guest_id
    left join public.rooms r
      on r.hotel_id = f.hotel_id
     and r.id = f.room_id
    where f.hotel_id = p_hotel_id
      and (p_status is null or f.status = p_status)
      and (
        v_cursor_at is null
        or v_cursor_id is null
        or (f.updated_at, f.id) < (v_cursor_at, v_cursor_id)
      )
    order by f.updated_at desc, f.id desc
    limit v_limit + 1
  ),
  visible as (
    select *
    from candidates
    where rn <= v_limit
  )
  select jsonb_build_object(
    'items',
      coalesce(
        (
          select jsonb_agg(
            (to_jsonb(v) - 'rn')
            order by v.updated_at desc, v.id desc
          )
          from visible v
        ),
        '[]'::jsonb
      ),
    'limit', v_limit,
    'has_more', (select count(*) > v_limit from candidates),
    'next_cursor',
      case
        when (select count(*) > v_limit from candidates)
        then (
          select private.day18_encode_cursor(v.updated_at, v.id)
          from visible v
          order by v.updated_at asc, v.id asc
          limit 1
        )
        else null
      end
  )
  into v_result;

  return v_result;
end;
$function$;

-- ============================================================================
-- 12. Manager-only query-health snapshot
-- ============================================================================

create or replace function public.get_day18_query_health(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tables jsonb;
  v_indexes jsonb;
begin
  if p_hotel_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Hotel management access required.'
      using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table', stats.relname,
        'estimated_rows', stats.n_live_tup,
        'dead_rows', stats.n_dead_tup,
        'sequential_scans', stats.seq_scan,
        'index_scans', stats.idx_scan,
        'last_analyze', stats.last_analyze,
        'last_autoanalyze', stats.last_autoanalyze
      )
      order by stats.relname
    ),
    '[]'::jsonb
  )
  into v_tables
  from pg_catalog.pg_stat_user_tables stats
  where stats.schemaname = 'public'
    and stats.relname = any(
      array[
        'reservations',
        'guests',
        'guest_sessions',
        'service_requests',
        'food_orders',
        'activity_logs',
        'notification_deliveries',
        'folios',
        'invoices',
        'payments',
        'housekeeping_tasks',
        'maintenance_tasks'
      ]
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'index', index_state.indexrelname,
        'table', index_state.relname,
        'scans', index_state.idx_scan,
        'tuples_read', index_state.idx_tup_read,
        'tuples_fetched', index_state.idx_tup_fetch
      )
      order by index_state.indexrelname
    ),
    '[]'::jsonb
  )
  into v_indexes
  from pg_catalog.pg_stat_user_indexes index_state
  where index_state.schemaname = 'public'
    and index_state.indexrelname like 'idx_d18_%';

  return jsonb_build_object(
    'captured_at', now(),
    'hotel_id', p_hotel_id,
    'invalid_index_count',
      (
        select count(*)
        from pg_catalog.pg_index index_catalog
        join pg_catalog.pg_class index_relation
          on index_relation.oid = index_catalog.indexrelid
        join pg_catalog.pg_namespace index_namespace
          on index_namespace.oid = index_relation.relnamespace
        where index_namespace.nspname = 'public'
          and not index_catalog.indisvalid
      ),
    'day18_index_count',
      (
        select count(*)
        from pg_catalog.pg_indexes
        where schemaname = 'public'
          and indexname like 'idx_d18_%'
      ),
    'tables', v_tables,
    'indexes', v_indexes
  );
end;
$function$;

-- ============================================================================
-- 13. Public execution closure
-- ============================================================================

revoke all on function public.get_reservations_page(
  uuid,integer,text,text,text,text
) from public, anon;

revoke all on function public.get_guests_page(
  uuid,integer,text,text
) from public, anon;

revoke all on function public.get_guest_sessions_page(
  uuid,integer,text,text
) from public, anon;

revoke all on function public.get_service_requests_page(
  uuid,integer,text,text,text
) from public, anon;

revoke all on function public.get_food_orders_page(
  uuid,integer,text,text
) from public, anon;

revoke all on function public.get_activity_logs_page(
  uuid,integer,text,text,text
) from public, anon;

revoke all on function public.get_notification_deliveries_page(
  uuid,integer,text,text,text
) from public, anon;

revoke all on function public.get_folios_page(
  uuid,integer,text,text
) from public, anon;

revoke all on function public.get_day18_query_health(uuid)
from public, anon;

grant execute on function public.get_reservations_page(
  uuid,integer,text,text,text,text
) to authenticated;

grant execute on function public.get_guests_page(
  uuid,integer,text,text
) to authenticated;

grant execute on function public.get_guest_sessions_page(
  uuid,integer,text,text
) to authenticated;

grant execute on function public.get_service_requests_page(
  uuid,integer,text,text,text
) to authenticated;

grant execute on function public.get_food_orders_page(
  uuid,integer,text,text
) to authenticated;

grant execute on function public.get_activity_logs_page(
  uuid,integer,text,text,text
) to authenticated;

grant execute on function public.get_notification_deliveries_page(
  uuid,integer,text,text,text
) to authenticated;

grant execute on function public.get_folios_page(
  uuid,integer,text,text
) to authenticated;

grant execute on function public.get_day18_query_health(uuid)
to authenticated;

-- ============================================================================
-- 14. Fixed 100-row migration acceptance
-- ============================================================================

create or replace function private.day18_migration_058_acceptance_rev1()
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
  v_admin_user uuid;
  v_hotel_id uuid;
  v_previous_sub text :=
    current_setting('request.jwt.claim.sub', true);
  v_previous_role text :=
    current_setting('request.jwt.claim.role', true);
  v_previous_claims text :=
    current_setting('request.jwt.claims', true);

  v_payload jsonb;
  v_error text;
  v_index_name text;
  v_signature text;
  v_function_oid oid;
begin
  -- 12 prerequisite checks
  return query
  select *
  from (
    values
      ('PREREQUISITE'::text, 'reservations_table'::text,
       to_regclass('public.reservations') is not null,
       'Reservation source exists.'::text),
      ('PREREQUISITE', 'guests_table',
       to_regclass('public.guests') is not null,
       'Guest source exists.'),
      ('PREREQUISITE', 'guest_sessions_table',
       to_regclass('public.guest_sessions') is not null,
       'Guest-session source exists.'),
      ('PREREQUISITE', 'service_requests_table',
       to_regclass('public.service_requests') is not null,
       'Service-request source exists.'),
      ('PREREQUISITE', 'food_orders_table',
       to_regclass('public.food_orders') is not null,
       'Food-order source exists.'),
      ('PREREQUISITE', 'activity_logs_table',
       to_regclass('public.activity_logs') is not null,
       'Activity source exists.'),
      ('PREREQUISITE', 'notification_deliveries_table',
       to_regclass('public.notification_deliveries') is not null,
       'Delivery source exists.'),
      ('PREREQUISITE', 'folios_table',
       to_regclass('public.folios') is not null,
       'Folio source exists.'),
      ('PREREQUISITE', 'invoices_table',
       to_regclass('public.invoices') is not null,
       'Invoice source exists.'),
      ('PREREQUISITE', 'payments_table',
       to_regclass('public.payments') is not null,
       'Payment source exists.'),
      ('PREREQUISITE', 'hotel_access_helper',
       to_regprocedure('private.user_has_hotel_access(uuid)') is not null,
       'Hotel-access authority exists.'),
      ('PREREQUISITE', 'hotel_management_helper',
       to_regprocedure('private.day17_can_manage_hotel(uuid)') is not null,
       'Hotel-management authority exists.')
  ) checks(suite, test_name, passed, details);

  -- 20 index checks
  foreach v_index_name in array array[
    'idx_d18_reservations_cursor',
    'idx_d18_reservations_status_cursor',
    'idx_d18_reservations_source_cursor',
    'idx_d18_guests_updated_cursor',
    'idx_d18_guests_name_prefix',
    'idx_d18_guests_phone_prefix',
    'idx_d18_guests_email_prefix',
    'idx_d18_guest_sessions_cursor',
    'idx_d18_guest_sessions_status_cursor',
    'idx_d18_service_requests_status_cursor',
    'idx_d18_service_requests_department_cursor',
    'idx_d18_food_orders_status_cursor',
    'idx_d18_activity_logs_cursor',
    'idx_d18_activity_logs_entity_cursor',
    'idx_d18_notification_deliveries_status_cursor',
    'idx_d18_folios_status_cursor',
    'idx_d18_invoices_cursor',
    'idx_d18_payments_cursor',
    'idx_d18_housekeeping_status_cursor',
    'idx_d18_maintenance_status_cursor'
  ]
  loop
    return query
    select
      'INDEX',
      v_index_name,
      index_catalog.indisvalid and index_catalog.indisready,
      pg_catalog.pg_get_indexdef(index_catalog.indexrelid)
    from pg_catalog.pg_index index_catalog
    join pg_catalog.pg_class index_relation
      on index_relation.oid = index_catalog.indexrelid
    join pg_catalog.pg_namespace index_namespace
      on index_namespace.oid = index_relation.relnamespace
    where index_namespace.nspname = 'public'
      and index_relation.relname = v_index_name;
  end loop;

  -- 4 private helper checks
  return query
  select *
  from (
    values
      ('HELPER'::text, 'page_limit'::text,
       to_regprocedure('private.day18_page_limit(integer)') is not null,
       'Bounded limit helper exists.'::text),
      ('HELPER', 'encode_cursor',
       to_regprocedure('private.day18_encode_cursor(timestamp with time zone,uuid)') is not null,
       'Opaque cursor encoder exists.'),
      ('HELPER', 'decode_cursor',
       to_regprocedure('private.day18_decode_cursor(text)') is not null,
       'Opaque cursor decoder exists.'),
      ('HELPER', 'assert_page_access',
       to_regprocedure('private.day18_assert_page_access(uuid)') is not null,
       'Tenant access assertion exists.')
  ) checks(suite, test_name, passed, details);

  -- 9 RPCs × 5 contract checks = 45
  foreach v_signature in array array[
    'public.get_reservations_page(uuid,integer,text,text,text,text)',
    'public.get_guests_page(uuid,integer,text,text)',
    'public.get_guest_sessions_page(uuid,integer,text,text)',
    'public.get_service_requests_page(uuid,integer,text,text,text)',
    'public.get_food_orders_page(uuid,integer,text,text)',
    'public.get_activity_logs_page(uuid,integer,text,text,text)',
    'public.get_notification_deliveries_page(uuid,integer,text,text,text)',
    'public.get_folios_page(uuid,integer,text,text)',
    'public.get_day18_query_health(uuid)'
  ]
  loop
    v_function_oid := to_regprocedure(v_signature);

    return query
    select
      'RPC_EXISTS',
      v_signature,
      v_function_oid is not null,
      coalesce(v_function_oid::regprocedure::text, 'missing');

    return query
    select
      'RPC_SECURITY_DEFINER',
      v_signature,
      coalesce(proc.prosecdef, false),
      format('security_definer=%s', coalesce(proc.prosecdef, false))
    from pg_catalog.pg_proc proc
    where proc.oid = v_function_oid;

    return query
    select
      'RPC_SEARCH_PATH',
      v_signature,
      coalesce(proc.proconfig, array[]::text[])
        @> array['search_path=""']::text[],
      coalesce(array_to_string(proc.proconfig, ','), 'no proconfig')
    from pg_catalog.pg_proc proc
    where proc.oid = v_function_oid;

    return query
    select
      'RPC_AUTHENTICATED_EXECUTE',
      v_signature,
      has_function_privilege('authenticated', v_signature, 'EXECUTE'),
      'Authenticated execute privilege checked.';

    return query
    select
      'RPC_ANON_BLOCKED',
      v_signature,
      not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Anonymous execute privilege denied.';
  end loop;

  select pa.user_id
  into v_admin_user
  from public.platform_admins pa
  join auth.users au
    on au.id = pa.user_id
  where pa.status = 'active'
    and coalesce(
      au.banned_until,
      '-infinity'::timestamptz
    ) <= now()
  order by pa.created_at, pa.user_id
  limit 1;

  select h.id
  into v_hotel_id
  from public.hotels h
  where h.status = 'active'
  order by h.created_at, h.id
  limit 1;

  if v_admin_user is null or v_hotel_id is null then
    raise exception
      'Migration 058 acceptance requires an active platform admin and hotel.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    v_admin_user::text,
    true
  );
  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_user,
      'role', 'authenticated'
    )::text,
    true
  );

  -- 9 authorized runtime shape checks
  begin
    v_payload := public.get_reservations_page(
      v_hotel_id, 2, null, null, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'reservations_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_guests_page(
      v_hotel_id, 2, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'guests_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_guest_sessions_page(
      v_hotel_id, 2, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'guest_sessions_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_service_requests_page(
      v_hotel_id, 2, null, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'service_requests_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_food_orders_page(
      v_hotel_id, 2, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'food_orders_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_activity_logs_page(
      v_hotel_id, 2, null, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'activity_logs_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_notification_deliveries_page(
      v_hotel_id, 2, null, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'notification_deliveries_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_folios_page(
      v_hotel_id, 2, null, null
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'folios_page',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array['items','limit','has_more','next_cursor'],
    coalesce(v_error, v_payload::text);

  begin
    v_payload := public.get_day18_query_health(v_hotel_id);
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;
  return query select 'RUNTIME', 'query_health',
    v_error is null and jsonb_typeof(v_payload) = 'object'
      and v_payload ?& array[
        'captured_at',
        'hotel_id',
        'invalid_index_count',
        'day18_index_count',
        'tables',
        'indexes'
      ],
    coalesce(v_error, v_payload::text);

  -- 8 hard page-limit checks
  return query
  select 'LIMIT', 'reservations_limit_100',
    (public.get_reservations_page(
      v_hotel_id, 1000, null, null, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  return query
  select 'LIMIT', 'guests_limit_100',
    (public.get_guests_page(
      v_hotel_id, 1000, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  return query
  select 'LIMIT', 'guest_sessions_limit_100',
    (public.get_guest_sessions_page(
      v_hotel_id, 1000, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  return query
  select 'LIMIT', 'service_requests_limit_100',
    (public.get_service_requests_page(
      v_hotel_id, 1000, null, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  return query
  select 'LIMIT', 'food_orders_limit_100',
    (public.get_food_orders_page(
      v_hotel_id, 1000, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  return query
  select 'LIMIT', 'activity_logs_limit_100',
    (public.get_activity_logs_page(
      v_hotel_id, 1000, null, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  return query
  select 'LIMIT', 'deliveries_limit_100',
    (public.get_notification_deliveries_page(
      v_hotel_id, 1000, null, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  return query
  select 'LIMIT', 'folios_limit_100',
    (public.get_folios_page(
      v_hotel_id, 1000, null, null
    ) ->> 'limit')::integer = 100,
    'Requested 1000; effective limit is 100.';

  -- 2 global index-health checks
  return query
  select
    'INDEX_HEALTH',
    'invalid_public_indexes_zero',
    count(*) = 0,
    format('invalid_public_indexes=%s', count(*))
  from pg_catalog.pg_index index_catalog
  join pg_catalog.pg_class index_relation
    on index_relation.oid = index_catalog.indexrelid
  join pg_catalog.pg_namespace index_namespace
    on index_namespace.oid = index_relation.relnamespace
  where index_namespace.nspname = 'public'
    and not index_catalog.indisvalid;

  return query
  select
    'INDEX_HEALTH',
    'day18_index_count_20',
    count(*) = 20,
    format('day18_indexes=%s', count(*))
  from pg_catalog.pg_indexes
  where schemaname = 'public'
    and indexname like 'idx_d18_%';

  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_previous_sub, ''),
    true
  );
  perform set_config(
    'request.jwt.claim.role',
    coalesce(v_previous_role, ''),
    true
  );
  perform set_config(
    'request.jwt.claims',
    coalesce(v_previous_claims, '{}'),
    true
  );
end;
$function$;

revoke all on function
  private.day18_migration_058_acceptance_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day18_migration_058_acceptance_rev1()
order by suite, test_name;
