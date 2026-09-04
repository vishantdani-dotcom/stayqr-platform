-- StayQR Commercial-Ready: Guest ID Scan + safe extraction + verified profile apply REV1
-- Provider-independent. Does not enable UIDAI online authentication and does not
-- treat OCR or QR presence as Aadhaar verification.

create or replace function public.record_guest_document_extraction(
  target_hotel_id uuid,
  target_document_id uuid,
  extraction_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid := auth.uid();
  doc public.guest_documents%rowtype;
  extraction_status text := lower(trim(coalesce(extraction_payload->>'status','limited')));
  extraction_method text := lower(trim(coalesce(extraction_payload->>'method','manual')));
  extracted_fields jsonb := coalesce(extraction_payload->'extracted_fields','{}'::jsonb);
  safe_fields jsonb := '{}'::jsonb;
  masked_number text;
  qr_digest text := lower(trim(coalesce(extraction_payload->>'secure_qr_payload_sha256','')));
  confidence_value numeric;
  activity_id uuid;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage']::text[]) then
    raise exception 'Guest document extraction access denied.';
  end if;
  if jsonb_typeof(coalesce(extraction_payload,'{}'::jsonb)) <> 'object' then raise exception 'Extraction payload must be a JSON object.'; end if;
  if pg_column_size(extraction_payload) > 16384 then raise exception 'Extraction payload is too large.'; end if;
  if extraction_status not in ('extracted','limited','manual_review') then raise exception 'Unsupported extraction status.'; end if;
  if length(extraction_method) > 80 then raise exception 'Extraction method is too long.'; end if;
  if jsonb_typeof(extracted_fields) <> 'object' then raise exception 'Extracted fields must be a JSON object.'; end if;

  select * into doc
  from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.id=target_document_id and gd.deleted_at is null
  for update;
  if not found then raise exception 'Guest document not found.'; end if;

  -- Strict allow-list. Raw OCR text, raw QR payload, Aadhaar number and biometrics
  -- have no storage path in this RPC.
  safe_fields := jsonb_strip_nulls(jsonb_build_object(
    'full_name', nullif(left(trim(extracted_fields->>'full_name'),120),''),
    'date_of_birth', nullif(trim(extracted_fields->>'date_of_birth'),''),
    'gender', nullif(lower(trim(extracted_fields->>'gender')),''),
    'address_line1', nullif(left(trim(extracted_fields->>'address_line1'),240),''),
    'address_line2', nullif(left(trim(extracted_fields->>'address_line2'),240),''),
    'city', nullif(left(trim(extracted_fields->>'city'),120),''),
    'state_region', nullif(left(trim(extracted_fields->>'state_region'),120),''),
    'postal_code', nullif(left(trim(extracted_fields->>'postal_code'),24),''),
    'nationality', nullif(left(trim(extracted_fields->>'nationality'),80),''),
    'country_of_residence', nullif(left(trim(extracted_fields->>'country_of_residence'),80),''),
    'document_number_masked', nullif(left(trim(extracted_fields->>'document_number_masked'),64),'')
  ));

  if safe_fields ? 'gender' and safe_fields->>'gender' not in ('male','female','non_binary','other','prefer_not_to_say') then
    safe_fields := safe_fields - 'gender';
  end if;
  if safe_fields ? 'date_of_birth' then
    begin
      perform (safe_fields->>'date_of_birth')::date;
    exception when others then
      safe_fields := safe_fields - 'date_of_birth';
    end;
  end if;

  masked_number := coalesce(nullif(trim(extraction_payload->>'document_number_masked'),''), safe_fields->>'document_number_masked');
  if doc.document_type='aadhaar' and masked_number is not null and length(regexp_replace(masked_number,'\D','','g')) >= 12 then
    raise exception 'Full Aadhaar-like numbers are not permitted in extraction evidence.';
  end if;
  if doc.document_type='aadhaar' and safe_fields ? 'document_number_masked' and length(regexp_replace(safe_fields->>'document_number_masked','\D','','g')) >= 12 then
    raise exception 'Full Aadhaar-like numbers are not permitted in extracted fields.';
  end if;
  if qr_digest<>'' and qr_digest !~ '^[0-9a-f]{64}$' then raise exception 'Invalid QR payload digest.'; end if;

  begin
    confidence_value := nullif(extraction_payload->>'confidence','')::numeric;
  exception when others then confidence_value := null;
  end;
  if confidence_value is not null and (confidence_value < 0 or confidence_value > 1) then confidence_value := null; end if;

  update public.guest_documents gd
  set metadata = coalesce(gd.metadata,'{}'::jsonb) || jsonb_build_object(
      'extraction', jsonb_build_object(
        'status', extraction_status,
        'method', extraction_method,
        'confidence', confidence_value,
        'extracted_fields', safe_fields,
        'secure_qr_detected', coalesce((extraction_payload->>'secure_qr_detected')::boolean,false),
        'secure_qr_payload_sha256', nullif(qr_digest,''),
        'raw_ocr_text_stored', false,
        'raw_qr_payload_stored', false,
        'recorded_at', date_trunc('second',now()),
        'recorded_by', actor_id
      )
    ),
    document_number_masked = coalesce(masked_number,gd.document_number_masked),
    updated_at = now()
  where gd.hotel_id=target_hotel_id and gd.id=target_document_id
  returning * into doc;

  activity_id := private.write_activity_log(
    target_hotel_id,'guest.document_extraction_recorded','guest_document',doc.id,
    'Safe ID extraction evidence recorded without raw OCR or QR payload.',null,
    jsonb_build_object('status',extraction_status,'method',extraction_method,'secure_qr_detected',coalesce((extraction_payload->>'secure_qr_detected')::boolean,false)),
    jsonb_build_object('guest_id',doc.guest_id,'raw_ocr_text_stored',false,'raw_qr_payload_stored',false)
  );

  return jsonb_build_object('ok',true,'activity_id',activity_id,'document_id',doc.id,'extraction',doc.metadata->'extraction');
end;
$$;
revoke all on function public.record_guest_document_extraction(uuid,uuid,jsonb) from public, anon;
grant execute on function public.record_guest_document_extraction(uuid,uuid,jsonb) to authenticated, service_role;

create or replace function public.apply_guest_document_identity_fields(
  target_hotel_id uuid,
  target_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid := auth.uid();
  doc public.guest_documents%rowtype;
  fields jsonb;
  before_guest jsonb;
  after_guest public.guests%rowtype;
  activity_id uuid;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_permission(target_hotel_id,'guests.manage') then raise exception 'Only authorized guest managers can apply verified identity details.'; end if;

  select * into doc from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.id=target_document_id and gd.deleted_at is null
  for update;
  if not found then raise exception 'Guest document not found.'; end if;
  if doc.verification_status <> 'verified' then raise exception 'Only a verified document can update Guest 360.'; end if;

  fields := coalesce(doc.metadata->'extraction'->'extracted_fields','{}'::jsonb);
  if jsonb_typeof(fields) <> 'object' or coalesce(doc.metadata->'extraction'->>'status','') <> 'extracted' then
    raise exception 'No safe extracted fields are available for this document.';
  end if;

  if doc.document_type='aadhaar' and not exists(
    select 1 from public.guest_identity_verifications giv
    where giv.hotel_id=target_hotel_id and giv.guest_id=doc.guest_id and giv.guest_document_id=doc.id
      and giv.status='verified' and giv.signature_valid=true
      and giv.verification_method in ('aadhaar_secure_qr_uidai_reader','aadhaar_offline_xml')
  ) then
    raise exception 'Aadhaar OCR fields cannot be applied without linked UIDAI signed verification evidence.';
  end if;

  select to_jsonb(g) into before_guest from public.guests g where g.hotel_id=target_hotel_id and g.id=doc.guest_id;

  update public.guests g set
    full_name = coalesce(nullif(trim(fields->>'full_name'),''),g.full_name),
    date_of_birth = coalesce(nullif(fields->>'date_of_birth','')::date,g.date_of_birth),
    gender = coalesce(case when fields->>'gender' in ('male','female','non_binary','other','prefer_not_to_say') then fields->>'gender' else null end,g.gender),
    nationality = coalesce(nullif(trim(fields->>'nationality'),''),g.nationality),
    country_of_residence = coalesce(nullif(trim(fields->>'country_of_residence'),''),g.country_of_residence),
    address_line1 = coalesce(nullif(trim(fields->>'address_line1'),''),g.address_line1),
    address_line2 = coalesce(nullif(trim(fields->>'address_line2'),''),g.address_line2),
    city = coalesce(nullif(trim(fields->>'city'),''),g.city),
    state_region = coalesce(nullif(trim(fields->>'state_region'),''),g.state_region),
    postal_code = coalesce(nullif(trim(fields->>'postal_code'),''),g.postal_code),
    id_type = doc.document_type,
    id_number = coalesce(doc.document_number_masked,g.id_number),
    normalized_id_type = doc.document_type,
    normalized_id_number = case when doc.document_number_masked is not null then lower(regexp_replace(doc.document_number_masked,'\s+','','g')) else g.normalized_id_number end,
    identity_verification_status='verified',
    updated_at=now()
  where g.hotel_id=target_hotel_id and g.id=doc.guest_id
  returning * into after_guest;

  activity_id := private.write_activity_log(
    target_hotel_id,'guest.verified_identity_applied','guest',doc.guest_id,
    'Verified document details applied to Guest 360.',
    jsonb_build_object('full_name',before_guest->>'full_name','identity_verification_status',before_guest->>'identity_verification_status'),
    jsonb_build_object('full_name',after_guest.full_name,'identity_verification_status',after_guest.identity_verification_status),
    jsonb_build_object('guest_document_id',doc.id,'document_type',doc.document_type,'raw_ocr_text_stored',false)
  );

  return jsonb_build_object('ok',true,'activity_id',activity_id,'guest',to_jsonb(after_guest));
end;
$$;
revoke all on function public.apply_guest_document_identity_fields(uuid,uuid) from public, anon;
grant execute on function public.apply_guest_document_identity_fields(uuid,uuid) to authenticated, service_role;

-- Aadhaar may never be manually verified from OCR/visual review alone.
create or replace function public.review_guest_document(target_hotel_id uuid,target_document_id uuid,target_action text,target_rejection_reason text default null)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid := auth.uid(); normalized_action text := lower(trim(coalesce(target_action,'')));
  document_before public.guest_documents%rowtype; document_after public.guest_documents%rowtype;
  normalized_reason text := nullif(trim(target_rejection_reason),''); guest_next_status text; activity_id uuid; apply_result jsonb;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_permission(target_hotel_id,'guests.manage') then raise exception 'Only authorized guest managers can review KYC documents.'; end if;
  if normalized_action not in ('verify','reject','expire','reset_pending') then raise exception 'Unsupported review action.'; end if;
  if normalized_action='reject' and normalized_reason is null then raise exception 'A rejection reason is required.'; end if;

  select * into document_before from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.id=target_document_id and gd.deleted_at is null for update;
  if not found then raise exception 'Guest document was not found.'; end if;
  if document_before.document_type='aadhaar' and normalized_action='verify' then
    raise exception 'Aadhaar cannot be marked verified from OCR or visual review alone. Use UIDAI Secure QR or signed offline XML verification.';
  end if;

  update public.guest_documents gd set
    verification_status=case normalized_action when 'verify' then 'verified' when 'reject' then 'rejected' when 'expire' then 'expired' else 'pending' end,
    verified_by=case when normalized_action='reset_pending' then null else actor_id end,
    verified_at=case when normalized_action='reset_pending' then null else now() end,
    rejection_reason=case when normalized_action='reject' then normalized_reason else null end,
    reviewed_at=now(), review_action=case normalized_action when 'verify' then 'verified' when 'reject' then 'rejected' when 'expire' then 'expired' else 'reset_pending' end,
    updated_at=now()
  where gd.hotel_id=target_hotel_id and gd.id=target_document_id returning * into document_after;

  if normalized_action='verify' then guest_next_status:='verified';
  elsif exists(select 1 from public.guest_documents d where d.hotel_id=target_hotel_id and d.guest_id=document_after.guest_id and d.id<>document_after.id and d.deleted_at is null and d.verification_status='verified') then guest_next_status:='verified';
  elsif normalized_action='reject' then guest_next_status:='rejected';
  elsif normalized_action='reset_pending' then guest_next_status:='pending'; else guest_next_status:='unverified'; end if;

  update public.guests g set identity_verification_status=guest_next_status,updated_at=now()
  where g.hotel_id=target_hotel_id and g.id=document_after.guest_id;

  activity_id := private.write_activity_log(target_hotel_id,'front_office.guest_document_'||normalized_action,'guest_document',document_after.id,
    'Private guest document review state changed.',
    jsonb_build_object('verification_status',document_before.verification_status,'rejection_reason',document_before.rejection_reason),
    jsonb_build_object('verification_status',document_after.verification_status,'rejection_reason',document_after.rejection_reason,'guest_identity_status',guest_next_status),
    jsonb_build_object('guest_id',document_after.guest_id,'review_action',normalized_action));

  if normalized_action='verify' and coalesce(document_after.metadata->'extraction'->>'status','')='extracted' then
    apply_result := public.apply_guest_document_identity_fields(target_hotel_id,document_after.id);
  end if;

  return jsonb_build_object('ok',true,'activity_id',activity_id,'guest_identity_status',guest_next_status,'document',to_jsonb(document_after),'profile_apply',apply_result);
end;
$$;
revoke all on function public.review_guest_document(uuid,uuid,text,text) from public, anon;
grant execute on function public.review_guest_document(uuid,uuid,text,text) to authenticated, service_role;

-- Link official UIDAI Secure QR verification to the exact saved Aadhaar document,
-- mark that document verified, and apply only the operator-confirmed reader fields.
create or replace function public.record_uidai_secure_qr_reader_verification(
  target_hotel_id uuid,target_guest_id uuid,target_guest_session_id uuid,target_guest_document_id uuid,
  confirmed_uidai_reader_verified boolean,reference_last4 text default null,verified_fields jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid := auth.uid(); consent_row public.guest_consents%rowtype; doc public.guest_documents%rowtype;
  result_row public.guest_identity_verifications%rowtype; reference_value text := regexp_replace(coalesce(reference_last4,''),'\D','','g');
  safe_fields jsonb; evidence jsonb; evidence_hash text; apply_result jsonb;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage']::text[]) then raise exception 'Guest identity verification access denied.'; end if;
  if confirmed_uidai_reader_verified is distinct from true then raise exception 'Record this result only after the official UIDAI Secure QR Reader reports the QR as digitally verified.'; end if;
  if target_guest_document_id is null then raise exception 'Link the UIDAI Secure QR verification to the saved Aadhaar document.'; end if;
  if reference_value<>'' and length(reference_value)<>4 then raise exception 'Only the last four reference digits may be recorded.'; end if;
  if jsonb_typeof(coalesce(verified_fields,'{}'::jsonb))<>'object' or pg_column_size(coalesce(verified_fields,'{}'::jsonb))>8192 then raise exception 'Verified fields must be a small JSON object.'; end if;

  select * into doc from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id and gd.guest_id=target_guest_id and gd.deleted_at is null for update;
  if not found then raise exception 'Guest document does not belong to this guest and hotel.'; end if;
  if doc.document_type<>'aadhaar' then raise exception 'UIDAI Secure QR evidence can only be linked to an Aadhaar document.'; end if;
  if target_guest_session_id is not null and not exists(select 1 from public.guest_sessions gs where gs.hotel_id=target_hotel_id and gs.id=target_guest_session_id and gs.guest_id=target_guest_id) then raise exception 'Guest session does not belong to this guest and hotel.'; end if;

  select * into consent_row from public.guest_consents c
  where c.hotel_id=target_hotel_id and c.guest_id=target_guest_id and c.purpose='aadhaar_offline_verification' and c.status='granted' and c.revoked_at is null
  order by c.captured_at desc limit 1;
  if not found then raise exception 'Aadhaar offline verification consent is required.'; end if;

  safe_fields := jsonb_strip_nulls(jsonb_build_object(
    'full_name',nullif(left(trim(verified_fields->>'full_name'),120),''),
    'date_of_birth',nullif(trim(verified_fields->>'date_of_birth'),''),
    'gender',nullif(lower(trim(verified_fields->>'gender')),''),
    'address_line1',nullif(left(trim(verified_fields->>'address_line1'),240),''),
    'city',nullif(left(trim(verified_fields->>'city'),120),''),
    'state_region',nullif(left(trim(verified_fields->>'state_region'),120),''),
    'postal_code',nullif(left(trim(verified_fields->>'postal_code'),24),''),
    'nationality','India','country_of_residence','India',
    'document_number_masked',case when reference_value='' then doc.document_number_masked else 'XXXX XXXX '||reference_value end
  ));
  if safe_fields ? 'gender' and safe_fields->>'gender' not in ('male','female','non_binary','other','prefer_not_to_say') then safe_fields:=safe_fields-'gender'; end if;

  evidence := jsonb_build_object('hotel_id',target_hotel_id,'guest_id',target_guest_id,'guest_document_id',target_guest_document_id,'reference_last4',nullif(reference_value,''),'verified_fields',safe_fields,'reader','UIDAI Secure QR Reader','confirmed_at',date_trunc('second',now()),'actor_user_id',actor_id);
  evidence_hash := encode(extensions.digest(convert_to(evidence::text,'UTF8'),'sha256'),'hex');

  insert into public.guest_identity_verifications(hotel_id,guest_id,guest_session_id,guest_document_id,verification_method,provider,status,reference_id_masked,signature_valid,payload_sha256,verified_fields,source_version,verified_by,metadata)
  values(target_hotel_id,target_guest_id,target_guest_session_id,target_guest_document_id,'aadhaar_secure_qr_uidai_reader','uidai_secure_qr_reader','verified',case when reference_value='' then null else '••••'||reference_value end,true,evidence_hash,safe_fields,'official-reader',actor_id,
    jsonb_build_object('verification_source','operator_recorded_after_official_uidai_reader_verification','raw_qr_payload_stored',false,'aadhaar_number_stored',false,'biometric_data_stored',false,'consent_id',consent_row.id))
  on conflict (hotel_id,guest_id,payload_sha256) do update set verified_at=now(),verified_by=excluded.verified_by,metadata=public.guest_identity_verifications.metadata||excluded.metadata
  returning * into result_row;

  update public.guest_documents gd set verification_status='verified',verified_by=actor_id,verified_at=now(),reviewed_at=now(),review_action='verified',rejection_reason=null,
    document_number_masked=coalesce(safe_fields->>'document_number_masked',gd.document_number_masked),
    metadata=coalesce(gd.metadata,'{}'::jsonb)||jsonb_build_object('uidai_secure_qr_verification_id',result_row.id,'uidai_secure_qr_signature_valid',true),updated_at=now()
  where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id;

  -- Reader-confirmed fields supersede OCR suggestions for profile application.
  update public.guest_documents gd set metadata=coalesce(gd.metadata,'{}'::jsonb)||jsonb_build_object('extraction',coalesce(gd.metadata->'extraction','{}'::jsonb)||jsonb_build_object('status','extracted','extracted_fields',safe_fields,'raw_ocr_text_stored',false,'raw_qr_payload_stored',false))
  where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id;

  apply_result := public.apply_guest_document_identity_fields(target_hotel_id,target_guest_document_id);

  perform private.write_activity_log(target_hotel_id,'guest.aadhaar_secure_qr_verified','guest',target_guest_id,
    'UIDAI Secure QR verification evidence recorded after official reader validation.',null,
    jsonb_build_object('verification_id',result_row.id,'guest_document_id',target_guest_document_id,'reference_id_masked',result_row.reference_id_masked),
    jsonb_build_object('provider','uidai_secure_qr_reader','raw_qr_payload_stored',false));

  return jsonb_build_object('ok',true,'verification_id',result_row.id,'status','verified','method','aadhaar_secure_qr_uidai_reader','profile_apply',apply_result);
end;
$$;
revoke all on function public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb) from public, anon;
grant execute on function public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb) to authenticated, service_role;

-- Offline XML verification also closes the linked document when one is supplied.
create or replace function public.record_verified_aadhaar_offline_result(
  target_hotel_id uuid,target_guest_id uuid,target_guest_session_id uuid,target_guest_document_id uuid,actor_user_id uuid,
  payload_sha256 text,reference_id_masked text,source_version text,verified_fields jsonb,verification_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare caller_role text:=current_setting('request.jwt.claim.role',true); consent_row public.guest_consents%rowtype; result_row public.guest_identity_verifications%rowtype; doc public.guest_documents%rowtype; safe_fields jsonb; apply_result jsonb;
begin
  if caller_role is distinct from 'service_role' then raise exception 'Service-role execution required.'; end if;
  if payload_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'Invalid verification payload digest.'; end if;
  if not exists(select 1 from public.guests g where g.hotel_id=target_hotel_id and g.id=target_guest_id) then raise exception 'Guest not found.'; end if;
  if target_guest_session_id is not null and not exists(select 1 from public.guest_sessions gs where gs.hotel_id=target_hotel_id and gs.id=target_guest_session_id and gs.guest_id=target_guest_id) then raise exception 'Guest session does not belong to this guest and hotel.'; end if;
  if target_guest_document_id is not null then
    select * into doc from public.guest_documents gd where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id and gd.guest_id=target_guest_id and gd.deleted_at is null for update;
    if not found or doc.document_type<>'aadhaar' then raise exception 'Linked Aadhaar document was not found.'; end if;
  end if;
  select * into consent_row from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=target_guest_id and c.purpose='aadhaar_offline_verification' and c.status='granted' and c.revoked_at is null order by c.captured_at desc limit 1;
  if not found then raise exception 'Aadhaar offline verification consent is required.'; end if;

  safe_fields := jsonb_strip_nulls(jsonb_build_object(
    'full_name',nullif(left(trim(verified_fields->>'full_name'),120),''),'date_of_birth',nullif(trim(verified_fields->>'date_of_birth'),''),'gender',nullif(lower(trim(verified_fields->>'gender')),''),
    'address_line1',nullif(left(trim(verified_fields->>'address_line1'),240),''),'city',nullif(left(trim(verified_fields->>'city'),120),''),'state_region',nullif(left(trim(verified_fields->>'state_region'),120),''),'postal_code',nullif(left(trim(verified_fields->>'postal_code'),24),''),
    'nationality','India','country_of_residence','India','document_number_masked',case when reference_id_masked is null then null else left(reference_id_masked,64) end
  ));
  if safe_fields ? 'gender' and safe_fields->>'gender' not in ('male','female','non_binary','other','prefer_not_to_say') then safe_fields:=safe_fields-'gender'; end if;

  insert into public.guest_identity_verifications(hotel_id,guest_id,guest_session_id,guest_document_id,verification_method,provider,status,reference_id_masked,signature_valid,payload_sha256,verified_fields,source_version,verified_by,metadata)
  values(target_hotel_id,target_guest_id,target_guest_session_id,target_guest_document_id,'aadhaar_offline_xml','uidai_offline','verified',nullif(trim(reference_id_masked),''),true,payload_sha256,safe_fields,nullif(trim(source_version),''),actor_user_id,coalesce(verification_metadata,'{}'::jsonb)||jsonb_build_object('consent_id',consent_row.id))
  on conflict (hotel_id,guest_id,payload_sha256) do update set verified_at=now(),verified_by=excluded.verified_by,metadata=public.guest_identity_verifications.metadata||excluded.metadata
  returning * into result_row;

  if target_guest_document_id is not null then
    update public.guest_documents gd set verification_status='verified',verified_by=actor_user_id,verified_at=now(),reviewed_at=now(),review_action='verified',rejection_reason=null,
      metadata=coalesce(gd.metadata,'{}'::jsonb)||jsonb_build_object('offline_xml_verification_id',result_row.id,'extraction',coalesce(gd.metadata->'extraction','{}'::jsonb)||jsonb_build_object('status','extracted','extracted_fields',safe_fields,'raw_ocr_text_stored',false,'raw_qr_payload_stored',false)),updated_at=now()
    where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id;
    apply_result := public.apply_guest_document_identity_fields(target_hotel_id,target_guest_document_id);
  else
    update public.guests g set identity_verification_status='verified',updated_at=now() where g.hotel_id=target_hotel_id and g.id=target_guest_id;
  end if;

  return jsonb_build_object('ok',true,'verification_id',result_row.id,'status',result_row.status,'profile_apply',apply_result);
end;
$$;
revoke all on function public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) to service_role;

commit;
