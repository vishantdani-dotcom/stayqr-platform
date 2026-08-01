-- ============================================================================
-- StayQR v1.0
-- Day 7 Migration 016
-- Fix Supabase Storage policy helper execution
--
-- ROOT CAUSE
-- The eight Storage RLS policies call:
--   private.storage_object_hotel_id(name)
--
-- Migration 013 revoked EXECUTE on that helper from authenticated. PostgreSQL
-- therefore rejected Storage policy evaluation with:
--   42501: permission denied for function storage_object_hotel_id
--
-- SECURITY
-- - The helper only parses the first folder segment as a UUID.
-- - It reads no table, secret or user data.
-- - EXECUTE is granted only to authenticated.
-- - anon and PUBLIC remain denied.
--
-- Run once in Supabase SQL Editor with role: postgres.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607260016:storage-policy-helper-execute')
);

create or replace function private.storage_object_hotel_id(object_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  first_folder text;
begin
  first_folder := split_part(coalesce(object_name, ''), '/', 1);

  begin
    return first_folder::uuid;
  exception when others then
    return null;
  end;
end;
$$;

revoke all on function private.storage_object_hotel_id(text)
from public, anon, authenticated;

grant execute on function private.storage_object_hotel_id(text)
to authenticated;

comment on function private.storage_object_hotel_id(text) is
  'Parses the hotel UUID from the first Storage object path segment. Authenticated execution is required only for Storage RLS policy evaluation.';

do $verify$
declare
  sample_id uuid := gen_random_uuid();
begin
  if not has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception
      'Migration 016 failed: authenticated lacks USAGE on private schema.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'private.storage_object_hotel_id(text)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 016 failed: authenticated cannot execute Storage helper.';
  end if;

  if has_function_privilege(
    'anon',
    'private.storage_object_hotel_id(text)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 016 failed: anon unexpectedly has Storage helper access.';
  end if;

  if private.storage_object_hotel_id(
    sample_id::text || '/day7-verification/file.txt'
  ) is distinct from sample_id then
    raise exception
      'Migration 016 failed: valid hotel-folder parsing is incorrect.';
  end if;

  if private.storage_object_hotel_id(
    'not-a-hotel/day7-verification/file.txt'
  ) is not null then
    raise exception
      'Migration 016 failed: invalid hotel-folder parsing must return null.';
  end if;
end;
$verify$;

commit;
