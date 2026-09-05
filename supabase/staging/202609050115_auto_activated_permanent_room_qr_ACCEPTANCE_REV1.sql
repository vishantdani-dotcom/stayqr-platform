-- StayQR Final Product Freeze REV9 / Migration 115 acceptance
with defs as (
  select
    pg_get_functiondef('public.resolve_permanent_room_qr(uuid)'::regprocedure) as resolver_def,
    pg_get_functiondef('public.resolve_permanent_room_qr(uuid,text)'::regprocedure) as legacy_pin_def,
    pg_get_functiondef('public.get_permanent_room_qr_links(uuid)'::regprocedure) as links_def,
    pg_get_functiondef('public.regenerate_permanent_room_qr(uuid,uuid)'::regprocedure) as regenerate_def
), checks as (
  select '01_ZERO_PIN_RESOLVER_EXISTS' check_name,
    to_regprocedure('public.resolve_permanent_room_qr(uuid)') is not null ok
  union all
  select '02_ZERO_PIN_RESOLVER_ANON_ALLOWED',
    has_function_privilege('anon','public.resolve_permanent_room_qr(uuid)','EXECUTE')
  union all
  select '03_LEGACY_PIN_FALLBACK_PRESERVED',
    to_regprocedure('public.resolve_permanent_room_qr(uuid,text)') is not null
  union all
  select '04_ZERO_PIN_RESOLVER_HAS_NO_PIN_CHALLENGE',
    resolver_def not ilike '%room_qr_pin_challenges%' and resolver_def not ilike '%p_pin%'
  from defs
  union all
  select '05_ACTIVE_STAY_REQUIRED',
    resolver_def ilike '%guest_sessions%' and resolver_def ilike '%status = ''active''%' and resolver_def ilike '%checkout_time%'
  from defs
  union all
  select '06_SIGNED_TOKEN_LIFECYCLE_PRESERVED',
    resolver_def ilike '%guest_access_tokens%' and resolver_def ilike '%private.render_guest_access_token%' and resolver_def ilike '%private.issue_guest_access_token%'
  from defs
  union all
  select '07_REVOKE_AND_EXPIRY_AUTHORITATIVE',
    resolver_def ilike '%v_token.status <> ''active''%' and resolver_def ilike '%v_token.expires_at <= now()%'
  from defs
  union all
  select '08_ROOM_QR_TABLE_NOT_EXPOSED_TO_ANON',
    not has_table_privilege('anon','public.room_qr_codes','SELECT')
  union all
  select '09_DIRECTORY_IS_AUTO_ACCESS_AWARE',
    links_def ilike '%auto_access_enabled%' and links_def ilike '%occupant_count%' and links_def ilike '%access_active%'
  from defs
  union all
  select '10_REGENERATE_AUTH_ONLY',
    has_function_privilege('authenticated','public.regenerate_permanent_room_qr(uuid,uuid)','EXECUTE')
    and not has_function_privilege('anon','public.regenerate_permanent_room_qr(uuid,uuid)','EXECUTE')
  union all
  select '11_REGENERATE_PERMISSION_AND_AUDIT',
    regenerate_def ilike '%private.user_has_permission%' and regenerate_def ilike '%private.write_activity_log%'
  from defs
  union all
  select '12_PERMANENT_ROOM_CODES_UNIQUE',
    not exists (
      select 1
      from public.room_qr_codes q
      group by q.public_code
      having count(*) > 1
    )
)
select check_name, case when ok then 'PASS' else 'FAIL' end status
from checks
order by check_name;
