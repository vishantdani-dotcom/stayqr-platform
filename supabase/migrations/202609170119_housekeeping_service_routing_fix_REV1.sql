-- StayQR HOUSEKEEPING SERVICE ROUTING FIX — REV1
-- Migration: 202609170119
--
-- Scope:
--   Fix the built-in Housekeeping guest-service catalogue rows that were seeded
--   with service_request_types.department = 'guest_services' by the older
--   onboarding seed. Migration 118 correctly isolates departments, so those
--   misclassified requests no longer reached the Housekeeping account.
--
-- STRICT LOCK:
--   * Restaurant routing is NOT changed.
--   * Dashboard/global-observer routing is NOT changed.
--   * Notification helper from Migration 118 is NOT replaced.
--   * Navbar, Service Worker, ringtone code, Background Push edge function,
--     Guest Guide UI, QR, billing, RLS and hotel/demo data are NOT changed.
--
-- Fix:
--   * Built-in code "housekeeping" -> department "housekeeping"
--   * Built-in code "towel"        -> department "housekeeping"
--   * Built-in code "checkout-request" -> department "front_office"
--   * Built-in "water" remains guest_services.
--   * Existing OPEN requests tied to those built-in types are reconciled to the
--     corrected department. Completed/cancelled history is left untouched.
--   * A narrow BEFORE trigger prevents future onboarding/default inserts from
--     recreating the same misclassification, but only when the row still uses
--     the legacy default department "guest_services".
--
-- Transactional: any failure rolls back everything.

begin;

do $preflight$
begin
  if to_regclass('public.service_request_types') is null
     or to_regclass('public.service_requests') is null
  then
    raise exception 'Migration 119 stopped: service request tables are missing.';
  end if;

  if to_regprocedure(
       'private.day118_role_can_receive_notification(text,text,jsonb,text)'
     ) is null
  then
    raise exception 'Migration 119 stopped: accepted Migration 118 routing helper is missing.';
  end if;

  -- Prove the already-working Restaurant and Dashboard routing contracts before
  -- this migration does anything.
  if not private.day118_role_can_receive_notification(
    'food_order.created',
    'food_order',
    '{"department":"restaurant"}'::jsonb,
    'restaurant'
  ) then
    raise exception 'Migration 119 stopped: Restaurant food routing baseline is not healthy.';
  end if;

  if private.day118_role_can_receive_notification(
    'service_request.created',
    'service_request',
    '{"department":"housekeeping"}'::jsonb,
    'restaurant'
  ) then
    raise exception 'Migration 119 stopped: Restaurant housekeeping isolation baseline is not healthy.';
  end if;

  if not private.day118_role_can_receive_notification(
    'service_request.created',
    'service_request',
    '{"department":"housekeeping"}'::jsonb,
    'owner'
  ) then
    raise exception 'Migration 119 stopped: Dashboard/global observer baseline is not healthy.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Future-proof only the built-in default service codes.
--    Hotel-customised departments are preserved because this only rewrites the
--    old "guest_services" default.
-- ---------------------------------------------------------------------------
create or replace function private.day119_normalize_builtin_service_department()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_code text := lower(trim(coalesce(new.code, '')));
  v_department text := lower(trim(coalesce(new.department, 'guest_services')));
begin
  if v_department = 'guest_services' then
    if v_code in ('housekeeping', 'towel') then
      new.department := 'housekeeping';
    elsif v_code = 'checkout-request' then
      new.department := 'front_office';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function
  private.day119_normalize_builtin_service_department()
from public, anon, authenticated;

drop trigger if exists
  day119_normalize_builtin_service_department
on public.service_request_types;

create trigger day119_normalize_builtin_service_department
before insert or update of code, department
on public.service_request_types
for each row
execute function private.day119_normalize_builtin_service_department();

-- ---------------------------------------------------------------------------
-- 2. Correct existing catalogue rows only where they still have the legacy
--    guest_services default. This preserves intentional hotel customisation.
-- ---------------------------------------------------------------------------
update public.service_request_types
set
  department = 'housekeeping',
  updated_at = now()
where lower(trim(code)) in ('housekeeping', 'towel')
  and lower(trim(department)) = 'guest_services';

update public.service_request_types
set
  department = 'front_office',
  updated_at = now()
where lower(trim(code)) = 'checkout-request'
  and lower(trim(department)) = 'guest_services';

-- ---------------------------------------------------------------------------
-- 3. Reconcile only OPEN operational requests tied to those built-in types.
--    Completed/cancelled history is intentionally not rewritten.
--    Day 17 emits no new server event because status is unchanged.
-- ---------------------------------------------------------------------------
update public.service_requests sr
set
  department = srt.department,
  updated_at = now()
from public.service_request_types srt
where sr.request_type_id = srt.id
  and sr.hotel_id = srt.hotel_id
  and lower(trim(sr.department)) = 'guest_services'
  and lower(trim(srt.code)) in ('housekeeping', 'towel', 'checkout-request')
  and sr.status not in ('completed', 'cancelled');

-- ---------------------------------------------------------------------------
-- 4. Acceptance.
-- ---------------------------------------------------------------------------
do $acceptance$
declare
  v_trigger_count integer;
begin
  if exists (
    select 1
    from public.service_request_types
    where lower(trim(code)) in ('housekeeping', 'towel')
      and lower(trim(department)) <> 'housekeeping'
  ) then
    raise exception 'Migration 119 acceptance failed: a built-in Housekeeping/Towel type is still misrouted.';
  end if;

  if exists (
    select 1
    from public.service_request_types
    where lower(trim(code)) = 'checkout-request'
      and lower(trim(department)) <> 'front_office'
  ) then
    raise exception 'Migration 119 acceptance failed: built-in Checkout Request is still misrouted.';
  end if;

  if exists (
    select 1
    from public.service_requests sr
    join public.service_request_types srt
      on srt.id = sr.request_type_id
     and srt.hotel_id = sr.hotel_id
    where sr.status not in ('completed', 'cancelled')
      and lower(trim(srt.code)) in ('housekeeping', 'towel')
      and lower(trim(sr.department)) <> 'housekeeping'
  ) then
    raise exception 'Migration 119 acceptance failed: an open built-in Housekeeping request is still misrouted.';
  end if;

  select count(*)
  into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal
    and n.nspname = 'public'
    and c.relname = 'service_request_types'
    and t.tgname = 'day119_normalize_builtin_service_department'
    and t.tgenabled = 'O';

  if v_trigger_count <> 1 then
    raise exception 'Migration 119 acceptance failed: built-in service department guard is missing/disabled.';
  end if;

  -- Re-prove the two locked paths and the repaired Housekeeping path.
  if not private.day118_role_can_receive_notification(
    'food_order.created',
    'food_order',
    '{"department":"restaurant"}'::jsonb,
    'restaurant'
  ) then
    raise exception 'Migration 119 acceptance failed: Restaurant food routing regressed.';
  end if;

  if private.day118_role_can_receive_notification(
    'service_request.created',
    'service_request',
    '{"department":"housekeeping"}'::jsonb,
    'restaurant'
  ) then
    raise exception 'Migration 119 acceptance failed: Restaurant received Housekeeping routing.';
  end if;

  if not private.day118_role_can_receive_notification(
    'service_request.created',
    'service_request',
    '{"department":"housekeeping"}'::jsonb,
    'housekeeping'
  ) then
    raise exception 'Migration 119 acceptance failed: Housekeeping routing is not allowed.';
  end if;

  if not private.day118_role_can_receive_notification(
    'service_request.created',
    'service_request',
    '{"department":"housekeeping"}'::jsonb,
    'owner'
  ) then
    raise exception 'Migration 119 acceptance failed: Dashboard/global observer regressed.';
  end if;
end;
$acceptance$;

commit;

select jsonb_build_object(
  'status', 'HOUSEKEEPING_SERVICE_ROUTING_REV1_PASSED',
  'restaurant_food_locked',
    private.day118_role_can_receive_notification(
      'food_order.created',
      'food_order',
      '{"department":"restaurant"}'::jsonb,
      'restaurant'
    ),
  'restaurant_housekeeping_blocked',
    not private.day118_role_can_receive_notification(
      'service_request.created',
      'service_request',
      '{"department":"housekeeping"}'::jsonb,
      'restaurant'
    ),
  'housekeeping_housekeeping_allowed',
    private.day118_role_can_receive_notification(
      'service_request.created',
      'service_request',
      '{"department":"housekeeping"}'::jsonb,
      'housekeeping'
    ),
  'dashboard_global_observer_locked',
    private.day118_role_can_receive_notification(
      'service_request.created',
      'service_request',
      '{"department":"housekeeping"}'::jsonb,
      'owner'
    ),
  'housekeeping_catalogue_rows', (
    select count(*)
    from public.service_request_types
    where lower(trim(code)) in ('housekeeping', 'towel')
      and lower(trim(department)) = 'housekeeping'
  ),
  'guard_trigger_enabled', exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'public'
      and c.relname = 'service_request_types'
      and t.tgname = 'day119_normalize_builtin_service_department'
      and t.tgenabled = 'O'
  )
) as final_acceptance;
