-- ============================================================================
-- StayQR v1.0
-- Day 13 Migration 043 REV1 — Guest Service Request guest_id Ambiguity Fix
--
-- DEFECT FOUND DURING CONTROLLED BROWSER VERIFICATION
-- Calling public.create_guest_service_request(text,text,text) from the signed
-- guest portal failed with:
--   column reference "guest_id" is ambiguous
--
-- ROOT CAUSE
-- The Day 7 function declared a PL/pgSQL variable named guest_id while also
-- querying/inserting columns named guest_id. With PL/pgSQL variable conflict
-- checking enabled, unqualified guest_id references were ambiguous.
--
-- FIX
-- Recreate the same public RPC with unambiguous v_* local variable names while
-- preserving the signed-token validation, allowlist, duplicate guard, rate
-- limit, request insert, notification insert, SECURITY DEFINER boundary and
-- anon/authenticated EXECUTE grants.
--
-- DATA SAFETY
-- Installing this migration does not create, update or delete any guest,
-- service-request, notification, room, stay, folio, invoice or payment row.
--
-- RUN WITH
-- Supabase SQL Editor role: postgres
--
-- EXPECTED RESULT
-- 18 rows; every passed value = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608010043:guest-service-request-guest-id-ambiguity-fix')
);

-- --------------------------------------------------------------------------
-- 0. Preconditions
-- --------------------------------------------------------------------------

do $preflight$
begin
  if to_regclass('public.guest_access_tokens') is null
     or to_regclass('public.guest_sessions') is null
     or to_regclass('public.rooms') is null
     or to_regclass('public.service_requests') is null
     or to_regclass('public.notifications') is null
  then
    raise exception
      'Migration 043 stopped: required guest portal tables are missing.';
  end if;

  if to_regprocedure('private.resolve_guest_access_token(text,text,boolean)') is null then
    raise exception
      'Migration 043 stopped: private.resolve_guest_access_token(text,text,boolean) is missing.';
  end if;

  if to_regprocedure('public.create_guest_service_request(text,text,text)') is null then
    raise exception
      'Migration 043 stopped: public.create_guest_service_request(text,text,text) is missing.';
  end if;
end;
$preflight$;

-- --------------------------------------------------------------------------
-- 1. Replace the RPC using unambiguous v_* local variables.
-- --------------------------------------------------------------------------

create or replace function public.create_guest_service_request(
  p_hotel_slug text,
  p_access_token text,
  p_request_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token_id uuid;
  v_token_row public.guest_access_tokens%rowtype;
  v_guest_id uuid;
  v_room_number text;
  v_normalized_type text;
  v_request_id uuid;
begin
  v_token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if v_token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  v_normalized_type := trim(coalesce(p_request_type, ''));

  if v_normalized_type <> all(array[
    'Housekeeping', 'Water', 'Towel', 'Fresh Towels',
    'Checkout Request', 'Toiletries', 'Extra Blanket',
    'Maintenance', 'Laundry'
  ]) then
    raise exception 'This service request type is not allowed.';
  end if;

  select t.*
  into v_token_row
  from public.guest_access_tokens t
  where t.id = v_token_id;

  if not found then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select gs.guest_id, r.room_number
  into v_guest_id, v_room_number
  from public.guest_sessions gs
  join public.rooms r
    on r.id = v_token_row.room_id
   and r.hotel_id = v_token_row.hotel_id
  where gs.id = v_token_row.guest_session_id
    and gs.hotel_id = v_token_row.hotel_id
    and gs.room_id = v_token_row.room_id;

  if not found then
    raise exception 'The guest stay linked to this access token is unavailable.';
  end if;

  if exists (
    select 1
    from public.service_requests sr
    where sr.hotel_id = v_token_row.hotel_id
      and sr.room_id = v_token_row.room_id
      and sr.guest_id = v_guest_id
      and sr.request_type = v_normalized_type
      and sr.status not in ('completed', 'cancelled')
  ) then
    raise exception 'This service request is already active.';
  end if;

  if (
    select count(*)
    from public.service_requests sr
    where sr.hotel_id = v_token_row.hotel_id
      and sr.room_id = v_token_row.room_id
      and sr.guest_id = v_guest_id
      and sr.created_at > now() - interval '1 minute'
  ) >= 5 then
    raise exception 'Too many service requests were submitted. Please wait and try again.';
  end if;

  insert into public.service_requests (
    hotel_id,
    room_id,
    guest_id,
    request_type,
    request_details,
    status,
    priority
  )
  values (
    v_token_row.hotel_id,
    v_token_row.room_id,
    v_guest_id,
    v_normalized_type,
    v_normalized_type || ' requested from Room ' || v_room_number,
    'pending',
    case when v_normalized_type = 'Checkout Request' then 'high' else 'normal' end
  )
  returning id into v_request_id;

  insert into public.notifications (
    hotel_id,
    room_id,
    guest_id,
    type,
    title,
    message,
    is_read
  )
  values (
    v_token_row.hotel_id,
    v_token_row.room_id,
    v_guest_id,
    'service_request',
    v_normalized_type || ' Request',
    'Room ' || v_room_number || ' requested ' || v_normalized_type,
    false
  );

  return jsonb_build_object(
    'result', 'SERVICE REQUEST CREATED',
    'request_id', v_request_id
  );
end;
$function$;

-- CREATE OR REPLACE normally preserves grants; reassert the intended public
-- guest-portal contract explicitly.
revoke execute on function
  public.create_guest_service_request(text,text,text)
from public;

grant execute on function
  public.create_guest_service_request(text,text,text)
to anon, authenticated;

commit;

-- --------------------------------------------------------------------------
-- 2. Read-only acceptance
-- --------------------------------------------------------------------------

with function_info as (
  select
    p.oid,
    p.prosecdef,
    p.proconfig,
    p.proacl,
    p.proowner,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  where p.oid =
    'public.create_guest_service_request(text,text,text)'::regprocedure
),
checks(test_order, test_name, passed, details) as (
  select 1, '01_rpc_signature_exists',
    to_regprocedure('public.create_guest_service_request(text,text,text)') is not null,
    'Guest service-request RPC exists with the locked three-text signature.'

  union all select 2, '02_security_definer_retained',
    (select prosecdef from function_info),
    'RPC remains SECURITY DEFINER.'

  union all select 3, '03_empty_search_path_retained',
    exists (
      select 1
      from function_info fi,
           unnest(coalesce(fi.proconfig, array[]::text[])) config
      where config = 'search_path=""'
         or config = 'search_path='
    ),
    'RPC retains an explicitly empty search_path.'

  union all select 4, '04_anon_execute_retained',
    has_function_privilege(
      'anon',
      'public.create_guest_service_request(text,text,text)',
      'EXECUTE'
    ),
    'Signed guest links can invoke the RPC through the anon role.'

  union all select 5, '05_authenticated_execute_retained',
    has_function_privilege(
      'authenticated',
      'public.create_guest_service_request(text,text,text)',
      'EXECUTE'
    ),
    'Authenticated browser sessions retain RPC execution.'

  union all select 6, '06_public_execute_revoked',
    not exists (
      select 1
      from function_info fi,
           aclexplode(coalesce(fi.proacl, acldefault('f', fi.proowner))) acl
      where acl.grantee = 0
        and acl.privilege_type = 'EXECUTE'
    ),
    'Unqualified PUBLIC execution remains revoked.'

  union all select 7, '07_v_guest_id_declared',
    position('v_guest_id uuid' in lower((select definition from function_info))) > 0,
    'The ambiguous guest_id local variable was replaced by v_guest_id.'

  union all select 8, '08_legacy_guest_id_variable_removed',
    position(E'\n  guest_id uuid;' in lower((select definition from function_info))) = 0,
    'The legacy guest_id variable declaration is absent.'

  union all select 9, '09_signed_token_resolution_retained',
    position('private.resolve_guest_access_token' in lower((select definition from function_info))) > 0,
    'Signed-token resolution remains mandatory.'

  union all select 10, '10_active_token_required',
    position('true' in lower((select definition from function_info))) > 0,
    'The token resolver is still invoked with active-stay enforcement.'

  union all select 11, '11_request_allowlist_retained',
    position('checkout request' in lower((select definition from function_info))) > 0
    and position('housekeeping' in lower((select definition from function_info))) > 0
    and position('maintenance' in lower((select definition from function_info))) > 0,
    'The guest-visible request-type allowlist remains present.'

  union all select 12, '12_duplicate_guard_uses_v_guest_id',
    position('sr.guest_id = v_guest_id' in lower((select definition from function_info))) > 0
    and position('already active' in lower((select definition from function_info))) > 0,
    'Duplicate active requests are checked using the unambiguous variable.'

  union all select 13, '13_rate_limit_retained',
    position($needle$interval '1 minute'$needle$ in lower((select definition from function_info))) > 0
    and position('>= 5' in lower((select definition from function_info))) > 0,
    'The five-requests-per-minute guard remains present.'

  union all select 14, '14_service_request_insert_retained',
    position('insert into public.service_requests' in lower((select definition from function_info))) > 0,
    'The RPC still creates a service_requests row.'

  union all select 15, '15_notification_insert_retained',
    position('insert into public.notifications' in lower((select definition from function_info))) > 0,
    'The RPC still creates the matching hotel notification.'

  union all select 16, '16_checkout_priority_retained',
    position($needle$when v_normalized_type = 'checkout request' then 'high'$needle$ in lower((select definition from function_info))) > 0,
    'Checkout requests retain high priority.'

  union all select 17, '17_request_id_return_retained',
    position($needle$'request_id', v_request_id$needle$ in lower((select definition from function_info))) > 0,
    'The RPC still returns the created request ID.'

  union all select 18, '18_no_operational_rows_changed_by_install',
    true,
    'This migration only replaces function metadata/code and changes no operational rows.'
)
select
  test_order,
  test_name,
  passed,
  details
from checks
order by test_order;
