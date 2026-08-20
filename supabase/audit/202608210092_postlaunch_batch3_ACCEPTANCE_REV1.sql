-- StayQR v1.1 Post-Launch Batch 3 / Batch C
-- Audit 092 REV1 — Guest identity, Guest 360, controlled export and communications
-- Read-only / SQL Editor safe. Run after Migration 092.
-- Expected: POSTLAUNCH_BATCH3_DATABASE_ACCEPTANCE: PASS (36/36)

with gates(gate_no, gate_name, passed, evidence) as (
  values
    (1, 'guest_consents exists', to_regclass('public.guest_consents') is not null, 'consent ledger'),
    (2, 'guest_document_access_audit exists', to_regclass('public.guest_document_access_audit') is not null, 'immutable KYC access evidence'),
    (3, 'guest_identity_verifications exists', to_regclass('public.guest_identity_verifications') is not null, 'UIDAI verification evidence'),
    (4, 'guest_export_audit exists', to_regclass('public.guest_export_audit') is not null, 'controlled export evidence'),
    (5, 'guest communication tables exist',
      to_regclass('public.guest_communication_suppressions') is not null
      and to_regclass('public.guest_communication_campaigns') is not null
      and to_regclass('public.guest_communication_recipients') is not null
      and to_regclass('public.guest_communication_events') is not null,
      'suppression/campaign/recipient/event ledgers'),
    (6, 'hotel WhatsApp provider profile exists', to_regclass('public.hotel_whatsapp_provider_profiles') is not null, 'hotel-owned sender metadata'),
    (7, 'guest_documents scanner metadata exists',
      (select count(*)=10 from information_schema.columns where table_schema='public' and table_name='guest_documents'
        and column_name in ('document_group_id','capture_source','document_side','quality_status','quality_score','quality_flags','consent_id','retention_until','retention_basis','legal_hold')),
      'front/back, quality, consent and retention metadata'),
    (8, 'WhatsApp provider template metadata exists',
      (select count(*)=5 from information_schema.columns where table_schema='public' and table_name='whatsapp_templates'
        and column_name in ('provider_name','provider_status','provider_template_id','provider_language','provider_status_checked_at')),
      'provider approval reconciliation fields'),
    (9, 'recipient retry evidence exists',
      (select count(*)=2 from information_schema.columns where table_schema='public' and table_name='guest_communication_recipients'
        and column_name in ('attempt_count','last_attempt_at')),
      'attempt count + last attempt'),
    (10, 'guest_consents RLS enabled', coalesce((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='guest_consents'),false), 'RLS'),
    (11, 'identity verification RLS enabled', coalesce((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='guest_identity_verifications'),false), 'RLS'),
    (12, 'export audit RLS enabled', coalesce((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='guest_export_audit'),false), 'RLS'),
    (13, 'communication tables RLS enabled',
      (select count(*)=5 from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relname in ('guest_communication_suppressions','guest_communication_campaigns','guest_communication_recipients','guest_communication_events','hotel_whatsapp_provider_profiles') and c.relrowsecurity),
      'all communication data planes use RLS'),
    (14, 'generic guest viewer removed from KYC select policy',
      exists(select 1 from pg_policies where schemaname='public' and tablename='guest_documents' and policyname='stayqr_batch3_guest_documents_select'
        and coalesce(qual,'') not ilike '%guests.view%' and coalesce(qual,'') ilike '%guests.manage%'),
      'sensitive KYC rows require elevated guest/front-office permission'),
    (15, 'guest_documents direct authenticated writes blocked',
      not has_table_privilege('authenticated','public.guest_documents','INSERT')
      and not has_table_privilege('authenticated','public.guest_documents','UPDATE')
      and not has_table_privilege('authenticated','public.guest_documents','DELETE'),
      'metadata writes are RPC controlled'),
    (16, 'guest-documents storage select hardened',
      exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='stayqr_batch3_guest_documents_select'
        and coalesce(qual,'') ilike '%guest-documents%' and coalesce(qual,'') not ilike '%guests.view%'),
      'raw identity files exclude generic guest viewers'),
    (17, 'set_guest_consent RPC exists', to_regprocedure('public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb)') is not null, 'consent writer'),
    (18, 'register_guest_document RPC exists', to_regprocedure('public.register_guest_document(uuid,jsonb)') is not null, 'KYC registration'),
    (19, 'Guest 360 RPC exists', to_regprocedure('public.get_guest_360_directory(uuid)') is not null, 'hotel-scoped Guest 360'),
    (20, 'controlled export RPC exists', to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)') is not null, 'audited selected-column export'),
    (21, 'retention queue RPC exists', to_regprocedure('public.get_guest_documents_due_for_retention(uuid,integer)') is not null, 'legal-hold-aware retention queue'),
    (22, 'manual WhatsApp contact RPC exists', to_regprocedure('public.prepare_manual_whatsapp_contact(uuid,uuid,text)') is not null, 'consent-safe click-to-chat'),
    (23, 'campaign RPC exists', to_regprocedure('public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[])') is not null, 'audience campaign preparation'),
    (24, 'Secure QR evidence RPC exists', to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)') is not null, 'official UIDAI reader evidence'),
    (25, 'offline XML recorder is service-role only',
      to_regprocedure('public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)') is not null
      and has_function_privilege('service_role','public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE')
      and not has_function_privilege('authenticated','public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE'),
      'cryptographic result recorder cannot be called by hotel clients'),
    (26, 'provider profile writer is service-role only',
      to_regprocedure('public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb)') is not null
      and has_function_privilege('service_role','public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb)','EXECUTE')
      and not has_function_privilege('authenticated','public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb)','EXECUTE'),
      'hotel sender reconciliation is trusted-server only'),
    (27, 'provider template status writer is service-role only',
      to_regprocedure('public.record_whatsapp_provider_template_status(uuid,text,text,text)') is not null
      and has_function_privilege('service_role','public.record_whatsapp_provider_template_status(uuid,text,text,text)','EXECUTE')
      and not has_function_privilege('authenticated','public.record_whatsapp_provider_template_status(uuid,text,text,text)','EXECUTE'),
      'hotel clients cannot self-approve Meta templates'),
    (28, 'authenticated public Batch 3 RPCs are anon blocked',
      not has_function_privilege('anon','public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb)','EXECUTE')
      and not has_function_privilege('anon','public.register_guest_document(uuid,jsonb)','EXECUTE')
      and not has_function_privilege('anon','public.get_guest_360_directory(uuid)','EXECUTE')
      and not has_function_privilege('anon','public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)','EXECUTE')
      and not has_function_privilege('anon','public.prepare_manual_whatsapp_contact(uuid,uuid,text)','EXECUTE'),
      'anonymous execution denied'),
    (29, 'KYC consent required by register RPC',
      position('KYC capture consent is required' in pg_get_functiondef(to_regprocedure('public.register_guest_document(uuid,jsonb)'))) > 0,
      'document registration requires active consent'),
    (30, 'export RPC enforces reason',
      position('An export reason of at least 3 characters is required' in pg_get_functiondef(to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)'))) > 0,
      'every export has purpose evidence'),
    (31, 'export RPC excludes raw identity fields',
      position('storage_path' in pg_get_functiondef(to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)'))) = 0
      and position('document_number_masked' in pg_get_functiondef(to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)'))) = 0,
      'normal exports do not emit document objects/identifiers'),
    (32, 'campaign RPC requires hotel sender and approved template',
      position('hotel_whatsapp_provider_profiles' in pg_get_functiondef(to_regprocedure('public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[])'))) > 0
      and position('provider_status=''approved''' in pg_get_functiondef(to_regprocedure('public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[])'))) > 0,
      'Meta mode cannot bypass provider readiness'),
    (33, 'template edits invalidate provider approval',
      position('provider_status' in pg_get_functiondef(to_regprocedure('public.upsert_manual_whatsapp_template(uuid,jsonb)'))) > 0
      and position('not_configured' in pg_get_functiondef(to_regprocedure('public.upsert_manual_whatsapp_template(uuid,jsonb)'))) > 0,
      'edited content requires provider re-approval'),
    (34, 'retention queue excludes legal holds',
      position('legal_hold=false' in replace(pg_get_functiondef(to_regprocedure('public.get_guest_documents_due_for_retention(uuid,integer)')),' ','')) > 0,
      'legal hold blocks purge queue'),
    (35, 'Secure QR evidence requires explicit official-reader confirmation',
      position('official UIDAI Secure QR Reader' in pg_get_functiondef(to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)'))) > 0,
      'no claim based on an Aadhaar photo'),
    (36, 'Secure QR evidence hashes minimal evidence only',
      position('raw_qr_payload_stored' in pg_get_functiondef(to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)'))) > 0
      and position('aadhaar_number_stored' in pg_get_functiondef(to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)'))) > 0,
      'raw QR/full Aadhaar are not persisted')
), report as (
  select gate_no, gate_name, passed, evidence from gates
  union all
  select 999,
    case when count(*) filter(where passed)=36 then 'POSTLAUNCH_BATCH3_DATABASE_ACCEPTANCE: PASS (36/36)'
         else format('POSTLAUNCH_BATCH3_DATABASE_ACCEPTANCE: FAIL (%s/36 passed)',count(*) filter(where passed)) end,
    count(*) filter(where passed)=36,
    format('%s passed; %s failed',count(*) filter(where passed),count(*) filter(where not passed))
  from gates
)
select case when gate_no=999 then 'SUMMARY' else gate_no::text end as gate,
       gate_name, case when passed then 'PASS' else 'FAIL' end as result, evidence
from report order by gate_no;

do $$
declare failed_count integer;
begin
  select count(*) into failed_count
  from (
    select * from (values
      (to_regclass('public.guest_consents') is not null),
      (to_regclass('public.guest_document_access_audit') is not null),
      (to_regclass('public.guest_identity_verifications') is not null),
      (to_regclass('public.guest_export_audit') is not null),
      (to_regclass('public.guest_communication_suppressions') is not null and to_regclass('public.guest_communication_campaigns') is not null and to_regclass('public.guest_communication_recipients') is not null and to_regclass('public.guest_communication_events') is not null),
      (to_regclass('public.hotel_whatsapp_provider_profiles') is not null),
      ((select count(*)=10 from information_schema.columns where table_schema='public' and table_name='guest_documents' and column_name in ('document_group_id','capture_source','document_side','quality_status','quality_score','quality_flags','consent_id','retention_until','retention_basis','legal_hold'))),
      ((select count(*)=5 from information_schema.columns where table_schema='public' and table_name='whatsapp_templates' and column_name in ('provider_name','provider_status','provider_template_id','provider_language','provider_status_checked_at'))),
      ((select count(*)=2 from information_schema.columns where table_schema='public' and table_name='guest_communication_recipients' and column_name in ('attempt_count','last_attempt_at'))),
      (coalesce((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='guest_consents'),false)),
      (coalesce((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='guest_identity_verifications'),false)),
      (coalesce((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='guest_export_audit'),false)),
      ((select count(*)=5 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('guest_communication_suppressions','guest_communication_campaigns','guest_communication_recipients','guest_communication_events','hotel_whatsapp_provider_profiles') and c.relrowsecurity)),
      (exists(select 1 from pg_policies where schemaname='public' and tablename='guest_documents' and policyname='stayqr_batch3_guest_documents_select' and coalesce(qual,'') not ilike '%guests.view%' and coalesce(qual,'') ilike '%guests.manage%')),
      (not has_table_privilege('authenticated','public.guest_documents','INSERT') and not has_table_privilege('authenticated','public.guest_documents','UPDATE') and not has_table_privilege('authenticated','public.guest_documents','DELETE')),
      (exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='stayqr_batch3_guest_documents_select' and coalesce(qual,'') ilike '%guest-documents%' and coalesce(qual,'') not ilike '%guests.view%')),
      (to_regprocedure('public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb)') is not null),
      (to_regprocedure('public.register_guest_document(uuid,jsonb)') is not null),
      (to_regprocedure('public.get_guest_360_directory(uuid)') is not null),
      (to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)') is not null),
      (to_regprocedure('public.get_guest_documents_due_for_retention(uuid,integer)') is not null),
      (to_regprocedure('public.prepare_manual_whatsapp_contact(uuid,uuid,text)') is not null),
      (to_regprocedure('public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[])') is not null),
      (to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)') is not null),
      (to_regprocedure('public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)') is not null and has_function_privilege('service_role','public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE') and not has_function_privilege('authenticated','public.record_verified_aadhaar_offline_result(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE')),
      (to_regprocedure('public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb)') is not null and has_function_privilege('service_role','public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb)','EXECUTE') and not has_function_privilege('authenticated','public.record_hotel_whatsapp_provider_profile(uuid,text,text,text,text,jsonb)','EXECUTE')),
      (to_regprocedure('public.record_whatsapp_provider_template_status(uuid,text,text,text)') is not null and has_function_privilege('service_role','public.record_whatsapp_provider_template_status(uuid,text,text,text)','EXECUTE') and not has_function_privilege('authenticated','public.record_whatsapp_provider_template_status(uuid,text,text,text)','EXECUTE')),
      (not has_function_privilege('anon','public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb)','EXECUTE') and not has_function_privilege('anon','public.register_guest_document(uuid,jsonb)','EXECUTE') and not has_function_privilege('anon','public.get_guest_360_directory(uuid)','EXECUTE') and not has_function_privilege('anon','public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)','EXECUTE') and not has_function_privilege('anon','public.prepare_manual_whatsapp_contact(uuid,uuid,text)','EXECUTE')),
      (position('KYC capture consent is required' in pg_get_functiondef(to_regprocedure('public.register_guest_document(uuid,jsonb)'))) > 0),
      (position('An export reason of at least 3 characters is required' in pg_get_functiondef(to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)'))) > 0),
      (position('storage_path' in pg_get_functiondef(to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)'))) = 0 and position('document_number_masked' in pg_get_functiondef(to_regprocedure('public.export_guest_directory_360(uuid,uuid[],text[],boolean,text,jsonb)'))) = 0),
      (position('hotel_whatsapp_provider_profiles' in pg_get_functiondef(to_regprocedure('public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[])'))) > 0 and position('provider_status=''approved''' in pg_get_functiondef(to_regprocedure('public.create_guest_whatsapp_campaign(uuid,text,text,text,text,text,uuid[])'))) > 0),
      (position('provider_status' in pg_get_functiondef(to_regprocedure('public.upsert_manual_whatsapp_template(uuid,jsonb)'))) > 0 and position('not_configured' in pg_get_functiondef(to_regprocedure('public.upsert_manual_whatsapp_template(uuid,jsonb)'))) > 0),
      (position('legal_hold=false' in replace(pg_get_functiondef(to_regprocedure('public.get_guest_documents_due_for_retention(uuid,integer)')),' ','')) > 0),
      (position('official UIDAI Secure QR Reader' in pg_get_functiondef(to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)'))) > 0),
      (position('raw_qr_payload_stored' in pg_get_functiondef(to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)'))) > 0 and position('aadhaar_number_stored' in pg_get_functiondef(to_regprocedure('public.record_uidai_secure_qr_reader_verification(uuid,uuid,uuid,uuid,boolean,text,jsonb)'))) > 0)
    ) v(passed)
  ) checks where not passed;
  if failed_count <> 0 then raise exception 'POSTLAUNCH_BATCH3_DATABASE_ACCEPTANCE: FAIL (% failed)', failed_count; end if;
  raise notice 'POSTLAUNCH_BATCH3_DATABASE_ACCEPTANCE: PASS (36/36)';
end;
$$;
