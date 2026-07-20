-- StayQR Day 2 - Step 1 verification
-- READ-ONLY.
-- Run only after migration 202607200002 completes without a red error.
-- Export the single JSON result as CSV and upload it.

with
required_tables as (
  select unnest(array[
    'room_types',
    'rate_plans',
    'seasonal_rates',
    'reservation_number_sequences',
    'reservations',
    'reservation_rooms',
    'reservation_guests',
    'reservation_status_history',
    'room_blocks',
    'room_inventory_allocations'
  ])::text as table_name
),
table_state as (
  select
    rt.table_name,
    to_regclass('public.' || rt.table_name) is not null as table_exists,
    coalesce(c.relrowsecurity, false) as rls_enabled,
    (
      select count(*)
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = rt.table_name
    ) as policy_count
  from required_tables rt
  left join pg_class c
    on c.oid = to_regclass('public.' || rt.table_name)
),
room_type_summary as (
  select
    h.id as hotel_id,
    h.hotel_name,
    count(distinct rt.id)::bigint as room_type_count,
    count(distinct r.id)::bigint as room_count,
    count(distinct r.id) filter (
      where r.room_type_id is not null
    )::bigint as rooms_with_type,
    count(distinct rp.id)::bigint as rate_plan_count,
    count(distinct rp.id) filter (
      where rp.base_rate = 0
    )::bigint as unpriced_rate_plan_count
  from public.hotels h
  left join public.room_types rt on rt.hotel_id = h.id
  left join public.rooms r on r.hotel_id = h.id
  left join public.rate_plans rp on rp.hotel_id = h.id
  group by h.id, h.hotel_name
),
allocation_summary as (
  select
    allocation_type,
    status,
    count(*)::bigint as allocation_count
  from public.room_inventory_allocations
  group by allocation_type, status
),
active_stay_check as (
  select
    (
      select count(*)
      from public.guest_sessions gs
      where gs.status = 'active'
        and gs.room_id is not null
        and gs.reservation_room_id is null
    )::bigint as active_direct_stays,
    (
      select count(*)
      from public.room_inventory_allocations ria
      where ria.allocation_type = 'stay'
        and ria.status = 'active'
    )::bigint as active_stay_allocations
),
overlap_constraint as (
  select
    conname,
    contype,
    pg_get_constraintdef(oid) as definition
  from pg_constraint
  where conrelid =
      'public.room_inventory_allocations'::regclass
    and conname =
      'room_inventory_no_overlapping_active_allocations'
),
trigger_state as (
  select
    event_object_table as table_name,
    trigger_name,
    event_manipulation
  from information_schema.triggers
  where trigger_schema = 'public'
    and trigger_name in (
      'reservations_validate_status',
      'reservations_log_status',
      'reservations_sync_allocations',
      'reservation_rooms_sync_allocation',
      'room_blocks_sync_allocation',
      'guest_sessions_sync_inventory'
    )
)
select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'migration',
      '202607200002_reservation_foundation_and_availability',
    'table_state', (
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.table_name),
        '[]'::jsonb
      )
      from table_state x
    ),
    'room_type_summary', (
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.hotel_name),
        '[]'::jsonb
      )
      from room_type_summary x
    ),
    'allocation_summary', (
      select coalesce(
        jsonb_agg(
          to_jsonb(x)
          order by x.allocation_type, x.status
        ),
        '[]'::jsonb
      )
      from allocation_summary x
    ),
    'active_stay_check', (
      select to_jsonb(x) from active_stay_check x
    ),
    'overlap_constraint', (
      select coalesce(
        jsonb_agg(to_jsonb(x)),
        '[]'::jsonb
      )
      from overlap_constraint x
    ),
    'trigger_state', (
      select coalesce(
        jsonb_agg(
          to_jsonb(x)
          order by x.table_name, x.trigger_name, x.event_manipulation
        ),
        '[]'::jsonb
      )
      from trigger_state x
    ),
    'required_parent_indexes', jsonb_build_object(
      'guests_hotel_id_id',
        to_regclass('public.uq_guests_hotel_id_id') is not null,
      'guest_sessions_hotel_id_id',
        to_regclass('public.uq_guest_sessions_hotel_id_id') is not null,
      'rooms_hotel_id_id',
        to_regclass('public.uq_rooms_hotel_id_id') is not null,
      'room_types_hotel_id_id',
        to_regclass('public.uq_room_types_hotel_id_id') is not null
    ),
    'functions', jsonb_build_object(
      'available_rooms',
        to_regprocedure(
          'public.get_available_rooms(uuid,date,date,uuid)'
        ) is not null,
      'room_type_availability',
        to_regprocedure(
          'public.get_room_type_availability(uuid,date,date)'
        ) is not null,
      'rate_quote',
        to_regprocedure(
          'public.get_rate_quote(uuid,uuid,date,date)'
        ) is not null,
      'next_reservation_number',
        to_regprocedure(
          'private.next_reservation_number(uuid,date)'
        ) is not null
    ),
    'reservation_counts', jsonb_build_object(
      'reservations', (
        select count(*) from public.reservations
      ),
      'reservation_rooms', (
        select count(*) from public.reservation_rooms
      ),
      'room_blocks', (
        select count(*) from public.room_blocks
      )
    ),
    'rooms_missing_room_type', (
      select count(*)
      from public.rooms
      where room_type_id is null
    )
  )
) as stayqr_reservation_foundation_verification;
