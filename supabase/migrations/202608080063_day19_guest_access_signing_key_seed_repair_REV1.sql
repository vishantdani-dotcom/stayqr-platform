-- ============================================================================
-- StayQR v1.0
-- Day 19 Migration 063 REV1
-- Guest Access Signing-Key Seed Repair
-- Date: 2026-08-08
--
-- PURPOSE
-- Restore the Day 7 invariant that private.guest_access_signing_keys contains
-- exactly one active 32-byte signing key after a fresh canonical database build.
--
-- ROOT CAUSE
-- The Day 18 canonical schema rebuild preserved the signing-key table and token
-- lifecycle objects, but data-only seed state was not present on the fresh
-- Staging database. Without an active signing key, guest token issuance fails.
--
-- SAFETY
-- - Forward-only and idempotent.
-- - Does not edit Day 18 migrations 060/061 or Day 19 migration 062.
-- - If one active key already exists, no new key is inserted.
-- - If more than one active key exists, the migration aborts rather than guessing.
-- - Never exposes the signing secret in acceptance output.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '60s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608080063:guest-access-signing-key-seed-repair')
);

-- ============================================================================
-- 1. PRECONDITIONS
-- ============================================================================

do $preflight$
begin
  if to_regnamespace('private') is null then
    raise exception
      'Migration 063: required schema private is missing.';
  end if;

  if to_regclass('private.guest_access_signing_keys') is null then
    raise exception
      'Migration 063: private.guest_access_signing_keys is missing.';
  end if;

  if to_regnamespace('extensions') is null then
    raise exception
      'Migration 063: required schema extensions is missing.';
  end if;

  if to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception
      'Migration 063: extensions.gen_random_bytes(integer) is missing.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'guest_access_signing_keys'
      and column_name = 'secret'
      and data_type = 'bytea'
  ) then
    raise exception
      'Migration 063: signing-key secret column contract is missing.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'guest_access_signing_keys'
      and column_name = 'status'
  ) then
    raise exception
      'Migration 063: signing-key status column contract is missing.';
  end if;
end;
$preflight$;


-- ============================================================================
-- 2. REFUSE AMBIGUOUS/BROKEN MULTI-ACTIVE STATE
-- ============================================================================

do $guard$
declare
  v_active_count integer;
begin
  select count(*)
  into v_active_count
  from private.guest_access_signing_keys
  where status = 'active';

  if v_active_count > 1 then
    raise exception
      'Migration 063: expected at most one active signing key before repair, found %.',
      v_active_count;
  end if;
end;
$guard$;


-- ============================================================================
-- 3. PRESERVE THE DAY 7 EXACTLY-ONE-ACTIVE DATABASE INVARIANT
-- ============================================================================

create unique index if not exists uq_guest_access_one_active_signing_key
on private.guest_access_signing_keys ((status))
where status = 'active';


-- ============================================================================
-- 4. IDEMPOTENT SEED REPAIR
-- ============================================================================

insert into private.guest_access_signing_keys (
  secret,
  status
)
select
  extensions.gen_random_bytes(32),
  'active'
where not exists (
  select 1
  from private.guest_access_signing_keys
  where status = 'active'
);


-- ============================================================================
-- 5. KEEP SIGNING MATERIAL OUT OF BROWSER ROLES
-- ============================================================================

revoke all on private.guest_access_signing_keys
from public, anon, authenticated;


-- ============================================================================
-- 6. VERIFY BEFORE COMMIT
-- ============================================================================

do $verify$
declare
  v_active_count integer;
  v_bad_secret_count integer;
  v_retired_active_count integer;
begin
  select count(*)
  into v_active_count
  from private.guest_access_signing_keys
  where status = 'active';

  if v_active_count <> 1 then
    raise exception
      'Migration 063 verification failed: expected exactly 1 active signing key, found %.',
      v_active_count;
  end if;

  select count(*)
  into v_bad_secret_count
  from private.guest_access_signing_keys k
  where k.status = 'active'
    and octet_length(k.secret) <> 32;

  if v_bad_secret_count <> 0 then
    raise exception
      'Migration 063 verification failed: active signing key is not 32 bytes.';
  end if;

  select count(*)
  into v_retired_active_count
  from private.guest_access_signing_keys k
  where k.status = 'active'
    and k.retired_at is not null;

  if v_retired_active_count <> 0 then
    raise exception
      'Migration 063 verification failed: active signing key has retired_at set.';
  end if;

  if has_table_privilege(
    'anon',
    'private.guest_access_signing_keys',
    'SELECT'
  )
  or has_table_privilege(
    'anon',
    'private.guest_access_signing_keys',
    'INSERT'
  )
  or has_table_privilege(
    'anon',
    'private.guest_access_signing_keys',
    'UPDATE'
  )
  or has_table_privilege(
    'anon',
    'private.guest_access_signing_keys',
    'DELETE'
  ) then
    raise exception
      'Migration 063 verification failed: anon retains signing-key table privileges.';
  end if;

  if has_table_privilege(
    'authenticated',
    'private.guest_access_signing_keys',
    'SELECT'
  )
  or has_table_privilege(
    'authenticated',
    'private.guest_access_signing_keys',
    'INSERT'
  )
  or has_table_privilege(
    'authenticated',
    'private.guest_access_signing_keys',
    'UPDATE'
  )
  or has_table_privilege(
    'authenticated',
    'private.guest_access_signing_keys',
    'DELETE'
  ) then
    raise exception
      'Migration 063 verification failed: authenticated retains signing-key table privileges.';
  end if;
end;
$verify$;

commit;


-- ============================================================================
-- 7. POST-COMMIT ACCEPTANCE OUTPUT
-- Never return the secret itself.
-- Expected: one row, passed = true, active_signing_keys = 1, secret_bytes = 32.
-- ============================================================================

select
  (
    count(*) = 1
    and min(octet_length(secret)) = 32
    and max(octet_length(secret)) = 32
    and count(*) filter (where retired_at is not null) = 0
  ) as passed,
  count(*) as active_signing_keys,
  min(octet_length(secret)) as secret_bytes,
  min(created_at) as active_key_created_at
from private.guest_access_signing_keys
where status = 'active';
