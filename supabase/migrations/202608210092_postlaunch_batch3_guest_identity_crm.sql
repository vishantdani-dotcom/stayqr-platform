-- StayQR Post-Launch Batch 3 / Batch C
-- Items 6 + 7: secure guest identity/KYC, Aadhaar offline verification,
-- Guest 360, controlled exports, consent/suppression and WhatsApp evidence.
-- Additive hardening on top of the locked Batch B baseline.

begin;

-- -----------------------------------------------------------------------------
-- 1. Consent / privacy evidence
-- -----------------------------------------------------------------------------
create table if not exists public.guest_consents (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_id uuid not null,
  guest_session_id uuid,
  purpose text not null,
  status text not null default 'granted',
  source text not null default 'staff_recorded',
  captured_by uuid references auth.users(id) on delete set null,
  captured_at timestamptz not null default now(),
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint guest_consents_guest_fk
    foreign key (hotel_id, guest_id) references public.guests(hotel_id, id) on delete cascade,
  constraint guest_consents_session_fk
    foreign key (hotel_id, guest_session_id) references public.guest_sessions(hotel_id, id) on delete restrict,
  constraint guest_consents_purpose_check check (purpose in (
    'kyc_capture',
    'aadhaar_offline_verification',
    'whatsapp_transactional',
    'whatsapp_marketing',
    'data_export'
  )),
  constraint guest_consents_status_check check (status in ('granted', 'revoked')),
  constraint guest_consents_source_check check (source in (
    'staff_recorded', 'guest_written', 'guest_digital', 'imported'
  )),
  constraint guest_consents_state_check check (
    (status = 'granted' and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null)
  ),
  constraint guest_consents_evidence_check check (
    jsonb_typeof(evidence) = 'object' and pg_column_size(evidence) <= 8192
  )
);

create index if not exists idx_guest_consents_guest_purpose
  on public.guest_consents(hotel_id, guest_id, purpose, captured_at desc);

create unique index if not exists uq_guest_consents_active_purpose
  on public.guest_consents(hotel_id, guest_id, purpose)
  where status = 'granted' and revoked_at is null;

-- -----------------------------------------------------------------------------
-- 2. KYC capture metadata / retention
-- -----------------------------------------------------------------------------
alter table public.guest_documents
  add column if not exists document_group_id uuid,
  add column if not exists capture_source text not null default 'upload',
  add column if not exists document_side text not null default 'single',
  add column if not exists quality_status text not null default 'not_assessed',
  add column if not exists quality_score numeric(5,2),
  add column if not exists quality_flags text[] not null default '{}'::text[],
  add column if not exists consent_id uuid,
  add column if not exists retention_until timestamptz,
  add column if not exists retention_basis text,
  add column if not exists legal_hold boolean not null default false;

update public.guest_documents
set document_group_id = coalesce(document_group_id, id)
where document_group_id is null;

alter table public.guest_documents
  alter column document_group_id set default gen_random_uuid(),
  alter column document_group_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'guest_documents_capture_source_batch3_check'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_capture_source_batch3_check
      check (capture_source in ('upload', 'camera', 'scanner_import'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'guest_documents_side_batch3_check'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_side_batch3_check
      check (document_side in ('single', 'front', 'back'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'guest_documents_quality_batch3_check'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_quality_batch3_check
      check (quality_status in ('not_assessed', 'pass', 'review'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'guest_documents_quality_score_batch3_check'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_quality_score_batch3_check
      check (quality_score is null or (quality_score >= 0 and quality_score <= 100));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'guest_documents_retention_batch3_check'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_retention_batch3_check
      check (retention_until is null or retention_until > created_at);
  end if;
end $$;

alter table public.guest_documents
  drop constraint if exists guest_documents_consent_id_batch3_fkey;
alter table public.guest_documents
  add constraint guest_documents_consent_id_batch3_fkey
  foreign key (consent_id) references public.guest_consents(id) on delete set null;

create index if not exists idx_guest_documents_group_batch3
  on public.guest_documents(hotel_id, guest_id, document_group_id, document_side)
  where deleted_at is null;
create index if not exists idx_guest_documents_retention_batch3
  on public.guest_documents(hotel_id, retention_until)
  where deleted_at is null and legal_hold is false and retention_until is not null;

-- -----------------------------------------------------------------------------
-- 3. Immutable document-access evidence
-- -----------------------------------------------------------------------------
create table if not exists public.guest_document_access_audit (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_id uuid not null,
  guest_document_id uuid not null references public.guest_documents(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint guest_document_access_guest_fk
    foreign key (hotel_id, guest_id) references public.guests(hotel_id, id) on delete cascade,
  constraint guest_document_access_action_check check (action in (
    'view', 'download', 'review', 'delete', 'retention_purge'
  )),
  constraint guest_document_access_reason_check check (
    reason is null or char_length(btrim(reason)) between 3 and 500
  ),
  constraint guest_document_access_metadata_check check (
    jsonb_typeof(metadata) = 'object' and pg_column_size(metadata) <= 8192
  )
);
create index if not exists idx_guest_document_access_recent
  on public.guest_document_access_audit(hotel_id, guest_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 4. UIDAI offline-verification evidence (no Aadhaar number, no XML, no share code)
-- -----------------------------------------------------------------------------
create table if not exists public.guest_identity_verifications (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_id uuid not null,
  guest_session_id uuid,
  guest_document_id uuid references public.guest_documents(id) on delete set null,
  verification_method text not null,
  provider text not null default 'uidai_offline',
  status text not null,
  reference_id_masked text,
  signature_valid boolean not null default false,
  payload_sha256 text not null,
  verified_fields jsonb not null default '{}'::jsonb,
  source_version text,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint guest_identity_verifications_guest_fk
    foreign key (hotel_id, guest_id) references public.guests(hotel_id, id) on delete cascade,
  constraint guest_identity_verifications_session_fk
    foreign key (hotel_id, guest_session_id) references public.guest_sessions(hotel_id, id) on delete restrict,
  constraint guest_identity_verifications_method_check
    check (verification_method in ('aadhaar_offline_xml', 'aadhaar_secure_qr_uidai_reader')),
  constraint guest_identity_verifications_status_check
    check (status in ('verified', 'failed', 'manual_review')),
  constraint guest_identity_verifications_hash_check
    check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  constraint guest_identity_verifications_fields_check
    check (jsonb_typeof(verified_fields) = 'object' and pg_column_size(verified_fields) <= 16384),
  constraint guest_identity_verifications_metadata_check
    check (jsonb_typeof(metadata) = 'object' and pg_column_size(metadata) <= 8192),
  constraint guest_identity_verifications_verified_check
    check (status <> 'verified' or signature_valid is true)
);
create unique index if not exists uq_guest_identity_verification_payload
  on public.guest_identity_verifications(hotel_id, guest_id, payload_sha256);
create index if not exists idx_guest_identity_verifications_recent
  on public.guest_identity_verifications(hotel_id, guest_id, verified_at desc);

-- -----------------------------------------------------------------------------
-- 5. Controlled export evidence
-- -----------------------------------------------------------------------------
create table if not exists public.guest_export_audit (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  export_type text not null,
  reason text not null,
  columns text[] not null,
  guest_count integer not null default 0,
  filters jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint guest_export_type_check check (export_type in ('directory', 'kyc_summary')),
  constraint guest_export_reason_check check (char_length(btrim(reason)) between 3 and 500),
  constraint guest_export_count_check check (guest_count between 0 and 2000),
  constraint guest_export_filters_check check (jsonb_typeof(filters) = 'object' and pg_column_size(filters) <= 8192)
);
create index if not exists idx_guest_export_audit_recent
  on public.guest_export_audit(hotel_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 6. Communication consent suppression, campaigns and delivery evidence
-- -----------------------------------------------------------------------------
create table if not exists public.guest_communication_suppressions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_id uuid not null,
  channel text not null,
  reason text not null,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint guest_comm_suppressions_guest_fk
    foreign key (hotel_id, guest_id) references public.guests(hotel_id, id) on delete cascade,
  constraint guest_comm_suppressions_channel_check check (channel in ('whatsapp', 'sms', 'email')),
  constraint guest_comm_suppressions_reason_check check (reason in (
    'guest_opt_out', 'invalid_destination', 'staff_block', 'legal_hold', 'other'
  )),
  constraint guest_comm_suppressions_state_check check (
    (active is true and revoked_at is null) or (active is false and revoked_at is not null)
  ),
  constraint guest_comm_suppressions_metadata_check check (
    jsonb_typeof(metadata) = 'object' and pg_column_size(metadata) <= 8192
  )
);
create unique index if not exists uq_guest_comm_active_suppression
  on public.guest_communication_suppressions(hotel_id, guest_id, channel)
  where active is true;

-- Extend Day 17 WhatsApp templates with provider approval evidence. Hotel users can
-- author/publish content, but only service-role/provider reconciliation may mark a
-- template as approved by Meta.
alter table public.whatsapp_templates
  add column if not exists provider_name text,
  add column if not exists provider_status text not null default 'not_configured',
  add column if not exists provider_template_id text,
  add column if not exists provider_language text,
  add column if not exists provider_status_checked_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='whatsapp_templates_provider_status_batch3_check') then
    alter table public.whatsapp_templates add constraint whatsapp_templates_provider_status_batch3_check
      check (provider_status in ('not_configured','pending','approved','rejected','paused','disabled'));
  end if;
end $$;

create or replace function public.upsert_manual_whatsapp_template(p_hotel_id uuid, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.whatsapp_templates%rowtype;
  v_event_key text; v_locale text; v_template_name text; v_body_template text; v_status text;
begin
  if v_user_id is null or not private.day17_can_manage_hotel(p_hotel_id) then raise exception 'Manual WhatsApp template management denied.'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'WhatsApp template payload must be a JSON object.'; end if;
  v_event_key:=nullif(trim(p_payload->>'event_key'),'');
  v_locale:=coalesce(nullif(trim(p_payload->>'locale'),''),'en');
  v_template_name:=nullif(trim(p_payload->>'template_name'),'');
  v_body_template:=nullif(trim(p_payload->>'body_template'),'');
  v_status:=coalesce(nullif(trim(p_payload->>'status'),''),'draft');
  if not exists(select 1 from public.notification_event_catalog nec where nec.event_key=v_event_key and nec.is_active) then raise exception 'Unsupported notification event key.'; end if;
  if length(v_locale) not between 2 and 20 then raise exception 'locale must contain 2 to 20 characters.'; end if;
  if v_template_name is null then raise exception 'template_name is required.'; end if;
  if v_body_template is null then raise exception 'body_template is required.'; end if;
  if v_status not in ('draft','published','archived') then raise exception 'Unsupported WhatsApp template status.'; end if;
  insert into public.whatsapp_templates(
    hotel_id,event_key,locale,template_name,body_template,status,created_by,updated_by,created_at,updated_at
  ) values (
    p_hotel_id,v_event_key,v_locale,v_template_name,v_body_template,v_status,v_user_id,v_user_id,now(),now()
  ) on conflict(hotel_id,event_key,locale) where hotel_id is not null do update set
    template_name=excluded.template_name, body_template=excluded.body_template, status=excluded.status,
    provider_name=case when whatsapp_templates.template_name is distinct from excluded.template_name or whatsapp_templates.body_template is distinct from excluded.body_template then null else whatsapp_templates.provider_name end,
    provider_status=case when whatsapp_templates.template_name is distinct from excluded.template_name or whatsapp_templates.body_template is distinct from excluded.body_template then 'not_configured' else whatsapp_templates.provider_status end,
    provider_template_id=case when whatsapp_templates.template_name is distinct from excluded.template_name or whatsapp_templates.body_template is distinct from excluded.body_template then null else whatsapp_templates.provider_template_id end,
    provider_language=case when whatsapp_templates.template_name is distinct from excluded.template_name or whatsapp_templates.body_template is distinct from excluded.body_template then null else whatsapp_templates.provider_language end,
    provider_status_checked_at=case when whatsapp_templates.template_name is distinct from excluded.template_name or whatsapp_templates.body_template is distinct from excluded.body_template then null else whatsapp_templates.provider_status_checked_at end,
    updated_by=v_user_id,updated_at=now()
  returning * into v_row;
  return jsonb_build_object('saved',true,'template',to_jsonb(v_row));
end;
$$;
revoke all on function public.upsert_manual_whatsapp_template(uuid,jsonb) from public, anon;
grant execute on function public.upsert_manual_whatsapp_template(uuid,jsonb) to authenticated, service_role;

create table if not exists public.hotel_whatsapp_provider_profiles (
  hotel_id uuid primary key references public.hotels(id) on delete cascade,
  provider text not null default 'meta_cloud',
  business_account_id text,
  phone_number_id text not null,
  sender_display_name text,
  status text not null default 'pending',
  configured_by uuid references auth.users(id) on delete set null,
  configured_at timestamptz not null default now(),
  last_verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint hotel_whatsapp_provider_provider_batch3_check check (provider='meta_cloud'),
  constraint hotel_whatsapp_provider_phone_batch3_check check (char_length(btrim(phone_number_id)) between 5 and 120),
  constraint hotel_whatsapp_provider_status_batch3_check check (status in ('pending','active','disabled','failed')),
  constraint hotel_whatsapp_provider_metadata_batch3_check check (jsonb_typeof(metadata)='object' and pg_column_size(metadata)<=8192)
);

create table if not exists public.guest_communication_campaigns (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  channel text not null default 'whatsapp',
  name text not null,
  purpose text not null,
  provider_mode text not null default 'manual',
  provider_template_name text,
  provider_template_language text not null default 'en',
  template_components jsonb not null default '[]'::jsonb,
  status text not null default 'draft',
  created_by uuid references auth.users(id) on delete set null,
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint guest_comm_campaign_channel_check check (channel = 'whatsapp'),
  constraint guest_comm_campaign_name_check check (char_length(btrim(name)) between 3 and 160),
  constraint guest_comm_campaign_purpose_check check (purpose in ('transactional', 'marketing')),
  constraint guest_comm_campaign_provider_check check (provider_mode in ('manual', 'meta_cloud')),
  constraint guest_comm_campaign_status_check check (status in (
    'draft', 'ready', 'sending', 'completed', 'cancelled', 'failed'
  )),
  constraint guest_comm_campaign_components_check check (jsonb_typeof(template_components) = 'array'),
  constraint guest_comm_campaign_metadata_check check (jsonb_typeof(metadata) = 'object' and pg_column_size(metadata) <= 8192)
);
create index if not exists idx_guest_comm_campaigns_recent
  on public.guest_communication_campaigns(hotel_id, created_at desc);

create table if not exists public.guest_communication_recipients (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  campaign_id uuid not null references public.guest_communication_campaigns(id) on delete cascade,
  guest_id uuid not null,
  phone_e164 text,
  consent_id uuid references public.guest_consents(id) on delete set null,
  status text not null default 'eligible',
  idempotency_key text not null,
  provider_message_id text,
  error_code text,
  error_message text,
  queued_at timestamptz,
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  failed_at timestamptz,
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint guest_comm_recipient_guest_fk
    foreign key (hotel_id, guest_id) references public.guests(hotel_id, id) on delete cascade,
  constraint guest_comm_recipient_status_check check (status in (
    'eligible', 'suppressed', 'opened_manual', 'queued', 'sent', 'delivered', 'read', 'failed', 'skipped'
  )),
  constraint guest_comm_recipient_phone_check check (phone_e164 is null or phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  constraint guest_comm_recipient_key_check check (char_length(idempotency_key) between 8 and 180),
  constraint guest_comm_recipient_attempt_count_check check (attempt_count between 0 and 20),
  constraint guest_comm_recipient_metadata_check check (jsonb_typeof(metadata) = 'object' and pg_column_size(metadata) <= 8192)
);
create unique index if not exists uq_guest_comm_recipient_campaign_guest
  on public.guest_communication_recipients(campaign_id, guest_id);
create unique index if not exists uq_guest_comm_recipient_idempotency
  on public.guest_communication_recipients(hotel_id, idempotency_key);
create index if not exists idx_guest_comm_recipient_provider_message
  on public.guest_communication_recipients(provider_message_id)
  where provider_message_id is not null;

create table if not exists public.guest_communication_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_id uuid not null,
  campaign_id uuid references public.guest_communication_campaigns(id) on delete set null,
  recipient_id uuid references public.guest_communication_recipients(id) on delete set null,
  channel text not null default 'whatsapp',
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  provider_message_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint guest_comm_events_guest_fk
    foreign key (hotel_id, guest_id) references public.guests(hotel_id, id) on delete cascade,
  constraint guest_comm_events_channel_check check (channel = 'whatsapp'),
  constraint guest_comm_events_type_check check (event_type in (
    'manual_opened', 'queued', 'sent', 'delivered', 'read', 'failed', 'suppressed', 'opt_out'
  )),
  constraint guest_comm_events_metadata_check check (jsonb_typeof(metadata) = 'object' and pg_column_size(metadata) <= 8192)
);
create index if not exists idx_guest_comm_events_recent
  on public.guest_communication_events(hotel_id, guest_id, created_at desc);
create unique index if not exists uq_guest_comm_event_recipient_type
  on public.guest_communication_events(recipient_id, event_type);
create unique index if not exists uq_guest_comm_recipient_provider_message
  on public.guest_communication_recipients(provider_message_id)
  where provider_message_id is not null;

-- -----------------------------------------------------------------------------
-- 7. Shared updated-at triggers
-- -----------------------------------------------------------------------------
drop trigger if exists guest_consents_touch_batch3 on public.guest_consents;
create trigger guest_consents_touch_batch3
before update on public.guest_consents
for each row execute function private.set_updated_at();

drop trigger if exists guest_comm_campaigns_touch_batch3 on public.guest_communication_campaigns;
create trigger guest_comm_campaigns_touch_batch3
before update on public.guest_communication_campaigns
for each row execute function private.set_updated_at();

drop trigger if exists guest_comm_recipients_touch_batch3 on public.guest_communication_recipients;
create trigger guest_comm_recipients_touch_batch3
before update on public.guest_communication_recipients
for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- 8. RLS / grants
-- -----------------------------------------------------------------------------
alter table public.guest_consents enable row level security;
alter table public.guest_document_access_audit enable row level security;
alter table public.guest_identity_verifications enable row level security;
alter table public.guest_export_audit enable row level security;
alter table public.guest_communication_suppressions enable row level security;
alter table public.guest_communication_campaigns enable row level security;
alter table public.guest_communication_recipients enable row level security;
alter table public.guest_communication_events enable row level security;
alter table public.hotel_whatsapp_provider_profiles enable row level security;

-- Sensitive KYC rows are no longer exposed to generic guests.view.
drop policy if exists stayqr_day10_guest_documents_select on public.guest_documents;
create policy stayqr_batch3_guest_documents_select
on public.guest_documents for select to authenticated
using (
  private.user_has_any_permission(hotel_id, array[
    'guests.manage', 'checkin.manage', 'checkout.manage'
  ]::text[])
);

-- Write access to document metadata stays RPC-only for authenticated users.
revoke insert, update, delete on public.guest_documents from authenticated;
grant select on public.guest_documents to authenticated;

-- Storage content follows the same sensitive-KYC boundary.
drop policy if exists stayqr_guest_documents_select on storage.objects;
create policy stayqr_batch3_guest_documents_select
on storage.objects for select to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_any_permission(
    private.storage_object_hotel_id(name),
    array['guests.manage', 'checkin.manage', 'checkout.manage']::text[]
  )
);

-- Existing insert/update/delete storage rules remain intact.

drop policy if exists stayqr_batch3_guest_consents_select on public.guest_consents;
create policy stayqr_batch3_guest_consents_select
on public.guest_consents for select to authenticated
using (private.user_has_any_permission(hotel_id, array['guests.manage','checkin.manage','checkout.manage']::text[]));

drop policy if exists stayqr_batch3_guest_suppressions_select on public.guest_communication_suppressions;
create policy stayqr_batch3_guest_suppressions_select
on public.guest_communication_suppressions for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'));

drop policy if exists stayqr_batch3_guest_campaigns_select on public.guest_communication_campaigns;
create policy stayqr_batch3_guest_campaigns_select
on public.guest_communication_campaigns for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'));

drop policy if exists stayqr_batch3_guest_recipients_select on public.guest_communication_recipients;
create policy stayqr_batch3_guest_recipients_select
on public.guest_communication_recipients for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'));

drop policy if exists stayqr_batch3_guest_events_select on public.guest_communication_events;
create policy stayqr_batch3_guest_events_select
on public.guest_communication_events for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'));

drop policy if exists stayqr_batch3_hotel_whatsapp_provider_select on public.hotel_whatsapp_provider_profiles;
create policy stayqr_batch3_hotel_whatsapp_provider_select
on public.hotel_whatsapp_provider_profiles for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage') or private.is_platform_admin());

drop policy if exists stayqr_batch3_guest_document_access_select on public.guest_document_access_audit;
create policy stayqr_batch3_guest_document_access_select
on public.guest_document_access_audit for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'));

drop policy if exists stayqr_batch3_guest_identity_verifications_select on public.guest_identity_verifications;
create policy stayqr_batch3_guest_identity_verifications_select
on public.guest_identity_verifications for select to authenticated
using (private.user_has_any_permission(hotel_id, array['guests.manage','checkin.manage','checkout.manage']::text[]));

drop policy if exists stayqr_batch3_guest_export_audit_select on public.guest_export_audit;
create policy stayqr_batch3_guest_export_audit_select
on public.guest_export_audit for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage') or private.is_platform_admin());

revoke all on table public.guest_consents from public, anon, authenticated;
revoke all on table public.guest_document_access_audit from public, anon, authenticated;
revoke all on table public.guest_identity_verifications from public, anon, authenticated;
revoke all on table public.guest_export_audit from public, anon, authenticated;
revoke all on table public.guest_communication_suppressions from public, anon, authenticated;
revoke all on table public.guest_communication_campaigns from public, anon, authenticated;
revoke all on table public.guest_communication_recipients from public, anon, authenticated;
revoke all on table public.guest_communication_events from public, anon, authenticated;
revoke all on table public.hotel_whatsapp_provider_profiles from public, anon, authenticated;

grant select on table public.guest_consents to authenticated;
grant select on table public.guest_document_access_audit to authenticated;
grant select on table public.guest_identity_verifications to authenticated;
grant select on table public.guest_export_audit to authenticated;
grant select on table public.guest_communication_suppressions to authenticated;
grant select on table public.guest_communication_campaigns to authenticated;
grant select on table public.guest_communication_recipients to authenticated;
grant select on table public.guest_communication_events to authenticated;
grant select on table public.hotel_whatsapp_provider_profiles to authenticated;
grant all on table public.guest_consents to service_role;
grant all on table public.guest_document_access_audit to service_role;
grant all on table public.guest_identity_verifications to service_role;
grant all on table public.guest_export_audit to service_role;
grant all on table public.guest_communication_suppressions to service_role;
grant all on table public.guest_communication_campaigns to service_role;
grant all on table public.guest_communication_recipients to service_role;
grant all on table public.guest_communication_events to service_role;
grant all on table public.hotel_whatsapp_provider_profiles to service_role;

-- -----------------------------------------------------------------------------
-- 9. Consent / suppression RPCs
-- -----------------------------------------------------------------------------
create or replace function public.set_guest_consent(
  target_hotel_id uuid,
  target_guest_id uuid,
  target_purpose text,
  grant_consent boolean,
  target_source text default 'staff_recorded',
  target_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  existing_row public.guest_consents%rowtype;
  consent_row public.guest_consents%rowtype;
  purpose_value text := lower(trim(coalesce(target_purpose, '')));
  source_value text := lower(trim(coalesce(target_source, 'staff_recorded')));
  evidence_value jsonb := coalesce(target_evidence, '{}'::jsonb);
  session_value uuid;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id, array['guests.manage','checkin.manage']::text[]) then
    raise exception 'Guest consent management access denied.';
  end if;
  if purpose_value not in ('kyc_capture','aadhaar_offline_verification','whatsapp_transactional','whatsapp_marketing','data_export') then
    raise exception 'Unsupported consent purpose.';
  end if;
  if source_value not in ('staff_recorded','guest_written','guest_digital','imported') then
    raise exception 'Unsupported consent source.';
  end if;
  if not exists (select 1 from public.guests g where g.hotel_id = target_hotel_id and g.id = target_guest_id) then
    raise exception 'Guest not found in the current hotel.';
  end if;
  if jsonb_typeof(evidence_value) <> 'object' or pg_column_size(evidence_value) > 8192 then
    raise exception 'Consent evidence must be a JSON object no larger than 8 KB.';
  end if;
  begin
    session_value := nullif(evidence_value->>'guest_session_id','')::uuid;
  exception when invalid_text_representation then
    raise exception 'guest_session_id evidence must be a valid UUID.';
  end;
  if session_value is not null and not exists (
    select 1 from public.guest_sessions gs
    where gs.hotel_id=target_hotel_id and gs.id=session_value and gs.guest_id=target_guest_id
  ) then
    raise exception 'Consent guest session does not belong to this guest and hotel.';
  end if;

  select * into existing_row
  from public.guest_consents c
  where c.hotel_id = target_hotel_id and c.guest_id = target_guest_id
    and c.purpose = purpose_value and c.status = 'granted' and c.revoked_at is null
  order by c.captured_at desc limit 1 for update;

  if grant_consent then
    if found then return jsonb_build_object('ok',true,'idempotent',true,'consent',to_jsonb(existing_row)); end if;
    insert into public.guest_consents(
      hotel_id, guest_id, guest_session_id, purpose, status, source, captured_by, evidence
    ) values (
      target_hotel_id, target_guest_id, session_value, purpose_value, 'granted', source_value,
      actor_id, evidence_value
    ) returning * into consent_row;
  else
    if not found then return jsonb_build_object('ok',true,'idempotent',true,'consent',null); end if;
    update public.guest_consents c
    set status='revoked', revoked_by=actor_id, revoked_at=now(), updated_at=now()
    where c.id = existing_row.id
    returning * into consent_row;

    if purpose_value in ('whatsapp_transactional','whatsapp_marketing') then
      insert into public.guest_communication_suppressions(
        hotel_id, guest_id, channel, reason, active, created_by,
        metadata
      ) values (
        target_hotel_id, target_guest_id, 'whatsapp', 'guest_opt_out', true, actor_id,
        jsonb_build_object('source','consent_revocation','purpose',purpose_value)
      ) on conflict (hotel_id, guest_id, channel) where active is true do nothing;
    end if;
  end if;

  perform private.write_activity_log(
    target_hotel_id,
    case when grant_consent then 'guest.consent_granted' else 'guest.consent_revoked' end,
    'guest', target_guest_id,
    'Guest consent state changed.', null,
    jsonb_build_object('purpose',purpose_value,'granted',grant_consent),
    jsonb_build_object('consent_id',consent_row.id,'source',source_value)
  );

  return jsonb_build_object('ok',true,'idempotent',false,'consent',to_jsonb(consent_row));
end;
$$;

revoke all on function public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb) from public, anon;
grant execute on function public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb) to authenticated, service_role;

create or replace function public.set_guest_channel_suppression(
  target_hotel_id uuid,
  target_guest_id uuid,
  target_channel text,
  suppress boolean,
  target_reason text default 'staff_block'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  channel_value text := lower(trim(coalesce(target_channel,'')));
  reason_value text := lower(trim(coalesce(target_reason,'staff_block')));
  row_value public.guest_communication_suppressions%rowtype;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_permission(target_hotel_id,'guests.manage') then raise exception 'Guest communication management access denied.'; end if;
  if channel_value not in ('whatsapp','sms','email') then raise exception 'Unsupported channel.'; end if;
  if reason_value not in ('guest_opt_out','invalid_destination','staff_block','legal_hold','other') then raise exception 'Unsupported suppression reason.'; end if;

  if suppress then
    insert into public.guest_communication_suppressions(
      hotel_id,guest_id,channel,reason,active,created_by
    ) values (target_hotel_id,target_guest_id,channel_value,reason_value,true,actor_id)
    on conflict (hotel_id,guest_id,channel) where active is true
    do update set reason=excluded.reason, created_by=actor_id, created_at=now(), metadata='{}'::jsonb
    returning * into row_value;
  else
    update public.guest_communication_suppressions s
    set active=false, revoked_by=actor_id, revoked_at=now()
    where s.hotel_id=target_hotel_id and s.guest_id=target_guest_id
      and s.channel=channel_value and s.active=true
    returning * into row_value;
  end if;

  perform private.write_activity_log(
    target_hotel_id,
    case when suppress then 'guest.communication_suppressed' else 'guest.communication_unsuppressed' end,
    'guest', target_guest_id,
    'Guest communication suppression changed.', null,
    jsonb_build_object('channel',channel_value,'suppressed',suppress,'reason',reason_value), '{}'
  );
  return jsonb_build_object('ok',true,'suppression',to_jsonb(row_value));
end;
$$;
revoke all on function public.set_guest_channel_suppression(uuid,uuid,text,boolean,text) from public, anon;
grant execute on function public.set_guest_channel_suppression(uuid,uuid,text,boolean,text) to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 9B. Batch 3 KYC registration: consent, scanner metadata and retention
-- -----------------------------------------------------------------------------
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

create or replace function private.audit_guest_document_state_batch3()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if old.verification_status is distinct from new.verification_status then
    insert into public.guest_document_access_audit(hotel_id,guest_id,guest_document_id,actor_user_id,action,reason,metadata)
    values(new.hotel_id,new.guest_id,new.id,auth.uid(),'review',null,jsonb_build_object('from',old.verification_status,'to',new.verification_status));
  end if;
  if old.deleted_at is null and new.deleted_at is not null then
    insert into public.guest_document_access_audit(hotel_id,guest_id,guest_document_id,actor_user_id,action,reason,metadata)
    values(new.hotel_id,new.guest_id,new.id,auth.uid(),'delete',null,jsonb_build_object('soft_deleted_at',new.deleted_at));
  end if;
  return new;
end;
$$;
drop trigger if exists guest_documents_audit_state_batch3 on public.guest_documents;
create trigger guest_documents_audit_state_batch3
after update of verification_status,deleted_at on public.guest_documents
for each row execute function private.audit_guest_document_state_batch3();

-- -----------------------------------------------------------------------------
-- 10. Guest 360 directory summary RPC
-- -----------------------------------------------------------------------------
create or replace function public.get_guest_360_directory(target_hotel_id uuid)
returns table (
  guest_id uuid,
  full_name text,
  phone text,
  email text,
  preferred_language text,
  nationality text,
  country_of_residence text,
  identity_verification_status text,
  created_at timestamptz,
  updated_at timestamptz,
  total_stays bigint,
  completed_stays bigint,
  active_session_id uuid,
  active_room_number text,
  active_checkin timestamptz,
  active_checkout timestamptz,
  last_stay_at timestamptz,
  document_count bigint,
  verified_document boolean,
  whatsapp_transactional_consent boolean,
  whatsapp_marketing_consent boolean,
  kyc_capture_consent boolean,
  aadhaar_offline_consent boolean,
  whatsapp_suppressed boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with sessions as (
    select gs.guest_id,
      count(*)::bigint total_stays,
      count(*) filter (where gs.status <> 'active')::bigint completed_stays,
      max(gs.checkin_time) last_stay_at
    from public.guest_sessions gs
    where gs.hotel_id=target_hotel_id
    group by gs.guest_id
  ), active_stay as (
    select distinct on (gs.guest_id)
      gs.guest_id, gs.id session_id, r.room_number,
      gs.checkin_time, coalesce(gs.extended_until,gs.checkout_time) checkout_time
    from public.guest_sessions gs
    left join public.rooms r on r.id=gs.room_id and r.hotel_id=gs.hotel_id
    where gs.hotel_id=target_hotel_id and gs.status='active'
    order by gs.guest_id, gs.checkin_time desc
  ), docs as (
    select gd.guest_id, count(*)::bigint document_count,
      bool_or(gd.verification_status='verified') verified_document
    from public.guest_documents gd
    where gd.hotel_id=target_hotel_id and gd.deleted_at is null
    group by gd.guest_id
  )
  select g.id, g.full_name, g.phone, g.email, g.preferred_language,
    g.nationality, g.country_of_residence, g.identity_verification_status,
    g.created_at, g.updated_at,
    coalesce(s.total_stays,0), coalesce(s.completed_stays,0),
    a.session_id, a.room_number, a.checkin_time, a.checkout_time, s.last_stay_at,
    coalesce(d.document_count,0), coalesce(d.verified_document,false),
    exists(select 1 from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=g.id and c.purpose='whatsapp_transactional' and c.status='granted' and c.revoked_at is null),
    exists(select 1 from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=g.id and c.purpose='whatsapp_marketing' and c.status='granted' and c.revoked_at is null),
    exists(select 1 from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=g.id and c.purpose='kyc_capture' and c.status='granted' and c.revoked_at is null),
    exists(select 1 from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=g.id and c.purpose='aadhaar_offline_verification' and c.status='granted' and c.revoked_at is null),
    exists(select 1 from public.guest_communication_suppressions x where x.hotel_id=target_hotel_id and x.guest_id=g.id and x.channel='whatsapp' and x.active=true)
  from public.guests g
  left join sessions s on s.guest_id=g.id
  left join active_stay a on a.guest_id=g.id
  left join docs d on d.guest_id=g.id
  where g.hotel_id=target_hotel_id
    and private.user_has_permission(target_hotel_id,'guests.view')
  order by g.updated_at desc;
$$;
revoke all on function public.get_guest_360_directory(uuid) from public, anon;
grant execute on function public.get_guest_360_directory(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 11. Document access audit and retention queue
-- -----------------------------------------------------------------------------
create or replace function public.audit_guest_document_access(
  target_hotel_id uuid,
  target_document_id uuid,
  target_action text,
  target_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  doc public.guest_documents%rowtype;
  audit_id uuid;
  action_value text := lower(trim(coalesce(target_action,'')));
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage','checkout.manage']::text[]) then
    raise exception 'Private KYC access denied.';
  end if;
  if action_value not in ('view','download','review','delete','retention_purge') then raise exception 'Unsupported document access action.'; end if;
  select * into doc from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.id=target_document_id and gd.deleted_at is null;
  if not found then raise exception 'Guest document not found.'; end if;
  insert into public.guest_document_access_audit(
    hotel_id,guest_id,guest_document_id,actor_user_id,action,reason
  ) values (
    target_hotel_id,doc.guest_id,doc.id,actor_id,action_value,nullif(trim(target_reason),'')
  ) returning id into audit_id;
  return jsonb_build_object('ok',true,'audit_id',audit_id,'storage_bucket',doc.storage_bucket,'storage_path',doc.storage_path);
end;
$$;
revoke all on function public.audit_guest_document_access(uuid,uuid,text,text) from public, anon;
grant execute on function public.audit_guest_document_access(uuid,uuid,text,text) to authenticated, service_role;

create or replace function public.get_guest_documents_due_for_retention(target_hotel_id uuid, result_limit integer default 100)
returns table(id uuid, guest_id uuid, storage_bucket text, storage_path text, retention_until timestamptz)
language sql stable security definer set search_path=''
as $$
  select gd.id,gd.guest_id,gd.storage_bucket,gd.storage_path,gd.retention_until
  from public.guest_documents gd
  where gd.hotel_id=target_hotel_id and gd.deleted_at is null and gd.legal_hold=false
    and gd.retention_until is not null and gd.retention_until <= now()
    and private.user_has_permission(target_hotel_id,'guests.manage')
  order by gd.retention_until asc
  limit greatest(1,least(coalesce(result_limit,100),500));
$$;
revoke all on function public.get_guest_documents_due_for_retention(uuid,integer) from public, anon;
grant execute on function public.get_guest_documents_due_for_retention(uuid,integer) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 12. Controlled export RPC
-- -----------------------------------------------------------------------------
create or replace function public.export_guest_directory_360(
  target_hotel_id uuid,
  target_guest_ids uuid[] default null,
  target_columns text[] default array['guest_name','phone','email','nationality','current_status','current_room','total_stays']::text[],
  include_kyc_summary boolean default false,
  export_reason text default null,
  export_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid := auth.uid();
  allowed_columns constant text[] := array[
    'guest_name','phone','email','preferred_language','nationality','country_of_residence',
    'current_status','current_room','check_in','check_out','total_stays','last_stay','created_at',
    'kyc_status','kyc_document_count','whatsapp_transactional_consent','whatsapp_marketing_consent','whatsapp_suppressed'
  ];
  selected_columns text[];
  row_data jsonb;
  filtered_data jsonb;
  rows_json jsonb := '[]'::jsonb;
  row_count integer := 0;
  export_id uuid;
  rec record;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_permission(target_hotel_id,'guests.view') then raise exception 'Guest export access denied.'; end if;
  if include_kyc_summary and not private.user_has_permission(target_hotel_id,'guests.manage') then raise exception 'KYC-summary export requires guests.manage.'; end if;
  if nullif(trim(export_reason),'') is null or char_length(trim(export_reason)) < 3 then raise exception 'An export reason of at least 3 characters is required.'; end if;

  select array_agg(distinct c order by c) into selected_columns
  from unnest(coalesce(target_columns,'{}'::text[])) c
  where c=any(allowed_columns)
    and (include_kyc_summary or c not in ('kyc_status','kyc_document_count'));
  if coalesce(cardinality(selected_columns),0)=0 then raise exception 'Select at least one allowed export column.'; end if;

  for rec in select * from public.get_guest_360_directory(target_hotel_id) d
    where target_guest_ids is null or d.guest_id=any(target_guest_ids)
    limit 2000
  loop
    row_data := jsonb_build_object(
      'guest_name',rec.full_name,
      'phone',rec.phone,
      'email',rec.email,
      'preferred_language',rec.preferred_language,
      'nationality',rec.nationality,
      'country_of_residence',rec.country_of_residence,
      'current_status',case when rec.active_session_id is null then 'Not in-house' else 'In-house' end,
      'current_room',rec.active_room_number,
      'check_in',rec.active_checkin,
      'check_out',rec.active_checkout,
      'total_stays',rec.total_stays,
      'last_stay',rec.last_stay_at,
      'created_at',rec.created_at,
      'kyc_status',rec.identity_verification_status,
      'kyc_document_count',rec.document_count,
      'whatsapp_transactional_consent',rec.whatsapp_transactional_consent,
      'whatsapp_marketing_consent',rec.whatsapp_marketing_consent,
      'whatsapp_suppressed',rec.whatsapp_suppressed
    );
    select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) into filtered_data
    from jsonb_each(row_data) e where e.key=any(selected_columns);
    rows_json := rows_json || jsonb_build_array(filtered_data);
    row_count := row_count + 1;
  end loop;

  insert into public.guest_export_audit(
    hotel_id,actor_user_id,export_type,reason,columns,guest_count,filters
  ) values (
    target_hotel_id,actor_id,case when include_kyc_summary then 'kyc_summary' else 'directory' end,
    trim(export_reason),selected_columns,row_count,coalesce(export_filters,'{}'::jsonb)
  ) returning id into export_id;

  perform private.write_activity_log(target_hotel_id,'guest.directory_exported','guest_export',export_id,
    'Controlled guest directory export generated.',null,
    jsonb_build_object('guest_count',row_count,'include_kyc_summary',include_kyc_summary),
    jsonb_build_object('columns',selected_columns,'reason',trim(export_reason)));

  return jsonb_build_object('ok',true,'export_id',export_id,'columns',selected_columns,'rows',rows_json,'guest_count',row_count);
end;
$$;
revoke all on function public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb) from public, anon;
grant execute on function public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 13. WhatsApp audience / manual action / campaign creation
-- -----------------------------------------------------------------------------
create or replace function public.get_guest_communication_audience(target_hotel_id uuid)
returns table(
  guest_id uuid, full_name text, phone_e164 text,
  transactional_consent boolean, marketing_consent boolean,
  suppressed boolean, suppression_reason text, active_room text
)
language sql stable security definer set search_path=''
as $$
  select g.id,g.full_name,
    case
      when regexp_replace(coalesce(g.phone,''),'\D','','g') ~ '^[0-9]{10}$'
        then '+91'||regexp_replace(g.phone,'\D','','g')
      when regexp_replace(coalesce(g.phone,''),'\D','','g') ~ '^[1-9][0-9]{7,14}$'
        then '+'||regexp_replace(g.phone,'\D','','g')
      else null
    end,
    exists(select 1 from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=g.id and c.purpose='whatsapp_transactional' and c.status='granted' and c.revoked_at is null),
    exists(select 1 from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=g.id and c.purpose='whatsapp_marketing' and c.status='granted' and c.revoked_at is null),
    exists(select 1 from public.guest_communication_suppressions s where s.hotel_id=target_hotel_id and s.guest_id=g.id and s.channel='whatsapp' and s.active=true),
    (select s.reason from public.guest_communication_suppressions s where s.hotel_id=target_hotel_id and s.guest_id=g.id and s.channel='whatsapp' and s.active=true order by s.created_at desc limit 1),
    (select r.room_number from public.guest_sessions gs join public.rooms r on r.id=gs.room_id and r.hotel_id=gs.hotel_id where gs.hotel_id=target_hotel_id and gs.guest_id=g.id and gs.status='active' order by gs.checkin_time desc limit 1)
  from public.guests g
  where g.hotel_id=target_hotel_id and private.user_has_permission(target_hotel_id,'guests.manage')
  order by g.full_name;
$$;
revoke all on function public.get_guest_communication_audience(uuid) from public, anon;
grant execute on function public.get_guest_communication_audience(uuid) to authenticated, service_role;

create or replace function public.prepare_manual_whatsapp_contact(
  target_hotel_id uuid,
  target_guest_id uuid,
  target_purpose text default 'transactional'
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid := auth.uid();
  purpose_value text := lower(trim(coalesce(target_purpose,'transactional')));
  guest_row public.guests%rowtype;
  consent_row public.guest_consents%rowtype;
  digits text;
  e164 text;
  event_id uuid;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_permission(target_hotel_id,'guests.manage') then raise exception 'Guest communication access denied.'; end if;
  if purpose_value not in ('transactional','marketing') then raise exception 'Unsupported WhatsApp purpose.'; end if;
  select * into guest_row from public.guests g where g.hotel_id=target_hotel_id and g.id=target_guest_id;
  if not found then raise exception 'Guest not found.'; end if;
  if exists(select 1 from public.guest_communication_suppressions s where s.hotel_id=target_hotel_id and s.guest_id=target_guest_id and s.channel='whatsapp' and s.active=true) then
    raise exception 'WhatsApp is suppressed for this guest.';
  end if;
  select * into consent_row from public.guest_consents c
  where c.hotel_id=target_hotel_id and c.guest_id=target_guest_id
    and c.purpose=case when purpose_value='marketing' then 'whatsapp_marketing' else 'whatsapp_transactional' end
    and c.status='granted' and c.revoked_at is null order by c.captured_at desc limit 1;
  if not found then raise exception 'Stored WhatsApp consent is required before contacting this guest.'; end if;
  digits := regexp_replace(coalesce(guest_row.phone,''),'\D','','g');
  if length(digits)=10 then digits:='91'||digits; end if;
  if digits !~ '^[1-9][0-9]{7,14}$' then raise exception 'Guest phone number is not valid for WhatsApp.'; end if;
  e164 := '+'||digits;
  insert into public.guest_communication_events(hotel_id,guest_id,channel,event_type,actor_user_id,metadata)
  values(target_hotel_id,target_guest_id,'whatsapp','manual_opened',actor_id,jsonb_build_object('purpose',purpose_value,'consent_id',consent_row.id))
  returning id into event_id;
  return jsonb_build_object('ok',true,'event_id',event_id,'phone_e164',e164,'consent_id',consent_row.id,'guest_name',guest_row.full_name);
end;
$$;
revoke all on function public.prepare_manual_whatsapp_contact(uuid,uuid,text) from public, anon;
grant execute on function public.prepare_manual_whatsapp_contact(uuid,uuid,text) to authenticated, service_role;

create or replace function public.create_guest_whatsapp_campaign(
  target_hotel_id uuid,
  target_name text,
  target_purpose text,
  target_provider_mode text,
  target_template_name text,
  target_template_language text,
  target_guest_ids uuid[]
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid := auth.uid();
  purpose_value text := lower(trim(coalesce(target_purpose,'transactional')));
  provider_value text := lower(trim(coalesce(target_provider_mode,'manual')));
  campaign public.guest_communication_campaigns%rowtype;
  template_row public.whatsapp_templates%rowtype;
  guest_rec record;
  consent_id_value uuid;
  eligible_count integer := 0;
  suppressed_count integer := 0;
  digits text;
  e164 text;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_permission(target_hotel_id,'guests.manage') then raise exception 'Campaign management access denied.'; end if;
  if purpose_value not in ('transactional','marketing') then raise exception 'Unsupported campaign purpose.'; end if;
  if provider_value not in ('manual','meta_cloud') then raise exception 'Unsupported provider mode.'; end if;
  if provider_value='meta_cloud' and nullif(trim(target_template_name),'') is null then raise exception 'Meta Cloud campaigns require an approved template name.'; end if;
  if provider_value='meta_cloud' then
    if not exists(
      select 1 from public.hotel_whatsapp_provider_profiles p
      where p.hotel_id=target_hotel_id and p.provider='meta_cloud' and p.status='active'
    ) then raise exception 'This hotel does not have an active Meta Cloud WhatsApp sender configured.'; end if;
    select * into template_row
    from public.whatsapp_templates wt
    where wt.hotel_id=target_hotel_id
      and wt.template_name=trim(target_template_name)
      and coalesce(wt.provider_language,wt.locale)=coalesce(nullif(trim(target_template_language),''),'en')
      and wt.status='published'
      and wt.provider_name='meta_cloud'
      and wt.provider_status='approved'
    order by wt.updated_at desc limit 1;
    if not found then raise exception 'Select a published WhatsApp template with confirmed Meta approval.'; end if;
  end if;
  if coalesce(cardinality(target_guest_ids),0)=0 then raise exception 'Select at least one guest.'; end if;
  if cardinality(target_guest_ids)>500 then raise exception 'A campaign can contain at most 500 guests.'; end if;

  insert into public.guest_communication_campaigns(
    hotel_id,channel,name,purpose,provider_mode,provider_template_name,
    provider_template_language,status,created_by
  ) values (
    target_hotel_id,'whatsapp',trim(target_name),purpose_value,provider_value,
    nullif(trim(target_template_name),''),coalesce(nullif(trim(target_template_language),''),'en'),
    'ready',actor_id
  ) returning * into campaign;

  for guest_rec in
    select g.id,g.phone from public.guests g where g.hotel_id=target_hotel_id and g.id=any(target_guest_ids)
  loop
    select c.id into consent_id_value from public.guest_consents c
    where c.hotel_id=target_hotel_id and c.guest_id=guest_rec.id
      and c.purpose=case when purpose_value='marketing' then 'whatsapp_marketing' else 'whatsapp_transactional' end
      and c.status='granted' and c.revoked_at is null order by c.captured_at desc limit 1;
    digits := regexp_replace(coalesce(guest_rec.phone,''),'\D','','g');
    if length(digits)=10 then digits:='91'||digits; end if;
    e164 := case when digits ~ '^[1-9][0-9]{7,14}$' then '+'||digits else null end;

    if consent_id_value is null or e164 is null or exists(
      select 1 from public.guest_communication_suppressions s
      where s.hotel_id=target_hotel_id and s.guest_id=guest_rec.id and s.channel='whatsapp' and s.active=true
    ) then
      insert into public.guest_communication_recipients(
        hotel_id,campaign_id,guest_id,phone_e164,consent_id,status,idempotency_key,metadata
      ) values (
        target_hotel_id,campaign.id,guest_rec.id,e164,consent_id_value,'suppressed',
        'campaign:'||campaign.id::text||':guest:'||guest_rec.id::text,
        jsonb_build_object('reason',case when consent_id_value is null then 'missing_consent' when e164 is null then 'invalid_phone' else 'suppressed' end)
      );
      suppressed_count := suppressed_count+1;
    else
      insert into public.guest_communication_recipients(
        hotel_id,campaign_id,guest_id,phone_e164,consent_id,status,idempotency_key
      ) values (
        target_hotel_id,campaign.id,guest_rec.id,e164,consent_id_value,'eligible',
        'campaign:'||campaign.id::text||':guest:'||guest_rec.id::text
      );
      eligible_count := eligible_count+1;
    end if;
  end loop;

  return jsonb_build_object('ok',true,'campaign_id',campaign.id,'eligible_count',eligible_count,'suppressed_count',suppressed_count);
end;
$$;
revoke all on function public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[]) from public, anon;
grant execute on function public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[]) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 14. Service-role helper used only by the verified UIDAI Edge Function
-- -----------------------------------------------------------------------------
create or replace function public.record_verified_aadhaar_offline_result(
  target_hotel_id uuid,
  target_guest_id uuid,
  target_guest_session_id uuid,
  target_guest_document_id uuid,
  actor_user_id uuid,
  payload_sha256 text,
  reference_id_masked text,
  source_version text,
  verified_fields jsonb,
  verification_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  caller_role text := current_setting('request.jwt.claim.role', true);
  consent_row public.guest_consents%rowtype;
  result_row public.guest_identity_verifications%rowtype;
begin
  if caller_role is distinct from 'service_role' then raise exception 'Service-role execution required.'; end if;
  if payload_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'Invalid verification payload digest.'; end if;
  if not exists(select 1 from public.guests g where g.hotel_id=target_hotel_id and g.id=target_guest_id) then raise exception 'Guest not found.'; end if;
  if target_guest_session_id is not null and not exists(
    select 1 from public.guest_sessions gs
    where gs.hotel_id=target_hotel_id and gs.id=target_guest_session_id and gs.guest_id=target_guest_id
  ) then raise exception 'Guest session does not belong to this guest and hotel.'; end if;
  if target_guest_document_id is not null and not exists(
    select 1 from public.guest_documents gd
    where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id and gd.guest_id=target_guest_id and gd.deleted_at is null
  ) then raise exception 'Guest document does not belong to this guest and hotel.'; end if;
  select * into consent_row from public.guest_consents c
  where c.hotel_id=target_hotel_id and c.guest_id=target_guest_id
    and c.purpose='aadhaar_offline_verification' and c.status='granted' and c.revoked_at is null
  order by c.captured_at desc limit 1;
  if not found then raise exception 'Aadhaar offline verification consent is required.'; end if;

  insert into public.guest_identity_verifications(
    hotel_id,guest_id,guest_session_id,guest_document_id,verification_method,provider,status,
    reference_id_masked,signature_valid,payload_sha256,verified_fields,source_version,verified_by,metadata
  ) values (
    target_hotel_id,target_guest_id,target_guest_session_id,target_guest_document_id,
    'aadhaar_offline_xml','uidai_offline','verified',nullif(trim(reference_id_masked),''),true,
    payload_sha256,coalesce(verified_fields,'{}'::jsonb),nullif(trim(source_version),''),actor_user_id,
    coalesce(verification_metadata,'{}'::jsonb)||jsonb_build_object('consent_id',consent_row.id)
  ) on conflict (hotel_id,guest_id,payload_sha256)
  do update set verified_at=now(), verified_by=excluded.verified_by, metadata=guest_identity_verifications.metadata||excluded.metadata
  returning * into result_row;

  update public.guests g
  set identity_verification_status='verified', updated_at=now()
  where g.hotel_id=target_hotel_id and g.id=target_guest_id;

  return jsonb_build_object('ok',true,'verification_id',result_row.id,'status',result_row.status);
end;
$$;
revoke all on function public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) to service_role;

-- -----------------------------------------------------------------------------
-- 15. UIDAI Secure QR evidence recorded only after the official UIDAI reader
-- reports a digitally verified QR. StayQR does not parse or store the QR payload.
-- -----------------------------------------------------------------------------
create or replace function public.record_uidai_secure_qr_reader_verification(
  target_hotel_id uuid,
  target_guest_id uuid,
  target_guest_session_id uuid,
  target_guest_document_id uuid,
  confirmed_uidai_reader_verified boolean,
  reference_last4 text default null,
  verified_fields jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid := auth.uid();
  consent_row public.guest_consents%rowtype;
  result_row public.guest_identity_verifications%rowtype;
  reference_value text := regexp_replace(coalesce(reference_last4,''),'\D','','g');
  evidence jsonb;
  evidence_hash text;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage']::text[]) then
    raise exception 'Guest identity verification access denied.';
  end if;
  if confirmed_uidai_reader_verified is distinct from true then
    raise exception 'Record this result only after the official UIDAI Secure QR Reader reports the QR as digitally verified.';
  end if;
  if jsonb_typeof(coalesce(verified_fields,'{}'::jsonb)) <> 'object' or pg_column_size(coalesce(verified_fields,'{}'::jsonb))>8192 then
    raise exception 'Verified fields must be a small JSON object.';
  end if;
  if reference_value<>'' and length(reference_value)<>4 then raise exception 'Only the last four reference digits may be recorded.'; end if;
  if not exists(select 1 from public.guests g where g.hotel_id=target_hotel_id and g.id=target_guest_id) then raise exception 'Guest not found.'; end if;
  if target_guest_session_id is not null and not exists(
    select 1 from public.guest_sessions gs where gs.hotel_id=target_hotel_id and gs.id=target_guest_session_id and gs.guest_id=target_guest_id
  ) then raise exception 'Guest session does not belong to this guest and hotel.'; end if;
  if target_guest_document_id is not null and not exists(
    select 1 from public.guest_documents gd where gd.hotel_id=target_hotel_id and gd.id=target_guest_document_id and gd.guest_id=target_guest_id and gd.deleted_at is null
  ) then raise exception 'Guest document does not belong to this guest and hotel.'; end if;
  select * into consent_row from public.guest_consents c
  where c.hotel_id=target_hotel_id and c.guest_id=target_guest_id
    and c.purpose='aadhaar_offline_verification' and c.status='granted' and c.revoked_at is null
  order by c.captured_at desc limit 1;
  if not found then raise exception 'Aadhaar offline verification consent is required.'; end if;

  evidence := jsonb_build_object(
    'hotel_id',target_hotel_id,'guest_id',target_guest_id,'guest_session_id',target_guest_session_id,
    'reference_last4',nullif(reference_value,''),'verified_fields',coalesce(verified_fields,'{}'::jsonb),
    'reader','UIDAI Secure QR Reader','confirmed_at',date_trunc('second',now()),'actor_user_id',actor_id
  );
  evidence_hash := encode(extensions.digest(convert_to(evidence::text,'UTF8'),'sha256'),'hex');

  insert into public.guest_identity_verifications(
    hotel_id,guest_id,guest_session_id,guest_document_id,verification_method,provider,status,
    reference_id_masked,signature_valid,payload_sha256,verified_fields,source_version,verified_by,metadata
  ) values (
    target_hotel_id,target_guest_id,target_guest_session_id,target_guest_document_id,
    'aadhaar_secure_qr_uidai_reader','uidai_secure_qr_reader','verified',
    case when reference_value='' then null else '••••'||reference_value end,true,evidence_hash,
    coalesce(verified_fields,'{}'::jsonb),'official-reader',actor_id,
    jsonb_build_object(
      'verification_source','operator_recorded_after_official_uidai_reader_verification',
      'raw_qr_payload_stored',false,'aadhaar_number_stored',false,'biometric_data_stored',false,
      'consent_id',consent_row.id
    )
  ) returning * into result_row;

  update public.guests g set identity_verification_status='verified', updated_at=now()
  where g.hotel_id=target_hotel_id and g.id=target_guest_id;

  perform private.write_activity_log(
    target_hotel_id,'guest.aadhaar_secure_qr_verified','guest',target_guest_id,
    'UIDAI Secure QR verification evidence recorded after official reader validation.',null,
    jsonb_build_object('verification_id',result_row.id,'reference_id_masked',result_row.reference_id_masked),
    jsonb_build_object('provider','uidai_secure_qr_reader','raw_qr_payload_stored',false)
  );
  return jsonb_build_object('ok',true,'verification_id',result_row.id,'status','verified','method','aadhaar_secure_qr_uidai_reader');
end;
$$;
revoke all on function public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb) from public, anon;
grant execute on function public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 16. Provider reconciliation is service-role only. Secrets remain Edge Function
-- environment variables; the database stores only non-secret sender/template IDs.
-- -----------------------------------------------------------------------------
create or replace function public.record_hotel_whatsapp_provider_profile(
  target_hotel_id uuid, target_business_account_id text, target_phone_number_id text,
  target_sender_display_name text, target_status text, target_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare caller_role text := current_setting('request.jwt.claim.role',true); row_value public.hotel_whatsapp_provider_profiles%rowtype;
begin
  if caller_role is distinct from 'service_role' then raise exception 'Service-role execution required.'; end if;
  if lower(trim(coalesce(target_status,''))) not in ('pending','active','disabled','failed') then raise exception 'Unsupported provider status.'; end if;
  if char_length(trim(coalesce(target_phone_number_id,'')))<5 then raise exception 'phone_number_id is required.'; end if;
  insert into public.hotel_whatsapp_provider_profiles(
    hotel_id,provider,business_account_id,phone_number_id,sender_display_name,status,configured_at,last_verified_at,metadata
  ) values (
    target_hotel_id,'meta_cloud',nullif(trim(target_business_account_id),''),trim(target_phone_number_id),
    nullif(trim(target_sender_display_name),''),lower(trim(target_status)),now(),
    case when lower(trim(target_status))='active' then now() else null end,coalesce(target_metadata,'{}'::jsonb)
  ) on conflict(hotel_id) do update set
    business_account_id=excluded.business_account_id,phone_number_id=excluded.phone_number_id,
    sender_display_name=excluded.sender_display_name,status=excluded.status,configured_at=now(),
    last_verified_at=case when excluded.status='active' then now() else hotel_whatsapp_provider_profiles.last_verified_at end,
    metadata=excluded.metadata
  returning * into row_value;
  return jsonb_build_object('ok',true,'profile',to_jsonb(row_value));
end;
$$;
revoke all on function public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb) to service_role;

create or replace function public.record_whatsapp_provider_template_status(
  target_template_id uuid, target_provider_status text, target_provider_template_id text default null,
  target_provider_language text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare caller_role text := current_setting('request.jwt.claim.role',true); row_value public.whatsapp_templates%rowtype; status_value text:=lower(trim(coalesce(target_provider_status,'')));
begin
  if caller_role is distinct from 'service_role' then raise exception 'Service-role execution required.'; end if;
  if status_value not in ('not_configured','pending','approved','rejected','paused','disabled') then raise exception 'Unsupported provider template status.'; end if;
  update public.whatsapp_templates wt set
    provider_name='meta_cloud',provider_status=status_value,
    provider_template_id=nullif(trim(target_provider_template_id),''),
    provider_language=coalesce(nullif(trim(target_provider_language),''),wt.locale),
    provider_status_checked_at=now(),updated_at=now()
  where wt.id=target_template_id
  returning * into row_value;
  if not found then raise exception 'WhatsApp template not found.'; end if;
  return jsonb_build_object('ok',true,'template',to_jsonb(row_value));
end;
$$;
revoke all on function public.record_whatsapp_provider_template_status(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.record_whatsapp_provider_template_status(uuid,text,text,text) to service_role;

commit;
