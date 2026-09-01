-- StayQR Commercial-Ready Final Completion REV1
-- Additive, tenant-safe foundation for owner billing, activation score,
-- Cashfree recurring, Meta readiness, UIDAI online auth and 24x7 support.
begin;

alter table public.hotel_subscriptions
  add column if not exists autopay_status text not null default 'not_configured',
  add column if not exists mandate_id text,
  add column if not exists mandate_status text,
  add column if not exists next_charge_at timestamptz,
  add column if not exists last_charge_status text,
  add column if not exists last_charge_at timestamptz,
  add column if not exists recurring_retry_count integer not null default 0,
  add column if not exists recurring_failure_code text,
  add column if not exists recurring_failure_message text;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='hotel_subscriptions_autopay_status_cr_check') then
    alter table public.hotel_subscriptions add constraint hotel_subscriptions_autopay_status_cr_check
      check (autopay_status in ('not_configured','provider_activation_pending','authorization_pending','authenticated','active','paused','past_due','cancelled','failed'));
  end if;
  if not exists(select 1 from pg_constraint where conname='hotel_subscriptions_recurring_retry_cr_check') then
    alter table public.hotel_subscriptions add constraint hotel_subscriptions_recurring_retry_cr_check
      check (recurring_retry_count between 0 and 100);
  end if;
end $$;

create table if not exists public.platform_provider_readiness (
  provider_key text primary key,
  status text not null default 'pending',
  environment text not null default 'not_configured',
  external_reference text,
  capabilities jsonb not null default '{}'::jsonb,
  last_verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_provider_key_cr_check check (provider_key in ('cashfree_recurring','meta_whatsapp','uidai_online')),
  constraint platform_provider_status_cr_check check (status in ('pending','in_review','sandbox_ready','active','suspended','failed')),
  constraint platform_provider_environment_cr_check check (environment in ('not_configured','sandbox','production')),
  constraint platform_provider_json_cr_check check (jsonb_typeof(capabilities)='object' and jsonb_typeof(metadata)='object')
);

insert into public.platform_provider_readiness(provider_key,status,environment,capabilities,metadata)
values
  ('cashfree_recurring','pending','not_configured','{"mandate":false,"autopay":false}'::jsonb,'{"truth":"Merchant capability must be verified before activation."}'::jsonb),
  ('meta_whatsapp','pending','not_configured','{"cloud_api":false,"templates":false}'::jsonb,'{"truth":"Meta Business Portfolio and WABA activation pending."}'::jsonb),
  ('uidai_online','pending','not_configured','{"otp":false,"demographic":false}'::jsonb,'{"truth":"Authorized AUA/KUA/Sub-AUA provider onboarding pending."}'::jsonb)
on conflict(provider_key) do nothing;

create table if not exists public.stayqr_support_profile (
  singleton boolean primary key default true check (singleton),
  coverage text not null default '24x7' check (coverage='24x7'),
  primary_channel text not null default 'whatsapp' check (primary_channel='whatsapp'),
  support_whatsapp_e164 text,
  after_hours_owner text not null default 'Founder',
  p0_ack_minutes integer check (p0_ack_minutes is null or p0_ack_minutes between 1 and 120),
  p1_ack_minutes integer check (p1_ack_minutes is null or p1_ack_minutes between 1 and 240),
  escalation_policy text not null default 'Founder-owned after-hours escalation',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint support_whatsapp_e164_cr_check check (support_whatsapp_e164 is null or support_whatsapp_e164 ~ '^\+[1-9][0-9]{7,14}$')
);
insert into public.stayqr_support_profile(singleton) values(true) on conflict(singleton) do nothing;

create table if not exists public.owner_subscription_requests (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  subscription_id uuid references public.hotel_subscriptions(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  requested_plan_id uuid references public.subscription_plans(id) on delete set null,
  billing_cycle text,
  reason text not null,
  status text not null default 'pending',
  idempotency_key text not null unique,
  provider text,
  provider_request_id text,
  failure_code text,
  failure_message text,
  details jsonb not null default '{}'::jsonb,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint owner_subscription_action_cr_check check (action in ('enable_autopay','upgrade','downgrade','cancel','reactivate','retry_payment')),
  constraint owner_subscription_cycle_cr_check check (billing_cycle is null or billing_cycle in ('monthly','annual')),
  constraint owner_subscription_status_cr_check check (status in ('pending','provider_activation_pending','processing','completed','failed','cancelled')),
  constraint owner_subscription_reason_cr_check check (char_length(btrim(reason)) between 3 and 500),
  constraint owner_subscription_details_cr_check check (jsonb_typeof(details)='object')
);
create index if not exists idx_owner_subscription_requests_hotel_recent on public.owner_subscription_requests(hotel_id,created_at desc);

create table if not exists public.subscription_recurring_attempts (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  subscription_id uuid references public.hotel_subscriptions(id) on delete set null,
  owner_request_id uuid references public.owner_subscription_requests(id) on delete set null,
  provider text not null default 'cashfree',
  provider_payment_id text,
  provider_event_id text,
  attempt_type text not null,
  amount_minor bigint,
  currency_code text not null default 'INR',
  status text not null,
  failure_code text,
  failure_message text,
  attempted_at timestamptz not null default now(),
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint recurring_attempt_type_cr_check check (attempt_type in ('mandate_create','authorization','charge','retry','sync','cancel','pause','activate','change_plan')),
  constraint recurring_attempt_status_cr_check check (status in ('pending','processing','succeeded','failed','skipped')),
  constraint recurring_attempt_amount_cr_check check (amount_minor is null or amount_minor>=0),
  constraint recurring_attempt_currency_cr_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint recurring_attempt_metadata_cr_check check (jsonb_typeof(metadata)='object')
);
create unique index if not exists uq_recurring_attempt_provider_event on public.subscription_recurring_attempts(provider,provider_event_id) where provider_event_id is not null;
create index if not exists idx_recurring_attempt_hotel_recent on public.subscription_recurring_attempts(hotel_id,attempted_at desc);

alter table public.guest_consents drop constraint if exists guest_consents_purpose_check;
alter table public.guest_consents add constraint guest_consents_purpose_check check (purpose in (
  'kyc_capture','aadhaar_offline_verification','aadhaar_online_authentication','whatsapp_transactional','whatsapp_marketing','data_export'
));

alter table public.guest_identity_verifications drop constraint if exists guest_identity_verifications_method_check;
alter table public.guest_identity_verifications add constraint guest_identity_verifications_method_check check (
  verification_method in ('aadhaar_offline_xml','aadhaar_secure_qr_uidai_reader','aadhaar_online_auth')
);

create table if not exists public.uidai_online_auth_requests (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_id uuid not null,
  guest_session_id uuid,
  consent_id uuid not null references public.guest_consents(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  provider text not null,
  provider_request_id text,
  transaction_reference text not null unique,
  auth_mode text not null default 'otp',
  status text not null default 'created',
  aadhaar_last4 text,
  aadhaar_sha256 text not null,
  provider_response_code text,
  failure_message text,
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  evidence jsonb not null default '{}'::jsonb,
  constraint uidai_online_guest_cr_fk foreign key(hotel_id,guest_id) references public.guests(hotel_id,id) on delete cascade,
  constraint uidai_online_session_cr_fk foreign key(hotel_id,guest_session_id) references public.guest_sessions(hotel_id,id) on delete restrict,
  constraint uidai_online_mode_cr_check check (auth_mode in ('otp','demographic','face','fingerprint','iris')),
  constraint uidai_online_status_cr_check check (status in ('created','otp_sent','pending','verified','failed','expired','cancelled')),
  constraint uidai_online_last4_cr_check check (aadhaar_last4 is null or aadhaar_last4 ~ '^[0-9]{4}$'),
  constraint uidai_online_hash_cr_check check (aadhaar_sha256 ~ '^[0-9a-f]{64}$'),
  constraint uidai_online_evidence_cr_check check (jsonb_typeof(evidence)='object' and pg_column_size(evidence)<=16384)
);
create index if not exists idx_uidai_online_requests_hotel_guest_recent on public.uidai_online_auth_requests(hotel_id,guest_id,requested_at desc);

revoke all on public.platform_provider_readiness,public.stayqr_support_profile,public.owner_subscription_requests,public.subscription_recurring_attempts,public.uidai_online_auth_requests from public,anon,authenticated;
grant select on public.owner_subscription_requests,public.subscription_recurring_attempts,public.uidai_online_auth_requests to authenticated;
grant all on public.platform_provider_readiness,public.stayqr_support_profile,public.owner_subscription_requests,public.subscription_recurring_attempts,public.uidai_online_auth_requests to service_role;

alter table public.owner_subscription_requests enable row level security;
alter table public.subscription_recurring_attempts enable row level security;
alter table public.uidai_online_auth_requests enable row level security;

drop policy if exists owner_subscription_requests_select_cr on public.owner_subscription_requests;
create policy owner_subscription_requests_select_cr on public.owner_subscription_requests for select to authenticated using (
  private.user_has_any_permission(hotel_id,array['hotel.manage','payments.view','payments.manage']::text[]) or private.is_platform_admin()
);
drop policy if exists subscription_recurring_attempts_select_cr on public.subscription_recurring_attempts;
create policy subscription_recurring_attempts_select_cr on public.subscription_recurring_attempts for select to authenticated using (
  private.user_has_any_permission(hotel_id,array['hotel.manage','payments.view','payments.manage']::text[]) or private.is_platform_admin()
);
drop policy if exists uidai_online_requests_select_cr on public.uidai_online_auth_requests;
create policy uidai_online_requests_select_cr on public.uidai_online_auth_requests for select to authenticated using (
  private.user_has_permission(hotel_id,'guests.manage') or private.is_platform_admin()
);

create or replace function public.set_guest_consent(
  target_hotel_id uuid,target_guest_id uuid,target_purpose text,grant_consent boolean,
  target_source text default 'staff_recorded',target_evidence jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); existing_row public.guest_consents%rowtype; consent_row public.guest_consents%rowtype;
  purpose_value text:=lower(trim(coalesce(target_purpose,''))); source_value text:=lower(trim(coalesce(target_source,'staff_recorded')));
  evidence_value jsonb:=coalesce(target_evidence,'{}'::jsonb); session_value uuid;
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage']::text[]) then raise exception 'Guest consent management access denied.'; end if;
  if purpose_value not in ('kyc_capture','aadhaar_offline_verification','aadhaar_online_authentication','whatsapp_transactional','whatsapp_marketing','data_export') then raise exception 'Unsupported consent purpose.'; end if;
  if source_value not in ('staff_recorded','guest_written','guest_digital','imported') then raise exception 'Unsupported consent source.'; end if;
  if not exists(select 1 from public.guests g where g.hotel_id=target_hotel_id and g.id=target_guest_id) then raise exception 'Guest not found in the current hotel.'; end if;
  if jsonb_typeof(evidence_value)<>'object' or pg_column_size(evidence_value)>8192 then raise exception 'Consent evidence must be a JSON object no larger than 8 KB.'; end if;
  begin session_value:=nullif(evidence_value->>'guest_session_id','')::uuid; exception when invalid_text_representation then raise exception 'guest_session_id evidence must be a valid UUID.'; end;
  if session_value is not null and not exists(select 1 from public.guest_sessions gs where gs.hotel_id=target_hotel_id and gs.id=session_value and gs.guest_id=target_guest_id) then raise exception 'Consent guest session does not belong to this guest and hotel.'; end if;
  select * into existing_row from public.guest_consents c where c.hotel_id=target_hotel_id and c.guest_id=target_guest_id and c.purpose=purpose_value and c.status='granted' and c.revoked_at is null order by c.captured_at desc limit 1 for update;
  if grant_consent then
    if found then return jsonb_build_object('ok',true,'idempotent',true,'consent',to_jsonb(existing_row)); end if;
    insert into public.guest_consents(hotel_id,guest_id,guest_session_id,purpose,status,source,captured_by,evidence)
    values(target_hotel_id,target_guest_id,session_value,purpose_value,'granted',source_value,actor_id,evidence_value) returning * into consent_row;
  else
    if not found then return jsonb_build_object('ok',true,'idempotent',true,'consent',null); end if;
    update public.guest_consents set status='revoked',revoked_by=actor_id,revoked_at=now(),updated_at=now() where id=existing_row.id returning * into consent_row;
    if purpose_value in ('whatsapp_transactional','whatsapp_marketing') then
      insert into public.guest_communication_suppressions(hotel_id,guest_id,channel,reason,active,created_by,metadata)
      values(target_hotel_id,target_guest_id,'whatsapp','guest_opt_out',true,actor_id,jsonb_build_object('source','consent_revocation','purpose',purpose_value))
      on conflict(hotel_id,guest_id,channel) where active is true do nothing;
    end if;
  end if;
  perform private.write_activity_log(target_hotel_id,case when grant_consent then 'guest.consent_granted' else 'guest.consent_revoked' end,'guest',target_guest_id,'Guest consent state changed.',null,jsonb_build_object('purpose',purpose_value,'granted',grant_consent),jsonb_build_object('consent_id',consent_row.id,'source',source_value));
  return jsonb_build_object('ok',true,'idempotent',false,'consent',to_jsonb(consent_row));
end $$;
revoke all on function public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb) from public,anon;
grant execute on function public.set_guest_consent(uuid,uuid,text,boolean,text,jsonb) to authenticated,service_role;

create or replace function public.set_commercial_provider_readiness(
  p_provider_key text,p_status text,p_environment text,p_external_reference text default null,
  p_capabilities jsonb default '{}'::jsonb,p_evidence jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=private.require_platform_admin_20260728(); v_row public.platform_provider_readiness%rowtype;
begin
  if p_provider_key not in ('cashfree_recurring','meta_whatsapp','uidai_online') then raise exception 'Unsupported commercial provider.'; end if;
  if p_status not in ('pending','in_review','sandbox_ready','active','suspended','failed') then raise exception 'Unsupported provider readiness status.'; end if;
  if p_environment not in ('not_configured','sandbox','production') then raise exception 'Unsupported provider environment.'; end if;
  if p_status='active' and (nullif(trim(coalesce(p_external_reference,'')),'') is null or coalesce(p_evidence,'{}'::jsonb)='{}'::jsonb) then raise exception 'Active provider readiness requires an external reference and non-empty verification evidence.'; end if;
  insert into public.platform_provider_readiness(provider_key,status,environment,external_reference,capabilities,last_verified_at,verified_by,metadata,updated_at)
  values(p_provider_key,p_status,p_environment,nullif(trim(p_external_reference),''),coalesce(p_capabilities,'{}'::jsonb),case when p_status in ('sandbox_ready','active') then now() else null end,v_actor,coalesce(p_evidence,'{}'::jsonb),now())
  on conflict(provider_key) do update set status=excluded.status,environment=excluded.environment,external_reference=excluded.external_reference,capabilities=excluded.capabilities,last_verified_at=excluded.last_verified_at,verified_by=v_actor,metadata=excluded.metadata,updated_at=now()
  returning * into v_row;
  return jsonb_build_object('ok',true,'provider',to_jsonb(v_row));
end $$;
revoke all on function public.set_commercial_provider_readiness(text,text,text,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.set_commercial_provider_readiness(text,text,text,text,jsonb,jsonb) to authenticated,service_role;

create or replace function public.configure_stayqr_support_profile(
  p_support_whatsapp_e164 text,p_p0_ack_minutes integer default null,p_p1_ack_minutes integer default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=private.require_platform_admin_20260728(); v_phone text:=nullif(trim(coalesce(p_support_whatsapp_e164,'')),''); v_row public.stayqr_support_profile%rowtype;
begin
  if v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'Support WhatsApp must be in E.164 format.'; end if;
  update public.stayqr_support_profile set support_whatsapp_e164=v_phone,p0_ack_minutes=p_p0_ack_minutes,p1_ack_minutes=p_p1_ack_minutes,coverage='24x7',primary_channel='whatsapp',after_hours_owner='Founder',updated_by=v_actor,updated_at=now() where singleton=true returning * into v_row;
  return jsonb_build_object('ok',true,'support',to_jsonb(v_row));
end $$;
revoke all on function public.configure_stayqr_support_profile(text,integer,integer) from public,anon,authenticated;
grant execute on function public.configure_stayqr_support_profile(text,integer,integer) to authenticated,service_role;

create or replace function public.configure_meta_whatsapp_provider(
  p_hotel_id uuid,p_business_account_id text,p_phone_number_id text,p_sender_display_name text,
  p_status text default 'pending',p_evidence jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=private.require_platform_admin_20260728(); v_platform_status text; v_row public.hotel_whatsapp_provider_profiles%rowtype;
begin
  if p_status not in ('pending','active','disabled','failed') then raise exception 'Unsupported Meta provider status.'; end if;
  if nullif(trim(coalesce(p_phone_number_id,'')),'') is null then raise exception 'Meta phone-number ID is required.'; end if;
  select status into v_platform_status from public.platform_provider_readiness where provider_key='meta_whatsapp';
  if p_status='active' and (v_platform_status<>'active' or coalesce(p_evidence,'{}'::jsonb)='{}'::jsonb) then raise exception 'Meta sender cannot be active until platform provider readiness and verification evidence are active.'; end if;
  insert into public.hotel_whatsapp_provider_profiles(hotel_id,provider,business_account_id,phone_number_id,sender_display_name,status,configured_by,configured_at,last_verified_at,metadata)
  values(p_hotel_id,'meta_cloud',nullif(trim(p_business_account_id),''),trim(p_phone_number_id),nullif(trim(p_sender_display_name),''),p_status,v_actor,now(),case when p_status='active' then now() else null end,coalesce(p_evidence,'{}'::jsonb))
  on conflict(hotel_id) do update set business_account_id=excluded.business_account_id,phone_number_id=excluded.phone_number_id,sender_display_name=excluded.sender_display_name,status=excluded.status,configured_by=v_actor,configured_at=now(),last_verified_at=excluded.last_verified_at,metadata=excluded.metadata
  returning * into v_row;
  return jsonb_build_object('ok',true,'profile',to_jsonb(v_row));
end $$;
revoke all on function public.configure_meta_whatsapp_provider(uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.configure_meta_whatsapp_provider(uuid,text,text,text,text,jsonb) to authenticated,service_role;

create or replace function public.request_owner_subscription_action(
  p_hotel_id uuid,p_action text,p_plan_id uuid default null,p_billing_cycle text default null,
  p_reason text default null,p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid(); v_action text:=lower(trim(coalesce(p_action,''))); v_reason text:=trim(coalesce(p_reason,''));
  v_subscription public.hotel_subscriptions%rowtype; v_request public.owner_subscription_requests%rowtype; v_provider_status text;
begin
  if v_actor is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(p_hotel_id,array['hotel.manage','payments.manage']::text[]) then raise exception 'Owner billing management access denied.'; end if;
  if v_action not in ('enable_autopay','upgrade','downgrade','cancel','reactivate','retry_payment') then raise exception 'Unsupported owner billing action.'; end if;
  if length(v_reason) not between 3 and 500 then raise exception 'A billing action reason of 3 to 500 characters is required.'; end if;
  if nullif(trim(coalesce(p_idempotency_key,'')),'') is null then raise exception 'A billing action idempotency key is required.'; end if;
  if p_billing_cycle is not null and p_billing_cycle not in ('monthly','annual') then raise exception 'Billing cycle must be monthly or annual.'; end if;
  if v_action in ('upgrade','downgrade') and (p_plan_id is null or not exists(select 1 from public.subscription_plans sp where sp.id=p_plan_id and sp.status='active' and sp.is_public)) then raise exception 'Select an active public plan.'; end if;
  select * into v_request from public.owner_subscription_requests where idempotency_key=p_idempotency_key;
  if found then return jsonb_build_object('ok',true,'idempotent',true,'request',to_jsonb(v_request)); end if;
  select * into v_subscription from public.hotel_subscriptions hs where hs.hotel_id=p_hotel_id order by (hs.status in ('trial','trialing','active','past_due','suspended')) desc,hs.updated_at desc limit 1 for update;
  if v_subscription.id is null then raise exception 'No current hotel subscription was found.'; end if;
  select status into v_provider_status from public.platform_provider_readiness where provider_key='cashfree_recurring';
  insert into public.owner_subscription_requests(hotel_id,subscription_id,actor_user_id,action,requested_plan_id,billing_cycle,reason,status,idempotency_key,provider,details)
  values(p_hotel_id,v_subscription.id,v_actor,v_action,p_plan_id,p_billing_cycle,v_reason,case when v_provider_status='active' then 'pending' else 'provider_activation_pending' end,p_idempotency_key,'cashfree',jsonb_build_object('provider_status_at_request',coalesce(v_provider_status,'pending')))
  returning * into v_request;
  if v_action='cancel' and v_subscription.id is not null then
    update public.hotel_subscriptions set cancellation_reason=v_reason,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('cancel_at_period_end',true,'cancellation_requested_at',now(),'cancellation_requested_by',v_actor),updated_at=now() where id=v_subscription.id;
    update public.owner_subscription_requests set status='completed',completed_at=now(),updated_at=now() where id=v_request.id returning * into v_request;
  elsif v_action='reactivate' and v_subscription.id is not null and coalesce((v_subscription.metadata->>'cancel_at_period_end')::boolean,false) then
    update public.hotel_subscriptions set cancellation_reason=null,metadata=coalesce(metadata,'{}'::jsonb)-'cancel_at_period_end'-'cancellation_requested_at'-'cancellation_requested_by',updated_at=now() where id=v_subscription.id;
    update public.owner_subscription_requests set status='completed',completed_at=now(),updated_at=now() where id=v_request.id returning * into v_request;
  end if;
  perform private.write_activity_log(p_hotel_id,'subscription.owner_action_requested','hotel_subscription',v_subscription.id,'Hotel owner submitted a billing action.',null,jsonb_build_object('action',v_action,'status',v_request.status),jsonb_build_object('request_id',v_request.id,'reason',v_reason));
  return jsonb_build_object('ok',true,'idempotent',false,'request',to_jsonb(v_request));
end $$;
revoke all on function public.request_owner_subscription_action(uuid,text,uuid,text,text,text) from public,anon;
grant execute on function public.request_owner_subscription_action(uuid,text,uuid,text,text,text) to authenticated,service_role;

create or replace function public.get_commercial_ready_workspace(p_hotel_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid(); v_hotel public.hotels%rowtype; v_subscription public.hotel_subscriptions%rowtype;
  v_plan jsonb; v_provider jsonb; v_support public.stayqr_support_profile%rowtype; v_checklist jsonb; v_score integer:=0; v_completed integer:=0;
  v_profile boolean; v_rooms boolean; v_staff boolean; v_guide boolean; v_qr boolean; v_billing boolean; v_operational boolean; v_support_ready boolean;
begin
  if v_actor is null then raise exception 'Authentication is required.'; end if;
  if not (private.user_has_hotel_access(p_hotel_id) or private.is_platform_admin()) then raise exception 'Commercial-ready workspace access denied.'; end if;
  select * into v_hotel from public.hotels where id=p_hotel_id;
  if not found then raise exception 'Hotel not found.'; end if;
  select * into v_subscription from public.hotel_subscriptions hs where hs.hotel_id=p_hotel_id order by (hs.status in ('trial','trialing','active','past_due','suspended')) desc,hs.updated_at desc limit 1;
  select to_jsonb(sp) into v_plan from public.subscription_plans sp where sp.id=v_subscription.plan_id;
  select * into v_support from public.stayqr_support_profile where singleton=true;
  v_profile:=nullif(trim(v_hotel.hotel_name),'') is not null and nullif(trim(v_hotel.slug),'') is not null and nullif(trim(v_hotel.timezone),'') is not null and nullif(trim(v_hotel.currency_code),'') is not null;
  v_rooms:=exists(select 1 from public.rooms r where r.hotel_id=p_hotel_id and r.is_active);
  v_staff:=exists(select 1 from public.staff s where s.hotel_id=p_hotel_id and s.status='active');
  v_guide:=exists(select 1 from public.guest_guide_settings g where g.hotel_id=p_hotel_id and g.publish_status='published' and g.published_version>0);
  v_qr:=exists(select 1 from public.room_qr_codes q where q.hotel_id=p_hotel_id and q.is_active);
  v_billing:=v_subscription.id is not null and v_subscription.status in ('trial','trialing','active') and v_subscription.plan_id is not null;
  v_operational:=exists(select 1 from public.guest_sessions gs where gs.hotel_id=p_hotel_id);
  v_support_ready:=v_support.coverage='24x7' and v_support.after_hours_owner is not null;
  v_score:=(case when v_profile then 10 else 0 end)+(case when v_rooms then 15 else 0 end)+(case when v_staff then 10 else 0 end)+(case when v_guide then 15 else 0 end)+(case when v_qr then 10 else 0 end)+(case when v_billing then 20 else 0 end)+(case when v_operational then 10 else 0 end)+(case when v_support_ready then 10 else 0 end);
  v_completed:=(v_profile::int+v_rooms::int+v_staff::int+v_guide::int+v_qr::int+v_billing::int+v_operational::int+v_support_ready::int);
  v_checklist:=jsonb_build_array(
    jsonb_build_object('key','hotel_profile','label','Hotel profile','complete',v_profile,'weight',10,'complete_text','Hotel identity and regional settings ready.','action','Complete hotel profile and regional settings.'),
    jsonb_build_object('key','rooms','label','Rooms configured','complete',v_rooms,'weight',15,'complete_text','Active room inventory exists.','action','Add at least one active room.'),
    jsonb_build_object('key','staff','label','Staff configured','complete',v_staff,'weight',10,'complete_text','Active hotel staff access exists.','action','Invite and activate hotel staff.'),
    jsonb_build_object('key','guest_guide','label','Guest Guide published','complete',v_guide,'weight',15,'complete_text','A published Guest Guide is available.','action','Publish the hotel Guest Guide.'),
    jsonb_build_object('key','qr_guides','label','Room QR guides','complete',v_qr,'weight',10,'complete_text','Active permanent room QR exists.','action','Generate room QR guides.'),
    jsonb_build_object('key','billing','label','Billing ready','complete',v_billing,'weight',20,'complete_text','Plan and subscription are assigned.','action','Complete plan and subscription setup.'),
    jsonb_build_object('key','operational_test','label','Operational test','complete',v_operational,'weight',10,'complete_text','A stay lifecycle has been exercised.','action','Run a controlled test reservation/stay.'),
    jsonb_build_object('key','support','label','24x7 support path','complete',v_support_ready,'weight',10,'complete_text','24x7 escalation ownership is defined.','action','Confirm StayQR support escalation settings.')
  );
  select coalesce(jsonb_object_agg(provider_key,jsonb_build_object('status',status,'environment',environment,'external_reference',external_reference,'capabilities',capabilities,'last_verified_at',last_verified_at)),'{}'::jsonb) into v_provider from public.platform_provider_readiness;
  return jsonb_build_object(
    'hotel',jsonb_build_object('id',v_hotel.id,'hotel_name',v_hotel.hotel_name,'subscription_status',v_hotel.subscription_status),
    'activation',jsonb_build_object('score',v_score,'completed_items',v_completed,'total_items',8,'checklist',v_checklist),
    'billing',jsonb_build_object('subscription',case when v_subscription.id is null then null else jsonb_build_object(
      'id',v_subscription.id,'plan_id',v_subscription.plan_id,'status',v_subscription.status,
      'billing_mode',v_subscription.billing_mode,'billing_cycle',v_subscription.billing_cycle,
      'currency_code',v_subscription.currency_code,'amount_minor',v_subscription.amount_minor,
      'provider',v_subscription.provider,'provider_status',v_subscription.provider_status,
      'current_period_start',v_subscription.current_period_start,'current_period_end',v_subscription.current_period_end,
      'start_date',v_subscription.start_date,'end_date',v_subscription.end_date,
      'autopay_status',v_subscription.autopay_status,'mandate_status',v_subscription.mandate_status,
      'next_charge_at',v_subscription.next_charge_at,'last_charge_status',v_subscription.last_charge_status,
      'last_charge_at',v_subscription.last_charge_at,'recurring_retry_count',v_subscription.recurring_retry_count,
      'recurring_failure_code',v_subscription.recurring_failure_code,'recurring_failure_message',v_subscription.recurring_failure_message,
      'cancel_at_period_end',coalesce((v_subscription.metadata->>'cancel_at_period_end')::boolean,false),
      'cancellation_reason',v_subscription.cancellation_reason
    ) end,'plan',v_plan,
      'available_plans',(select coalesce(jsonb_agg(jsonb_build_object('id',sp.id,'plan_name',sp.plan_name,'plan_code',sp.plan_code,'price_monthly',sp.price_monthly,'price_annual',sp.price_annual,'currency_code',sp.currency_code,'max_rooms',sp.max_rooms,'max_staff',sp.max_staff) order by sp.price_monthly),'[]'::jsonb) from public.subscription_plans sp where sp.status='active' and sp.is_public),
      'payment_history',(select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'event_type',x.event_type,'status',coalesce(x.new_status,x.old_status),'details',x.details,'occurred_at',x.occurred_at,'created_at',x.created_at) order by x.occurred_at desc),'[]'::jsonb) from (select * from public.subscription_events e where e.hotel_id=p_hotel_id order by e.occurred_at desc limit 30) x),
      'owner_requests',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select * from public.owner_subscription_requests r where r.hotel_id=p_hotel_id order by r.created_at desc limit 30) x)),
    'providers',v_provider,
    'support',jsonb_build_object('coverage',v_support.coverage,'primary_channel',v_support.primary_channel,'after_hours_owner',v_support.after_hours_owner,'p0_ack_minutes',v_support.p0_ack_minutes,'p1_ack_minutes',v_support.p1_ack_minutes,'whatsapp_configured',v_support.support_whatsapp_e164 is not null,'whatsapp_url',case when v_support.support_whatsapp_e164 is null then null else 'https://wa.me/'||regexp_replace(v_support.support_whatsapp_e164,'\D','','g') end,'escalation_policy',v_support.escalation_policy)
  );
end $$;
revoke all on function public.get_commercial_ready_workspace(uuid) from public,anon;
grant execute on function public.get_commercial_ready_workspace(uuid) to authenticated,service_role;

commit;
