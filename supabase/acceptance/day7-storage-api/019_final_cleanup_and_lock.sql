-- ============================================================================
-- StayQR v1.0
-- Day 7 SQL 019 — Final Storage Audit Cleanup and Lock Verification
--
-- PURPOSE
-- Removes all temporary Day 7 full-CRUD/Storage audit database objects after:
--   - SQL 018 restored the Platform Admin and staff snapshots;
--   - the browser Storage API audit completed 25/25;
--   - the evidence JSON was downloaded.
--
-- PERMANENT SECURITY CHANGES RETAINED
--   - Migration 016 authenticated permission for the Storage path parser.
--   - All tenant RLS policies.
--   - All eight private Storage policies.
--
-- Run once in Supabase SQL Editor with role: postgres.
-- Expected: exactly 12 rows and every passed value = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:day7:storage-api-audit:sql019:20260727')
);

do $pre_cleanup$
declare
  context_phase text;
  actor_id uuid := 'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid;
begin
  if to_regclass(
    'private.day7_storage_api_audit_context_20260727'
  ) is not null then
    select phase
    into context_phase
    from private.day7_storage_api_audit_context_20260727
    where context_key = 'day7-storage-api';

    if context_phase is distinct from 'isolation-complete' then
      raise exception
        'SQL 019 refused cleanup: expected context phase isolation-complete, found %.',
        coalesce(context_phase, 'NOT FOUND');
    end if;
  end if;

  if not exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = actor_id
      and pa.status = 'active'
  ) then
    raise exception
      'SQL 019 refused cleanup: Platform Admin restoration is not active.';
  end if;

  if exists (
    select 1
    from storage.objects o
    where o.name like '%/day7-isolation/%'
  ) then
    raise exception
      'SQL 019 refused cleanup: residual Day 7 Storage API fixture objects remain.';
  end if;
end;
$pre_cleanup$;

drop function if exists
  private.run_day7_full_crud_storage_isolation_20260726();

drop function if exists
  private.run_day7_full_crud_storage_isolation_rev2_20260726();

drop table if exists
  private.day7_storage_api_audit_context_20260727;

commit;

with checks(test_name, passed, details) as (
  values
    (
      '01_storage_audit_context_removed',
      to_regclass(
        'private.day7_storage_api_audit_context_20260727'
      ) is null,
      'Temporary SQL 017/018 Storage audit context table is absent.'
    ),
    (
      '02_audit_042_rev1_helper_removed',
      to_regprocedure(
        'private.run_day7_full_crud_storage_isolation_20260726()'
      ) is null,
      'Audit 042 original private helper is absent.'
    ),
    (
      '03_audit_042_rev2_helper_removed',
      to_regprocedure(
        'private.run_day7_full_crud_storage_isolation_rev2_20260726()'
      ) is null,
      'Audit 042 REV2 private helper is absent.'
    ),
    (
      '04_platform_admin_restored',
      exists (
        select 1
        from public.platform_admins pa
        where pa.user_id =
          'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid
          and pa.status = 'active'
      ),
      'The Storage audit actor is restored as an active Platform Admin.'
    ),
    (
      '05_no_active_hotel_b_staff_access',
      not exists (
        select 1
        from public.staff s
        where s.auth_user_id =
          'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid
          and s.hotel_id =
          '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid
          and s.status = 'active'
      ),
      'The audit actor has no active Hotel Apex Stay Inn staff access.'
    ),
    (
      '06_no_storage_audit_objects_remain',
      not exists (
        select 1
        from storage.objects o
        where o.name like '%/day7-isolation/%'
      ),
      'No Day 7 Storage API fixture or positive-control object remains.'
    ),
    (
      '07_storage_helper_authenticated_only',
      has_schema_privilege('authenticated', 'private', 'USAGE')
      and has_function_privilege(
        'authenticated',
        'private.storage_object_hotel_id(text)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'private.storage_object_hotel_id(text)',
        'EXECUTE'
      ),
      'Storage path parsing is executable by authenticated policy evaluation, not anon.'
    ),
    (
      '08_all_tenant_tables_have_rls',
      not exists (
        select 1
        from information_schema.columns col
        join pg_class c
          on c.relname = col.table_name
        join pg_namespace n
          on n.oid = c.relnamespace
         and n.nspname = col.table_schema
        where col.table_schema = 'public'
          and col.column_name = 'hotel_id'
          and c.relkind in ('r', 'p')
          and not c.relrowsecurity
      ),
      'Every public tenant table carrying hotel_id still has RLS enabled.'
    ),
    (
      '09_no_anonymous_table_access',
      not exists (
        select 1
        from information_schema.role_table_grants
        where table_schema = 'public'
          and grantee = 'anon'
      )
      and not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and roles && array['anon'::name, 'public'::name]
      ),
      'Anonymous users retain no direct public-table grants or policies.'
    ),
    (
      '10_only_approved_anonymous_rpcs',
      not exists (
        select distinct rp.routine_name
        from information_schema.routine_privileges rp
        where rp.routine_schema = 'public'
          and rp.grantee = 'anon'
          and rp.privilege_type = 'EXECUTE'
        except
        select unnest(array[
          'resolve_guest_portal',
          'get_guest_service_requests',
          'create_guest_service_request',
          'get_guest_food_menu',
          'get_guest_food_orders',
          'place_guest_food_order'
        ]::text[])
      )
      and not exists (
        select unnest(array[
          'resolve_guest_portal',
          'get_guest_service_requests',
          'create_guest_service_request',
          'get_guest_food_menu',
          'get_guest_food_orders',
          'place_guest_food_order'
        ]::text[])
        except
        select distinct rp.routine_name
        from information_schema.routine_privileges rp
        where rp.routine_schema = 'public'
          and rp.grantee = 'anon'
          and rp.privilege_type = 'EXECUTE'
      ),
      'Anonymous execution remains restricted to the six approved guest RPCs.'
    ),
    (
      '11_private_storage_policy_matrix_intact',
      (
        select count(*) = 2
        from storage.buckets
        where id in ('hotel-assets', 'guest-documents')
          and public = false
      )
      and (
        select count(*) = 8
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname in (
            'stayqr_hotel_assets_select',
            'stayqr_hotel_assets_insert',
            'stayqr_hotel_assets_update',
            'stayqr_hotel_assets_delete',
            'stayqr_guest_documents_select',
            'stayqr_guest_documents_insert',
            'stayqr_guest_documents_update',
            'stayqr_guest_documents_delete'
          )
      ),
      'Both StayQR buckets are private and all eight scoped policies remain.'
    ),
    (
      '12_guest_token_binding_consistent',
      not exists (
        select 1
        from public.guest_access_tokens t
        join public.guest_sessions gs
          on gs.id = t.guest_session_id
        join public.rooms r
          on r.id = t.room_id
        where t.hotel_id <> gs.hotel_id
           or t.room_id <> gs.room_id
           or t.hotel_id <> r.hotel_id
      ),
      'Guest tokens remain bound to the correct hotel, room and stay.'
    )
)
select test_name, passed, details
from checks
order by test_name;
