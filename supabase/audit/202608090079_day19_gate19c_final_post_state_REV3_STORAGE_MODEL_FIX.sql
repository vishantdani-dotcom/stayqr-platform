-- ============================================================================
-- StayQR v1.0
-- Day 19 Audit 079 REV3
-- Gate 19C final post-state verification after Migration 069
-- READ ONLY / NO MUTATION
-- Expected result: exactly 12 checks and every passed value = t.
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_storage_objects_rls_enabled',
      coalesce((
        select c.relrowsecurity
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'storage'
          and c.relname = 'objects'
      ), false),
      'storage.objects RLS is enabled.'
    ),
    (
      '02_required_storage_policies_11',
      (
        select count(*) = 11
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = any(array[
            'stayqr_hotel_assets_select',
            'stayqr_hotel_assets_insert',
            'stayqr_hotel_assets_update',
            'stayqr_hotel_assets_delete',
            'stayqr_guest_documents_select',
            'stayqr_guest_documents_insert',
            'stayqr_guest_documents_update',
            'stayqr_guest_documents_delete',
            'stayqr_guest_guide_media_insert',
            'stayqr_guest_guide_media_update',
            'stayqr_guest_guide_media_delete'
          ]::text[])
      ),
      'All 11 required StayQR Storage RLS policies remain installed.'
    ),
    (
      '03_storage_path_helper_boundary',
      has_function_privilege(
        'authenticated',
        'private.storage_object_hotel_id(text)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'private.storage_object_hotel_id(text)',
        'EXECUTE'
      ),
      'Storage path helper is executable by authenticated and closed to anon.'
    ),
    (
      '04_hotel_assets_private',
      coalesce((
        select not b.public
        from storage.buckets b
        where b.id = 'hotel-assets'
      ), false),
      'hotel-assets remains private.'
    ),
    (
      '05_guest_documents_private',
      coalesce((
        select not b.public
        from storage.buckets b
        where b.id = 'guest-documents'
      ), false),
      'guest-documents remains private.'
    ),
    (
      '06_guest_guide_media_public',
      coalesce((
        select b.public
        from storage.buckets b
        where b.id = 'guest-guide-media'
      ), false),
      'guest-guide-media remains public-read; write operations remain policy controlled.'
    ),
    (
      '07_hotel_onboarding_insert_hardened',
      exists (
        select 1
        from pg_policies p
        where p.schemaname = 'public'
          and p.tablename = 'hotel_onboarding'
          and p.policyname = 'stayqr_hotel_onboarding_insert'
          and coalesce(p.with_check, '') !~* 'owner_user_id'
          and coalesce(p.with_check, '') ~* 'user_has_permission'
          and coalesce(p.with_check, '') ~* 'hotel.manage'
      ),
      'Direct hotel_onboarding INSERT no longer accepts owner_user_id as a cross-tenant bypass.'
    ),
    (
      '08_hotel_onboarding_update_hardened',
      exists (
        select 1
        from pg_policies p
        where p.schemaname = 'public'
          and p.tablename = 'hotel_onboarding'
          and p.policyname = 'stayqr_hotel_onboarding_update'
          and coalesce(p.qual, '') !~* 'owner_user_id'
          and coalesce(p.with_check, '') !~* 'owner_user_id'
          and coalesce(p.qual, '') ~* 'user_has_permission'
          and coalesce(p.with_check, '') ~* 'user_has_permission'
          and coalesce(p.qual, '') ~* 'hotel.manage'
          and coalesce(p.with_check, '') ~* 'hotel.manage'
      ),
      'Direct hotel_onboarding UPDATE no longer accepts owner_user_id as a cross-tenant bypass.'
    ),
    (
      '09_onboarding_rpc_boundary_intact',
      has_function_privilege(
        'authenticated',
        'public.bootstrap_hotel_onboarding(jsonb)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.save_hotel_onboarding_step(uuid,text,jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.bootstrap_hotel_onboarding(jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.save_hotel_onboarding_step(uuid,text,jsonb)',
        'EXECUTE'
      ),
      'Supported onboarding RPCs remain available to authenticated and closed to anon.'
    ),
    (
      '10_no_gate19c_fixture_hotels',
      not exists (
        select 1
        from public.hotels
        where slug like 'day19-isolation-b-%'
           or hotel_name = 'Day 19 Isolation Fixture Hotel B'
      ),
      'No temporary Gate 19C hotel remains.'
    ),
    (
      '11_no_gate19c_storage_objects',
      not exists (
        select 1
        from storage.objects
        where name like '%/day7-isolation/%'
      ),
      'No temporary Gate 19C Storage object remains.'
    ),
    (
      '12_hotel_onboarding_rls_enabled',
      coalesce((
        select c.relrowsecurity
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'hotel_onboarding'
      ), false),
      'hotel_onboarding RLS remains enabled.'
    )
)
select test_name, passed, details
from checks
order by test_name;

do $$
declare
  v_failed integer;
begin
  with checks(passed) as (
    values
      (
        coalesce((
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'storage'
            and c.relname = 'objects'
        ), false)
      ),
      (
        (
          select count(*) = 11
          from pg_policies
          where schemaname = 'storage'
            and tablename = 'objects'
            and policyname = any(array[
              'stayqr_hotel_assets_select',
              'stayqr_hotel_assets_insert',
              'stayqr_hotel_assets_update',
              'stayqr_hotel_assets_delete',
              'stayqr_guest_documents_select',
              'stayqr_guest_documents_insert',
              'stayqr_guest_documents_update',
              'stayqr_guest_documents_delete',
              'stayqr_guest_guide_media_insert',
              'stayqr_guest_guide_media_update',
              'stayqr_guest_guide_media_delete'
            ]::text[])
        )
      ),
      (
        has_function_privilege(
          'authenticated',
          'private.storage_object_hotel_id(text)',
          'EXECUTE'
        )
        and not has_function_privilege(
          'anon',
          'private.storage_object_hotel_id(text)',
          'EXECUTE'
        )
      ),
      (
        coalesce((
          select not b.public from storage.buckets b
          where b.id = 'hotel-assets'
        ), false)
      ),
      (
        coalesce((
          select not b.public from storage.buckets b
          where b.id = 'guest-documents'
        ), false)
      ),
      (
        coalesce((
          select b.public from storage.buckets b
          where b.id = 'guest-guide-media'
        ), false)
      ),
      (
        exists (
          select 1
          from pg_policies p
          where p.schemaname = 'public'
            and p.tablename = 'hotel_onboarding'
            and p.policyname = 'stayqr_hotel_onboarding_insert'
            and coalesce(p.with_check, '') !~* 'owner_user_id'
            and coalesce(p.with_check, '') ~* 'user_has_permission'
            and coalesce(p.with_check, '') ~* 'hotel.manage'
        )
      ),
      (
        exists (
          select 1
          from pg_policies p
          where p.schemaname = 'public'
            and p.tablename = 'hotel_onboarding'
            and p.policyname = 'stayqr_hotel_onboarding_update'
            and coalesce(p.qual, '') !~* 'owner_user_id'
            and coalesce(p.with_check, '') !~* 'owner_user_id'
            and coalesce(p.qual, '') ~* 'user_has_permission'
            and coalesce(p.with_check, '') ~* 'user_has_permission'
            and coalesce(p.qual, '') ~* 'hotel.manage'
            and coalesce(p.with_check, '') ~* 'hotel.manage'
        )
      ),
      (
        has_function_privilege(
          'authenticated',
          'public.bootstrap_hotel_onboarding(jsonb)',
          'EXECUTE'
        )
        and has_function_privilege(
          'authenticated',
          'public.save_hotel_onboarding_step(uuid,text,jsonb)',
          'EXECUTE'
        )
        and not has_function_privilege(
          'anon',
          'public.bootstrap_hotel_onboarding(jsonb)',
          'EXECUTE'
        )
        and not has_function_privilege(
          'anon',
          'public.save_hotel_onboarding_step(uuid,text,jsonb)',
          'EXECUTE'
        )
      ),
      (
        not exists (
          select 1
          from public.hotels
          where slug like 'day19-isolation-b-%'
             or hotel_name = 'Day 19 Isolation Fixture Hotel B'
        )
      ),
      (
        not exists (
          select 1
          from storage.objects
          where name like '%/day7-isolation/%'
        )
      ),
      (
        coalesce((
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'hotel_onboarding'
        ), false)
      )
  )
  select count(*) filter (where not passed)
  into v_failed
  from checks;

  if v_failed <> 0 then
    raise exception
      'Audit 079 REV3 failed: % Gate 19C final post-state check(s) failed.',
      v_failed;
  end if;
end
$$;

select
  '=== AUDIT 079 REV3 PASS - GATE 19C FINAL POST-STATE 12/12 ==='::text
    as gate_result;
