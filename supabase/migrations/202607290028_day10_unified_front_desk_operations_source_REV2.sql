-- StayQR v1.0
-- Day 10 Migration 028 REV2
-- Unified Arrivals / Departures / In-House source
--
-- Root cause fixed:
-- public.get_reservation_operations previously started only from
-- reservations + reservation_rooms, so active direct walk-ins with
-- reservation_id/reservation_room_id NULL could never appear.
--
-- This migration preserves the public function signature and existing
-- reservation queues while adding direct walk-ins to:
--   * in_house
--   * today_departures
--
-- It also exposes explicit source metadata without inventing reservation IDs.

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
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Reservation operations access denied.';
  end if;

  select h.timezone
  into hotel_timezone
  from public.hotels h
  where h.id = target_hotel_id;

  if hotel_timezone is null then
    raise exception 'Hotel timezone was not found.';
  end if;

  if target_date is null then
    target_date :=
      (now() at time zone hotel_timezone)::date;
  end if;

  upcoming_days :=
    greatest(1, least(coalesce(upcoming_days, 7), 31));

  with reservation_rows as (
    select
      'reservation'::text as operation_source,
      false as is_walk_in,
      r.id as reservation_id,
      r.reservation_number::text as reservation_number,
      r.status::text as reservation_status,
      r.arrival_date,
      case
        when gs.status::text = 'active'
         and coalesce(gs.extended_until, gs.checkout_time) is not null
        then (
          coalesce(gs.extended_until, gs.checkout_time)
          at time zone hotel_timezone
        )::date
        else r.departure_date
      end as departure_date,
      case
        when gs.status::text = 'active'
         and gs.checkin_time is not null
        then (
          gs.checkin_time
          at time zone hotel_timezone
        )::time
        else r.expected_checkin_time
      end as expected_checkin_time,
      case
        when gs.status::text = 'active'
         and coalesce(
           gs.extended_until,
           gs.checkout_time
         ) is not null
        then (
          coalesce(
            gs.extended_until,
            gs.checkout_time
          )
          at time zone hotel_timezone
        )::time
        else r.expected_checkout_time
      end as expected_checkout_time,
      r.primary_guest_id,
      g.full_name as guest_name,
      g.phone as guest_phone,
      rr.id as reservation_room_id,
      rr.status::text as room_status,
      rr.room_id,
      rm.room_number::text as room_number,
      rt.name::text as room_type,
      rr.adults::integer as adults,
      rr.children::integer as children,
      rr.total_amount::numeric as total_amount,
      r.deposit_collected::numeric as deposit_collected,
      r.updated_at,
      gs.id as guest_session_id,
      gs.status::text as guest_session_status,
      gs.checkin_time,
      coalesce(gs.extended_until, gs.checkout_time) as checkout_time,
      gs.checkout_time as scheduled_checkout_time,
      gs.extended_until,
      case
        when gs.id is not null and gs.status::text = 'active'
        then true
        else false
      end as can_move_room,
      case
        when gs.id is not null and gs.status::text = 'active'
        then true
        else false
      end as can_extend_stay
    from public.reservations r
    join public.reservation_rooms rr
      on rr.hotel_id = r.hotel_id
     and rr.reservation_id = r.id
     and rr.status::text not in ('cancelled', 'released')
    left join public.guests g
      on g.hotel_id = r.hotel_id
     and g.id = r.primary_guest_id
    left join public.rooms rm
      on rm.hotel_id = rr.hotel_id
     and rm.id = rr.room_id
    join public.room_types rt
      on rt.hotel_id = rr.hotel_id
     and rt.id = rr.room_type_id
    left join public.guest_sessions gs
      on gs.hotel_id = rr.hotel_id
     and gs.reservation_room_id = rr.id
    where r.hotel_id = target_hotel_id
  ),

  direct_walkin_rows as (
    select
      'walk_in'::text as operation_source,
      true as is_walk_in,
      null::uuid as reservation_id,
      (
        'WALKIN-'
        || upper(substr(replace(gs.id::text, '-', ''), 1, 8))
      )::text as reservation_number,
      'checked_in'::text as reservation_status,
      (gs.checkin_time at time zone hotel_timezone)::date
        as arrival_date,
      (
        coalesce(gs.extended_until, gs.checkout_time)
        at time zone hotel_timezone
      )::date as departure_date,
      (
        gs.checkin_time
        at time zone hotel_timezone
      )::time as expected_checkin_time,
      (
        coalesce(
          gs.extended_until,
          gs.checkout_time
        )
        at time zone hotel_timezone
      )::time as expected_checkout_time,
      gs.guest_id as primary_guest_id,
      g.full_name as guest_name,
      g.phone as guest_phone,
      null::uuid as reservation_room_id,
      'checked_in'::text as room_status,
      gs.room_id,
      rm.room_number::text as room_number,
      rt.name::text as room_type,
      coalesce(occupancy.adults, 1)::integer as adults,
      coalesce(occupancy.children, 0)::integer as children,
      coalesce(room_charge.total_amount, 0)::numeric
        as total_amount,
      0::numeric as deposit_collected,
      gs.created_at as updated_at,
      gs.id as guest_session_id,
      gs.status::text as guest_session_status,
      gs.checkin_time,
      coalesce(gs.extended_until, gs.checkout_time)
        as checkout_time,
      gs.checkout_time as scheduled_checkout_time,
      gs.extended_until,
      true as can_move_room,
      true as can_extend_stay
    from public.guest_sessions gs
    join public.guests g
      on g.hotel_id = gs.hotel_id
     and g.id = gs.guest_id
    join public.rooms rm
      on rm.hotel_id = gs.hotel_id
     and rm.id = gs.room_id
    join public.room_types rt
      on rt.hotel_id = rm.hotel_id
     and rt.id = rm.room_type_id

    left join lateral (
      select
        (
          1
          + count(*) filter (
              where coalesce(
                nullif(lower(trim(gc.guest_category::text)), ''),
                'adult'
              ) = 'adult'
            )
        )::integer as adults,
        (
          count(*) filter (
            where coalesce(
              nullif(lower(trim(gc.guest_category::text)), ''),
              'adult'
            ) in ('child', 'infant')
          )
        )::integer as children
      from public.guest_companions gc
      where gc.hotel_id = gs.hotel_id
        and gc.guest_session_id = gs.id
    ) occupancy on true

    left join lateral (
      select
        coalesce(sum(p.amount), 0)::numeric as total_amount
      from public.payments p
      where p.hotel_id = gs.hotel_id
        and p.guest_session_id = gs.id
        and p.payment_type::text = 'room_charge'
    ) room_charge on true

    where gs.hotel_id = target_hotel_id
      and gs.status::text = 'active'
      and gs.reservation_id is null
      and gs.reservation_room_id is null
      and gs.room_id is not null
  ),

  operation_rows as (
    select * from reservation_rows
    union all
    select * from direct_walkin_rows
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
        'expected_checkin_time', expected_checkin_time,
        'expected_checkout_time', expected_checkout_time,
        'guest_id', primary_guest_id,
        'guest_name', guest_name,
        'guest_phone', guest_phone,
        'reservation_room_id', reservation_room_id,
        'room_status', room_status,
        'room_id', room_id,
        'room_number', room_number,
        'room_type', room_type,
        'adults', adults,
        'children', children,
        'total_amount', total_amount,
        'deposit_collected', deposit_collected,
        'updated_at', updated_at,
        'guest_session_id', guest_session_id,
        'guest_session_status', guest_session_status,
        'checkin_time', checkin_time,
        'checkout_time', checkout_time,
        'scheduled_checkout_time', scheduled_checkout_time,
        'extended_until', extended_until,
        'can_move_room', can_move_room,
        'can_extend_stay', can_extend_stay
      ) as item,
      *
    from operation_rows
  )

  select jsonb_build_object(
    'hotel_id', target_hotel_id,
    'business_date', target_date,

    'today_arrivals', coalesce((
      select jsonb_agg(
        item
        order by expected_checkin_time nulls last,
                 reservation_number
      )
      from item_rows
      where operation_source = 'reservation'
        and arrival_date = target_date
        and reservation_status in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
    ), '[]'::jsonb),

    'upcoming_arrivals', coalesce((
      select jsonb_agg(
        item
        order by arrival_date,
                 expected_checkin_time nulls last
      )
      from item_rows
      where operation_source = 'reservation'
        and arrival_date > target_date
        and arrival_date <= target_date + upcoming_days
        and reservation_status in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
    ), '[]'::jsonb),

    'today_departures', coalesce((
      select jsonb_agg(
        item
        order by expected_checkout_time nulls last,
                 room_number
      )
      from item_rows
      where departure_date = target_date
        and room_status = 'checked_in'
        and guest_session_status = 'active'
    ), '[]'::jsonb),

    'in_house', coalesce((
      select jsonb_agg(
        item
        order by room_number,
                 checkin_time
      )
      from item_rows
      where room_status = 'checked_in'
        and guest_session_status = 'active'
    ), '[]'::jsonb),

    'unallocated_arrivals', coalesce((
      select jsonb_agg(
        item
        order by arrival_date,
                 reservation_number
      )
      from item_rows
      where operation_source = 'reservation'
        and room_id is null
        and arrival_date <= target_date + upcoming_days
        and reservation_status
          in ('tentative', 'confirmed', 'checked_in')
        and room_status in ('held', 'confirmed')
    ), '[]'::jsonb),

    'overdue_arrivals', coalesce((
      select jsonb_agg(
        item
        order by arrival_date,
                 reservation_number
      )
      from item_rows
      where operation_source = 'reservation'
        and arrival_date < target_date
        and reservation_status in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
        and guest_session_id is null
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
'Day 10 unified front-desk source REV2. Preserves reservation arrivals, adds active direct walk-ins, and normalizes operational schedule fields to hotel-local time without mixing time and timestamptz types.';

revoke all on function public.get_reservation_operations(
  uuid,
  date,
  integer
) from public, anon;

grant execute on function public.get_reservation_operations(
  uuid,
  date,
  integer
) to authenticated, service_role;

commit;
