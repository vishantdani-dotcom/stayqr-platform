-- StayQR v1.0
-- Day 10 Migration 031 REV1
-- Authoritative overdue-arrival and overdue-departure classification
--
-- This migration replaces only the unified read RPC.
-- It does not alter reservations, guest sessions, rooms, payments,
-- allocations, history, housekeeping or any other operational row.

begin;

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
as $function$
declare
  result jsonb;
  hotel_timezone text;
  hotel_local_today date;
  as_of_at timestamptz;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception
      'Reservation operations access denied.';
  end if;

  select hotel.timezone
  into hotel_timezone
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  if hotel_timezone is null then
    raise exception
      'Hotel timezone was not found.';
  end if;

  hotel_local_today :=
    (now() at time zone hotel_timezone)::date;

  if target_date is null then
    target_date := hotel_local_today;
  end if;

  upcoming_days :=
    greatest(
      1,
      least(
        coalesce(upcoming_days, 7),
        31
      )
    );

  -- Current-date boards use the actual current instant. Historical boards use
  -- the selected hotel's local end of business date so their overdue labels
  -- remain deterministic rather than depending on the viewer's timezone.
  as_of_at :=
    case
      when target_date = hotel_local_today
      then now()
      else (
        target_date + time '23:59:59'
      ) at time zone hotel_timezone
    end;

  with reservation_rows as (
    select
      'reservation'::text as operation_source,
      false as is_walk_in,
      reservation.id as reservation_id,
      reservation.reservation_number::text
        as reservation_number,
      reservation.status::text
        as reservation_status,
      reservation.arrival_date,
      case
        when guest_session.status::text = 'active'
         and coalesce(
               guest_session.extended_until,
               guest_session.checkout_time
             ) is not null
        then (
          coalesce(
            guest_session.extended_until,
            guest_session.checkout_time
          ) at time zone hotel_timezone
        )::date
        else reservation.departure_date
      end as departure_date,
      case
        when guest_session.status::text = 'active'
         and guest_session.checkin_time is not null
        then (
          guest_session.checkin_time
          at time zone hotel_timezone
        )::time
        else reservation.expected_checkin_time
      end as expected_checkin_time,
      case
        when guest_session.status::text = 'active'
         and coalesce(
               guest_session.extended_until,
               guest_session.checkout_time
             ) is not null
        then (
          coalesce(
            guest_session.extended_until,
            guest_session.checkout_time
          ) at time zone hotel_timezone
        )::time
        else reservation.expected_checkout_time
      end as expected_checkout_time,
      reservation.primary_guest_id,
      guest.full_name as guest_name,
      guest.phone as guest_phone,
      reservation_room.id as reservation_room_id,
      reservation_room.status::text as room_status,
      reservation_room.room_id,
      room.room_number::text as room_number,
      room_type.name::text as room_type,
      reservation_room.adults::integer as adults,
      reservation_room.children::integer as children,
      reservation_room.total_amount::numeric
        as total_amount,
      reservation.deposit_collected::numeric
        as deposit_collected,
      reservation.updated_at,
      guest_session.id as guest_session_id,
      guest_session.status::text
        as guest_session_status,
      guest_session.checkin_time,
      coalesce(
        guest_session.extended_until,
        guest_session.checkout_time
      ) as checkout_time,
      guest_session.checkout_time
        as scheduled_checkout_time,
      guest_session.extended_until,
      case
        when guest_session.id is not null
         and guest_session.status::text = 'active'
        then true
        else false
      end as can_move_room,
      case
        when guest_session.id is not null
         and guest_session.status::text = 'active'
        then true
        else false
      end as can_extend_stay
    from public.reservations reservation
    join public.reservation_rooms reservation_room
      on reservation_room.hotel_id =
         reservation.hotel_id
     and reservation_room.reservation_id =
         reservation.id
     and reservation_room.status::text
           not in ('cancelled', 'released')
    left join public.guests guest
      on guest.hotel_id = reservation.hotel_id
     and guest.id = reservation.primary_guest_id
    left join public.rooms room
      on room.hotel_id = reservation_room.hotel_id
     and room.id = reservation_room.room_id
    join public.room_types room_type
      on room_type.hotel_id =
         reservation_room.hotel_id
     and room_type.id =
         reservation_room.room_type_id
    left join public.guest_sessions guest_session
      on guest_session.hotel_id =
         reservation_room.hotel_id
     and guest_session.reservation_room_id =
         reservation_room.id
    where reservation.hotel_id = target_hotel_id
  ),

  direct_walkin_rows as (
    select
      'walk_in'::text as operation_source,
      true as is_walk_in,
      null::uuid as reservation_id,
      (
        'WALKIN-'
        || upper(
          substr(
            replace(guest_session.id::text, '-', ''),
            1,
            8
          )
        )
      )::text as reservation_number,
      'checked_in'::text as reservation_status,
      (
        guest_session.checkin_time
        at time zone hotel_timezone
      )::date as arrival_date,
      (
        coalesce(
          guest_session.extended_until,
          guest_session.checkout_time
        ) at time zone hotel_timezone
      )::date as departure_date,
      (
        guest_session.checkin_time
        at time zone hotel_timezone
      )::time as expected_checkin_time,
      (
        coalesce(
          guest_session.extended_until,
          guest_session.checkout_time
        ) at time zone hotel_timezone
      )::time as expected_checkout_time,
      guest_session.guest_id as primary_guest_id,
      guest.full_name as guest_name,
      guest.phone as guest_phone,
      null::uuid as reservation_room_id,
      'checked_in'::text as room_status,
      guest_session.room_id,
      room.room_number::text as room_number,
      room_type.name::text as room_type,
      coalesce(occupancy.adults, 1)::integer
        as adults,
      coalesce(occupancy.children, 0)::integer
        as children,
      coalesce(room_charge.total_amount, 0)::numeric
        as total_amount,
      0::numeric as deposit_collected,
      guest_session.created_at as updated_at,
      guest_session.id as guest_session_id,
      guest_session.status::text
        as guest_session_status,
      guest_session.checkin_time,
      coalesce(
        guest_session.extended_until,
        guest_session.checkout_time
      ) as checkout_time,
      guest_session.checkout_time
        as scheduled_checkout_time,
      guest_session.extended_until,
      true as can_move_room,
      true as can_extend_stay
    from public.guest_sessions guest_session
    join public.guests guest
      on guest.hotel_id = guest_session.hotel_id
     and guest.id = guest_session.guest_id
    join public.rooms room
      on room.hotel_id = guest_session.hotel_id
     and room.id = guest_session.room_id
    join public.room_types room_type
      on room_type.hotel_id = room.hotel_id
     and room_type.id = room.room_type_id

    left join lateral (
      select
        (
          1
          + count(*) filter (
              where coalesce(
                nullif(
                  lower(
                    trim(
                      companion.guest_category::text
                    )
                  ),
                  ''
                ),
                'adult'
              ) = 'adult'
            )
        )::integer as adults,
        (
          count(*) filter (
            where coalesce(
              nullif(
                lower(
                  trim(
                    companion.guest_category::text
                  )
                ),
                ''
              ),
              'adult'
            ) in ('child', 'infant')
          )
        )::integer as children
      from public.guest_companions companion
      where companion.hotel_id =
            guest_session.hotel_id
        and companion.guest_session_id =
            guest_session.id
    ) occupancy on true

    left join lateral (
      select
        coalesce(
          sum(payment.amount),
          0
        )::numeric as total_amount
      from public.payments payment
      where payment.hotel_id =
            guest_session.hotel_id
        and payment.guest_session_id =
            guest_session.id
        and payment.payment_type::text =
            'room_charge'
    ) room_charge on true

    where guest_session.hotel_id =
          target_hotel_id
      and guest_session.status::text =
          'active'
      and guest_session.reservation_id
          is null
      and guest_session.reservation_room_id
          is null
      and guest_session.room_id is not null
  ),

  operation_rows as (
    select * from reservation_rows
    union all
    select * from direct_walkin_rows
  ),

  classified_rows as (
    select
      operation_row.*,

      case
        -- A confirmed reservation from an earlier business date never
        -- generated a guest session.
        when operation_row.operation_source =
             'reservation'
         and operation_row.guest_session_id is null
         and operation_row.room_status = 'confirmed'
         and operation_row.reservation_status
               in ('confirmed', 'checked_in')
         and operation_row.arrival_date < target_date
        then 'missed_arrival'

        -- Today's expected check-in time has passed without a guest session.
        when operation_row.operation_source =
             'reservation'
         and operation_row.guest_session_id is null
         and operation_row.room_status = 'confirmed'
         and operation_row.reservation_status
               in ('confirmed', 'checked_in')
         and operation_row.arrival_date = target_date
         and target_date = hotel_local_today
         and operation_row.expected_checkin_time
               is not null
         and (
           operation_row.arrival_date
           + operation_row.expected_checkin_time
         ) at time zone hotel_timezone < now()
        then 'late_arrival'

        -- An active checked-in stay remained open after an earlier checkout
        -- business date.
        when operation_row.room_status = 'checked_in'
         and operation_row.guest_session_status =
             'active'
         and operation_row.departure_date <
             target_date
        then 'overdue_departure'

        -- Today's effective checkout time has passed and the stay is active.
        -- An extension changes checkout_time/departure_date first, so properly
        -- extended stays are not classified as late.
        when operation_row.room_status = 'checked_in'
         and operation_row.guest_session_status =
             'active'
         and operation_row.departure_date =
             target_date
         and target_date = hotel_local_today
         and operation_row.checkout_time < now()
        then 'late_checkout'

        else null
      end as exception_type,

      case
        when operation_row.operation_source =
             'reservation'
         and operation_row.guest_session_id is null
         and operation_row.room_status = 'confirmed'
         and operation_row.reservation_status
               in ('confirmed', 'checked_in')
         and (
           operation_row.arrival_date < target_date
           or (
             operation_row.arrival_date =
               target_date
             and target_date = hotel_local_today
             and operation_row.expected_checkin_time
                   is not null
             and (
               operation_row.arrival_date
               + operation_row.expected_checkin_time
             ) at time zone hotel_timezone < now()
           )
         )
        then (
          operation_row.arrival_date
          + coalesce(
              operation_row.expected_checkin_time,
              time '18:00:00'
            )
        ) at time zone hotel_timezone

        when operation_row.room_status =
             'checked_in'
         and operation_row.guest_session_status =
             'active'
         and (
           operation_row.departure_date <
             target_date
           or (
             operation_row.departure_date =
               target_date
             and target_date = hotel_local_today
             and operation_row.checkout_time < now()
           )
         )
        then operation_row.checkout_time

        else null
      end as overdue_since
    from operation_rows operation_row
  ),

  item_rows as (
    select
      jsonb_build_object(
        'operation_source', operation_source,
        'is_walk_in', is_walk_in,
        'reservation_id', reservation_id,
        'reservation_number', reservation_number,
        'reservation_status', reservation_status,
        'arrival_date', arrival_date,
        'departure_date', departure_date,
        'expected_checkin_time',
          expected_checkin_time,
        'expected_checkout_time',
          expected_checkout_time,
        'guest_id', primary_guest_id,
        'guest_name', guest_name,
        'guest_phone', guest_phone,
        'reservation_room_id',
          reservation_room_id,
        'room_status', room_status,
        'room_id', room_id,
        'room_number', room_number,
        'room_type', room_type,
        'adults', adults,
        'children', children,
        'total_amount', total_amount,
        'deposit_collected',
          deposit_collected,
        'updated_at', updated_at,
        'guest_session_id',
          guest_session_id,
        'guest_session_status',
          guest_session_status,
        'checkin_time', checkin_time,
        'checkout_time', checkout_time,
        'scheduled_checkout_time',
          scheduled_checkout_time,
        'extended_until', extended_until,
        'can_move_room', can_move_room,
        'can_extend_stay', can_extend_stay,

        -- REV1 exception contract.
        'is_overdue',
          exception_type is not null,
        'exception_type', exception_type,
        'overdue_since', overdue_since,
        'minutes_overdue',
          case
            when exception_type is not null
             and overdue_since is not null
            then greatest(
              0,
              floor(
                extract(
                  epoch from (
                    as_of_at - overdue_since
                  )
                ) / 60
              )::bigint
            )
            else 0::bigint
          end
      ) as item,
      classified_rows.*
    from classified_rows
  ),

  overdue_exception_rows as (
    select *
    from item_rows
    where exception_type is not null
  ),

  overdue_arrival_rows as (
    select *
    from item_rows
    where exception_type in (
      'missed_arrival',
      'late_arrival'
    )
  ),

  overdue_departure_rows as (
    select *
    from item_rows
    where exception_type in (
      'overdue_departure',
      'late_checkout'
    )
  )

  select jsonb_build_object(
    'hotel_id', target_hotel_id,
    'business_date', target_date,
    'hotel_timezone', hotel_timezone,
    'hotel_local_today', hotel_local_today,
    'generated_at', now(),
    'as_of_at', as_of_at,

    'today_arrivals', coalesce((
      select jsonb_agg(
        item
        order by
          expected_checkin_time nulls last,
          reservation_number
      )
      from item_rows
      where operation_source = 'reservation'
        and arrival_date = target_date
        and reservation_status
              in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
    ), '[]'::jsonb),

    'upcoming_arrivals', coalesce((
      select jsonb_agg(
        item
        order by
          arrival_date,
          expected_checkin_time nulls last
      )
      from item_rows
      where operation_source = 'reservation'
        and arrival_date > target_date
        and arrival_date <=
            target_date + upcoming_days
        and reservation_status
              in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
    ), '[]'::jsonb),

    -- Today departures intentionally remains the complete schedule for the
    -- selected day. A same-day late checkout can also appear in the exception
    -- queue because schedule and exception queues answer different questions.
    'today_departures', coalesce((
      select jsonb_agg(
        item
        order by
          expected_checkout_time nulls last,
          room_number
      )
      from item_rows
      where departure_date = target_date
        and room_status = 'checked_in'
        and guest_session_status = 'active'
    ), '[]'::jsonb),

    -- In-house intentionally contains every active checked-in stay, including
    -- an overdue stay. The overdue queue is an exception lens, not a removal
    -- from occupancy.
    'in_house', coalesce((
      select jsonb_agg(
        item
        order by
          room_number,
          checkin_time
      )
      from item_rows
      where room_status = 'checked_in'
        and guest_session_status = 'active'
    ), '[]'::jsonb),

    'unallocated_arrivals', coalesce((
      select jsonb_agg(
        item
        order by
          arrival_date,
          reservation_number
      )
      from item_rows
      where operation_source = 'reservation'
        and room_id is null
        and arrival_date <=
            target_date + upcoming_days
        and reservation_status
              in (
                'tentative',
                'confirmed',
                'checked_in'
              )
        and room_status in ('held', 'confirmed')
    ), '[]'::jsonb),

    -- Canonical Day 10 key.
    'overdue_exceptions', coalesce((
      select jsonb_agg(
        item
        order by
          overdue_since,
          room_number nulls last,
          reservation_number
      )
      from overdue_exception_rows
    ), '[]'::jsonb),

    -- Backward-compatible key used by the existing six-tab frontend. It now
    -- contains both arrival and departure exceptions.
    'overdue_arrivals', coalesce((
      select jsonb_agg(
        item
        order by
          overdue_since,
          room_number nulls last,
          reservation_number
      )
      from overdue_exception_rows
    ), '[]'::jsonb),

    -- Specialized keys are supplied for the final hardened frontend and other
    -- consumers without breaking the existing response contract.
    'late_arrivals', coalesce((
      select jsonb_agg(
        item
        order by
          overdue_since,
          reservation_number
      )
      from overdue_arrival_rows
    ), '[]'::jsonb),

    'overdue_departures', coalesce((
      select jsonb_agg(
        item
        order by
          overdue_since,
          room_number nulls last
      )
      from overdue_departure_rows
    ), '[]'::jsonb)
  )
  into result;

  return result;
end;
$function$;

comment on function public.get_reservation_operations(
  uuid,
  date,
  integer
) is
'Day 10 unified front-desk source REV3. Preserves the six existing queues and adds authoritative hotel-timezone-aware missed-arrival, late-arrival, overdue-departure and same-day late-checkout classification. Active overdue stays remain in In House; same-day late checkouts remain in Today Departures and also appear in the exception lens.';

revoke all
on function public.get_reservation_operations(
  uuid,
  date,
  integer
)
from public, anon;

grant execute
on function public.get_reservation_operations(
  uuid,
  date,
  integer
)
to authenticated, service_role;

commit;
