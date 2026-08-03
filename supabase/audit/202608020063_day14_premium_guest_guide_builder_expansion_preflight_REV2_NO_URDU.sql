-- StayQR v1.0 — Day 14 Premium Guest Guide Builder Expansion
-- Audit 063 — Schema-Safe Preflight Inventory REV2 NO-URDU
-- Date: 2026-08-02
-- Scope correction: Urdu and RTL support are excluded.
--
-- PURPOSE
-- Inventory the live database before Migration 047 adds:
--   * premium template + builder settings
--   * configurable/reorderable sections
--   * hotel / room-type / room inheritance
--   * media library and public guest-guide media delivery
--   * room/device instructions and galleries
--   * contacts, social links and local convenience
--   * payment profile and QR media
--   * major Indian language presets and editable greetings
--   * draft / preview / publish / version history
--
-- This is an inventory audit, not a final acceptance audit.
-- Mixed passed=true / passed=false rows are expected.
-- It does not modify hotel business data.
--
-- SQL-EDITOR SAFETY
-- Every optional relation/column is tested through catalogs or guarded
-- dynamic SQL so absent builder tables cannot abort the audit.

begin;

create schema if not exists private;

create or replace function private.day14_builder_safe_count_rev2(
  p_relation text,
  p_where text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_relation regclass;
  v_sql text;
  v_count bigint := 0;
begin
  v_relation := to_regclass(p_relation);

  if v_relation is null then
    return 0;
  end if;

  v_sql := format('select count(*) from %s', v_relation);

  if nullif(trim(coalesce(p_where, '')), '') is not null then
    v_sql := v_sql || ' where ' || p_where;
  end if;

  execute v_sql into v_count;
  return coalesce(v_count, 0);
exception
  when others then
    return -1;
end;
$function$;

revoke all on function private.day14_builder_safe_count_rev2(text,text)
from public, anon, authenticated;

create or replace function private.day14_builder_preflight_rev2()
returns table (
  area text,
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count bigint;
  v_text text;
begin
  -- ========================================================================
  -- A. ACCEPTED DAY 14 BASELINE
  -- ========================================================================

  return query
  select 'BASELINE', '01_hotel_guest_content',
    to_regclass('public.hotel_guest_content') is not null,
    'Migration 045 multilingual content table exists.';

  return query
  select 'BASELINE', '02_guest_feedback',
    to_regclass('public.guest_feedback') is not null,
    'Migration 045 private feedback table exists.';

  return query
  select 'BASELINE', '03_guest_review_rewards',
    to_regclass('public.guest_review_rewards') is not null,
    'Migration 045 review/reward audit table exists.';

  return query
  select 'BASELINE', '04_resolve_guest_portal',
    to_regprocedure('public.resolve_guest_portal(text,text)') is not null,
    'Signed guest portal resolver exists.';

  return query
  select 'BASELINE', '05_submit_guest_feedback',
    to_regprocedure(
      'public.submit_guest_feedback(text,text,integer,text,boolean)'
    ) is not null,
    'Signed feedback RPC exists.';

  return query
  select 'BASELINE', '06_review_reward_action',
    to_regprocedure(
      'public.record_guest_review_reward_action(text,text,text)'
    ) is not null,
    'Signed review/reward RPC exists.';

  return query
  select 'BASELINE', '07_content_read_rpc',
    to_regprocedure(
      'public.get_hotel_guest_content(uuid,text)'
    ) is not null,
    'Hotel content read RPC exists.';

  return query
  select 'BASELINE', '08_content_write_rpc',
    to_regprocedure(
      'public.upsert_hotel_guest_content(uuid,text,jsonb)'
    ) is not null,
    'Hotel content write RPC exists.';

  return query
  select 'BASELINE', '09_anon_portal_execute',
    coalesce(
      has_function_privilege(
        'anon',
        'public.resolve_guest_portal(text,text)',
        'EXECUTE'
      ),
      false
    ),
    'Anonymous signed links can resolve.';

  return query
  select 'BASELINE', '10_authenticated_portal_execute',
    coalesce(
      has_function_privilege(
        'authenticated',
        'public.resolve_guest_portal(text,text)',
        'EXECUTE'
      ),
      false
    ),
    'Authenticated browser profiles can resolve signed links.';

  return query
  select 'BASELINE', '11_no_duplicate_active_tokens',
    not exists (
      select 1
      from public.guest_access_tokens
      where status = 'active'
      group by guest_session_id
      having count(*) > 1
    ),
    'At most one active token exists per guest stay.';

  return query
  select 'BASELINE', '12_no_expired_active_tokens',
    not exists (
      select 1
      from public.guest_access_tokens
      where status = 'active'
        and expires_at <= now()
    ),
    'No expired token remains active.';

  -- ========================================================================
  -- B. TENANT / ROOM INHERITANCE CONTRACTS
  -- ========================================================================

  return query
  select 'INHERITANCE', '01_hotels_table',
    to_regclass('public.hotels') is not null,
    'Hotels relation exists.';

  return query
  select 'INHERITANCE', '02_room_types_table',
    to_regclass('public.room_types') is not null,
    'Room types relation exists.';

  return query
  select 'INHERITANCE', '03_rooms_table',
    to_regclass('public.rooms') is not null,
    'Rooms relation exists.';

  return query
  select 'INHERITANCE', '04_rooms_room_type_id',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'rooms'
        and column_name = 'room_type_id'
        and udt_name = 'uuid'
    ),
    'Rooms can inherit content from a room type.';

  return query
  select 'INHERITANCE', '05_rooms_metadata',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'rooms'
        and column_name = 'metadata'
        and udt_name = 'jsonb'
    ),
    'Room metadata column exists.';

  return query
  select 'INHERITANCE', '06_room_types_metadata',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'room_types'
        and column_name = 'metadata'
        and udt_name = 'jsonb'
    ),
    'Room-type metadata column exists.';

  return query
  select 'INHERITANCE', '07_room_hotel_composite',
    exists (
      select 1
      from pg_indexes
      where schemaname = 'public'
        and tablename = 'rooms'
        and indexdef ilike '%hotel_id%'
        and indexdef ilike '%id%'
    ),
    'Rooms have tenant-aware indexing.';

  return query
  select 'INHERITANCE', '08_room_type_hotel_composite',
    exists (
      select 1
      from pg_indexes
      where schemaname = 'public'
        and tablename = 'room_types'
        and indexdef ilike '%hotel_id%'
        and indexdef ilike '%id%'
    ),
    'Room types have tenant-aware indexing.';

  v_count := private.day14_builder_safe_count_rev2(
    'public.hotels',
    null
  );
  return query
  select 'INHERITANCE', '09_hotel_count',
    v_count > 0,
    format('%s hotel row(s) are present.', v_count);

  v_count := private.day14_builder_safe_count_rev2(
    'public.room_types',
    'is_active'
  );
  return query
  select 'INHERITANCE', '10_active_room_type_count',
    v_count >= 0,
    format('%s active room-type row(s) are present.', v_count);

  v_count := private.day14_builder_safe_count_rev2(
    'public.rooms',
    'is_active'
  );
  return query
  select 'INHERITANCE', '11_active_room_count',
    v_count >= 0,
    format('%s active room row(s) are present.', v_count);

  return query
  select 'INHERITANCE', '12_room_type_fk_present',
    exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname = 'rooms'
        and c.contype = 'f'
        and pg_get_constraintdef(c.oid) ilike '%room_type%'
    ),
    'Rooms enforce a room-type relationship.';

  -- ========================================================================
  -- C. HOTEL PROFILE / PAYMENT / CONTACT INPUTS
  -- ========================================================================

  return query
  select 'PROFILE', '01_hotel_info_table',
    to_regclass('public.hotel_info') is not null,
    'Existing hotel profile relation exists.';

  foreach v_text in array array[
    'hotel_name',
    'address',
    'reception_phone',
    'emergency_phone',
    'checkin_time',
    'checkout_time',
    'breakfast_time',
    'wifi_name',
    'wifi_password',
    'hotel_rules',
    'about',
    'google_review_url',
    'reward_title',
    'reward_description',
    'reward_enabled'
  ]
  loop
    return query
    select
      'PROFILE',
      '02_hotel_info_column_' || v_text,
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'hotel_info'
          and column_name = v_text
      ),
      format('hotel_info.%s inventory.', v_text);
  end loop;

  return query
  select 'PROFILE', '03_existing_social_profile_columns',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name in ('hotels', 'hotel_info')
        and column_name in (
          'instagram_url',
          'facebook_url',
          'youtube_url',
          'website_url',
          'whatsapp_number',
          'email'
        )
    ),
    'At least one existing social/contact profile column is present.';

  return query
  select 'PROFILE', '04_existing_upi_column',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and column_name in ('upi_id', 'payment_upi_id')
        and table_name in ('hotels', 'hotel_info', 'hotel_settings')
    ),
    'An existing hotel UPI profile column is present.';

  return query
  select 'PROFILE', '05_existing_payment_qr_column',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and column_name in (
          'payment_qr_url',
          'payment_qr_path',
          'upi_qr_url'
        )
        and table_name in ('hotels', 'hotel_info', 'hotel_settings')
    ),
    'An existing hotel payment-QR field is present.';

  -- ========================================================================
  -- D. STORAGE
  -- ========================================================================

  return query
  select 'STORAGE', '01_storage_objects',
    to_regclass('storage.objects') is not null,
    'Supabase Storage objects relation exists.';

  return query
  select 'STORAGE', '02_storage_buckets',
    to_regclass('storage.buckets') is not null,
    'Supabase Storage buckets relation exists.';

  return query
  select 'STORAGE', '03_hotel_assets_bucket',
    exists (
      select 1
      from storage.buckets
      where id = 'hotel-assets'
    ),
    'Existing private hotel-assets bucket exists.';

  return query
  select 'STORAGE', '04_hotel_assets_private',
    coalesce((
      select not b.public
      from storage.buckets b
      where b.id = 'hotel-assets'
    ), false),
    'Existing hotel-assets bucket remains private.';

  return query
  select 'STORAGE', '05_guest_guide_media_bucket',
    exists (
      select 1
      from storage.buckets
      where id = 'guest-guide-media'
    ),
    'Dedicated guest-guide media bucket already exists.';

  return query
  select 'STORAGE', '06_storage_hotel_path_helper',
    to_regprocedure(
      'private.storage_object_hotel_id(text)'
    ) is not null,
    'Hotel-folder storage helper exists.';

  return query
  select 'STORAGE', '07_hotel_asset_select_policy',
    exists (
      select 1
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname = 'stayqr_hotel_assets_select'
    ),
    'Authenticated hotel-assets select policy exists.';

  return query
  select 'STORAGE', '08_hotel_asset_insert_policy',
    exists (
      select 1
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname = 'stayqr_hotel_assets_insert'
    ),
    'Hotel-managed upload policy exists.';

  return query
  select 'STORAGE', '09_image_mime_support',
    coalesce((
      select
        'image/jpeg' = any(allowed_mime_types)
        and 'image/png' = any(allowed_mime_types)
        and 'image/webp' = any(allowed_mime_types)
      from storage.buckets
      where id = 'hotel-assets'
    ), false),
    'Existing hotel-assets bucket supports JPG, PNG and WebP.';

  return query
  select 'STORAGE', '10_guest_media_public_read_policy',
    exists (
      select 1
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname ilike '%guest%guide%media%select%'
    ),
    'A guest-guide public-media read policy already exists.';

  -- ========================================================================
  -- E. LANGUAGE / GREETING READINESS
  -- ========================================================================

  return query
  select 'LANGUAGE', '01_locale_constraint_allows_indian_codes',
    exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname = 'hotel_guest_content'
        and c.contype = 'c'
        and pg_get_constraintdef(c.oid) ilike '%locale%'
    ),
    'Current locale constraint can be reviewed for Indian language codes.';

  foreach v_text in array array[
    'en','hi','mr','ta','te','bn','gu','kn','ml','pa','or','as'
  ]
  loop
    return query
    select
      'LANGUAGE',
      '02_existing_locale_' || v_text,
      exists (
        select 1
        from public.hotel_guest_content
        where locale = v_text
          and is_active
      ),
      format('Active %s guest-content row inventory.', v_text);
  end loop;

  return query
  select 'LANGUAGE', '03_multiple_locales_present',
    exists (
      select 1
      from public.hotel_guest_content
      where is_active
      group by hotel_id
      having count(distinct locale) >= 2
    ),
    'At least one hotel currently has multilingual content.';

  return query
  select 'LANGUAGE', '04_greetings_table',
    to_regclass('public.guest_guide_greetings') is not null,
    'Editable language-specific greetings table exists.';

  -- ========================================================================
  -- F. BUILDER / VERSIONING GAPS
  -- ========================================================================

  foreach v_text in array array[
    'guest_guide_settings',
    'guest_guide_sections',
    'guest_guide_section_translations',
    'guest_guide_items',
    'guest_guide_item_translations',
    'guest_guide_media',
    'guest_guide_payment_profiles',
    'guest_guide_greetings',
    'guest_guide_versions',
    'guest_guide_events'
  ]
  loop
    return query
    select
      'BUILDER',
      '01_table_' || v_text,
      to_regclass('public.' || v_text) is not null,
      format('Builder relation public.%s inventory.', v_text);
  end loop;

  foreach v_text in array array[
    'get_guest_guide_builder',
    'upsert_guest_guide_settings',
    'upsert_guest_guide_section',
    'upsert_guest_guide_item',
    'upsert_guest_guide_media',
    'upsert_guest_guide_greeting',
    'upsert_guest_guide_payment_profile',
    'publish_guest_guide',
    'record_guest_guide_event'
  ]
  loop
    return query
    select
      'BUILDER',
      '02_rpc_' || v_text,
      exists (
        select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = v_text
      ),
      format('Builder RPC public.%s inventory.', v_text);
  end loop;

  return query
  select 'BUILDER', '03_template_setting',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_settings'
        and column_name = 'template_key'
    ),
    'Template selection storage exists.';

  return query
  select 'BUILDER', '04_enabled_locales_setting',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_settings'
        and column_name = 'enabled_locales'
    ),
    'Hotel-enabled locale storage exists.';

  return query
  select 'BUILDER', '05_draft_publish_status',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_settings'
        and column_name in ('status', 'publish_status')
    ),
    'Draft/published state storage exists.';

  return query
  select 'BUILDER', '06_section_ordering',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_sections'
        and column_name = 'sort_order'
    ),
    'Guide section ordering exists.';

  return query
  select 'BUILDER', '07_section_visibility',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_sections'
        and column_name in ('is_enabled', 'is_visible')
    ),
    'Guide section visibility exists.';

  return query
  select 'BUILDER', '08_item_scope',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_items'
        and column_name = 'scope_type'
    ),
    'Hotel/room-type/room item scope exists.';

  return query
  select 'BUILDER', '09_media_scope',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_media'
        and column_name = 'scope_type'
    ),
    'Hotel/room-type/room media scope exists.';

  return query
  select 'BUILDER', '10_version_snapshot',
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_guide_versions'
        and column_name in ('snapshot', 'snapshot_json')
    ),
    'Published guide snapshot/version storage exists.';

  -- ========================================================================
  -- G. SECURITY PRIMITIVES
  -- ========================================================================

  return query
  select 'SECURITY', '01_user_has_permission',
    to_regprocedure(
      'private.user_has_permission(uuid,text)'
    ) is not null,
    'Canonical permission helper exists.';

  return query
  select 'SECURITY', '02_user_has_hotel_access',
    to_regprocedure(
      'private.user_has_hotel_access(uuid)'
    ) is not null,
    'Canonical hotel-access helper exists.';

  return query
  select 'SECURITY', '03_token_resolver',
    to_regprocedure(
      'private.resolve_guest_access_token(text,text,boolean)'
    ) is not null,
    'Signed guest-token resolver exists.';

  return query
  select 'SECURITY', '04_pgcrypto_uuid',
    to_regprocedure('gen_random_uuid()') is not null,
    'UUID generation function exists.';

  return query
  select 'SECURITY', '05_rooms_rls',
    coalesce((
      select c.relrowsecurity
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'rooms'
    ), false),
    'Rooms RLS is enabled.';

  return query
  select 'SECURITY', '06_room_types_rls',
    coalesce((
      select c.relrowsecurity
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'room_types'
    ), false),
    'Room types RLS is enabled.';

  return query
  select 'SECURITY', '07_hotel_guest_content_rls',
    coalesce((
      select c.relrowsecurity
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'hotel_guest_content'
    ), false),
    'Current guest content RLS is enabled.';

  return query
  select 'SECURITY', '08_anon_no_rooms_read',
    not has_table_privilege(
      'anon',
      'public.rooms',
      'SELECT'
    ),
    'Anonymous guests cannot directly enumerate rooms.';

  return query
  select 'SECURITY', '09_anon_no_guest_content_write',
    not (
      has_table_privilege(
        'anon',
        'public.hotel_guest_content',
        'INSERT'
      )
      or has_table_privilege(
        'anon',
        'public.hotel_guest_content',
        'UPDATE'
      )
      or has_table_privilege(
        'anon',
        'public.hotel_guest_content',
        'DELETE'
      )
    ),
    'Anonymous guests cannot directly edit current guest content.';

  return query
  select 'SECURITY', '10_service_role_not_public_setting',
    not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and column_name ilike '%service_role%'
    ),
    'No public builder column is intended to contain a service-role key.';

  -- ========================================================================
  -- H. CURRENT RUNTIME CONTENT
  -- ========================================================================

  v_count := private.day14_builder_safe_count_rev2(
    'public.hotel_guest_content',
    'is_active'
  );
  return query
  select 'RUNTIME', '01_active_localized_content_rows',
    v_count >= 0,
    format('%s active localized content row(s) exist.', v_count);

  v_count := private.day14_builder_safe_count_rev2(
    'public.amenities',
    'is_active and guest_visible'
  );
  return query
  select 'RUNTIME', '02_guest_visible_amenities',
    v_count >= 0,
    format('%s active guest-visible amenity row(s) exist.', v_count);

  v_count := private.day14_builder_safe_count_rev2(
    'public.guest_feedback',
    null
  );
  return query
  select 'RUNTIME', '03_feedback_rows',
    v_count >= 0,
    format('%s private feedback row(s) exist.', v_count);

  v_count := private.day14_builder_safe_count_rev2(
    'public.guest_access_tokens',
    $$status = 'active' and expires_at > now()$$
  );
  return query
  select 'RUNTIME', '04_active_signed_tokens',
    v_count >= 0,
    format('%s currently active signed guest token(s) exist.', v_count);

  v_count := private.day14_builder_safe_count_rev2(
    'public.guest_access_tokens',
    $$status = 'revoked'$$
  );
  return query
  select 'RUNTIME', '05_revoked_token_evidence',
    v_count >= 0,
    format('%s revoked token row(s) exist.', v_count);

  v_count := private.day14_builder_safe_count_rev2(
    'public.guest_review_rewards',
    null
  );
  return query
  select 'RUNTIME', '06_review_reward_events',
    v_count >= 0,
    format('%s review/reward audit row(s) exist.', v_count);

end;
$function$;

revoke all on function private.day14_builder_preflight_rev2()
from public, anon, authenticated;

commit;

select area, test_name, passed, details
from private.day14_builder_preflight_rev2()
order by
  case area
    when 'BASELINE' then 1
    when 'INHERITANCE' then 2
    when 'PROFILE' then 3
    when 'STORAGE' then 4
    when 'LANGUAGE' then 5
    when 'BUILDER' then 6
    when 'SECURITY' then 7
    when 'RUNTIME' then 8
    else 9
  end,
  test_name;
