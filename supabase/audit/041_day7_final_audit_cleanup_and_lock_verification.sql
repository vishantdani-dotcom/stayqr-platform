-- ============================================================================
-- StayQR v1.0
-- Day 7 Audit 041 — Final Isolation Audit Cleanup and Lock Verification
--
-- PURPOSE
-- Removes the restricted private audit helper functions created by Audit 040
-- revisions and confirms that the production security state still satisfies
-- the Day 7 exit gate after cleanup.
--
-- Run once in Supabase SQL Editor with role: postgres.
-- Expected: exactly 8 rows and every passed value = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:day7:final-audit-cleanup-lock:20260726')
);

drop function if exists
  private.run_day7_hotel_isolation_exit_gate_20260726();

drop function if exists
  private.run_day7_hotel_isolation_exit_gate_rev4_20260726();

drop function if exists
  private.run_day7_hotel_isolation_exit_gate_rev5_20260726();

commit;

with checks(test_name, passed, details) as (
  values
    (
      '01_rev3_audit_helper_removed',
      to_regprocedure(
        'private.run_day7_hotel_isolation_exit_gate_20260726()'
      ) is null,
      'Audit 040 REV3 helper is absent from production.'
    ),
    (
      '02_rev4_audit_helper_removed',
      to_regprocedure(
        'private.run_day7_hotel_isolation_exit_gate_rev4_20260726()'
      ) is null,
      'Audit 040 REV4 helper is absent from production.'
    ),
    (
      '03_rev5_audit_helper_removed',
      to_regprocedure(
        'private.run_day7_hotel_isolation_exit_gate_rev5_20260726()'
      ) is null,
      'Audit 040 REV5 helper is absent from production.'
    ),
    (
      '04_all_tenant_tables_still_have_rls',
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
      '05_no_anonymous_table_access',
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
      '06_only_approved_anonymous_rpcs',
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
      '07_guest_token_binding_consistent',
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
      'All guest tokens remain bound to the correct hotel, room and stay.'
    ),
    (
      '08_private_storage_matrix_intact',
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
      'Both private storage buckets and all eight scoped policies remain intact.'
    )
)
select test_name, passed, details
from checks
order by test_name;
