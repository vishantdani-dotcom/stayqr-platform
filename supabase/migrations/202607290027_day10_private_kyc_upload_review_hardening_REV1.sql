-- StayQR v1.0
-- Day 10 Migration 027 REV1
-- Private KYC upload registration, verification workflow and permission hardening
--
-- This migration:
--   1. Adds request-level idempotency and strict storage-path/file contracts.
--   2. Replaces direct guest_documents writes with authoritative RPCs.
--   3. Aligns private Storage permissions with front-office upload permissions.
--   4. Adds verify/reject/expire/reset review actions with immutable activity evidence.
--   5. Keeps files private; temporary viewing continues through Supabase signed URLs.
--
-- Safe to rerun. No existing document rows were present at the audited baseline.

begin;

-- ---------------------------------------------------------------------------
-- 0. Prerequisite guard
-- ---------------------------------------------------------------------------

do $prerequisites$
begin
  if to_regclass('public.guest_documents') is null then
    raise exception 'Migration 027 requires public.guest_documents from Migration 026.';
  end if;

  if to_regclass('storage.objects') is null then
    raise exception 'Migration 027 requires Supabase Storage.';
  end if;

  if to_regprocedure('private.user_has_permission(uuid,text)') is null
     or to_regprocedure('private.user_has_any_permission(uuid,text[])') is null then
    raise exception 'Migration 027 requires Day 6 authorization helpers.';
  end if;

  if to_regprocedure('private.write_activity_log(uuid,text,text,uuid,text,jsonb,jsonb,jsonb)') is null then
    raise exception 'Migration 027 requires the authoritative activity logger.';
  end if;
end;
$prerequisites$;

-- ---------------------------------------------------------------------------
-- 1. Metadata hardening
-- ---------------------------------------------------------------------------

alter table public.guest_documents
  add column if not exists request_id uuid,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_action text;

update public.guest_documents
set request_id = coalesce(request_id, gen_random_uuid())
where request_id is null;

alter table public.guest_documents
  alter column request_id set not null,
  alter column request_id set default gen_random_uuid();

create unique index if not exists uq_guest_documents_request_id_day10
  on public.guest_documents (hotel_id, request_id);

create index if not exists idx_guest_documents_review_queue_day10
  on public.guest_documents (
    hotel_id,
    verification_status,
    created_at desc
  )
  where deleted_at is null;

create index if not exists idx_guest_documents_guest_active_day10
  on public.guest_documents (hotel_id, guest_id, created_at desc)
  where deleted_at is null;

do $constraints$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guest_documents'::regclass
      and conname = 'guest_documents_bucket_check_day10'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_bucket_check_day10
      check (storage_bucket = 'guest-documents');
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guest_documents'::regclass
      and conname = 'guest_documents_mime_check_day10'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_mime_check_day10
      check (
        mime_type is null
        or mime_type in (
          'image/jpeg',
          'image/png',
          'application/pdf'
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guest_documents'::regclass
      and conname = 'guest_documents_file_size_limit_day10'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_file_size_limit_day10
      check (
        file_size_bytes is null
        or (
          file_size_bytes > 0
          and file_size_bytes <= 15728640
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guest_documents'::regclass
      and conname = 'guest_documents_storage_path_scope_day10'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_storage_path_scope_day10
      check (
        storage_path like
          hotel_id::text || '/' ||
          guest_id::text || '/' ||
          id::text || '/%'
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guest_documents'::regclass
      and conname = 'guest_documents_review_action_check_day10'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_review_action_check_day10
      check (
        review_action is null
        or review_action in (
          'verified',
          'rejected',
          'expired',
          'reset_pending'
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guest_documents'::regclass
      and conname = 'guest_documents_review_state_consistency_day10'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_review_state_consistency_day10
      check (
        (
          verification_status = 'pending'
          and verified_by is null
          and verified_at is null
          and rejection_reason is null
        )
        or (
          verification_status = 'verified'
          and verified_by is not null
          and verified_at is not null
          and rejection_reason is null
        )
        or (
          verification_status = 'rejected'
          and verified_by is not null
          and verified_at is not null
          and length(trim(coalesce(rejection_reason, ''))) > 0
        )
        or (
          verification_status = 'expired'
          and verified_by is not null
          and verified_at is not null
        )
      );
  end if;
end;
$constraints$;

-- ---------------------------------------------------------------------------
-- 2. Authoritative document registration
-- ---------------------------------------------------------------------------

create or replace function public.register_guest_document(
  target_hotel_id uuid,
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
  existing_document public.guest_documents%rowtype;
  inserted_document public.guest_documents%rowtype;
  expected_prefix text;
  activity_id uuid;
begin
  if actor_id is null then
    raise exception 'Authentication is required.';
  end if;

  if not private.user_has_any_permission(
    target_hotel_id,
    array['guests.manage', 'checkin.manage']
  ) then
    raise exception 'You do not have permission to upload guest documents.';
  end if;

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'A JSON object payload is required.';
  end if;

  requested_document_id := coalesce(
    nullif(payload ->> 'document_id', '')::uuid,
    gen_random_uuid()
  );
  requested_request_id := coalesce(
    nullif(payload ->> 'request_id', '')::uuid,
    requested_document_id
  );
  requested_guest_id := nullif(payload ->> 'guest_id', '')::uuid;
  requested_session_id := nullif(payload ->> 'guest_session_id', '')::uuid;
  requested_reservation_id := nullif(payload ->> 'reservation_id', '')::uuid;
  requested_document_type := lower(trim(coalesce(payload ->> 'document_type', '')));
  requested_storage_bucket := coalesce(
    nullif(trim(payload ->> 'storage_bucket'), ''),
    'guest-documents'
  );
  requested_storage_path := trim(coalesce(payload ->> 'storage_path', ''));
  requested_original_name := nullif(trim(payload ->> 'original_file_name'), '');
  requested_mime_type := lower(trim(coalesce(payload ->> 'mime_type', '')));
  requested_size := nullif(payload ->> 'file_size_bytes', '')::bigint;
  requested_masked_number := nullif(trim(payload ->> 'document_number_masked'), '');
  requested_issue_country := nullif(trim(payload ->> 'issue_country'), '');
  requested_issued_on := nullif(payload ->> 'issued_on', '')::date;
  requested_expires_on := nullif(payload ->> 'expires_on', '')::date;
  requested_metadata := coalesce(payload -> 'metadata', '{}'::jsonb);

  if requested_guest_id is null then
    raise exception 'guest_id is required.';
  end if;

  select *
  into existing_document
  from public.guest_documents gd
  where gd.hotel_id = target_hotel_id
    and gd.request_id = requested_request_id
  limit 1;

  if found then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'document', to_jsonb(existing_document)
    );
  end if;

  if requested_document_type not in (
    'aadhaar',
    'passport',
    'driving_licence',
    'voter_id',
    'pan',
    'visa',
    'form_c',
    'other'
  ) then
    raise exception 'Unsupported document type.';
  end if;

  if requested_storage_bucket <> 'guest-documents' then
    raise exception 'Guest documents must use the private guest-documents bucket.';
  end if;

  if requested_mime_type not in (
    'image/jpeg',
    'image/png',
    'application/pdf'
  ) then
    raise exception 'Only JPEG, PNG and PDF files are allowed.';
  end if;

  if requested_size is null
     or requested_size <= 0
     or requested_size > 15728640 then
    raise exception 'The document must be between 1 byte and 15 MB.';
  end if;

  if requested_original_name is null
     or length(requested_original_name) > 255 then
    raise exception 'A valid original file name is required.';
  end if;

  if requested_masked_number is not null
     and length(requested_masked_number) > 64 then
    raise exception 'The masked document number is too long.';
  end if;

  if requested_issued_on is not null
     and requested_expires_on is not null
     and requested_expires_on < requested_issued_on then
    raise exception 'Document expiry cannot be before issue date.';
  end if;

  if not exists (
    select 1
    from public.guests g
    where g.hotel_id = target_hotel_id
      and g.id = requested_guest_id
  ) then
    raise exception 'Guest does not belong to the selected hotel.';
  end if;

  if requested_session_id is not null
     and not exists (
       select 1
       from public.guest_sessions gs
       where gs.hotel_id = target_hotel_id
         and gs.id = requested_session_id
         and gs.guest_id = requested_guest_id
     ) then
    raise exception 'Guest session does not belong to this guest and hotel.';
  end if;

  if requested_reservation_id is not null
     and not exists (
       select 1
       from public.reservation_guests rg
       join public.reservations r
         on r.hotel_id = rg.hotel_id
        and r.id = rg.reservation_id
       where rg.hotel_id = target_hotel_id
         and rg.reservation_id = requested_reservation_id
         and rg.guest_id = requested_guest_id
     ) then
    raise exception 'Reservation does not belong to this guest and hotel.';
  end if;

  expected_prefix :=
    target_hotel_id::text || '/' ||
    requested_guest_id::text || '/' ||
    requested_document_id::text || '/';

  if requested_storage_path not like expected_prefix || '%' then
    raise exception 'Storage path must be scoped to hotel/guest/document.';
  end if;

  if not exists (
    select 1
    from storage.objects object_record
    where object_record.bucket_id = requested_storage_bucket
      and object_record.name = requested_storage_path
  ) then
    raise exception 'Uploaded storage object was not found.';
  end if;

  begin
    insert into public.guest_documents (
      id,
      hotel_id,
      guest_id,
      guest_session_id,
      reservation_id,
      request_id,
      document_type,
      storage_bucket,
      storage_path,
      original_file_name,
      mime_type,
      file_size_bytes,
      document_number_masked,
      issue_country,
      issued_on,
      expires_on,
      verification_status,
      uploaded_by,
      metadata
    )
    values (
      requested_document_id,
      target_hotel_id,
      requested_guest_id,
      requested_session_id,
      requested_reservation_id,
      requested_request_id,
      requested_document_type,
      requested_storage_bucket,
      requested_storage_path,
      requested_original_name,
      requested_mime_type,
      requested_size,
      requested_masked_number,
      requested_issue_country,
      requested_issued_on,
      requested_expires_on,
      'pending',
      actor_id,
      requested_metadata
    )
    returning * into inserted_document;
  exception
    when unique_violation then
      select *
      into existing_document
      from public.guest_documents gd
      where gd.hotel_id = target_hotel_id
        and gd.request_id = requested_request_id
      limit 1;

      if found then
        return jsonb_build_object(
          'ok', true,
          'idempotent', true,
          'document', to_jsonb(existing_document)
        );
      end if;

      raise;
  end;

  update public.guests g
  set
    identity_verification_status = case
      when g.identity_verification_status = 'verified' then 'verified'
      else 'pending'
    end,
    updated_at = now()
  where g.hotel_id = target_hotel_id
    and g.id = requested_guest_id;

  activity_id := private.write_activity_log(
    target_hotel_id,
    'front_office.guest_document_uploaded',
    'guest_document',
    inserted_document.id,
    'Private guest document uploaded and registered for review.',
    null,
    jsonb_build_object(
      'guest_id', inserted_document.guest_id,
      'guest_session_id', inserted_document.guest_session_id,
      'document_type', inserted_document.document_type,
      'verification_status', inserted_document.verification_status
    ),
    jsonb_build_object(
      'request_id', inserted_document.request_id,
      'storage_bucket', inserted_document.storage_bucket,
      'storage_path', inserted_document.storage_path,
      'mime_type', inserted_document.mime_type,
      'file_size_bytes', inserted_document.file_size_bytes
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'activity_id', activity_id,
    'document', to_jsonb(inserted_document)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Authoritative verification/rejection workflow
-- ---------------------------------------------------------------------------

create or replace function public.review_guest_document(
  target_hotel_id uuid,
  target_document_id uuid,
  target_action text,
  target_rejection_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id uuid := auth.uid();
  normalized_action text := lower(trim(coalesce(target_action, '')));
  document_before public.guest_documents%rowtype;
  document_after public.guest_documents%rowtype;
  normalized_reason text := nullif(trim(target_rejection_reason), '');
  guest_next_status text;
  activity_id uuid;
begin
  if actor_id is null then
    raise exception 'Authentication is required.';
  end if;

  if not private.user_has_permission(target_hotel_id, 'guests.manage') then
    raise exception 'Only authorized guest managers can review KYC documents.';
  end if;

  if normalized_action not in (
    'verify',
    'reject',
    'expire',
    'reset_pending'
  ) then
    raise exception 'Unsupported review action.';
  end if;

  if normalized_action = 'reject' and normalized_reason is null then
    raise exception 'A rejection reason is required.';
  end if;

  select *
  into document_before
  from public.guest_documents gd
  where gd.hotel_id = target_hotel_id
    and gd.id = target_document_id
    and gd.deleted_at is null
  for update;

  if not found then
    raise exception 'Guest document was not found.';
  end if;

  update public.guest_documents gd
  set
    verification_status = case normalized_action
      when 'verify' then 'verified'
      when 'reject' then 'rejected'
      when 'expire' then 'expired'
      else 'pending'
    end,
    verified_by = case
      when normalized_action = 'reset_pending' then null
      else actor_id
    end,
    verified_at = case
      when normalized_action = 'reset_pending' then null
      else now()
    end,
    rejection_reason = case
      when normalized_action = 'reject' then normalized_reason
      else null
    end,
    reviewed_at = now(),
    review_action = case normalized_action
      when 'verify' then 'verified'
      when 'reject' then 'rejected'
      when 'expire' then 'expired'
      else 'reset_pending'
    end,
    updated_at = now()
  where gd.hotel_id = target_hotel_id
    and gd.id = target_document_id
  returning * into document_after;

  if normalized_action = 'verify' then
    guest_next_status := 'verified';
  elsif exists (
    select 1
    from public.guest_documents other_document
    where other_document.hotel_id = target_hotel_id
      and other_document.guest_id = document_after.guest_id
      and other_document.id <> document_after.id
      and other_document.deleted_at is null
      and other_document.verification_status = 'verified'
  ) then
    guest_next_status := 'verified';
  elsif normalized_action = 'reject' then
    guest_next_status := 'rejected';
  elsif normalized_action = 'reset_pending' then
    guest_next_status := 'pending';
  else
    guest_next_status := 'unverified';
  end if;

  update public.guests g
  set
    identity_verification_status = guest_next_status,
    updated_at = now()
  where g.hotel_id = target_hotel_id
    and g.id = document_after.guest_id;

  activity_id := private.write_activity_log(
    target_hotel_id,
    'front_office.guest_document_' || normalized_action,
    'guest_document',
    document_after.id,
    'Private guest document review state changed.',
    jsonb_build_object(
      'verification_status', document_before.verification_status,
      'rejection_reason', document_before.rejection_reason
    ),
    jsonb_build_object(
      'verification_status', document_after.verification_status,
      'rejection_reason', document_after.rejection_reason,
      'guest_identity_status', guest_next_status
    ),
    jsonb_build_object(
      'guest_id', document_after.guest_id,
      'review_action', normalized_action
    )
  );

  return jsonb_build_object(
    'ok', true,
    'activity_id', activity_id,
    'guest_identity_status', guest_next_status,
    'document', to_jsonb(document_after)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Grants and RLS: metadata writes only through RPCs
-- ---------------------------------------------------------------------------

revoke all on function public.register_guest_document(uuid, jsonb)
  from public, anon;
revoke all on function public.review_guest_document(uuid, uuid, text, text)
  from public, anon;

grant execute on function public.register_guest_document(uuid, jsonb)
  to authenticated;
grant execute on function public.review_guest_document(uuid, uuid, text, text)
  to authenticated;

revoke insert, update, delete
  on public.guest_documents
  from authenticated;
grant select
  on public.guest_documents
  to authenticated;

comment on function public.register_guest_document(uuid, jsonb) is
  'Day 10 private KYC registration RPC. Validates tenant scope, storage object, MIME, size, path, guest/session linkage and request idempotency.';

comment on function public.review_guest_document(uuid, uuid, text, text) is
  'Day 10 authoritative guest-document verify/reject/expire/reset workflow with guest identity synchronization and immutable activity evidence.';

-- Existing table RLS remains as defense in depth. Direct writes are blocked by
-- table privileges; SECURITY DEFINER RPCs perform the authoritative validation.

-- ---------------------------------------------------------------------------
-- 5. Storage policy alignment
-- ---------------------------------------------------------------------------

-- All object names must begin with the hotel UUID. Registration additionally
-- enforces hotel/guest/document/file path scoping.

drop policy if exists stayqr_guest_documents_select
  on storage.objects;
create policy stayqr_guest_documents_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_any_permission(
    private.storage_object_hotel_id(name),
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

drop policy if exists stayqr_guest_documents_insert
  on storage.objects;
create policy stayqr_guest_documents_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'guest-documents'
  and private.user_has_any_permission(
    private.storage_object_hotel_id(name),
    array['guests.manage', 'checkin.manage']
  )
);

drop policy if exists stayqr_guest_documents_update
  on storage.objects;
create policy stayqr_guest_documents_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
)
with check (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
);

drop policy if exists stayqr_guest_documents_delete
  on storage.objects;
create policy stayqr_guest_documents_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
);

commit;
