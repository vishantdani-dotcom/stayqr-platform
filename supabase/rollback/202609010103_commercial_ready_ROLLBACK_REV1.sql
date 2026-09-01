begin;

do $$ begin
  if exists(select 1 from public.owner_subscription_requests limit 1)
     or exists(select 1 from public.subscription_recurring_attempts limit 1)
     or exists(select 1 from public.uidai_online_auth_requests limit 1) then
    raise exception 'Rollback stopped: Commercial-Ready evidence exists. Export/retain evidence and obtain explicit authorization before removal.';
  end if;
end $$;

drop function if exists public.get_commercial_ready_workspace(uuid);
drop function if exists public.request_owner_subscription_action(uuid,text,uuid,text,text,text);
drop function if exists public.set_commercial_provider_readiness(text,text,text,text,jsonb,jsonb);
drop function if exists public.configure_stayqr_support_profile(text,integer,integer);
drop function if exists public.configure_meta_whatsapp_provider(uuid,text,text,text,text,jsonb);
drop table if exists public.uidai_online_auth_requests;
drop table if exists public.subscription_recurring_attempts;
drop table if exists public.owner_subscription_requests;
drop table if exists public.stayqr_support_profile;
drop table if exists public.platform_provider_readiness;

alter table public.hotel_subscriptions
  drop constraint if exists hotel_subscriptions_autopay_status_cr_check,
  drop constraint if exists hotel_subscriptions_recurring_retry_cr_check,
  drop column if exists autopay_status,
  drop column if exists mandate_id,
  drop column if exists mandate_status,
  drop column if exists next_charge_at,
  drop column if exists last_charge_status,
  drop column if exists last_charge_at,
  drop column if exists recurring_retry_count,
  drop column if exists recurring_failure_code,
  drop column if exists recurring_failure_message;

alter table public.guest_consents drop constraint if exists guest_consents_purpose_check;
alter table public.guest_consents add constraint guest_consents_purpose_check check (purpose in ('kyc_capture','aadhaar_offline_verification','whatsapp_transactional','whatsapp_marketing','data_export'));
alter table public.guest_identity_verifications drop constraint if exists guest_identity_verifications_method_check;
alter table public.guest_identity_verifications add constraint guest_identity_verifications_method_check check (verification_method in ('aadhaar_offline_xml','aadhaar_secure_qr_uidai_reader'));

commit;
