begin;

-- StayQR Check-in Print Pack REV4 / Migration 121
-- Surgical database closure for secure multi-occupant ID capture:
-- 1) preserve KYC capture-consent enforcement;
-- 2) allow a securely mapped companion to attach an ID to the shared stay;
-- 3) reassert deterministic companion client_id -> guest_id check-in results.

create or replace function public.register_guest_document(target_hotel_id uuid, payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  requested_document_id uuid;
  requested_request_id uuid;
  requested_guest_id uuid;
  requested_session_id uuid;
  requested_reservation_id uuid;
  requested_document_type text;
  requested_storage_bucket text;
  requested_storage_path text;
  requested_original_name text;
  requested_mime_type text;
  requested_size bigint;
  requested_masked_number text;
  requested_issue_country text;
  requested_issued_on date;
  requested_expires_on date;
  requested_metadata jsonb;
  requested_group_id uuid;
  requested_capture_source text;
  requested_document_side text;
  requested_quality_status text;
  requested_quality_score numeric(5,2);
  requested_quality_flags text[];
  requested_retention_until timestamptz;
  requested_retention_basis text;
  consent_row public.guest_consents%rowtype;
  existing_document public.guest_documents%rowtype;
  inserted_document public.guest_documents%rowtype;
  expected_prefix text;
  activity_id uuid;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage']::text[]) then
    raise exception 'You do not have permission to upload guest documents.';
  end if;
  if payload is null or jsonb_typeof(payload) <> 'object' then raise exception 'A JSON object payload is required.'; end if;

  requested_document_id := coalesce(nullif(payload->>'document_id','')::uuid,gen_random_uuid());
  requested_request_id := coalesce(nullif(payload->>'request_id','')::uuid,requested_document_id);
  requested_guest_id := nullif(payload->>'guest_id','')::uuid;
  requested_session_id := nullif(payload->>'guest_session_id','')::uuid;
  requested_reservation_id := nullif(payload->>'reservation_id','')::uuid;
  requested_document_type := lower(trim(coalesce(payload->>'document_type','')));
  requested_storage_bucket := coalesce(nullif(trim(payload->>'storage_bucket'),''),'guest-documents');
  requested_storage_path := trim(coalesce(payload->>'storage_path',''));
  requested_original_name := nullif(trim(payload->>'original_file_name'),'');
  requested_mime_type := lower(trim(coalesce(payload->>'mime_type','')));
  requested_size := nullif(payload->>'file_size_bytes','')::bigint;
  requested_masked_number := nullif(trim(payload->>'document_number_masked'),'');
  requested_issue_country := nullif(trim(payload->>'issue_country'),'');
  requested_issued_on := nullif(payload->>'issued_on','')::date;
  requested_expires_on := nullif(payload->>'expires_on','')::date;
  requested_metadata := coalesce(payload->'metadata','{}'::jsonb);
  requested_group_id := coalesce(nullif(payload->>'document_group_id','')::uuid,requested_document_id);
  requested_capture_source := lower(trim(coalesce(payload->>'capture_source','upload')));
  requested_document_side := lower(trim(coalesce(payload->>'document_side','single')));
  requested_quality_status := lower(trim(coalesce(payload->>'quality_status','not_assessed')));
  requested_quality_score := nullif(payload->>'quality_score','')::numeric;
  requested_quality_flags := coalesce(array(select jsonb_array_elements_text(coalesce(payload->'quality_flags','[]'::jsonb))),'{}'::text[]);
  requested_retention_until := nullif(payload->>'retention_until','')::timestamptz;
  requested_retention_basis := nullif(trim(payload->>'retention_basis'),'');

  if requested_guest_id is null then raise exception 'guest_id is required.'; end if;
  select * into existing_document from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.request_id=requested_request_id limit 1;
  if found then return jsonb_build_object('ok',true,'idempotent',true,'document',to_jsonb(existing_document)); end if;

  if requested_document_type not in ('aadhaar','passport','driving_licence','voter_id','pan','visa','form_c','other') then raise exception 'Unsupported document type.'; end if;
  if requested_storage_bucket <> 'guest-documents' then raise exception 'Guest documents must use the private guest-documents bucket.'; end if;
  if requested_mime_type not in ('image/jpeg','image/png','application/pdf') then raise exception 'Only JPEG, PNG and PDF files are allowed.'; end if;
  if requested_size is null or requested_size<=0 or requested_size>15728640 then raise exception 'The document must be between 1 byte and 15 MB.'; end if;
  if requested_original_name is null or length(requested_original_name)>255 then raise exception 'A valid original file name is required.'; end if;
  if requested_masked_number is not null and length(requested_masked_number)>64 then raise exception 'The masked document number is too long.'; end if;
  if requested_issued_on is not null and requested_expires_on is not null and requested_expires_on<requested_issued_on then raise exception 'Document expiry cannot be before issue date.'; end if;
  if requested_capture_source not in ('upload','camera','scanner_import') then raise exception 'Unsupported capture source.'; end if;
  if requested_document_side not in ('single','front','back') then raise exception 'Unsupported document side.'; end if;
  if requested_quality_status not in ('not_assessed','pass','review') then raise exception 'Unsupported quality status.'; end if;
  if requested_quality_score is not null and (requested_quality_score<0 or requested_quality_score>100) then raise exception 'Quality score must be between 0 and 100.'; end if;
  if requested_retention_until is not null and requested_retention_until<=now() then raise exception 'Retention date must be in the future.'; end if;
  if requested_retention_until is not null and requested_retention_basis is null then raise exception 'Retention basis is required when a retention date is set.'; end if;

  if not exists(select 1 from public.guests g where g.hotel_id=target_hotel_id and g.id=requested_guest_id) then raise exception 'Guest does not belong to the selected hotel.'; end if;
  select * into consent_row from public.guest_consents c
  where c.hotel_id=target_hotel_id and c.guest_id=requested_guest_id and c.purpose='kyc_capture'
    and c.status='granted' and c.revoked_at is null order by c.captured_at desc limit 1;
  if not found then raise exception 'KYC capture consent is required before storing an identity document.'; end if;
  if requested_session_id is not null and not exists(
    select 1
    from public.guest_sessions gs
    where gs.hotel_id=target_hotel_id
      and gs.id=requested_session_id
      and (
        gs.guest_id=requested_guest_id
        or exists(
          select 1
          from public.guest_companions gc
          where gc.hotel_id=target_hotel_id
            and gc.guest_session_id=gs.id
            and gc.guest_id=requested_guest_id
        )
      )
  ) then raise exception 'Guest session does not belong to this guest/companion and hotel.'; end if;
  if requested_reservation_id is not null and not exists(
    select 1 from public.reservation_guests rg join public.reservations r on r.hotel_id=rg.hotel_id and r.id=rg.reservation_id
    where rg.hotel_id=target_hotel_id and rg.reservation_id=requested_reservation_id and rg.guest_id=requested_guest_id
  ) then raise exception 'Reservation does not belong to this guest and hotel.'; end if;

  expected_prefix := target_hotel_id::text||'/'||requested_guest_id::text||'/'||requested_document_id::text||'/';
  if requested_storage_path not like expected_prefix||'%' then raise exception 'Storage path must be scoped to hotel/guest/document.'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id=requested_storage_bucket and o.name=requested_storage_path) then raise exception 'Uploaded storage object was not found.'; end if;

  insert into public.guest_documents(
    id,hotel_id,guest_id,guest_session_id,reservation_id,request_id,document_type,storage_bucket,storage_path,
    original_file_name,mime_type,file_size_bytes,document_number_masked,issue_country,issued_on,expires_on,
    verification_status,uploaded_by,metadata,document_group_id,capture_source,document_side,quality_status,
    quality_score,quality_flags,consent_id,retention_until,retention_basis
  ) values (
    requested_document_id,target_hotel_id,requested_guest_id,requested_session_id,requested_reservation_id,
    requested_request_id,requested_document_type,requested_storage_bucket,requested_storage_path,requested_original_name,
    requested_mime_type,requested_size,requested_masked_number,requested_issue_country,requested_issued_on,requested_expires_on,
    'pending',actor_id,requested_metadata,requested_group_id,requested_capture_source,requested_document_side,
    requested_quality_status,requested_quality_score,requested_quality_flags,consent_row.id,requested_retention_until,requested_retention_basis
  ) returning * into inserted_document;

  update public.guests g set identity_verification_status=case when g.identity_verification_status='verified' then 'verified' else 'pending' end,updated_at=now()
  where g.hotel_id=target_hotel_id and g.id=requested_guest_id;

  activity_id := private.write_activity_log(target_hotel_id,'front_office.guest_document_uploaded','guest_document',inserted_document.id,
    'Private guest document captured and registered for review.',null,
    jsonb_build_object('guest_id',inserted_document.guest_id,'document_type',inserted_document.document_type,'capture_source',inserted_document.capture_source,'document_side',inserted_document.document_side,'quality_status',inserted_document.quality_status),
    jsonb_build_object('request_id',inserted_document.request_id,'consent_id',inserted_document.consent_id,'retention_until',inserted_document.retention_until));
  return jsonb_build_object('ok',true,'idempotent',false,'activity_id',activity_id,'document',to_jsonb(inserted_document));
exception when unique_violation then
  select * into existing_document from public.guest_documents gd where gd.hotel_id=target_hotel_id and gd.request_id=requested_request_id limit 1;
  if found then return jsonb_build_object('ok',true,'idempotent',true,'document',to_jsonb(existing_document)); end if;
  raise;
end;
$$;
revoke all on function public.register_guest_document(uuid,jsonb) from public, anon;
grant execute on function public.register_guest_document(uuid,jsonb) to authenticated, service_role;

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
      'request_id', request_id_value
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
      'guest_id', guest_row.id,
      'companion_count', companion_count
    ),
    result_value,
    jsonb_build_object(
      'source', 'check_in_walk_in_guest',
      'hotel_timezone', hotel_timezone
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
      'companion_count', companion_count
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
  'StayQR multi-occupant direct/walk-in check-in. Preserves the Day 10 atomic contract and returns companion client_id-to-guest_id mappings so per-person ID documents can be attached safely after check-in.';

-- Safety acceptance: consent guard, companion document linkage and deterministic
-- result mapping must all be present together.
do $$
declare
  checkin_def text;
  register_def text;
begin
  checkin_def := pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'));
  register_def := pg_get_functiondef(to_regprocedure('public.register_guest_document(uuid,jsonb)'));

  if checkin_def is null
     or position('client_id' in checkin_def) = 0
     or position('companion_results' in checkin_def) = 0 then
    raise exception 'STOP: deterministic companion mapping contract is not present.';
  end if;

  if register_def is null
     or position('KYC capture consent is required before storing an identity document.' in register_def) = 0 then
    raise exception 'STOP: KYC capture consent guard is not present; migration aborted.';
  end if;

  if position('guest_companions' in register_def) = 0 then
    raise exception 'STOP: companion guest-session document linkage is not present.';
  end if;
end $$;

commit;

select jsonb_build_object(
  'status','CHECKIN_REV4_ID_CONSENT_COMPANION_MAPPING_PASSED',
  'companion_mapping_contract', position('client_id' in pg_get_functiondef(to_regprocedure('public.check_in_walk_in_guest(uuid,jsonb)'))) > 0,
  'kyc_consent_guard_preserved', position('KYC capture consent is required before storing an identity document.' in pg_get_functiondef(to_regprocedure('public.register_guest_document(uuid,jsonb)'))) > 0,
  'companion_document_linkage', position('guest_companions' in pg_get_functiondef(to_regprocedure('public.register_guest_document(uuid,jsonb)'))) > 0
) as final_acceptance;
