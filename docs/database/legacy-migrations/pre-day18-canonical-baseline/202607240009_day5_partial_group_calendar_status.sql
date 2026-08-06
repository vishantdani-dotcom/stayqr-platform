begin;

select pg_advisory_xact_lock(hashtextextended('stayqr:day5:partial-group-calendar-status', 0));

create or replace function public.get_booking_calendar_room_status(
  target_hotel_id uuid,
  range_start date,
  range_end date,
  room_type_filter uuid default null,
  reservation_status_filter text[] default null,
  block_status_filter text[] default array['active']::text[],
  page_limit integer default 40,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  raw_calendar jsonb;
  normalized_reservation_statuses text[];
  room_status_events jsonb;
  room_status_unallocated jsonb;
begin
  if reservation_status_filter is not null
     and exists (
       select 1
       from unnest(reservation_status_filter) status_value
       where status_value not in (
         'draft',
         'tentative',
         'confirmed',
         'checked_in',
         'checked_out',
         'cancelled',
         'no_show'
       )
     )
  then
    raise exception 'Reservation status filter is invalid.';
  end if;

  normalized_reservation_statuses :=
    case
      when reservation_status_filter is null
        or cardinality(reservation_status_filter) = 0
      then null
      else reservation_status_filter
    end;

  -- Day 4's read model remains authoritative for room, block, direct-stay,
  -- date-boundary and tenant-isolation rules. Reservation filtering is
  -- intentionally disabled here so mixed-status group bookings can be
  -- filtered at reservation-room level below.
  raw_calendar := public.get_booking_calendar(
    target_hotel_id => target_hotel_id,
    range_start => range_start,
    range_end => range_end,
    room_type_filter => room_type_filter,
    reservation_status_filter => null,
    block_status_filter => block_status_filter,
    page_limit => page_limit,
    page_offset => page_offset
  );

  select coalesce(
    jsonb_agg(
      case
        when event_row.item ->> 'event_type' = 'reservation'
        then event_row.item || jsonb_build_object(
          'booking_status', event_row.item ->> 'status',
          'status', coalesce(
            nullif(event_row.item ->> 'room_status', ''),
            event_row.item ->> 'status'
          ),
          'status_scope', 'reservation_room'
        )
        else event_row.item
      end
      order by event_row.ordinality
    ),
    '[]'::jsonb
  )
  into room_status_events
  from jsonb_array_elements(
    coalesce(raw_calendar -> 'events', '[]'::jsonb)
  ) with ordinality as event_row(item, ordinality)
  where event_row.item ->> 'event_type' <> 'reservation'
     or normalized_reservation_statuses is null
     or coalesce(
          nullif(event_row.item ->> 'room_status', ''),
          event_row.item ->> 'status'
        ) = any(normalized_reservation_statuses);

  select coalesce(
    jsonb_agg(
      unallocated_row.item || jsonb_build_object(
        'booking_status', unallocated_row.item ->> 'status',
        'status', coalesce(
          nullif(unallocated_row.item ->> 'room_status', ''),
          unallocated_row.item ->> 'status'
        ),
        'status_scope', 'reservation_room'
      )
      order by unallocated_row.ordinality
    ),
    '[]'::jsonb
  )
  into room_status_unallocated
  from jsonb_array_elements(
    coalesce(raw_calendar -> 'unallocated_reservations', '[]'::jsonb)
  ) with ordinality as unallocated_row(item, ordinality)
  where normalized_reservation_statuses is null
     or coalesce(
          nullif(unallocated_row.item ->> 'room_status', ''),
          unallocated_row.item ->> 'status'
        ) = any(normalized_reservation_statuses);

  return raw_calendar || jsonb_build_object(
    'events', room_status_events,
    'unallocated_reservations', room_status_unallocated,
    'reservation_status_filter', normalized_reservation_statuses,
    'reservation_status_scope', 'reservation_room'
  );
end;
$$;

revoke all on function public.get_booking_calendar_room_status(
  uuid,
  date,
  date,
  uuid,
  text[],
  text[],
  integer,
  integer
) from public;

grant execute on function public.get_booking_calendar_room_status(
  uuid,
  date,
  date,
  uuid,
  text[],
  text[],
  integer,
  integer
) to authenticated;

comment on function public.get_booking_calendar_room_status(
  uuid,
  date,
  date,
  uuid,
  text[],
  text[],
  integer,
  integer
) is
'Day 5 booking-calendar read model that uses reservation_rooms.status for room cards and status filters while preserving the reservation header status as booking_status.';

commit;

-- Supabase may display one blank pg_advisory_xact_lock row. That is expected.
