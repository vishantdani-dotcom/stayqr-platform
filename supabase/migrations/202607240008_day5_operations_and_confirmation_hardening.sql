begin;

select pg_advisory_xact_lock(hashtext('stayqr-day5-operations-confirmation-hardening-v1'));

-- Day 5 correction: a group reservation header becomes checked_in after its
-- first room is checked in. Remaining confirmed room rows must still appear in
-- arrival and exception queues until each room is checked in independently.
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
as $$
declare
  result jsonb;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Reservation operations access denied.';
  end if;

  if target_date is null then target_date := current_date; end if;
  upcoming_days := greatest(1, least(coalesce(upcoming_days, 7), 31));

  with room_rows as (
    select
      r.id as reservation_id,
      r.reservation_number,
      r.status as reservation_status,
      r.arrival_date,
      r.departure_date,
      r.expected_checkin_time,
      r.expected_checkout_time,
      r.primary_guest_id,
      g.full_name as guest_name,
      g.phone as guest_phone,
      rr.id as reservation_room_id,
      rr.status as room_status,
      rr.room_id,
      rm.room_number,
      rt.name as room_type,
      rr.adults,
      rr.children,
      rr.total_amount,
      r.deposit_collected,
      r.updated_at,
      gs.id as guest_session_id,
      gs.status as guest_session_status,
      gs.checkin_time,
      gs.checkout_time
    from public.reservations r
    join public.reservation_rooms rr
      on rr.hotel_id = r.hotel_id
     and rr.reservation_id = r.id
     and rr.status not in ('cancelled', 'released')
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
  ), item_rows as (
    select jsonb_build_object(
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
      'checkout_time', checkout_time
    ) as item,
    *
    from room_rows
  )
  select jsonb_build_object(
    'hotel_id', target_hotel_id,
    'business_date', target_date,
    'today_arrivals', coalesce((
      select jsonb_agg(item order by expected_checkin_time nulls last, reservation_number)
      from item_rows
      where arrival_date = target_date
        and reservation_status in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
    ), '[]'::jsonb),
    'upcoming_arrivals', coalesce((
      select jsonb_agg(item order by arrival_date, expected_checkin_time nulls last)
      from item_rows
      where arrival_date > target_date
        and arrival_date <= target_date + upcoming_days
        and reservation_status in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
    ), '[]'::jsonb),
    'today_departures', coalesce((
      select jsonb_agg(item order by expected_checkout_time nulls last, room_number)
      from item_rows
      where departure_date = target_date
        and room_status = 'checked_in'
    ), '[]'::jsonb),
    'in_house', coalesce((
      select jsonb_agg(item order by room_number)
      from item_rows
      where room_status = 'checked_in'
        and guest_session_status = 'active'
    ), '[]'::jsonb),
    'unallocated_arrivals', coalesce((
      select jsonb_agg(item order by arrival_date, reservation_number)
      from item_rows
      where room_id is null
        and arrival_date <= target_date + upcoming_days
        and reservation_status in ('tentative', 'confirmed', 'checked_in')
        and room_status in ('held', 'confirmed')
    ), '[]'::jsonb),
    'overdue_arrivals', coalesce((
      select jsonb_agg(item order by arrival_date, reservation_number)
      from item_rows
      where arrival_date < target_date
        and reservation_status in ('confirmed', 'checked_in')
        and room_status = 'confirmed'
        and guest_session_id is null
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

-- Confirmation output now carries room-level policies and meal plan while
-- continuing to use one authoritative reservation snapshot.
create or replace function public.get_reservation_confirmation(
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
  hotel_json jsonb;
  reservation_json jsonb;
  room_json jsonb;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Reservation confirmation access denied.';
  end if;

  select jsonb_build_object(
    'id', h.id,
    'hotel_name', h.hotel_name,
    'email', h.email,
    'phone', h.phone,
    'address', h.address,
    'city', h.city,
    'state', h.state,
    'location', h.location,
    'logo_url', h.logo_url,
    'website', h.website,
    'gst_number', h.gst_number,
    'currency_code', h.currency_code,
    'timezone', h.timezone,
    'invoice_terms', h.invoice_terms,
    'invoice_footer', h.invoice_footer
  ) into hotel_json
  from public.hotels h
  where h.id = target_hotel_id;

  if hotel_json is null then raise exception 'Hotel not found.'; end if;

  reservation_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  if reservation_json is null then raise exception 'Reservation not found.'; end if;

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
        'meal_plan', rp.meal_plan,
        'cancellation_policy', rp.cancellation_policy,
        'is_refundable', rp.is_refundable,
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
  ) into room_json
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
  where rr.hotel_id = target_hotel_id
    and rr.reservation_id = target_reservation_id;

  reservation_json := jsonb_set(
    reservation_json,
    '{rooms}',
    room_json,
    true
  );

  return jsonb_build_object(
    'generated_at', now(),
    'hotel', hotel_json,
    'reservation', reservation_json
  );
end;
$$;

revoke all on function public.get_reservation_operations(uuid,date,integer)
from public;
grant execute on function public.get_reservation_operations(uuid,date,integer)
to authenticated;

revoke all on function public.get_reservation_confirmation(uuid,uuid)
from public;
grant execute on function public.get_reservation_confirmation(uuid,uuid)
to authenticated;

commit;

-- Supabase may display one blank pg_advisory_xact_lock row. That is expected.
