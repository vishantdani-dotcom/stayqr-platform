-- ============================================================================
-- StayQR v1.0
-- Day 8 Audit 047 — Backend Runtime Cleanup and Frontend Readiness Gate
--
-- PURPOSE
-- Removes the temporary private runtime-audit helpers created by Audits 044
-- and 046, then verifies that the permanent Day 8 onboarding/configuration
-- backend remains intact and ready for frontend integration.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Removes audit helpers only.
-- - Does not insert, update or delete hotel business data.
--
-- EXPECTED RESULT
-- Exactly 18 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:day8:audit047:backend-cleanup:20260727')
);

drop function if exists
  private.run_day8_atomic_onboarding_acceptance_20260727();

drop function if exists
  private.run_day8_configuration_runtime_acceptance_20260727();

drop function if exists
  private.run_day8_onboarding_preflight_20260727();

commit;

with required_rpcs(signature) as (
  values
    ('public.bootstrap_hotel_onboarding(jsonb)'),
    ('public.save_hotel_onboarding_step(uuid,text,jsonb)'),
    ('public.activate_hotel_trial(uuid,uuid,integer)'),
    ('public.get_hotel_onboarding_readiness(uuid)'),
    ('public.refresh_hotel_onboarding_readiness(uuid)'),
    ('public.seed_hotel_menu_defaults(uuid)'),
    ('public.seed_hotel_configuration_defaults(uuid)'),
    ('public.configure_hotel_inventory(uuid,jsonb)'),
    ('public.import_hotel_rooms(uuid,jsonb)')
),
checks(test_name, passed, details) as (
  values
    (
      '01_audit_044_helper_removed',
      to_regprocedure(
        'private.run_day8_atomic_onboarding_acceptance_20260727()'
      ) is null,
      'Temporary Audit 044 runtime helper is absent.'
    ),
    (
      '02_audit_046_helper_removed',
      to_regprocedure(
        'private.run_day8_configuration_runtime_acceptance_20260727()'
      ) is null,
      'Temporary Audit 046 runtime helper is absent.'
    ),
    (
      '03_preflight_helper_removed',
      to_regprocedure(
        'private.run_day8_onboarding_preflight_20260727()'
      ) is null,
      'Temporary Audit 043 preflight helper is absent.'
    ),
    (
      '04_day8_foundation_tables_present',
      to_regclass('public.hotel_settings') is not null
      and to_regclass('public.hotel_onboarding') is not null
      and to_regclass('public.floors') is not null
      and to_regclass('public.invoice_number_sequences') is not null
      and to_regclass('public.amenities') is not null
      and to_regclass('public.service_request_types') is not null,
      'All Day 8 foundation and configuration tables remain present.'
    ),
    (
      '05_all_required_day8_rpcs_present',
      not exists (
        select 1
        from required_rpcs r
        where to_regprocedure(r.signature) is null
      ),
      'All nine approved onboarding, trial, readiness, defaults, inventory and room-import RPCs remain installed.'
    ),
    (
      '06_authenticated_rpc_execution',
      not exists (
        select 1
        from required_rpcs r
        where not has_function_privilege(
          'authenticated',
          r.signature,
          'EXECUTE'
        )
      ),
      'Authenticated users retain execute permission on every approved Day 8 RPC.'
    ),
    (
      '07_anonymous_day8_rpc_execution_blocked',
      not exists (
        select 1
        from required_rpcs r
        where has_function_privilege(
          'anon',
          r.signature,
          'EXECUTE'
        )
      ),
      'Anonymous users cannot execute any Day 8 onboarding or configuration RPC.'
    ),
    (
      '08_new_tenant_tables_have_rls',
      (
        select bool_and(c.relrowsecurity)
        from pg_class c
        where c.oid in (
          'public.hotel_settings'::regclass,
          'public.hotel_onboarding'::regclass,
          'public.floors'::regclass,
          'public.invoice_number_sequences'::regclass,
          'public.amenities'::regclass,
          'public.service_request_types'::regclass
        )
      ),
      'Every Day 8 tenant-owned table has RLS enabled.'
    ),
    (
      '09_amenity_request_policy_matrix',
      (
        select count(*) = 8
        from pg_policies p
        where p.schemaname = 'public'
          and (
            (
              p.tablename = 'amenities'
              and p.policyname like 'stayqr_amenities_%'
            )
            or
            (
              p.tablename = 'service_request_types'
              and p.policyname like
                'stayqr_service_request_types_%'
            )
          )
      ),
      'Amenities and request categories retain complete CRUD policy matrices.'
    ),
    (
      '10_existing_menu_categories_normalized',
      not exists (
        select 1
        from public.menu_items mi
        where nullif(trim(mi.category), '') is not null
          and mi.category_id is null
      ),
      'Every existing text menu category remains linked to a normalized hotel-owned category.'
    ),
    (
      '11_existing_request_types_normalized',
      not exists (
        select 1
        from public.service_requests sr
        where nullif(trim(sr.request_type), '') is not null
          and sr.request_type_id is null
      ),
      'Every existing service request remains linked to a normalized hotel-owned request category.'
    ),
    (
      '12_existing_room_integrity',
      not exists (
        select 1
        from public.rooms r
        where r.room_type_id is null
           or r.floor_id is null
           or nullif(trim(r.room_number), '') is null
      ),
      'Every existing room remains linked to a room type and floor.'
    ),
    (
      '13_inventory_uniqueness_intact',
      not exists (
        select 1
        from (
          select r.hotel_id, lower(trim(r.room_number))
          from public.rooms r
          group by r.hotel_id, lower(trim(r.room_number))
          having count(*) > 1
        ) d
      )
      and not exists (
        select 1
        from (
          select rt.hotel_id, upper(trim(rt.code))
          from public.room_types rt
          group by rt.hotel_id, upper(trim(rt.code))
          having count(*) > 1
        ) d
      )
      and not exists (
        select 1
        from (
          select rp.hotel_id, upper(trim(rp.code))
          from public.rate_plans rp
          group by rp.hotel_id, upper(trim(rp.code))
          having count(*) > 1
        ) d
      ),
      'Room numbers, room-type codes and rate-plan codes remain unique within each hotel.'
    ),
    (
      '14_existing_hotels_have_configuration_defaults',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.amenities a
          where a.hotel_id = h.id
            and a.is_active
        )
        or not exists (
          select 1
          from public.service_request_types srt
          where srt.hotel_id = h.id
            and srt.is_active
        )
        or not exists (
          select 1
          from public.menu_categories mc
          where mc.hotel_id = h.id
            and mc.is_active
        )
      ),
      'Every existing hotel retains active amenity, request-category and menu-category defaults.'
    ),
    (
      '15_future_hotel_default_trigger_present',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid = 'public.hotels'::regclass
          and t.tgname =
            'seed_new_hotel_configuration_defaults_20260727'
          and not t.tgisinternal
      ),
      'Every future hotel will receive configuration defaults automatically.'
    ),
    (
      '16_onboarding_readiness_snapshots_present',
      not exists (
        select 1
        from public.hotel_onboarding ho
        where not (ho.readiness_state ? 'checklist')
          or not (
            ho.readiness_state
            -> 'checklist'
            ? 'amenities'
          )
          or not (
            ho.readiness_state
            -> 'checklist'
            ? 'request_categories'
          )
          or not (
            ho.readiness_state
            -> 'checklist'
            ? 'qr_ready'
          )
      ),
      'Every hotel onboarding row retains the server readiness checklist.'
    ),
    (
      '17_no_synthetic_runtime_hotels_remain',
      not exists (
        select 1
        from public.hotels h
        where h.slug like 'stayqr-day8-audit-%'
           or h.slug like 'stayqr-day8-config-audit-%'
      )
      and not exists (
        select 1
        from public.hotel_onboarding ho
        where ho.form_state ->> 'source'
          in ('audit_044', 'audit_046')
      ),
      'No reversible Audit 044 or Audit 046 tenant remains in production.'
    ),
    (
      '18_day8_backend_ready_for_frontend',
      to_regprocedure(
        'public.bootstrap_hotel_onboarding(jsonb)'
      ) is not null
      and to_regprocedure(
        'public.configure_hotel_inventory(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.import_hotel_rooms(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.refresh_hotel_onboarding_readiness(uuid)'
      ) is not null,
      'The permanent Day 8 backend is clean and ready for frontend wizard integration.'
    )
)
select test_name, passed, details
from checks
order by test_name;
