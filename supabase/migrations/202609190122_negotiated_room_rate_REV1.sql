begin;

-- StayQR Front Desk negotiated room-rate REV1 / Migration 122
-- Purpose:
-- * Keep room_types.base_rate as the hotel master/reference rate.
-- * Allow an agreed walk-in rate for one stay without mutating Room Setup.
-- * Require a reason whenever the agreed rate differs from the authoritative standard rate.
-- * Bill the existing room_charge payment with the agreed amount.
-- * Preserve an auditable standard/agreed/discount-or-surcharge trail in existing JSON metadata.
-- No new table or column is introduced.

create or replace function public.check_in_walk_in_guest(
  target_hotel_id uuid,
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  existing_event public.walkin_checkin_events%rowtype;
  hotel_timezone text;
  room_row public.rooms%rowtype;
  room_type_row public.room_types%rowtype;
  guest_row public.guests%rowtype;
  companion_row public.guests%rowtype;
  companion_payload jsonb;
  companions_payload jsonb;
  stay_payload jsonb;
  request_id_value text;
  room_id_value uuid;
  checkin_time_value timestamptz;
  checkout_time_value timestamptz;
  starts_on_value date;
  ends_on_value date;
  room_charge_value numeric(12,2);
  standard_room_rate_value numeric(12,2);
  client_standard_room_rate_value numeric(12,2);
  rate_override_reason_value text;
  rate_overridden_value boolean := false;
  rate_discount_amount_value numeric(12,2) := 0;
  rate_surcharge_amount_value numeric(12,2) := 0;
  rate_adjustment_percent_value numeric(8,2) := 0;
  adults_value integer;
  children_value integer;
  created_session_id uuid;
  created_payment_id uuid;
  companion_count integer := 0;
  companion_adults integer := 0;
  companion_children integer := 0;
  companion_results jsonb := '[]'::jsonb;
  result_value jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Walk-in check-in payload must be a JSON object.';
  end if;

  request_id_value := nullif(trim(payload ->> 'request_id'), '');

  if request_id_value is null or length(request_id_value) < 8 then
    raise exception 'A stable request_id of at least 8 characters is required.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:walkin:'
      || target_hotel_id::text
      || ':'
      || request_id_value,
      0
    )
  );

  select event.*
  into existing_event
  from public.walkin_checkin_events event
  where event.hotel_id = target_hotel_id
    and event.idempotency_key = request_id_value
  limit 1;

  if existing_event.id is not null then
    return coalesce(existing_event.result_snapshot, '{}'::jsonb)
      || jsonb_build_object('idempotent', true);
  end if;

  begin
    room_id_value := (payload ->> 'room_id')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Room ID is invalid.';
  end;

  if room_id_value is null then
    raise exception 'Room is required.';
  end if;

  begin
    checkin_time_value := coalesce(
      nullif(payload ->> 'checkin_time', '')::timestamptz,
      now()
    );
    checkout_time_value :=
      nullif(payload ->> 'checkout_time', '')::timestamptz;
    room_charge_value :=
      round(coalesce((payload ->> 'room_charge')::numeric, 0), 2);
    client_standard_room_rate_value :=
      case
        when nullif(payload ->> 'standard_room_rate', '') is null then null
        else round((payload ->> 'standard_room_rate')::numeric, 2)
      end;
    rate_override_reason_value :=
      nullif(trim(payload ->> 'rate_override_reason'), '');
    adults_value :=
      greatest(coalesce((payload ->> 'adults')::integer, 1), 1);
    children_value :=
      greatest(coalesce((payload ->> 'children')::integer, 0), 0);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range then
      raise exception 'Check-in time, checkout time, occupancy or room charge is invalid.';
  end;

  if checkout_time_value is null
     or checkout_time_value <= checkin_time_value
  then
    raise exception 'Checkout time must be after check-in time.';
  end if;

  if room_charge_value < 0 then
    raise exception 'Room charge cannot be negative.';
  end if;

  companions_payload := coalesce(payload -> 'companions', '[]'::jsonb);

  if jsonb_typeof(companions_payload) <> 'array' then
    raise exception 'Companions must be a JSON array.';
  end if;

  select
    (
      count(*) filter (
        where coalesce(
          nullif(lower(trim(item ->> 'guest_category')), ''),
          'adult'
        ) = 'adult'
      )
    )::integer,
    (
      count(*) filter (
        where coalesce(
          nullif(lower(trim(item ->> 'guest_category')), ''),
          'adult'
        ) in ('child', 'infant')
      )
    )::integer
  into companion_adults, companion_children
  from jsonb_array_elements(companions_payload) as companion(item);

  if adults_value <> companion_adults + 1
     or children_value <> companion_children
  then
    raise exception
      'Adults/children counts must match the primary guest and companion categories.';
  end if;

  select h.timezone
  into hotel_timezone
  from public.hotels h
  where h.id = target_hotel_id
    and h.status = 'active'
  for update;

  if hotel_timezone is null then
    raise exception 'Active hotel or hotel timezone was not found.';
  end if;

  starts_on_value :=
    (checkin_time_value at time zone hotel_timezone)::date;
  ends_on_value :=
    (checkout_time_value at time zone hotel_timezone)::date;

  if ends_on_value <= starts_on_value then
    ends_on_value := starts_on_value + 1;
  end if;

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = room_id_value
  for update;

  if not found then
    raise exception 'Selected room was not found for this hotel.';
  end if;

  if room_row.status <> 'available' then
    raise exception 'Selected room is not currently available.';
  end if;

  select room_type.*
  into room_type_row
  from public.room_types room_type
  where room_type.hotel_id = target_hotel_id
    and room_type.id = room_row.room_type_id;

  if not found then
    raise exception 'Selected room type was not found.';
  end if;

  standard_room_rate_value :=
    round(coalesce(room_type_row.base_rate, 0)::numeric, 2);

  if client_standard_room_rate_value is not null
     and abs(client_standard_room_rate_value - standard_room_rate_value) >= 0.01
  then
    raise exception
      'The room standard rate changed after this screen loaded. Refresh check-in and confirm the agreed rate again.';
  end if;

  rate_overridden_value :=
    abs(room_charge_value - standard_room_rate_value) >= 0.01;

  if rate_overridden_value and rate_override_reason_value is null then
    raise exception 'A rate adjustment reason is required when the agreed room rate differs from the hotel standard rate.';
  end if;

  if rate_override_reason_value is not null
     and length(rate_override_reason_value) > 160
  then
    raise exception 'Rate adjustment reason is too long.';
  end if;

  rate_discount_amount_value :=
    round(greatest(standard_room_rate_value - room_charge_value, 0), 2);
  rate_surcharge_amount_value :=
    round(greatest(room_charge_value - standard_room_rate_value, 0), 2);
  rate_adjustment_percent_value :=
    case
      when standard_room_rate_value > 0 and rate_overridden_value then
        round(
          ((room_charge_value - standard_room_rate_value)
            / standard_room_rate_value * 100)::numeric,
          2
        )
      else 0
    end;

  if adults_value > room_type_row.max_adults
     or children_value > room_type_row.max_children
     or adults_value + children_value > room_type_row.max_occupancy
  then
    raise exception 'Guest count exceeds room capacity.';
  end if;

  if exists (
    select 1
    from public.guest_sessions session
    where session.hotel_id = target_hotel_id
      and session.room_id = room_id_value
      and session.status = 'active'
  ) then
    raise exception 'Selected room already has an active guest stay.';
  end if;

  if exists (
    select 1
    from public.room_inventory_allocations allocation
    where allocation.hotel_id = target_hotel_id
      and allocation.room_id = room_id_value
      and allocation.status = 'active'
      and allocation.stay_dates
        && daterange(starts_on_value, ends_on_value, '[)')
  ) then
    raise exception
      'Selected room is reserved, blocked or occupied during the requested stay.';
  end if;

  select *
  into guest_row
  from private.resolve_or_create_guest_day10(
    target_hotel_id,
    coalesce(payload -> 'guest', '{}'::jsonb)
  );

  insert into public.guest_sessions (
    hotel_id,
    room_id,
    guest_id,
    checkin_time,
    checkout_time,
    status,
    checked_in_by
  )
  values (
    target_hotel_id,
    room_id_value,
    guest_row.id,
    checkin_time_value,
    checkout_time_value,
    'active',
    auth.uid()
  )
  returning id into created_session_id;

  insert into public.payments (
    hotel_id,
    guest_id,
    room_id,
    amount,
    payment_type,
    payment_status,
    notes,
    payment_method,
    guest_session_id
  )
  values (
    target_hotel_id,
    guest_row.id,
    room_id_value,
    room_charge_value,
    'room_charge',
    'pending',
    coalesce(
      nullif(trim(payload ->> 'notes'), ''),
      format(
        'Walk-in room charge · Room %s · %s',
        room_row.room_number,
        guest_row.full_name
      )
    ),
    'cash',
    created_session_id
  )
  returning id into created_payment_id;

  update public.rooms
  set status = 'occupied'
  where hotel_id = target_hotel_id
    and id = room_id_value
    and status = 'available';

  if not found then
    raise exception
      'Room status changed during check-in. No check-in was committed.';
  end if;

  insert into public.stay_room_history (
    hotel_id,
    guest_session_id,
    room_id,
    segment_number,
    movement_type,
    segment_start,
    rate_amount,
    created_by,
    metadata
  )
  values (
    target_hotel_id,
    created_session_id,
    room_id_value,
    1,
    'check_in',
    checkin_time_value,
    room_charge_value,
    auth.uid(),
    jsonb_build_object(
      'source', 'check_in_walk_in_guest',
      'request_id', request_id_value,
      'rate', jsonb_build_object(
        'standard_room_rate', standard_room_rate_value,
        'agreed_room_rate', room_charge_value,
        'override_applied', rate_overridden_value,
        'discount_amount', rate_discount_amount_value,
        'surcharge_amount', rate_surcharge_amount_value,
        'adjustment_percent', rate_adjustment_percent_value,
        'reason', rate_override_reason_value,
        'approved_by', auth.uid(),
        'approved_at', now()
      )
    )
  );

  for companion_payload in
    select companion.item
    from jsonb_array_elements(companions_payload) as companion(item)
  loop
    select *
    into companion_row
    from private.resolve_or_create_guest_day10(
      target_hotel_id,
      companion_payload
    );

    if companion_row.id = guest_row.id then
      raise exception 'Primary guest cannot also be added as a companion.';
    end if;

    insert into public.guest_companions (
      hotel_id,
      guest_session_id,
      primary_guest_id,
      guest_id,
      relationship,
      guest_category,
      form_c_required,
      created_by
    )
    values (
      target_hotel_id,
      created_session_id,
      guest_row.id,
      companion_row.id,
      nullif(trim(companion_payload ->> 'relationship'), ''),
      coalesce(
        nullif(lower(trim(companion_payload ->> 'guest_category')), ''),
        'adult'
      ),
      coalesce(
        (companion_payload ->> 'form_c_required')::boolean,
        false
      ),
      auth.uid()
    );

    companion_results := companion_results || jsonb_build_array(
      jsonb_build_object(
        'client_id', nullif(trim(companion_payload ->> 'client_id'), ''),
        'guest_id', companion_row.id,
        'full_name', companion_row.full_name,
        'guest_category', coalesce(
          nullif(lower(trim(companion_payload ->> 'guest_category')), ''),
          'adult'
        ),
        'relationship', nullif(trim(companion_payload ->> 'relationship'), '')
      )
    );

    companion_count := companion_count + 1;
  end loop;

  stay_payload := coalesce(payload -> 'stay_details', '{}'::jsonb);

  if jsonb_typeof(stay_payload) <> 'object' then
    raise exception 'Stay details must be a JSON object.';
  end if;

  insert into public.guest_stay_details (
    hotel_id,
    guest_session_id,
    purpose_of_visit,
    arrival_from,
    next_destination,
    arrival_mode,
    arrival_transport_number,
    departure_mode,
    departure_transport_number,
    passport_number,
    passport_issue_country,
    passport_issued_on,
    passport_expires_on,
    visa_number,
    visa_type,
    visa_issue_place,
    visa_issued_on,
    visa_expires_on,
    date_of_arrival_in_india,
    intended_duration_in_india_days,
    form_c_status,
    early_checkin,
    late_checkout,
    special_notes,
    created_by,
    updated_by
  )
  values (
    target_hotel_id,
    created_session_id,
    nullif(trim(stay_payload ->> 'purpose_of_visit'), ''),
    nullif(trim(stay_payload ->> 'arrival_from'), ''),
    nullif(trim(stay_payload ->> 'next_destination'), ''),
    nullif(trim(stay_payload ->> 'arrival_mode'), ''),
    nullif(trim(stay_payload ->> 'arrival_transport_number'), ''),
    nullif(trim(stay_payload ->> 'departure_mode'), ''),
    nullif(trim(stay_payload ->> 'departure_transport_number'), ''),
    nullif(trim(stay_payload ->> 'passport_number'), ''),
    nullif(trim(stay_payload ->> 'passport_issue_country'), ''),
    nullif(stay_payload ->> 'passport_issued_on', '')::date,
    nullif(stay_payload ->> 'passport_expires_on', '')::date,
    nullif(trim(stay_payload ->> 'visa_number'), ''),
    nullif(trim(stay_payload ->> 'visa_type'), ''),
    nullif(trim(stay_payload ->> 'visa_issue_place'), ''),
    nullif(stay_payload ->> 'visa_issued_on', '')::date,
    nullif(stay_payload ->> 'visa_expires_on', '')::date,
    nullif(stay_payload ->> 'date_of_arrival_in_india', '')::date,
    nullif(stay_payload ->> 'intended_duration_in_india_days', '')::integer,
    coalesce(
      nullif(trim(stay_payload ->> 'form_c_status'), ''),
      case
        when guest_row.is_foreign_guest then 'pending'
        else 'not_required'
      end
    ),
    coalesce((stay_payload ->> 'early_checkin')::boolean, false),
    coalesce((stay_payload ->> 'late_checkout')::boolean, false),
    nullif(trim(stay_payload ->> 'special_notes'), ''),
    auth.uid(),
    auth.uid()
  );

  result_value := jsonb_build_object(
    'success', true,
    'idempotent', false,
    'request_id', request_id_value,
    'hotel_id', target_hotel_id,
    'guest_id', guest_row.id,
    'guest_session_id', created_session_id,
    'room_id', room_id_value,
    'room_number', room_row.room_number,
    'payment_id', created_payment_id,
    'room_charge', room_charge_value,
    'standard_room_rate', standard_room_rate_value,
    'agreed_room_rate', room_charge_value,
    'rate_override_applied', rate_overridden_value,
    'rate_discount_amount', rate_discount_amount_value,
    'rate_surcharge_amount', rate_surcharge_amount_value,
    'rate_adjustment_percent', rate_adjustment_percent_value,
    'rate_override_reason', rate_override_reason_value,
    'checkin_time', checkin_time_value,
    'checkout_time', checkout_time_value,
    'companion_count', companion_count,
    'companions', companion_results
  );

  insert into public.walkin_checkin_events (
    hotel_id,
    guest_session_id,
    guest_id,
    room_id,
    payment_id,
    idempotency_key,
    checked_in_by,
    checked_in_at,
    request_snapshot,
    result_snapshot,
    metadata
  )
  values (
    target_hotel_id,
    created_session_id,
    guest_row.id,
    room_id_value,
    created_payment_id,
    request_id_value,
    auth.uid(),
    checkin_time_value,
    jsonb_build_object(
      'request_id', request_id_value,
      'room_id', room_id_value,
      'checkout_time', checkout_time_value,
      'room_charge', room_charge_value,
      'standard_room_rate', standard_room_rate_value,
      'rate_override_applied', rate_overridden_value,
      'rate_override_reason', rate_override_reason_value,
      'guest_id', guest_row.id,
      'companion_count', companion_count
    ),
    result_value,
    jsonb_build_object(
      'source', 'check_in_walk_in_guest',
      'hotel_timezone', hotel_timezone,
      'rate', jsonb_build_object(
        'standard_room_rate', standard_room_rate_value,
        'agreed_room_rate', room_charge_value,
        'override_applied', rate_overridden_value,
        'discount_amount', rate_discount_amount_value,
        'surcharge_amount', rate_surcharge_amount_value,
        'adjustment_percent', rate_adjustment_percent_value,
        'reason', rate_override_reason_value
      )
    )
  );

  perform private.write_activity_log(
    target_hotel_id,
    'front_office.walkin_checked_in',
    'guest_session',
    created_session_id,
    format(
      'Walk-in guest %s checked in to Room %s.',
      guest_row.full_name,
      room_row.room_number
    ),
    null,
    result_value,
    jsonb_build_object(
      'request_id', request_id_value,
      'guest_id', guest_row.id,
      'room_id', room_id_value,
      'payment_id', created_payment_id,
      'companion_count', companion_count,
      'standard_room_rate', standard_room_rate_value,
      'agreed_room_rate', room_charge_value,
      'rate_override_applied', rate_overridden_value,
      'rate_override_reason', rate_override_reason_value
    )
  );

  return result_value;
end;
$function$;

revoke all on function public.check_in_walk_in_guest(uuid, jsonb)
  from public, anon;

grant execute on function public.check_in_walk_in_guest(uuid, jsonb)
  to authenticated, service_role;

comment on function public.check_in_walk_in_guest(uuid, jsonb) is
  'StayQR multi-occupant direct/walk-in check-in with authoritative hotel standard-rate comparison, audited per-stay negotiated/agreed rate overrides, and deterministic companion mappings.';

commit;

select jsonb_build_object(
  'status', 'NEGOTIATED_ROOM_RATE_REV1_PASSED',
  'rpc_present', to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)') is not null,
  'authoritative_standard_rate', position('standard_room_rate_value := ' in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0
    and position('room_type_row.base_rate' in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0,
  'override_reason_guard', position('A rate adjustment reason is required' in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0,
  'agreed_rate_bills_room_charge', position($needle$'room_charge', room_charge_value$needle$ in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0,
  'audit_metadata_present', position($needle$'standard_room_rate', standard_room_rate_value$needle$ in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0
    and position($needle$'rate_override_reason', rate_override_reason_value$needle$ in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0,
  'companion_mapping_preserved', position($needle$'client_id', nullif(trim(companion_payload ->> 'client_id'), '')$needle$ in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0
) as final_acceptance;
