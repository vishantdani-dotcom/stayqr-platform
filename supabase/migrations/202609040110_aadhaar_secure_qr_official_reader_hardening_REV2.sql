begin;

-- StayQR Aadhaar Secure QR official-reader hardening REV2.
-- UIDAI's current public guidance requires Secure QR reading through official UIDAI clients.
-- This migration therefore hardens StayQR's evidence capture after official-reader verification;
-- it does not parse or claim to validate raw Aadhaar QR payloads in the browser.

create or replace function public.record_uidai_secure_qr_reader_verification(
  target_hotel_id uuid,
  target_guest_id uuid,
  target_guest_session_id uuid,
  target_guest_document_id uuid,
  confirmed_uidai_reader_verified boolean,
  reference_last4 text,
  verified_fields jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  consent_row public.guest_consents%rowtype;
  result_row public.guest_identity_verifications%rowtype;
  doc public.guest_documents%rowtype;
  safe_fields jsonb;
  apply_result jsonb;
  evidence jsonb;
  evidence_hash text;
  reference_value text:=regexp_replace(coalesce(reference_last4,''),'\D','','g');
  reader_name text:=left(trim(coalesce(verified_fields->>'full_name','')),120);
  extracted_fields jsonb;
  extracted_name text;
  extracted_dob text;
  extracted_last4 text;
begin
  if actor_id is null then raise exception 'Authentication required.'; end if;
  if not private.user_has_permission(target_hotel_id,'guests.manage') and not private.user_has_permission(target_hotel_id,'checkin.manage') then
    raise exception 'Guest identity verification access denied.';
  end if;
  if confirmed_uidai_reader_verified is distinct from true then
    raise exception 'Official UIDAI Secure QR Reader verification must be explicitly confirmed.';
  end if;
  if reference_value !~ '^\d{4}$' then
    raise exception 'Aadhaar last four shown by the official UIDAI reader are required.';
  end if;
  if reader_name='' then raise exception 'Name shown by the official UIDAI reader is required.'; end if;
  if verified_fields::text ~ '\m[0-9]{4}[ -]?[0-9]{4}[ -]?[0-9]{4}\M' then
    raise exception 'Full Aadhaar-like numbers are not permitted in verified fields.';
  end if;

  select * into doc from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id and gd.guest_id=target_guest_id and gd.document_type='aadhaar' and gd.deleted_at is null
  for update;
  if not found then raise exception 'Link the UIDAI Secure QR verification to the exact saved Aadhaar document.'; end if;
  if doc.verification_status='verified' and exists(
    select 1 from public.guest_identity_verifications giv
    where giv.hotel_id=target_hotel_id and giv.guest_id=target_guest_id and giv.guest_document_id=target_guest_document_id
      and giv.verification_method='aadhaar_secure_qr_uidai_reader' and giv.status='verified' and giv.signature_valid=true
  ) then
    raise exception 'This Aadhaar document already has verified UIDAI Secure QR evidence.';
  end if;

  if not exists(select 1 from public.guests g where g.hotel_id=target_hotel_id and g.id=target_guest_id) then raise exception 'Guest not found.'; end if;
  if target_guest_session_id is not null and not exists(select 1 from public.guest_sessions gs where gs.hotel_id=target_hotel_id and gs.id=target_guest_session_id and gs.guest_id=target_guest_id) then
    raise exception 'Guest session does not belong to this guest and hotel.';
  end if;

  select * into consent_row from public.guest_consents c
  where c.hotel_id=target_hotel_id and c.guest_id=target_guest_id and c.purpose='aadhaar_offline_verification' and c.status='granted' and c.revoked_at is null
  order by c.captured_at desc limit 1;
  if not found then raise exception 'Aadhaar offline verification consent is required.'; end if;

  extracted_fields:=coalesce(doc.metadata->'extraction'->'extracted_fields','{}'::jsonb);
  extracted_name:=lower(trim(coalesce(extracted_fields->>'full_name',extracted_fields->>'name','')));
  extracted_dob:=trim(coalesce(extracted_fields->>'date_of_birth',extracted_fields->>'dob',''));
  extracted_last4:=right(regexp_replace(coalesce(doc.document_number_masked,extracted_fields->>'document_number_masked',''),'\D','','g'),4);

  if length(extracted_last4)=4 and extracted_last4<>reference_value then
    raise exception 'UIDAI reader last four do not match the saved Aadhaar document metadata.';
  end if;
  if extracted_name<>'' and extracted_name<>lower(reader_name) then
    raise exception 'UIDAI reader name does not match the saved Aadhaar document extraction.';
  end if;
  if extracted_dob<>'' and nullif(trim(verified_fields->>'date_of_birth'),'') is not null and extracted_dob<>trim(verified_fields->>'date_of_birth') then
    raise exception 'UIDAI reader date of birth does not match the saved Aadhaar document extraction.';
  end if;

  safe_fields:=jsonb_strip_nulls(jsonb_build_object(
    'full_name',reader_name,
    'date_of_birth',nullif(trim(verified_fields->>'date_of_birth'),''),
    'gender',nullif(lower(trim(verified_fields->>'gender')),''),
    'address_line1',nullif(left(trim(verified_fields->>'address_line1'),240),''),
    'city',nullif(left(trim(verified_fields->>'city'),120),''),
    'state_region',nullif(left(trim(verified_fields->>'state_region'),120),''),
    'postal_code',nullif(left(trim(verified_fields->>'postal_code'),24),''),
    'nationality','India',
    'country_of_residence','India',
    'document_number_masked','XXXX XXXX '||reference_value
  ));
  if safe_fields ? 'gender' and safe_fields->>'gender' not in ('male','female','non_binary','other','prefer_not_to_say') then safe_fields:=safe_fields-'gender'; end if;

  evidence:=jsonb_build_object(
    'hotel_id',target_hotel_id,
    'guest_id',target_guest_id,
    'guest_document_id',target_guest_document_id,
    'reference_last4',reference_value,
    'verified_fields',safe_fields,
    'verification_source','official_uidai_secure_qr_reader',
    'confirmed_at',date_trunc('second',now()),
    'actor_user_id',actor_id,
    'raw_qr_payload_stored',false,
    'aadhaar_number_stored',false
  );
  evidence_hash:=encode(extensions.digest(convert_to(evidence::text,'UTF8'),'sha256'),'hex');

  insert into public.guest_identity_verifications(
    hotel_id,guest_id,guest_session_id,guest_document_id,verification_method,provider,status,
    reference_id_masked,signature_valid,payload_sha256,verified_fields,source_version,verified_by,metadata
  ) values(
    target_hotel_id,target_guest_id,target_guest_session_id,target_guest_document_id,
    'aadhaar_secure_qr_uidai_reader','uidai_secure_qr_reader','verified','••••'||reference_value,true,evidence_hash,
    safe_fields,'official-reader-v2',actor_id,
    jsonb_build_object(
      'verification_source','operator_recorded_after_official_uidai_reader_verification',
      'official_reader_confirmation_required',true,
      'raw_qr_payload_stored',false,'aadhaar_number_stored',false,'biometric_data_stored',false,
      'consent_id',consent_row.id,'saved_document_cross_check',true
    )
  ) returning * into result_row;

  update public.guest_documents gd set
    verification_status='verified',verified_by=actor_id,verified_at=now(),reviewed_at=now(),review_action='verified',rejection_reason=null,
    document_number_masked='XXXX XXXX '||reference_value,
    metadata=coalesce(gd.metadata,'{}'::jsonb)||jsonb_build_object(
      'uidai_secure_qr_verification_id',result_row.id,
      'uidai_secure_qr_signature_valid',true,
      'uidai_secure_qr_source','official_uidai_reader',
      'uidai_secure_qr_cross_checked',true,
      'extraction',coalesce(gd.metadata->'extraction','{}'::jsonb)||jsonb_build_object(
        'status','extracted','method','official_uidai_reader','extracted_fields',safe_fields,
        'raw_ocr_text_stored',false,'raw_qr_payload_stored',false
      )
    ),updated_at=now()
  where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id;

  apply_result:=public.apply_guest_document_identity_fields(target_hotel_id,target_guest_document_id);

  perform private.write_activity_log(
    target_hotel_id,'guest.aadhaar_secure_qr_verified','guest',target_guest_id,
    'Aadhaar verified after official UIDAI Secure QR Reader confirmation and saved-document cross-check.',null,
    jsonb_build_object('verification_id',result_row.id,'guest_document_id',target_guest_document_id,'reference_id_masked',result_row.reference_id_masked),
    jsonb_build_object('provider','uidai_secure_qr_reader','official_reader_confirmation_required',true,'raw_qr_payload_stored',false)
  );

  return jsonb_build_object('ok',true,'verification_id',result_row.id,'status','verified','method','aadhaar_secure_qr_uidai_reader','profile_apply',apply_result);
end;
$$;

revoke all on function public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb) from public, anon;
grant execute on function public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb) to authenticated, service_role;

commit;
