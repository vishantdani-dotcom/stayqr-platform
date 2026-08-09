-- ============================================================================
-- StayQR v1.0
-- Day 19 Migration 067 REV1
-- Gate 19C — Anonymous API Surface + Storage Policy Restoration
-- Date: 2026-08-09
--
-- PURPOSE
-- 1. Close anonymous/PUBLIC direct table + sequence access across public.
-- 2. Close PUBLIC/anon function EXECUTE globally, then re-open only the exact
--    15 accepted signed-guest/invoice RPC signatures.
-- 3. Harden future default privileges, including PostgreSQL's built-in PUBLIC
--    function EXECUTE default.
-- 4. Restore the accepted Storage bucket/policy state omitted from the Day 18
--    public-schema canonical reconstruction:
--       hotel-assets      private, 4 authenticated tenant policies
--       guest-documents   private, 4 latest Day 10 KYC policies
--       guest-guide-media public,  3 authenticated tenant write policies
--
-- SAFETY
-- - No hotel/guest/reservation/payment/folio/business rows are changed.
-- - Storage bucket metadata and Storage RLS policies only.
-- - Idempotent ACL/policy canonicalization.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608090067:gate19c-anon-storage-rev1')
);

-- ============================================================================
-- 1. GLOBAL ANONYMOUS DIRECT-OBJECT CLOSURE
-- ============================================================================

revoke all privileges on all tables in schema public from public, anon;
revoke all privileges on all sequences in schema public from public, anon;
revoke execute on all functions in schema public from public, anon;

grant usage on schema public to anon;

-- Future objects must not silently regain browser access.
alter default privileges for role postgres in schema public
  revoke all on tables from anon;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon;
alter default privileges for role postgres in schema public
  revoke all on functions from anon;
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

-- Exact accepted anonymous RPC surface.
grant execute on function
  public.cancel_guest_food_order(text,text,uuid,text),
  public.cancel_guest_service_request(text,text,uuid,text),
  public.create_guest_service_request(text,text,text),
  public.get_guest_food_menu(text,text),
  public.get_guest_food_orders(text,text),
  public.get_guest_notifications(text,text),
  public.get_guest_service_catalog(text,text),
  public.get_guest_service_requests(text,text),
  public.place_guest_food_order(text,text,jsonb),
  public.record_guest_guide_event(text,text,text,text,uuid,text,jsonb),
  public.record_guest_review_reward_action(text,text,text),
  public.resolve_guest_portal(text,text),
  public.resolve_premium_guest_guide(text,text),
  public.submit_guest_feedback(text,text,integer,text,boolean),
  public.verify_invoice(uuid)
to anon;

-- ============================================================================
-- 2. STORAGE HELPER EXECUTION + BUCKET STATE
-- ============================================================================

grant usage on schema private to authenticated;
grant execute on function private.storage_object_hotel_id(text)
to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values
  (
    'hotel-assets',
    'hotel-assets',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml']
  ),
  (
    'guest-documents',
    'guest-documents',
    false,
    15728640,
    array['image/jpeg', 'image/png', 'application/pdf']
  ),
  (
    'guest-guide-media',
    'guest-guide-media',
    true,
    8388608,
    array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml']
  )
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

do $storage_rls$
begin
  if not coalesce((
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage'
      and c.relname = 'objects'
  ), false) then
    execute 'alter table storage.objects enable row level security';
  end if;
end
$storage_rls$;

-- ============================================================================
-- 3. HOTEL-ASSETS — ACCEPTED DAY 7 POLICIES
-- ============================================================================

drop policy if exists stayqr_hotel_assets_select on storage.objects;
drop policy if exists stayqr_hotel_assets_insert on storage.objects;
drop policy if exists stayqr_hotel_assets_update on storage.objects;
drop policy if exists stayqr_hotel_assets_delete on storage.objects;

create policy stayqr_hotel_assets_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'hotel-assets'
  and private.user_has_hotel_access(
    private.storage_object_hotel_id(name)
  )
);

create policy stayqr_hotel_assets_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'hotel-assets'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);

create policy stayqr_hotel_assets_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'hotel-assets'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
)
with check (
  bucket_id = 'hotel-assets'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);

create policy stayqr_hotel_assets_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'hotel-assets'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);

-- ============================================================================
-- 4. GUEST-DOCUMENTS — LATEST ACCEPTED DAY 10 KYC POLICIES
-- ============================================================================

drop policy if exists stayqr_guest_documents_select on storage.objects;
drop policy if exists stayqr_guest_documents_insert on storage.objects;
drop policy if exists stayqr_guest_documents_update on storage.objects;
drop policy if exists stayqr_guest_documents_delete on storage.objects;

create policy stayqr_guest_documents_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_any_permission(
    private.storage_object_hotel_id(name),
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

create policy stayqr_guest_documents_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'guest-documents'
  and private.user_has_any_permission(
    private.storage_object_hotel_id(name),
    array['guests.manage', 'checkin.manage']
  )
);

create policy stayqr_guest_documents_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
)
with check (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
);

create policy stayqr_guest_documents_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
);

-- ============================================================================
-- 5. GUEST-GUIDE-MEDIA — ACCEPTED DAY 14 TENANT WRITES
-- ============================================================================

drop policy if exists stayqr_guest_guide_media_insert on storage.objects;
drop policy if exists stayqr_guest_guide_media_update on storage.objects;
drop policy if exists stayqr_guest_guide_media_delete on storage.objects;

create policy stayqr_guest_guide_media_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'guest-guide-media'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);

create policy stayqr_guest_guide_media_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'guest-guide-media'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
)
with check (
  bucket_id = 'guest-guide-media'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);

create policy stayqr_guest_guide_media_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'guest-guide-media'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);

-- ============================================================================
-- 6. PRE-COMMIT VERIFICATION
-- ============================================================================

do $verify$
declare
  v_allowed_oids oid[] := array[
      'public.cancel_guest_food_order(text,text,uuid,text)'::regprocedure::oid,
      'public.cancel_guest_service_request(text,text,uuid,text)'::regprocedure::oid,
      'public.create_guest_service_request(text,text,text)'::regprocedure::oid,
      'public.get_guest_food_menu(text,text)'::regprocedure::oid,
      'public.get_guest_food_orders(text,text)'::regprocedure::oid,
      'public.get_guest_notifications(text,text)'::regprocedure::oid,
      'public.get_guest_service_catalog(text,text)'::regprocedure::oid,
      'public.get_guest_service_requests(text,text)'::regprocedure::oid,
      'public.place_guest_food_order(text,text,jsonb)'::regprocedure::oid,
      'public.record_guest_guide_event(text,text,text,text,uuid,text,jsonb)'::regprocedure::oid,
      'public.record_guest_review_reward_action(text,text,text)'::regprocedure::oid,
      'public.resolve_guest_portal(text,text)'::regprocedure::oid,
      'public.resolve_premium_guest_guide(text,text)'::regprocedure::oid,
      'public.submit_guest_feedback(text,text,integer,text,boolean)'::regprocedure::oid,
      'public.verify_invoice(uuid)'::regprocedure::oid
  ];
  v_oid oid;
  v_unexpected_count integer;
  v_policy_count integer;
begin
  -- Anonymous must have no effective public-table DML privilege.
  select count(*)
  into v_unexpected_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r','p','v','m')
    and (
      has_table_privilege('anon', c.oid, 'SELECT')
      or has_table_privilege('anon', c.oid, 'INSERT')
      or has_table_privilege('anon', c.oid, 'UPDATE')
      or has_table_privilege('anon', c.oid, 'DELETE')
    );

  if v_unexpected_count <> 0 then
    raise exception
      'Migration 067 verification failed: anon retains effective DML on % public relation(s).',
      v_unexpected_count;
  end if;

  -- Anonymous EXECUTE must be exactly the accepted 15 signatures.
  select count(*)
  into v_unexpected_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and has_function_privilege('anon', p.oid, 'EXECUTE')
    and not (p.oid = any(v_allowed_oids));

  if v_unexpected_count <> 0 then
    raise exception
      'Migration 067 verification failed: anon retains % unexpected public RPC execute privilege(s).',
      v_unexpected_count;
  end if;

  foreach v_oid in array v_allowed_oids loop
    if not has_function_privilege('anon', v_oid, 'EXECUTE') then
      raise exception
        'Migration 067 verification failed: approved anon RPC OID % is not executable.',
        v_oid;
    end if;
  end loop;

  -- Current Storage bucket visibility.
  if not exists (
    select 1 from storage.buckets
    where id = 'hotel-assets' and public = false
  ) or not exists (
    select 1 from storage.buckets
    where id = 'guest-documents' and public = false
  ) or not exists (
    select 1 from storage.buckets
    where id = 'guest-guide-media' and public = true
  ) then
    raise exception
      'Migration 067 verification failed: Storage bucket visibility is not canonical.';
  end if;

  select count(*)
  into v_policy_count
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
    ]::text[]);

  if v_policy_count <> 11 then
    raise exception
      'Migration 067 verification failed: expected 11 StayQR Storage policies, found %.',
      v_policy_count;
  end if;
end
$verify$;

commit;

select
  'M067_POSTCOMMIT'::text as suite,
  (
    not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind in ('r','p','v','m')
        and (
          has_table_privilege('anon', c.oid, 'SELECT')
          or has_table_privilege('anon', c.oid, 'INSERT')
          or has_table_privilege('anon', c.oid, 'UPDATE')
          or has_table_privilege('anon', c.oid, 'DELETE')
        )
    )
    and (
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
  ) as passed,
  'Anonymous direct public-table access is closed and the current StayQR Storage policy surface is restored.'::text as details;
