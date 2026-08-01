-- StayQR Day 4 — Booking Calendar Foundation Verification
-- READ-ONLY. Run after Migration 202607230005 succeeds.
-- Export the one JSON row as CSV and upload it.

with
function_state as (
  select *
  from (
    values
      (
        'get_booking_calendar',
        to_regprocedure(
          'public.get_booking_calendar(uuid,date,date,uuid,text[],text[],integer,integer)'
        ) is not null
      ),
      (
        'move_reservation_on_calendar',
        to_regprocedure(
          'public.move_reservation_on_calendar(uuid,uuid,uuid,uuid,date,timestamptz)'
        ) is not null
      ),
      (
        'create_calendar_room_block',
        to_regprocedure(
          'public.create_calendar_room_block(uuid,jsonb)'
        ) is not null
      ),
      (
        'update_calendar_room_block',
        to_regprocedure(
          'public.update_calendar_room_block(uuid,uuid,jsonb,timestamptz)'
        ) is not null
      ),
      (
        'change_calendar_room_block_status',
        to_regprocedure(
          'public.change_calendar_room_block_status(uuid,uuid,text,text)'
        ) is not null
      ),
      (
        'get_calendar_room_block_details',
        to_regprocedure(
          'public.get_calendar_room_block_details(uuid,uuid)'
        ) is not null
      )
  ) functions(function_name, function_exists)
),
column_state as (
  select *
  from (
    values
      (
        'room_blocks.updated_by',
        exists (
          select 1
          from information_schema.columns
          where table_schema = 'public'
            and table_name = 'room_blocks'
            and column_name = 'updated_by'
        )
      ),
      (
        'room_blocks.release_reason',
        exists (
          select 1
          from information_schema.columns
          where table_schema = 'public'
            and table_name = 'room_blocks'
            and column_name = 'release_reason'
        )
      )
  ) columns(column_name, column_exists)
),
index_state as (
  select *
  from (
    values
      (
        'idx_room_blocks_hotel_updated',
        to_regclass(
          'public.idx_room_blocks_hotel_updated'
        ) is not null
      ),
      (
        'idx_reservation_rooms_unallocated',
        to_regclass(
          'public.idx_reservation_rooms_unallocated'
        ) is not null
      ),
      (
        'room_inventory_overlap_constraint',
        exists (
          select 1
          from pg_constraint
          where conname =
            'room_inventory_no_overlapping_active_allocations'
            and conrelid =
              'public.room_inventory_allocations'::regclass
        )
      )
  ) indexes(index_name, index_exists)
)
select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'migration',
      '202607230005_booking_calendar_and_room_allocation',
    'function_state', (
      select jsonb_agg(
        to_jsonb(row_state)
        order by row_state.function_name
      )
      from function_state row_state
    ),
    'column_state', (
      select jsonb_agg(
        to_jsonb(row_state)
        order by row_state.column_name
      )
      from column_state row_state
    ),
    'index_state', (
      select jsonb_agg(
        to_jsonb(row_state)
        order by row_state.index_name
      )
      from index_state row_state
    ),
    'active_inventory_counts', jsonb_build_object(
      'reservation_allocations', (
        select count(*)
        from public.room_inventory_allocations allocation
        where allocation.status = 'active'
          and allocation.allocation_type = 'reservation'
      ),
      'room_blocks', (
        select count(*)
        from public.room_inventory_allocations allocation
        where allocation.status = 'active'
          and allocation.allocation_type = 'block'
      ),
      'direct_stays', (
        select count(*)
        from public.room_inventory_allocations allocation
        where allocation.status = 'active'
          and allocation.allocation_type = 'stay'
      )
    )
  )
) as stayqr_day4_calendar_foundation_verification;
