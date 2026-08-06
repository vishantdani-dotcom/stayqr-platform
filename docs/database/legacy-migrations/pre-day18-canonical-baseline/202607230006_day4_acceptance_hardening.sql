-- ============================================================================
-- StayQR Day 4 — Final Acceptance Hardening
--
-- Adds human-readable room-block actor details required by the Booking Calendar
-- quick-details acceptance gate. No existing reservation, room, stay or block
-- data is rewritten.
-- ============================================================================

begin;

select pg_advisory_xact_lock(hashtext('stayqr-day4-acceptance-hardening-v1'));

create or replace function private.resolve_calendar_actor_name(
  target_user_id uuid,
  target_hotel_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when target_user_id is null then null
    else coalesce(
      (
        select nullif(trim(administrator.display_name), '')
        from public.platform_admins administrator
        where administrator.user_id = target_user_id
          and administrator.status = 'active'
        limit 1
      ),
      (
        select nullif(trim(staff.full_name), '')
        from public.staff staff
        where staff.auth_user_id = target_user_id
          and staff.status = 'active'
          and (
            staff.hotel_id = target_hotel_id
            or staff.hotel_id is null
          )
        order by
          (staff.hotel_id = target_hotel_id) desc,
          staff.created_at
        limit 1
      ),
      target_user_id::text
    )
  end;
$$;

create or replace function private.build_room_block_json(
  target_hotel_id uuid,
  target_room_block_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', block.id,
    'hotel_id', block.hotel_id,
    'room_id', block.room_id,
    'room_number', room.room_number,
    'room_type_id', room.room_type_id,
    'room_type_name', room_type.name,
    'block_type', block.block_type,
    'status', block.status,
    'start_date', block.start_date,
    'end_date', block.end_date,
    'reason', block.reason,
    'notes', block.notes,
    'release_reason', block.release_reason,
    'created_by', block.created_by,
    'created_by_name', private.resolve_calendar_actor_name(
      block.created_by,
      block.hotel_id
    ),
    'updated_by', block.updated_by,
    'updated_by_name', private.resolve_calendar_actor_name(
      block.updated_by,
      block.hotel_id
    ),
    'released_at', block.released_at,
    'released_by', block.released_by,
    'released_by_name', private.resolve_calendar_actor_name(
      block.released_by,
      block.hotel_id
    ),
    'created_at', block.created_at,
    'updated_at', block.updated_at
  )
  from public.room_blocks block
  join public.rooms room
    on room.id = block.room_id
   and room.hotel_id = block.hotel_id
  join public.room_types room_type
    on room_type.id = room.room_type_id
   and room_type.hotel_id = room.hotel_id
  where block.hotel_id = target_hotel_id
    and block.id = target_room_block_id;
$$;

revoke all on function private.resolve_calendar_actor_name(uuid, uuid)
from public;

-- Verification guards.
do $$
begin
  if to_regprocedure(
    'private.resolve_calendar_actor_name(uuid,uuid)'
  ) is null then
    raise exception
      'Migration stopped: calendar actor-name resolver was not created.';
  end if;

  if to_regprocedure(
    'private.build_room_block_json(uuid,uuid)'
  ) is null then
    raise exception
      'Migration stopped: room-block JSON builder is unavailable.';
  end if;
end
$$;

commit;

-- Supabase may display one blank pg_advisory_xact_lock row. That is expected.
