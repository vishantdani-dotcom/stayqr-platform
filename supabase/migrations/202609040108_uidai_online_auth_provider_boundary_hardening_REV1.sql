-- StayQR Commercial-Ready — UIDAI online-auth provider boundary hardening REV1
-- Provider-agnostic only. Does not activate or configure any UIDAI/Aadhaar provider.

alter table public.uidai_online_auth_requests
  add column if not exists verification_attempts integer not null default 0,
  add column if not exists max_verification_attempts integer not null default 5,
  add column if not exists expires_at timestamptz,
  add column if not exists provider_verified_at timestamptz;

update public.uidai_online_auth_requests
set expires_at = coalesce(expires_at, requested_at + interval '10 minutes')
where expires_at is null;

alter table public.uidai_online_auth_requests
  alter column expires_at set default (now() + interval '10 minutes');

alter table public.uidai_online_auth_requests
  drop constraint if exists uidai_online_status_cr_check;
alter table public.uidai_online_auth_requests
  add constraint uidai_online_status_cr_check check (
    status in ('created','otp_sent','pending','verifying','evidence_pending','verified','failed','expired','cancelled')
  );

alter table public.uidai_online_auth_requests
  drop constraint if exists uidai_online_attempts_cr_check;
alter table public.uidai_online_auth_requests
  add constraint uidai_online_attempts_cr_check check (
    verification_attempts >= 0
    and max_verification_attempts between 1 and 10
    and verification_attempts <= max_verification_attempts
  );

create index if not exists idx_uidai_online_requests_expiry
  on public.uidai_online_auth_requests(hotel_id,status,expires_at)
  where status in ('created','otp_sent','pending','verifying','evidence_pending');
