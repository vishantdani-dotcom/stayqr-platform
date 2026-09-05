-- StayQR Simple Front Desk ID Capture REV1
-- Simplifies normal hotel check-in: staff can scan/upload an ID supplied by the guest
-- without the old KYC-consent ceremony. This does NOT claim UIDAI/government verification.
-- Existing tenant isolation, private storage, retention and audit protections remain.

begin;

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
  if requested_document_type='aadhaar' and requested_masked_number is not null and length(regexp_replace(requested_masked_number,'\D','','g')) >= 12 then raise exception 'Store only a masked Aadhaar reference, never the full Aadhaar number.'; end if;
  if requested_issued_on is not null and requested_expires_on is not null and requested_expires_on<requested_issued_on then raise exception 'Document expiry cannot be before issue date.'; end if;
  if requested_capture_source not in ('upload','camera','scanner_import') then raise exception 'Unsupported capture source.'; end if;
  if requested_document_side not in ('single','front','back') then raise exception 'Unsupported document side.'; end if;
  if requested_quality_status not in ('not_assessed','pass','review') then raise exception 'Unsupported quality status.'; end if;
  if requested_quality_score is not null and (requested_quality_score<0 or requested_quality_score>100) then raise exception 'Quality score must be between 0 and 100.'; end if;
  if requested_retention_until is not null and requested_retention_until<=now() then raise exception 'Retention date must be in the future.'; end if;
  if requested_retention_until is not null and requested_retention_basis is null then raise exception 'Retention basis is required when a retention date is set.'; end if;

  if not exists(select 1 from public.guests g where g.hotel_id=target_hotel_id and g.id=requested_guest_id) then raise exception 'Guest does not belong to the selected hotel.'; end if;
  if requested_session_id is not null and not exists(select 1 from public.guest_sessions gs where gs.hotel_id=target_hotel_id and gs.id=requested_session_id and gs.guest_id=requested_guest_id) then raise exception 'Guest session does not belong to this guest and hotel.'; end if;
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
    requested_quality_status,requested_quality_score,requested_quality_flags,null,requested_retention_until,requested_retention_basis
  ) returning * into inserted_document;


  activity_id := private.write_activity_log(target_hotel_id,'front_office.guest_document_uploaded','guest_document',inserted_document.id,
    'Guest identity document captured during front-desk registration.',null,
    jsonb_build_object('guest_id',inserted_document.guest_id,'document_type',inserted_document.document_type,'capture_source',inserted_document.capture_source,'document_side',inserted_document.document_side,'quality_status',inserted_document.quality_status),
    jsonb_build_object('request_id',inserted_document.request_id,'retention_until',inserted_document.retention_until,'workflow','simple_front_desk_id_capture_rev1'));
  return jsonb_build_object('ok',true,'idempotent',false,'activity_id',activity_id,'document',to_jsonb(inserted_document));
exception when unique_violation then
  select * into existing_document from public.guest_documents gd where gd.hotel_id=target_hotel_id and gd.request_id=requested_request_id limit 1;
  if found then return jsonb_build_object('ok',true,'idempotent',true,'document',to_jsonb(existing_document)); end if;
  raise;
end;
$$;
revoke all on function public.register_guest_document(uuid,jsonb) from public, anon;
grant execute on function public.register_guest_document(uuid,jsonb) to authenticated, service_role;


-- Apply safe OCR/scanned fields to the guest profile without claiming verification.
create or replace function public.apply_scanned_guest_identity_fields(
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
  after_guest public.guests%rowtype;
  activity_id uuid;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage']::text[]) then
    raise exception 'Guest identity update access denied.';
  end if;

  select * into doc
  from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.id=target_document_id and gd.deleted_at is null
  for update;
  if not found then raise exception 'Guest document not found.'; end if;

  fields := coalesce(doc.metadata->'extraction'->'extracted_fields','{}'::jsonb);
  if jsonb_typeof(fields) <> 'object' or coalesce(doc.metadata->'extraction'->>'status','') <> 'extracted' then
    raise exception 'No safe extracted fields are available for this document.';
  end if;

  if doc.document_type='aadhaar' and doc.document_number_masked is not null
     and length(regexp_replace(doc.document_number_masked,'\D','','g')) >= 12 then
    raise exception 'Full Aadhaar numbers cannot be applied to a guest profile.';
  end if;

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
    id_type = case when doc.document_type in ('aadhaar','passport','driving_licence','voter_id','pan','other') then doc.document_type else g.id_type end,
    id_number = coalesce(doc.document_number_masked,g.id_number),
    normalized_id_type = case when doc.document_type in ('aadhaar','passport','driving_licence','voter_id','pan','other') then doc.document_type else g.normalized_id_type end,
    normalized_id_number = case when doc.document_number_masked is not null then lower(regexp_replace(doc.document_number_masked,'\s+','','g')) else g.normalized_id_number end,
    updated_at=now()
  where g.hotel_id=target_hotel_id and g.id=doc.guest_id
  returning * into after_guest;

  if not found then raise exception 'Guest does not belong to the selected hotel.'; end if;

  activity_id := private.write_activity_log(
    target_hotel_id,'guest.scanned_identity_applied','guest',doc.guest_id,
    'Scanned ID details applied to the guest profile without a government-verification claim.',null,
    jsonb_build_object('document_id',doc.id,'document_type',doc.document_type,'full_name',after_guest.full_name),
    jsonb_build_object('workflow','simple_front_desk_id_capture_rev1','government_verification_claimed',false,'raw_ocr_text_stored',false,'raw_qr_payload_stored',false)
  );

  return jsonb_build_object(
    'ok',true,
    'activity_id',activity_id,
    'guest_id',doc.guest_id,
    'document_id',doc.id,
    'government_verification_claimed',false
  );
end;
$$;
revoke all on function public.apply_scanned_guest_identity_fields(uuid,uuid) from public, anon;
grant execute on function public.apply_scanned_guest_identity_fields(uuid,uuid) to authenticated, service_role;

commit;
