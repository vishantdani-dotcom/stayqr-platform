-- StayQR v1.1 Post-Launch Batch B — Final Completion Acceptance
-- Items 3, 4, 5, 8, 11, 13, 14
-- Staging only until release lock. Read-only audit.
-- Expected summary:
-- POSTLAUNCH_BATCH2_FINAL_DATABASE_ACCEPTANCE: PASS (24/24)

with defs as (
  select
    pg_get_functiondef('public.sync_my_verified_staff_phone(uuid)'::regprocedure) as sync_phone,
    pg_get_functiondef('public.update_hotel_branding(uuid,text,text)'::regprocedure) as branding,
    pg_get_functiondef('public.issue_permanent_room_qr_pin(uuid,uuid)'::regprocedure) as issue_pin,
    pg_get_functiondef('public.resolve_permanent_room_qr(uuid,text)'::regprocedure) as resolve_room,
    pg_get_functiondef('private.sync_room_qr_pin_from_guest_session()'::regprocedure) as sync_pin,
    pg_get_functiondef('private.sync_guest_access_from_session()'::regprocedure) as signed_token_sync
),
checks(check_no, check_name, passed, evidence) as (
  select 1, 'staff verified-phone timestamp exists', exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='staff' and column_name='phone_verified_at'
  ), 'public.staff.phone_verified_at'
  union all
  select 2, 'verified-phone sync is backed by confirmed Supabase Auth phone',
    position('phone_confirmed_at' in sync_phone) > 0 and position('auth.users' in sync_phone) > 0,
    'auth.users.phone_confirmed_at' from defs
  union all
  select 3, 'verified-phone sync is scoped to authenticated staff hotel identity',
    position('auth.uid()' in sync_phone) > 0 and position('s.hotel_id = p_hotel_id' in sync_phone) > 0,
    'auth.uid + p_hotel_id' from defs
  union all
  select 4, 'hotel cover URL exists', exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='hotels' and column_name='cover_url'
  ), 'public.hotels.cover_url'
  union all
  select 5, 'branding RPC is hotel.manage guarded',
    position('hotel.manage' in branding) > 0 and position('guest-guide-media' in branding) > 0,
    'tenant media URL + hotel.manage' from defs
  union all
  select 6, 'unified media bucket is public guest media with 20 MB cap',
    coalesce((select public and file_size_limit = 20971520 from storage.buckets where id='guest-guide-media'), false),
    'storage.buckets guest-guide-media'
  union all
  select 7, 'unified media bucket allows approved short-video MIME types',
    coalesce((select allowed_mime_types @> array['video/mp4','video/webm']::text[] from storage.buckets where id='guest-guide-media'), false),
    'video/mp4 + video/webm'
  union all
  select 8, 'guest-guide media MIME constraint exists', exists(
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='guest_guide_media' and c.conname='guest_guide_media_mime_type_check'
  ), 'guest_guide_media_mime_type_check'
  union all
  select 9, 'permanent room QR table exists', to_regclass('public.room_qr_codes') is not null, 'public.room_qr_codes'
  union all
  select 10, 'room QR public code is unique', exists(
    select 1 from pg_indexes
    where schemaname='public' and tablename='room_qr_codes' and indexdef ilike '%unique%' and indexdef ilike '%public_code%'
  ), 'unique public_code'
  union all
  select 11, 'per-stay room PIN challenge table exists', to_regclass('public.room_qr_pin_challenges') is not null, 'public.room_qr_pin_challenges'
  union all
  select 12, 'room QR state tables have RLS enabled',
    coalesce((select relrowsecurity from pg_class where oid='public.room_qr_codes'::regclass), false)
    and coalesce((select relrowsecurity from pg_class where oid='public.room_qr_pin_challenges'::regclass), false),
    'RLS enabled'
  union all
  select 13, 'anonymous users cannot read room QR state tables directly',
    not has_table_privilege('anon','public.room_qr_codes','select')
    and not has_table_privilege('anon','public.room_qr_pin_challenges','select'),
    'anon table access denied'
  union all
  select 14, 'all current rooms have a permanent QR identity',
    not exists (
      select 1 from public.rooms r
      where not exists (select 1 from public.room_qr_codes q where q.room_id=r.id and q.hotel_id=r.hotel_id)
    ),
    format('%s rooms / %s permanent QR rows', (select count(*) from public.rooms), (select count(*) from public.room_qr_codes))
  union all
  select 15, 'only one active PIN challenge can exist per room', exists(
    select 1 from pg_indexes
    where schemaname='public' and tablename='room_qr_pin_challenges'
      and indexname='uq_room_qr_pin_active_room' and indexdef ilike '%where (status = ''active''%'
  ), 'uq_room_qr_pin_active_room'
  union all
  select 16, 'stay PIN is hashed and plaintext PIN is not stored',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='room_qr_pin_challenges' and column_name='pin_hash')
    and not exists(select 1 from information_schema.columns where table_schema='public' and table_name='room_qr_pin_challenges' and column_name in ('pin','plain_pin','pin_code')),
    'bcrypt hash only'
  union all
  select 17, 'PIN issuing uses cryptographic random bytes and bcrypt',
    position('gen_random_bytes' in issue_pin) > 0 and position('gen_salt' in issue_pin) > 0 and position('crypt(' in issue_pin) > 0,
    'gen_random_bytes + bcrypt' from defs
  union all
  select 18, 'PIN issuance requires an active current stay',
    position('s.status = ''active''' in issue_pin) > 0 and position('checkout_time' in issue_pin) > 0,
    'active guest_session required' from defs
  union all
  select 19, 'stay change/checkout revokes prior active room PIN',
    position('Guest stay changed or ended' in sync_pin) > 0 and position('status = ''revoked''' in sync_pin) > 0,
    'guest_session lifecycle trigger' from defs
  union all
  select 20, 'public resolver requires active stay and unexpired PIN',
    position('s.status = ''active''' in resolve_room) > 0 and position('c.expires_at > now()' in resolve_room) > 0,
    'active stay + challenge expiry' from defs
  union all
  select 21, 'public resolver enforces five-attempt lockout',
    position('failed_attempts >= 5' in resolve_room) > 0 and position('status = ''locked''' in resolve_room) > 0,
    '5-attempt lockout' from defs
  union all
  select 22, 'permanent QR resolves only through existing signed guest token',
    position('private.render_guest_access_token' in resolve_room) > 0 and position('public.guest_access_tokens' in resolve_room) > 0,
    'signed guest token preserved' from defs
  union all
  select 23, 'manual token revocation/expiry remains authoritative',
    position('v_token.status <> ''active''' in resolve_room) > 0 and position('v_token.expires_at <= now()' in resolve_room) > 0,
    'revoked/expired token cannot be bypassed' from defs
  union all
  select 24, 'existing signed-token guest-session lifecycle trigger remains installed',
    signed_token_sync is not null and exists(
      select 1 from pg_trigger tg
      join pg_class c on c.oid=tg.tgrelid
      where c.oid='public.guest_sessions'::regclass
        and not tg.tgisinternal
        and pg_get_triggerdef(tg.oid) ilike '%sync_guest_access_from_session%'
    ),
    'private.sync_guest_access_from_session()' from defs
),
summary as (
  select count(*) filter(where passed) as passed_count, count(*) as total_count from checks
),
report as (
  select check_no, check_name, passed, evidence from checks
  union all
  select 999,
    case when passed_count=total_count
      then format('POSTLAUNCH_BATCH2_FINAL_DATABASE_ACCEPTANCE: PASS (%s/%s)', passed_count,total_count)
      else format('POSTLAUNCH_BATCH2_FINAL_DATABASE_ACCEPTANCE: FAIL (%s/%s)', passed_count,total_count)
    end,
    passed_count=total_count,
    'Items 5, 8, 11, 13, 14 database contracts; Items 3 and 4 preserved by source/browser regression gates'
  from summary
)
select
  case when check_no=999 then 'SUMMARY' else check_no::text end as check_no,
  check_name,
  case when passed then 'PASS' else 'FAIL' end as result,
  evidence
from report
order by check_no;
