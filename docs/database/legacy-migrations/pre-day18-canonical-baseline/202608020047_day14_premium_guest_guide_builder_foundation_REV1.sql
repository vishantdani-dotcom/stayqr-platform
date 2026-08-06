-- StayQR v1.0 — Day 14 Migration 047 REV1
-- Premium Guest Guide Builder Foundation
-- Date: 2026-08-02
--
-- APPROVED SCOPE
--   * premium StayQR Luxury template foundation
--   * hotel-editable guide settings, sections and translations
--   * hotel -> room type -> room content inheritance
--   * public guest-guide media bucket with tenant-scoped writes
--   * room/device instructions, galleries, contacts, social links,
--     local convenience, policies, dining and custom items
--   * hotel payment profile and payment QR metadata
--   * 12 supported languages (Urdu deliberately excluded)
--   * editable neutral/morning/afternoon/evening/night greetings
--   * draft -> publish workflow and immutable version snapshots
--   * signed guest resolver for the premium renderer
--   * token-bound event foundation for Day 16 analytics
--
-- SUPPORTED LOCALES
--   en, hi, mr, ta, te, bn, gu, kn, ml, pa, or, as
--
-- SAFETY
--   * Existing Day 14 RPCs and guest portal remain installed.
--   * The new premium resolver is additive.
--   * No arbitrary hotel HTML/CSS/JavaScript is stored or executed.
--   * Anonymous users receive no direct builder-table access.
--   * Guest access still requires a valid signed active-stay token.
--   * Expired tokens incorrectly left as active are reconciled to expired.
--
-- EXPECTED RESULT
--   72 rows
--   72 passed = true
--   0 failures

begin;

create schema if not exists private;

-- ============================================================================
-- 0. SAFE TOKEN RECONCILIATION
-- ============================================================================

update public.guest_access_tokens
set
  status = 'expired',
  updated_at = now()
where status = 'active'
  and expires_at <= now();

-- ============================================================================
-- 1. BUILDER SETTINGS
-- ============================================================================

create table if not exists public.guest_guide_settings (
  hotel_id uuid primary key
    references public.hotels(id) on delete cascade,
  template_key text not null default 'stayqr_luxury',
  default_locale text not null default 'en',
  enabled_locales text[] not null default array['en']::text[],
  publish_status text not null default 'draft',
  theme jsonb not null default '{}'::jsonb,
  branding jsonb not null default '{}'::jsonb,
  navigation jsonb not null default '{}'::jsonb,
  draft_revision bigint not null default 1,
  published_version integer not null default 0,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_settings_template_check
    check (
      template_key in (
        'stayqr_luxury'
      )
    ),

  constraint guest_guide_settings_default_locale_check
    check (
      default_locale = any (
        array[
          'en','hi','mr','ta','te','bn',
          'gu','kn','ml','pa','or','as'
        ]::text[]
      )
    ),

  constraint guest_guide_settings_enabled_locales_check
    check (
      cardinality(enabled_locales) >= 1
      and enabled_locales <@ array[
        'en','hi','mr','ta','te','bn',
        'gu','kn','ml','pa','or','as'
      ]::text[]
      and default_locale = any(enabled_locales)
    ),

  constraint guest_guide_settings_publish_status_check
    check (publish_status in ('draft', 'published')),

  constraint guest_guide_settings_json_check
    check (
      jsonb_typeof(theme) = 'object'
      and jsonb_typeof(branding) = 'object'
      and jsonb_typeof(navigation) = 'object'
    ),

  constraint guest_guide_settings_revision_check
    check (
      draft_revision >= 1
      and published_version >= 0
    )
);

-- ============================================================================
-- 2. CONFIGURABLE SECTIONS AND TRANSLATIONS
-- ============================================================================

create table if not exists public.guest_guide_sections (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  section_key text not null,
  section_type text not null,
  sort_order integer not null default 0,
  is_enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_sections_key_check
    check (section_key ~ '^[a-z][a-z0-9_]{1,63}$'),

  constraint guest_guide_sections_type_check
    check (
      section_type in (
        'hero',
        'stay',
        'actions',
        'wifi',
        'gallery',
        'instructions',
        'facilities',
        'dining',
        'services',
        'safety',
        'contacts',
        'social',
        'local',
        'payment',
        'feedback',
        'review',
        'policies',
        'closing',
        'custom'
      )
    ),

  constraint guest_guide_sections_settings_check
    check (jsonb_typeof(settings) = 'object'),

  constraint uq_guest_guide_sections_hotel_key
    unique (hotel_id, section_key)
);

create unique index if not exists uq_guest_guide_sections_hotel_id
on public.guest_guide_sections (hotel_id, id);

create index if not exists idx_guest_guide_sections_hotel_order
on public.guest_guide_sections (hotel_id, is_enabled, sort_order, section_key);

create table if not exists public.guest_guide_section_translations (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  section_id uuid not null,
  locale text not null,
  label text,
  title text,
  subtitle text,
  body text,
  button_label text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_section_translations_section_fkey
    foreign key (hotel_id, section_id)
    references public.guest_guide_sections(hotel_id, id)
    on delete cascade,

  constraint guest_guide_section_translations_locale_check
    check (
      locale = any (
        array[
          'en','hi','mr','ta','te','bn',
          'gu','kn','ml','pa','or','as'
        ]::text[]
      )
    ),

  constraint guest_guide_section_translations_metadata_check
    check (jsonb_typeof(metadata) = 'object'),

  constraint uq_guest_guide_section_translation
    unique (section_id, locale)
);

create index if not exists idx_guest_guide_section_translations_hotel_locale
on public.guest_guide_section_translations (hotel_id, locale, section_id);

-- ============================================================================
-- 3. SCOPE-AWARE GUIDE ITEMS AND TRANSLATIONS
-- ============================================================================

create table if not exists public.guest_guide_items (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  section_id uuid not null,
  scope_type text not null default 'hotel',
  room_type_id uuid,
  room_id uuid,
  item_key text not null,
  item_type text not null,
  icon text,
  action_type text not null default 'none',
  action_value text,
  sort_order integer not null default 0,
  is_enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_items_section_fkey
    foreign key (hotel_id, section_id)
    references public.guest_guide_sections(hotel_id, id)
    on delete cascade,

  constraint guest_guide_items_room_type_fkey
    foreign key (hotel_id, room_type_id)
    references public.room_types(hotel_id, id)
    on delete cascade,

  constraint guest_guide_items_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete cascade,

  constraint guest_guide_items_scope_check
    check (
      (
        scope_type = 'hotel'
        and room_type_id is null
        and room_id is null
      )
      or (
        scope_type = 'room_type'
        and room_type_id is not null
        and room_id is null
      )
      or (
        scope_type = 'room'
        and room_type_id is null
        and room_id is not null
      )
    ),

  constraint guest_guide_items_key_check
    check (item_key ~ '^[a-z][a-z0-9_]{1,95}$'),

  constraint guest_guide_items_type_check
    check (
      item_type in (
        'quick_action',
        'instruction',
        'facility',
        'contact',
        'social',
        'local_convenience',
        'policy',
        'dining',
        'safety',
        'custom'
      )
    ),

  constraint guest_guide_items_action_check
    check (
      action_type in (
        'none',
        'call',
        'whatsapp',
        'email',
        'url',
        'maps',
        'section',
        'food',
        'service',
        'payment',
        'checkout'
      )
    ),

  constraint guest_guide_items_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists uq_guest_guide_items_hotel_id
on public.guest_guide_items (hotel_id, id);

create unique index if not exists uq_guest_guide_item_scope_key
on public.guest_guide_items (
  hotel_id,
  section_id,
  scope_type,
  coalesce(
    room_type_id,
    '00000000-0000-0000-0000-000000000000'::uuid
  ),
  coalesce(
    room_id,
    '00000000-0000-0000-0000-000000000000'::uuid
  ),
  item_key
);

create index if not exists idx_guest_guide_items_scope
on public.guest_guide_items (
  hotel_id,
  section_id,
  scope_type,
  room_type_id,
  room_id,
  is_enabled,
  sort_order
);

create table if not exists public.guest_guide_item_translations (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  item_id uuid not null,
  locale text not null,
  title text,
  subtitle text,
  description text,
  instructions jsonb not null default '[]'::jsonb,
  disclaimer text,
  button_label text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_item_translations_item_fkey
    foreign key (hotel_id, item_id)
    references public.guest_guide_items(hotel_id, id)
    on delete cascade,

  constraint guest_guide_item_translations_locale_check
    check (
      locale = any (
        array[
          'en','hi','mr','ta','te','bn',
          'gu','kn','ml','pa','or','as'
        ]::text[]
      )
    ),

  constraint guest_guide_item_translations_instructions_check
    check (jsonb_typeof(instructions) = 'array'),

  constraint guest_guide_item_translations_metadata_check
    check (jsonb_typeof(metadata) = 'object'),

  constraint uq_guest_guide_item_translation
    unique (item_id, locale)
);

create index if not exists idx_guest_guide_item_translations_hotel_locale
on public.guest_guide_item_translations (hotel_id, locale, item_id);

-- ============================================================================
-- 4. PUBLIC GUEST-GUIDE MEDIA METADATA
-- ============================================================================

create table if not exists public.guest_guide_media (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  section_id uuid,
  item_id uuid,
  scope_type text not null default 'hotel',
  room_type_id uuid,
  room_id uuid,
  media_key text not null,
  category text not null,
  bucket_id text not null default 'guest-guide-media',
  object_path text not null,
  mime_type text,
  title text,
  caption text,
  alt_text text,
  locale text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_media_section_fkey
    foreign key (hotel_id, section_id)
    references public.guest_guide_sections(hotel_id, id)
    on delete set null,

  constraint guest_guide_media_item_fkey
    foreign key (hotel_id, item_id)
    references public.guest_guide_items(hotel_id, id)
    on delete set null,

  constraint guest_guide_media_room_type_fkey
    foreign key (hotel_id, room_type_id)
    references public.room_types(hotel_id, id)
    on delete cascade,

  constraint guest_guide_media_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete cascade,

  constraint guest_guide_media_scope_check
    check (
      (
        scope_type = 'hotel'
        and room_type_id is null
        and room_id is null
      )
      or (
        scope_type = 'room_type'
        and room_type_id is not null
        and room_id is null
      )
      or (
        scope_type = 'room'
        and room_type_id is null
        and room_id is not null
      )
    ),

  constraint guest_guide_media_key_check
    check (media_key ~ '^[a-z][a-z0-9_]{1,95}$'),

  constraint guest_guide_media_category_check
    check (
      category in (
        'logo',
        'profile',
        'hero',
        'property',
        'room',
        'bathroom',
        'facility',
        'dining',
        'ac',
        'ac_remote',
        'tv',
        'tv_remote',
        'geyser',
        'bathtub',
        'safe',
        'wifi',
        'payment_qr',
        'emergency',
        'policy',
        'custom'
      )
    ),

  constraint guest_guide_media_bucket_check
    check (bucket_id = 'guest-guide-media'),

  constraint guest_guide_media_object_path_check
    check (
      length(trim(object_path)) > 3
      and object_path !~ '(^|/)\.\.(/|$)'
    ),

  constraint guest_guide_media_locale_check
    check (
      locale is null
      or locale = any (
        array[
          'en','hi','mr','ta','te','bn',
          'gu','kn','ml','pa','or','as'
        ]::text[]
      )
    ),

  constraint guest_guide_media_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists uq_guest_guide_media_hotel_id
on public.guest_guide_media (hotel_id, id);

create unique index if not exists uq_guest_guide_media_scope_key
on public.guest_guide_media (
  hotel_id,
  scope_type,
  coalesce(
    room_type_id,
    '00000000-0000-0000-0000-000000000000'::uuid
  ),
  coalesce(
    room_id,
    '00000000-0000-0000-0000-000000000000'::uuid
  ),
  media_key
);

create index if not exists idx_guest_guide_media_scope
on public.guest_guide_media (
  hotel_id,
  scope_type,
  room_type_id,
  room_id,
  category,
  is_active,
  sort_order
);

-- ============================================================================
-- 5. PAYMENT PROFILE
-- ============================================================================

create table if not exists public.guest_guide_payment_profiles (
  hotel_id uuid primary key
    references public.hotels(id) on delete cascade,
  is_enabled boolean not null default false,
  payee_name text,
  upi_id text,
  qr_media_id uuid,
  instructions text,
  show_outstanding_balance boolean not null default true,
  require_reception_confirmation boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_payment_profiles_qr_fkey
    foreign key (hotel_id, qr_media_id)
    references public.guest_guide_media(hotel_id, id)
    on delete set null,

  constraint guest_guide_payment_profiles_upi_check
    check (
      upi_id is null
      or upi_id ~ '^[A-Za-z0-9._-]{2,256}@[A-Za-z0-9.-]{2,128}$'
    ),

  constraint guest_guide_payment_profiles_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

-- ============================================================================
-- 6. EDITABLE LANGUAGE GREETINGS — URDU EXCLUDED
-- ============================================================================

create table if not exists public.guest_guide_greetings (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  locale text not null,
  language_name text not null,
  native_name text not null,
  neutral_greeting text not null,
  morning_greeting text not null,
  afternoon_greeting text not null,
  evening_greeting text not null,
  night_greeting text not null,
  is_enabled boolean not null default false,
  sort_order integer not null default 0,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_guide_greetings_locale_check
    check (
      locale = any (
        array[
          'en','hi','mr','ta','te','bn',
          'gu','kn','ml','pa','or','as'
        ]::text[]
      )
    ),

  constraint guest_guide_greetings_nonblank_check
    check (
      length(trim(language_name)) > 0
      and length(trim(native_name)) > 0
      and length(trim(neutral_greeting)) > 0
      and length(trim(morning_greeting)) > 0
      and length(trim(afternoon_greeting)) > 0
      and length(trim(evening_greeting)) > 0
      and length(trim(night_greeting)) > 0
    ),

  constraint uq_guest_guide_greeting_locale
    unique (hotel_id, locale)
);

create index if not exists idx_guest_guide_greetings_hotel_order
on public.guest_guide_greetings (hotel_id, is_enabled, sort_order, locale);

-- ============================================================================
-- 7. IMMUTABLE PUBLISHED VERSIONS AND EVENT FOUNDATION
-- ============================================================================

create table if not exists public.guest_guide_versions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  publish_note text,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz not null default now(),

  constraint guest_guide_versions_number_check
    check (version_number >= 1),

  constraint guest_guide_versions_snapshot_check
    check (jsonb_typeof(snapshot) = 'object'),

  constraint uq_guest_guide_version_number
    unique (hotel_id, version_number)
);

create index if not exists idx_guest_guide_versions_hotel_latest
on public.guest_guide_versions (hotel_id, version_number desc);

create table if not exists public.guest_guide_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  guest_session_id uuid not null,
  guest_access_token_id uuid
    references public.guest_access_tokens(id) on delete set null,
  event_type text not null,
  section_key text,
  item_id uuid,
  locale text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),

  constraint guest_guide_events_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,

  constraint guest_guide_events_item_fkey
    foreign key (hotel_id, item_id)
    references public.guest_guide_items(hotel_id, id)
    on delete set null,

  constraint guest_guide_events_type_check
    check (
      event_type in (
        'guide_opened',
        'language_selected',
        'section_viewed',
        'wifi_copied',
        'call_clicked',
        'whatsapp_clicked',
        'email_clicked',
        'maps_clicked',
        'social_clicked',
        'local_convenience_clicked',
        'payment_clicked',
        'food_clicked',
        'service_clicked',
        'checkout_clicked',
        'review_clicked',
        'feedback_started',
        'feedback_submitted',
        'media_viewed'
      )
    ),

  constraint guest_guide_events_locale_check
    check (
      locale is null
      or locale = any (
        array[
          'en','hi','mr','ta','te','bn',
          'gu','kn','ml','pa','or','as'
        ]::text[]
      )
    ),

  constraint guest_guide_events_metadata_check
    check (
      jsonb_typeof(metadata) = 'object'
      and pg_column_size(metadata) <= 8192
    )
);

create index if not exists idx_guest_guide_events_hotel_time
on public.guest_guide_events (hotel_id, occurred_at desc);

create index if not exists idx_guest_guide_events_session_time
on public.guest_guide_events (hotel_id, guest_session_id, occurred_at desc);

-- ============================================================================
-- 8. PUBLIC MEDIA BUCKET WITH TENANT-SCOPED WRITES
-- ============================================================================

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'guest-guide-media',
  'guest-guide-media',
  true,
  8388608,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/svg+xml'
  ]
)
on conflict (id) do update
set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists stayqr_guest_guide_media_insert
on storage.objects;

drop policy if exists stayqr_guest_guide_media_update
on storage.objects;

drop policy if exists stayqr_guest_guide_media_delete
on storage.objects;

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
-- 9. UPDATED-AT AND DRAFT HELPERS
-- ============================================================================

create or replace function private.day14_builder_touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function private.day14_builder_touch_updated_at()
from public, anon, authenticated;

do $triggers$
declare
  v_table text;
begin
  foreach v_table in array array[
    'guest_guide_settings',
    'guest_guide_sections',
    'guest_guide_section_translations',
    'guest_guide_items',
    'guest_guide_item_translations',
    'guest_guide_media',
    'guest_guide_payment_profiles',
    'guest_guide_greetings'
  ]
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      v_table || '_touch_updated_at',
      v_table
    );

    execute format(
      'create trigger %I before update on public.%I
       for each row execute function private.day14_builder_touch_updated_at()',
      v_table || '_touch_updated_at',
      v_table
    );
  end loop;
end;
$triggers$;

create or replace function private.day14_mark_guide_draft(
  p_hotel_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.guest_guide_settings
  set
    publish_status = 'draft',
    draft_revision = draft_revision + 1,
    updated_by = auth.uid(),
    updated_at = now()
  where hotel_id = p_hotel_id;
end;
$function$;

revoke all on function private.day14_mark_guide_draft(uuid)
from public, anon, authenticated;

-- ============================================================================
-- 10. RLS AND DIRECT-ACCESS BOUNDARY
-- ============================================================================

alter table public.guest_guide_settings enable row level security;
alter table public.guest_guide_sections enable row level security;
alter table public.guest_guide_section_translations enable row level security;
alter table public.guest_guide_items enable row level security;
alter table public.guest_guide_item_translations enable row level security;
alter table public.guest_guide_media enable row level security;
alter table public.guest_guide_payment_profiles enable row level security;
alter table public.guest_guide_greetings enable row level security;
alter table public.guest_guide_versions enable row level security;
alter table public.guest_guide_events enable row level security;

do $policies$
declare
  v_table text;
  v_policy text;
begin
  foreach v_table in array array[
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
    v_policy := 'stayqr_' || v_table || '_select';

    execute format(
      'drop policy if exists %I on public.%I',
      v_policy,
      v_table
    );

    execute format(
      'create policy %I on public.%I
       for select to authenticated
       using (private.user_has_permission(hotel_id, ''hotel.manage''))',
      v_policy,
      v_table
    );
  end loop;
end;
$policies$;

revoke all on public.guest_guide_settings
from public, anon, authenticated;
revoke all on public.guest_guide_sections
from public, anon, authenticated;
revoke all on public.guest_guide_section_translations
from public, anon, authenticated;
revoke all on public.guest_guide_items
from public, anon, authenticated;
revoke all on public.guest_guide_item_translations
from public, anon, authenticated;
revoke all on public.guest_guide_media
from public, anon, authenticated;
revoke all on public.guest_guide_payment_profiles
from public, anon, authenticated;
revoke all on public.guest_guide_greetings
from public, anon, authenticated;
revoke all on public.guest_guide_versions
from public, anon, authenticated;
revoke all on public.guest_guide_events
from public, anon, authenticated;

grant select on public.guest_guide_settings to authenticated;
grant select on public.guest_guide_sections to authenticated;
grant select on public.guest_guide_section_translations to authenticated;
grant select on public.guest_guide_items to authenticated;
grant select on public.guest_guide_item_translations to authenticated;
grant select on public.guest_guide_media to authenticated;
grant select on public.guest_guide_payment_profiles to authenticated;
grant select on public.guest_guide_greetings to authenticated;
grant select on public.guest_guide_versions to authenticated;
grant select on public.guest_guide_events to authenticated;

-- ============================================================================
-- 11. DEFAULT SETTINGS, SECTIONS AND GREETINGS
-- ============================================================================

insert into public.guest_guide_settings (
  hotel_id,
  template_key,
  default_locale,
  enabled_locales,
  publish_status,
  theme,
  branding,
  navigation
)
select
  h.id,
  'stayqr_luxury',
  'en',
  coalesce(
    (
      select array_agg(c.locale order by c.locale)
      from public.hotel_guest_content c
      where c.hotel_id = h.id
        and c.is_active
        and c.locale = any (
          array[
            'en','hi','mr','ta','te','bn',
            'gu','kn','ml','pa','or','as'
          ]::text[]
        )
    ),
    array['en']::text[]
  ),
  'draft',
  jsonb_build_object(
    'mode', 'dark',
    'primary_color', '#080808',
    'accent_color', '#C9A84C',
    'surface_color', '#161616',
    'text_color', '#FAFAFA',
    'heading_font', 'Playfair Display',
    'body_font', 'Montserrat',
    'card_radius', 16,
    'glass_effect', true
  ),
  jsonb_build_object(
    'show_stayqr_branding', true,
    'stayqr_label', 'Powered by StayQR',
    'stayqr_tagline', 'Scan. Stay. Simplified.'
  ),
  jsonb_build_object(
    'sticky_quick_actions', true,
    'show_section_numbers', true,
    'compact_mobile_hero', true
  )
from public.hotels h
on conflict (hotel_id) do nothing;

with defaults(
  section_key,
  section_type,
  sort_order,
  label,
  title,
  subtitle
) as (
  values
    (
      'hero',
      'hero',
      10,
      '01 — Welcome',
      'Welcome',
      'Your secure digital companion for a comfortable stay.'
    ),
    (
      'stay_overview',
      'stay',
      20,
      '02 — Your Stay',
      'Stay at a Glance',
      'Room, timings and essential information.'
    ),
    (
      'quick_access',
      'actions',
      30,
      '03 — Quick Access',
      'Your Digital Concierge',
      'Everything you need, at your fingertips.'
    ),
    (
      'wifi',
      'wifi',
      40,
      '04 — Wi-Fi',
      'Stay Connected',
      'Secure hotel Wi-Fi details for your active stay.'
    ),
    (
      'room_gallery',
      'gallery',
      50,
      '05 — Your Room',
      'Room Gallery',
      'A visual introduction to your room.'
    ),
    (
      'room_guide',
      'instructions',
      60,
      '06 — Room Guide',
      'Smart Room Instructions',
      'AC, TV, remote, geyser, bathtub, safe and more.'
    ),
    (
      'hotel_facilities',
      'facilities',
      70,
      '07 — Facilities',
      'Hotel Facilities',
      'Explore the facilities available at the property.'
    ),
    (
      'dining',
      'dining',
      80,
      '08 — Dining',
      'Dining & Room Service',
      'Food timings, menu and ordering access.'
    ),
    (
      'guest_services',
      'services',
      90,
      '09 — Services',
      'Guest Services',
      'Request assistance from the appropriate hotel team.'
    ),
    (
      'safety',
      'safety',
      100,
      '10 — Safety',
      'Safety & Emergency',
      'Important safety information and emergency actions.'
    ),
    (
      'important_contacts',
      'contacts',
      110,
      '11 — Contacts',
      'Important Contacts',
      'Call, WhatsApp or email the hotel team.'
    ),
    (
      'stay_connected',
      'social',
      120,
      '12 — Stay Connected',
      'Stay Connected',
      'Connect with the hotel online.'
    ),
    (
      'local_convenience',
      'local',
      130,
      '13 — Local Convenience',
      'Discover the Local Area',
      'Nearby essentials and local experiences.'
    ),
    (
      'payment',
      'payment',
      140,
      '14 — Payment',
      'Payment Assistance',
      'View supported payment information and balance.'
    ),
    (
      'feedback',
      'feedback',
      150,
      '15 — Feedback',
      'How Was Your Stay?',
      'Share private feedback directly with the hotel.'
    ),
    (
      'google_review',
      'review',
      160,
      '16 — Review',
      'Enjoyed Your Stay?',
      'Share your experience through the hotel review page.'
    ),
    (
      'policies',
      'policies',
      170,
      '17 — Policies',
      'Hotel Policies',
      'Review the important terms for your stay.'
    ),
    (
      'thank_you',
      'closing',
      180,
      '18 — Thank You',
      'Thank You for Staying With Us',
      'We hope to welcome you again.'
    )
),
inserted as (
  insert into public.guest_guide_sections (
    hotel_id,
    section_key,
    section_type,
    sort_order,
    is_enabled,
    settings
  )
  select
    h.id,
    d.section_key,
    d.section_type,
    d.sort_order,
    true,
    '{}'::jsonb
  from public.hotels h
  cross join defaults d
  on conflict (hotel_id, section_key) do nothing
  returning hotel_id, id, section_key
)
insert into public.guest_guide_section_translations (
  hotel_id,
  section_id,
  locale,
  label,
  title,
  subtitle
)
select
  s.hotel_id,
  s.id,
  'en',
  d.label,
  d.title,
  d.subtitle
from public.guest_guide_sections s
join defaults d
  on d.section_key = s.section_key
on conflict (section_id, locale) do nothing;

with greeting_defaults(
  locale,
  language_name,
  native_name,
  neutral_greeting,
  morning_greeting,
  afternoon_greeting,
  evening_greeting,
  night_greeting,
  sort_order
) as (
  values
    (
      'en',
      'English',
      'English',
      'Hello',
      'Good morning',
      'Good afternoon',
      'Good evening',
      'Good night',
      10
    ),
    (
      'hi',
      'Hindi',
      'हिन्दी',
      'नमस्ते',
      'सुप्रभात',
      'नमस्कार',
      'शुभ संध्या',
      'शुभ रात्रि',
      20
    ),
    (
      'mr',
      'Marathi',
      'मराठी',
      'नमस्कार',
      'शुभ प्रभात',
      'शुभ दुपार',
      'शुभ संध्याकाळ',
      'शुभ रात्री',
      30
    ),
    (
      'ta',
      'Tamil',
      'தமிழ்',
      'வணக்கம்',
      'காலை வணக்கம்',
      'மதிய வணக்கம்',
      'மாலை வணக்கம்',
      'இனிய இரவு',
      40
    ),
    (
      'te',
      'Telugu',
      'తెలుగు',
      'నమస్కారం',
      'శుభోదయం',
      'శుభ మధ్యాహ్నం',
      'శుభ సాయంత్రం',
      'శుభ రాత్రి',
      50
    ),
    (
      'bn',
      'Bengali',
      'বাংলা',
      'নমস্কার',
      'সুপ্রভাত',
      'শুভ অপরাহ্ণ',
      'শুভ সন্ধ্যা',
      'শুভ রাত্রি',
      60
    ),
    (
      'gu',
      'Gujarati',
      'ગુજરાતી',
      'નમસ્તે',
      'સુપ્રભાત',
      'શુભ બપોર',
      'શુભ સાંજ',
      'શુભ રાત્રિ',
      70
    ),
    (
      'kn',
      'Kannada',
      'ಕನ್ನಡ',
      'ನಮಸ್ಕಾರ',
      'ಶುಭೋದಯ',
      'ಶುಭ ಮಧ್ಯಾಹ್ನ',
      'ಶುಭ ಸಂಜೆ',
      'ಶುಭ ರಾತ್ರಿ',
      80
    ),
    (
      'ml',
      'Malayalam',
      'മലയാളം',
      'നമസ്കാരം',
      'സുപ്രഭാതം',
      'ശുഭ ഉച്ചതിരിഞ്ഞ്',
      'ശുഭ സായാഹ്നം',
      'ശുഭ രാത്രി',
      90
    ),
    (
      'pa',
      'Punjabi',
      'ਪੰਜਾਬੀ',
      'ਸਤ ਸ੍ਰੀ ਅਕਾਲ',
      'ਸ਼ੁਭ ਸਵੇਰ',
      'ਸ਼ੁਭ ਦੁਪਹਿਰ',
      'ਸ਼ੁਭ ਸ਼ਾਮ',
      'ਸ਼ੁਭ ਰਾਤ',
      100
    ),
    (
      'or',
      'Odia',
      'ଓଡ଼ିଆ',
      'ନମସ୍କାର',
      'ସୁପ୍ରଭାତ',
      'ଶୁଭ ଅପରାହ୍ନ',
      'ଶୁଭ ସନ୍ଧ୍ୟା',
      'ଶୁଭରାତ୍ରି',
      110
    ),
    (
      'as',
      'Assamese',
      'অসমীয়া',
      'নমস্কাৰ',
      'সুপ্ৰভাত',
      'শুভ দুপৰীয়া',
      'শুভ সন্ধিয়া',
      'শুভ ৰাত্ৰি',
      120
    )
)
insert into public.guest_guide_greetings (
  hotel_id,
  locale,
  language_name,
  native_name,
  neutral_greeting,
  morning_greeting,
  afternoon_greeting,
  evening_greeting,
  night_greeting,
  is_enabled,
  sort_order
)
select
  h.id,
  g.locale,
  g.language_name,
  g.native_name,
  g.neutral_greeting,
  g.morning_greeting,
  g.afternoon_greeting,
  g.evening_greeting,
  g.night_greeting,
  (
    g.locale = any(
      coalesce(
        (
          select s.enabled_locales
          from public.guest_guide_settings s
          where s.hotel_id = h.id
        ),
        array['en']::text[]
      )
    )
  ),
  g.sort_order
from public.hotels h
cross join greeting_defaults g
on conflict (hotel_id, locale) do nothing;

insert into public.guest_guide_payment_profiles (
  hotel_id
)
select h.id
from public.hotels h
on conflict (hotel_id) do nothing;

-- ============================================================================
-- 12. SNAPSHOT BUILDER
-- ============================================================================

create or replace function private.day14_build_guide_snapshot(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_snapshot jsonb;
begin
  select jsonb_build_object(
    'schema_version', 1,
    'generated_at', now(),
    'hotel_id', p_hotel_id,
    'settings', jsonb_build_object(
      'template_key', s.template_key,
      'default_locale', s.default_locale,
      'enabled_locales', to_jsonb(s.enabled_locales),
      'theme', s.theme,
      'branding', s.branding,
      'navigation', s.navigation
    ),
    'legacy_content', coalesce(
      (
        select jsonb_object_agg(c.locale, c.content)
        from public.hotel_guest_content c
        where c.hotel_id = p_hotel_id
          and c.is_active
      ),
      '{}'::jsonb
    ),
    'sections', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', sec.id,
            'section_key', sec.section_key,
            'section_type', sec.section_type,
            'sort_order', sec.sort_order,
            'is_enabled', sec.is_enabled,
            'settings', sec.settings,
            'translations', coalesce(
              (
                select jsonb_object_agg(
                  tr.locale,
                  jsonb_strip_nulls(
                    jsonb_build_object(
                      'label', tr.label,
                      'title', tr.title,
                      'subtitle', tr.subtitle,
                      'body', tr.body,
                      'button_label', tr.button_label,
                      'metadata', tr.metadata
                    )
                  )
                )
                from public.guest_guide_section_translations tr
                where tr.section_id = sec.id
              ),
              '{}'::jsonb
            )
          )
          order by sec.sort_order, sec.section_key
        )
        from public.guest_guide_sections sec
        where sec.hotel_id = p_hotel_id
      ),
      '[]'::jsonb
    ),
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', i.id,
            'section_id', i.section_id,
            'scope_type', i.scope_type,
            'room_type_id', i.room_type_id,
            'room_id', i.room_id,
            'item_key', i.item_key,
            'item_type', i.item_type,
            'icon', i.icon,
            'action_type', i.action_type,
            'action_value', i.action_value,
            'sort_order', i.sort_order,
            'is_enabled', i.is_enabled,
            'metadata', i.metadata,
            'translations', coalesce(
              (
                select jsonb_object_agg(
                  tr.locale,
                  jsonb_strip_nulls(
                    jsonb_build_object(
                      'title', tr.title,
                      'subtitle', tr.subtitle,
                      'description', tr.description,
                      'instructions', tr.instructions,
                      'disclaimer', tr.disclaimer,
                      'button_label', tr.button_label,
                      'metadata', tr.metadata
                    )
                  )
                )
                from public.guest_guide_item_translations tr
                where tr.item_id = i.id
              ),
              '{}'::jsonb
            )
          )
          order by i.section_id, i.sort_order, i.item_key
        )
        from public.guest_guide_items i
        where i.hotel_id = p_hotel_id
      ),
      '[]'::jsonb
    ),
    'media', coalesce(
      (
        select jsonb_agg(
          jsonb_strip_nulls(
            jsonb_build_object(
              'id', m.id,
              'section_id', m.section_id,
              'item_id', m.item_id,
              'scope_type', m.scope_type,
              'room_type_id', m.room_type_id,
              'room_id', m.room_id,
              'media_key', m.media_key,
              'category', m.category,
              'bucket_id', m.bucket_id,
              'object_path', m.object_path,
              'mime_type', m.mime_type,
              'title', m.title,
              'caption', m.caption,
              'alt_text', m.alt_text,
              'locale', m.locale,
              'sort_order', m.sort_order,
              'is_active', m.is_active,
              'metadata', m.metadata
            )
          )
          order by m.sort_order, m.media_key
        )
        from public.guest_guide_media m
        where m.hotel_id = p_hotel_id
      ),
      '[]'::jsonb
    ),
    'payment_profile', coalesce(
      (
        select jsonb_strip_nulls(
          jsonb_build_object(
            'is_enabled', p.is_enabled,
            'payee_name', p.payee_name,
            'upi_id', p.upi_id,
            'qr_media_id', p.qr_media_id,
            'instructions', p.instructions,
            'show_outstanding_balance', p.show_outstanding_balance,
            'require_reception_confirmation',
              p.require_reception_confirmation,
            'metadata', p.metadata
          )
        )
        from public.guest_guide_payment_profiles p
        where p.hotel_id = p_hotel_id
      ),
      '{}'::jsonb
    ),
    'greetings', coalesce(
      (
        select jsonb_object_agg(
          g.locale,
          jsonb_build_object(
            'language_name', g.language_name,
            'native_name', g.native_name,
            'neutral', g.neutral_greeting,
            'morning', g.morning_greeting,
            'afternoon', g.afternoon_greeting,
            'evening', g.evening_greeting,
            'night', g.night_greeting,
            'is_enabled', g.is_enabled,
            'sort_order', g.sort_order
          )
        )
        from public.guest_guide_greetings g
        where g.hotel_id = p_hotel_id
      ),
      '{}'::jsonb
    )
  )
  into v_snapshot
  from public.guest_guide_settings s
  where s.hotel_id = p_hotel_id;

  if v_snapshot is null then
    raise exception 'Guest guide settings were not found.';
  end if;

  return v_snapshot;
end;
$function$;

revoke all on function private.day14_build_guide_snapshot(uuid)
from public, anon, authenticated;

-- ============================================================================
-- 13. ADMIN BUILDER RPCs
-- ============================================================================

create or replace function public.get_guest_guide_builder(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide builder access denied.';
  end if;

  return private.day14_build_guide_snapshot(p_hotel_id)
    || jsonb_build_object(
      'publish_state',
      (
        select jsonb_build_object(
          'publish_status', s.publish_status,
          'draft_revision', s.draft_revision,
          'published_version', s.published_version,
          'published_at', s.published_at
        )
        from public.guest_guide_settings s
        where s.hotel_id = p_hotel_id
      ),
      'room_types',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', rt.id,
              'name', rt.name,
              'code', rt.code,
              'description', rt.description,
              'is_active', rt.is_active
            )
            order by rt.sort_order, rt.name
          )
          from public.room_types rt
          where rt.hotel_id = p_hotel_id
        ),
        '[]'::jsonb
      ),
      'rooms',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', r.id,
              'room_number', r.room_number,
              'room_type_id', r.room_type_id,
              'room_type', r.room_type,
              'status', r.status,
              'is_active', r.is_active
            )
            order by r.room_number
          )
          from public.rooms r
          where r.hotel_id = p_hotel_id
        ),
        '[]'::jsonb
      ),
      'versions',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', v.id,
              'version_number', v.version_number,
              'publish_note', v.publish_note,
              'published_at', v.published_at,
              'published_by', v.published_by
            )
            order by v.version_number desc
          )
          from public.guest_guide_versions v
          where v.hotel_id = p_hotel_id
        ),
        '[]'::jsonb
      )
    );
end;
$function$;

create or replace function public.upsert_guest_guide_settings(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_default_locale text;
  v_enabled_locales text[];
  v_row public.guest_guide_settings%rowtype;
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide settings update denied.';
  end if;

  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Settings payload must be a JSON object.';
  end if;

  v_default_locale :=
    coalesce(
      nullif(trim(p_payload ->> 'default_locale'), ''),
      'en'
    );

  select coalesce(
    array_agg(value order by ordinal),
    array['en']::text[]
  )
  into v_enabled_locales
  from jsonb_array_elements_text(
    coalesce(
      p_payload -> 'enabled_locales',
      '["en"]'::jsonb
    )
  ) with ordinality as x(value, ordinal);

  if not (
    v_enabled_locales <@ array[
      'en','hi','mr','ta','te','bn',
      'gu','kn','ml','pa','or','as'
    ]::text[]
  ) then
    raise exception 'Unsupported locale in enabled_locales.';
  end if;

  if not (v_default_locale = any(v_enabled_locales)) then
    raise exception 'Default locale must be enabled.';
  end if;

  insert into public.guest_guide_settings (
    hotel_id,
    template_key,
    default_locale,
    enabled_locales,
    publish_status,
    theme,
    branding,
    navigation,
    updated_by
  )
  values (
    p_hotel_id,
    coalesce(
      nullif(trim(p_payload ->> 'template_key'), ''),
      'stayqr_luxury'
    ),
    v_default_locale,
    v_enabled_locales,
    'draft',
    coalesce(p_payload -> 'theme', '{}'::jsonb),
    coalesce(p_payload -> 'branding', '{}'::jsonb),
    coalesce(p_payload -> 'navigation', '{}'::jsonb),
    auth.uid()
  )
  on conflict (hotel_id)
  do update set
    template_key = excluded.template_key,
    default_locale = excluded.default_locale,
    enabled_locales = excluded.enabled_locales,
    publish_status = 'draft',
    theme = excluded.theme,
    branding = excluded.branding,
    navigation = excluded.navigation,
    draft_revision =
      public.guest_guide_settings.draft_revision + 1,
    updated_by = auth.uid(),
    updated_at = now()
  returning *
  into v_row;

  update public.guest_guide_greetings g
  set
    is_enabled = g.locale = any(v_enabled_locales),
    updated_by = auth.uid(),
    updated_at = now()
  where g.hotel_id = p_hotel_id;

  return jsonb_build_object(
    'result', 'GUEST GUIDE SETTINGS SAVED',
    'hotel_id', v_row.hotel_id,
    'publish_status', v_row.publish_status,
    'draft_revision', v_row.draft_revision,
    'enabled_locales', to_jsonb(v_row.enabled_locales)
  );
end;
$function$;

create or replace function public.upsert_guest_guide_section(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_section public.guest_guide_sections%rowtype;
  v_translation record;
  v_section_key text;
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide section update denied.';
  end if;

  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Section payload must be a JSON object.';
  end if;

  v_section_key :=
    nullif(trim(p_payload ->> 'section_key'), '');

  if v_section_key is null then
    raise exception 'section_key is required.';
  end if;

  insert into public.guest_guide_sections (
    hotel_id,
    section_key,
    section_type,
    sort_order,
    is_enabled,
    settings,
    created_by,
    updated_by
  )
  values (
    p_hotel_id,
    v_section_key,
    coalesce(
      nullif(trim(p_payload ->> 'section_type'), ''),
      'custom'
    ),
    coalesce((p_payload ->> 'sort_order')::integer, 0),
    coalesce((p_payload ->> 'is_enabled')::boolean, true),
    coalesce(p_payload -> 'settings', '{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (hotel_id, section_key)
  do update set
    section_type = excluded.section_type,
    sort_order = excluded.sort_order,
    is_enabled = excluded.is_enabled,
    settings = excluded.settings,
    updated_by = auth.uid(),
    updated_at = now()
  returning *
  into v_section;

  for v_translation in
    select key as locale, value as payload
    from jsonb_each(
      coalesce(
        p_payload -> 'translations',
        '{}'::jsonb
      )
    )
  loop
    insert into public.guest_guide_section_translations (
      hotel_id,
      section_id,
      locale,
      label,
      title,
      subtitle,
      body,
      button_label,
      metadata
    )
    values (
      p_hotel_id,
      v_section.id,
      v_translation.locale,
      nullif(
        trim(v_translation.payload ->> 'label'),
        ''
      ),
      nullif(
        trim(v_translation.payload ->> 'title'),
        ''
      ),
      nullif(
        trim(v_translation.payload ->> 'subtitle'),
        ''
      ),
      nullif(
        trim(v_translation.payload ->> 'body'),
        ''
      ),
      nullif(
        trim(v_translation.payload ->> 'button_label'),
        ''
      ),
      coalesce(
        v_translation.payload -> 'metadata',
        '{}'::jsonb
      )
    )
    on conflict (section_id, locale)
    do update set
      label = excluded.label,
      title = excluded.title,
      subtitle = excluded.subtitle,
      body = excluded.body,
      button_label = excluded.button_label,
      metadata = excluded.metadata,
      updated_at = now();
  end loop;

  perform private.day14_mark_guide_draft(p_hotel_id);

  return jsonb_build_object(
    'result', 'GUEST GUIDE SECTION SAVED',
    'section_id', v_section.id,
    'section_key', v_section.section_key
  );
end;
$function$;

create or replace function public.upsert_guest_guide_item(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_item public.guest_guide_items%rowtype;
  v_translation record;
  v_section_id uuid;
  v_scope_type text;
  v_room_type_id uuid;
  v_room_id uuid;
  v_item_key text;
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide item update denied.';
  end if;

  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Item payload must be a JSON object.';
  end if;

  v_section_id := (p_payload ->> 'section_id')::uuid;
  v_scope_type :=
    coalesce(
      nullif(trim(p_payload ->> 'scope_type'), ''),
      'hotel'
    );
  v_room_type_id :=
    nullif(p_payload ->> 'room_type_id', '')::uuid;
  v_room_id :=
    nullif(p_payload ->> 'room_id', '')::uuid;
  v_item_key :=
    nullif(trim(p_payload ->> 'item_key'), '');

  if v_section_id is null or v_item_key is null then
    raise exception 'section_id and item_key are required.';
  end if;

  if not exists (
    select 1
    from public.guest_guide_sections s
    where s.hotel_id = p_hotel_id
      and s.id = v_section_id
  ) then
    raise exception 'Section does not belong to the hotel.';
  end if;

  insert into public.guest_guide_items (
    hotel_id,
    section_id,
    scope_type,
    room_type_id,
    room_id,
    item_key,
    item_type,
    icon,
    action_type,
    action_value,
    sort_order,
    is_enabled,
    metadata,
    created_by,
    updated_by
  )
  values (
    p_hotel_id,
    v_section_id,
    v_scope_type,
    v_room_type_id,
    v_room_id,
    v_item_key,
    coalesce(
      nullif(trim(p_payload ->> 'item_type'), ''),
      'custom'
    ),
    nullif(trim(p_payload ->> 'icon'), ''),
    coalesce(
      nullif(trim(p_payload ->> 'action_type'), ''),
      'none'
    ),
    nullif(trim(p_payload ->> 'action_value'), ''),
    coalesce((p_payload ->> 'sort_order')::integer, 0),
    coalesce((p_payload ->> 'is_enabled')::boolean, true),
    coalesce(p_payload -> 'metadata', '{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (
    hotel_id,
    section_id,
    scope_type,
    (
      coalesce(
        room_type_id,
        '00000000-0000-0000-0000-000000000000'::uuid
      )
    ),
    (
      coalesce(
        room_id,
        '00000000-0000-0000-0000-000000000000'::uuid
      )
    ),
    item_key
  )
  do update set
    item_type = excluded.item_type,
    icon = excluded.icon,
    action_type = excluded.action_type,
    action_value = excluded.action_value,
    sort_order = excluded.sort_order,
    is_enabled = excluded.is_enabled,
    metadata = excluded.metadata,
    updated_by = auth.uid(),
    updated_at = now()
  returning *
  into v_item;

  for v_translation in
    select key as locale, value as payload
    from jsonb_each(
      coalesce(
        p_payload -> 'translations',
        '{}'::jsonb
      )
    )
  loop
    insert into public.guest_guide_item_translations (
      hotel_id,
      item_id,
      locale,
      title,
      subtitle,
      description,
      instructions,
      disclaimer,
      button_label,
      metadata
    )
    values (
      p_hotel_id,
      v_item.id,
      v_translation.locale,
      nullif(
        trim(v_translation.payload ->> 'title'),
        ''
      ),
      nullif(
        trim(v_translation.payload ->> 'subtitle'),
        ''
      ),
      nullif(
        trim(v_translation.payload ->> 'description'),
        ''
      ),
      coalesce(
        v_translation.payload -> 'instructions',
        '[]'::jsonb
      ),
      nullif(
        trim(v_translation.payload ->> 'disclaimer'),
        ''
      ),
      nullif(
        trim(v_translation.payload ->> 'button_label'),
        ''
      ),
      coalesce(
        v_translation.payload -> 'metadata',
        '{}'::jsonb
      )
    )
    on conflict (item_id, locale)
    do update set
      title = excluded.title,
      subtitle = excluded.subtitle,
      description = excluded.description,
      instructions = excluded.instructions,
      disclaimer = excluded.disclaimer,
      button_label = excluded.button_label,
      metadata = excluded.metadata,
      updated_at = now();
  end loop;

  perform private.day14_mark_guide_draft(p_hotel_id);

  return jsonb_build_object(
    'result', 'GUEST GUIDE ITEM SAVED',
    'item_id', v_item.id,
    'item_key', v_item.item_key
  );
end;
$function$;

create or replace function public.upsert_guest_guide_media(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_media public.guest_guide_media%rowtype;
  v_scope_type text;
  v_room_type_id uuid;
  v_room_id uuid;
  v_object_path text;
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide media update denied.';
  end if;

  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Media payload must be a JSON object.';
  end if;

  v_scope_type :=
    coalesce(
      nullif(trim(p_payload ->> 'scope_type'), ''),
      'hotel'
    );
  v_room_type_id :=
    nullif(p_payload ->> 'room_type_id', '')::uuid;
  v_room_id :=
    nullif(p_payload ->> 'room_id', '')::uuid;
  v_object_path :=
    nullif(trim(p_payload ->> 'object_path'), '');

  if v_object_path is null
     or split_part(v_object_path, '/', 1) <> p_hotel_id::text then
    raise exception
      'Media object_path must begin with the hotel UUID folder.';
  end if;

  insert into public.guest_guide_media (
    hotel_id,
    section_id,
    item_id,
    scope_type,
    room_type_id,
    room_id,
    media_key,
    category,
    bucket_id,
    object_path,
    mime_type,
    title,
    caption,
    alt_text,
    locale,
    sort_order,
    is_active,
    metadata,
    created_by,
    updated_by
  )
  values (
    p_hotel_id,
    nullif(p_payload ->> 'section_id', '')::uuid,
    nullif(p_payload ->> 'item_id', '')::uuid,
    v_scope_type,
    v_room_type_id,
    v_room_id,
    nullif(trim(p_payload ->> 'media_key'), ''),
    nullif(trim(p_payload ->> 'category'), ''),
    'guest-guide-media',
    v_object_path,
    nullif(trim(p_payload ->> 'mime_type'), ''),
    nullif(trim(p_payload ->> 'title'), ''),
    nullif(trim(p_payload ->> 'caption'), ''),
    nullif(trim(p_payload ->> 'alt_text'), ''),
    nullif(trim(p_payload ->> 'locale'), ''),
    coalesce((p_payload ->> 'sort_order')::integer, 0),
    coalesce((p_payload ->> 'is_active')::boolean, true),
    coalesce(p_payload -> 'metadata', '{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (
    hotel_id,
    scope_type,
    (
      coalesce(
        room_type_id,
        '00000000-0000-0000-0000-000000000000'::uuid
      )
    ),
    (
      coalesce(
        room_id,
        '00000000-0000-0000-0000-000000000000'::uuid
      )
    ),
    media_key
  )
  do update set
    section_id = excluded.section_id,
    item_id = excluded.item_id,
    category = excluded.category,
    object_path = excluded.object_path,
    mime_type = excluded.mime_type,
    title = excluded.title,
    caption = excluded.caption,
    alt_text = excluded.alt_text,
    locale = excluded.locale,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active,
    metadata = excluded.metadata,
    updated_by = auth.uid(),
    updated_at = now()
  returning *
  into v_media;

  perform private.day14_mark_guide_draft(p_hotel_id);

  return jsonb_build_object(
    'result', 'GUEST GUIDE MEDIA SAVED',
    'media_id', v_media.id,
    'media_key', v_media.media_key,
    'object_path', v_media.object_path
  );
end;
$function$;

create or replace function public.upsert_guest_guide_greeting(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.guest_guide_greetings%rowtype;
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide greeting update denied.';
  end if;

  insert into public.guest_guide_greetings (
    hotel_id,
    locale,
    language_name,
    native_name,
    neutral_greeting,
    morning_greeting,
    afternoon_greeting,
    evening_greeting,
    night_greeting,
    is_enabled,
    sort_order,
    updated_by
  )
  values (
    p_hotel_id,
    nullif(trim(p_payload ->> 'locale'), ''),
    nullif(trim(p_payload ->> 'language_name'), ''),
    nullif(trim(p_payload ->> 'native_name'), ''),
    nullif(trim(p_payload ->> 'neutral_greeting'), ''),
    nullif(trim(p_payload ->> 'morning_greeting'), ''),
    nullif(trim(p_payload ->> 'afternoon_greeting'), ''),
    nullif(trim(p_payload ->> 'evening_greeting'), ''),
    nullif(trim(p_payload ->> 'night_greeting'), ''),
    coalesce((p_payload ->> 'is_enabled')::boolean, false),
    coalesce((p_payload ->> 'sort_order')::integer, 0),
    auth.uid()
  )
  on conflict (hotel_id, locale)
  do update set
    language_name = excluded.language_name,
    native_name = excluded.native_name,
    neutral_greeting = excluded.neutral_greeting,
    morning_greeting = excluded.morning_greeting,
    afternoon_greeting = excluded.afternoon_greeting,
    evening_greeting = excluded.evening_greeting,
    night_greeting = excluded.night_greeting,
    is_enabled = excluded.is_enabled,
    sort_order = excluded.sort_order,
    updated_by = auth.uid(),
    updated_at = now()
  returning *
  into v_row;

  perform private.day14_mark_guide_draft(p_hotel_id);

  return jsonb_build_object(
    'result', 'GUEST GUIDE GREETING SAVED',
    'locale', v_row.locale,
    'is_enabled', v_row.is_enabled
  );
end;
$function$;

create or replace function public.upsert_guest_guide_payment_profile(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.guest_guide_payment_profiles%rowtype;
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide payment profile update denied.';
  end if;

  insert into public.guest_guide_payment_profiles (
    hotel_id,
    is_enabled,
    payee_name,
    upi_id,
    qr_media_id,
    instructions,
    show_outstanding_balance,
    require_reception_confirmation,
    metadata,
    updated_by
  )
  values (
    p_hotel_id,
    coalesce((p_payload ->> 'is_enabled')::boolean, false),
    nullif(trim(p_payload ->> 'payee_name'), ''),
    nullif(trim(p_payload ->> 'upi_id'), ''),
    nullif(p_payload ->> 'qr_media_id', '')::uuid,
    nullif(trim(p_payload ->> 'instructions'), ''),
    coalesce(
      (p_payload ->> 'show_outstanding_balance')::boolean,
      true
    ),
    coalesce(
      (p_payload ->> 'require_reception_confirmation')::boolean,
      true
    ),
    coalesce(p_payload -> 'metadata', '{}'::jsonb),
    auth.uid()
  )
  on conflict (hotel_id)
  do update set
    is_enabled = excluded.is_enabled,
    payee_name = excluded.payee_name,
    upi_id = excluded.upi_id,
    qr_media_id = excluded.qr_media_id,
    instructions = excluded.instructions,
    show_outstanding_balance =
      excluded.show_outstanding_balance,
    require_reception_confirmation =
      excluded.require_reception_confirmation,
    metadata = excluded.metadata,
    updated_by = auth.uid(),
    updated_at = now()
  returning *
  into v_row;

  perform private.day14_mark_guide_draft(p_hotel_id);

  return jsonb_build_object(
    'result', 'GUEST GUIDE PAYMENT PROFILE SAVED',
    'is_enabled', v_row.is_enabled,
    'upi_id', v_row.upi_id
  );
end;
$function$;

create or replace function public.publish_guest_guide(
  p_hotel_id uuid,
  p_publish_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_next_version integer;
  v_snapshot jsonb;
  v_version public.guest_guide_versions%rowtype;
begin
  if not private.user_has_permission(
    p_hotel_id,
    'hotel.manage'
  ) then
    raise exception 'Guest guide publish denied.';
  end if;

  perform 1
  from public.guest_guide_settings
  where hotel_id = p_hotel_id
  for update;

  select coalesce(max(version_number), 0) + 1
  into v_next_version
  from public.guest_guide_versions
  where hotel_id = p_hotel_id;

  v_snapshot :=
    private.day14_build_guide_snapshot(p_hotel_id);

  insert into public.guest_guide_versions (
    hotel_id,
    version_number,
    snapshot,
    publish_note,
    published_by
  )
  values (
    p_hotel_id,
    v_next_version,
    v_snapshot,
    nullif(trim(coalesce(p_publish_note, '')), ''),
    auth.uid()
  )
  returning *
  into v_version;

  update public.guest_guide_settings
  set
    publish_status = 'published',
    published_version = v_next_version,
    published_at = v_version.published_at,
    published_by = auth.uid(),
    updated_by = auth.uid(),
    updated_at = now()
  where hotel_id = p_hotel_id;

  return jsonb_build_object(
    'result', 'GUEST GUIDE PUBLISHED',
    'version_id', v_version.id,
    'version_number', v_version.version_number,
    'published_at', v_version.published_at
  );
end;
$function$;

-- ============================================================================
-- 14. TOKEN-BOUND EVENT RPC
-- ============================================================================

create or replace function public.record_guest_guide_event(
  p_hotel_slug text,
  p_access_token text,
  p_event_type text,
  p_section_key text default null,
  p_item_id uuid default null,
  p_locale text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token_id uuid;
  v_token public.guest_access_tokens%rowtype;
  v_row public.guest_guide_events%rowtype;
begin
  v_token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if v_token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select t.*
  into v_token
  from public.guest_access_tokens t
  where t.id = v_token_id;

  insert into public.guest_guide_events (
    hotel_id,
    guest_session_id,
    guest_access_token_id,
    event_type,
    section_key,
    item_id,
    locale,
    metadata
  )
  values (
    v_token.hotel_id,
    v_token.guest_session_id,
    v_token.id,
    lower(trim(p_event_type)),
    nullif(trim(coalesce(p_section_key, '')), ''),
    p_item_id,
    nullif(trim(coalesce(p_locale, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning *
  into v_row;

  return jsonb_build_object(
    'result', 'GUEST GUIDE EVENT RECORDED',
    'event_id', v_row.id,
    'event_type', v_row.event_type,
    'occurred_at', v_row.occurred_at
  );
end;
$function$;

-- ============================================================================
-- 15. PREMIUM SIGNED GUEST RESOLVER
-- ============================================================================

create or replace function public.resolve_premium_guest_guide(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token_id uuid;
  v_token public.guest_access_tokens%rowtype;
  v_snapshot jsonb;
  v_filtered_items jsonb;
  v_filtered_media jsonb;
  v_response jsonb;
  v_room_type_id uuid;
  v_hour integer;
  v_greeting_period text;
begin
  v_token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if v_token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select t.*
  into v_token
  from public.guest_access_tokens t
  where t.id = v_token_id;

  select r.room_type_id
  into v_room_type_id
  from public.rooms r
  where r.hotel_id = v_token.hotel_id
    and r.id = v_token.room_id;

  select v.snapshot
  into v_snapshot
  from public.guest_guide_versions v
  join public.guest_guide_settings s
    on s.hotel_id = v.hotel_id
   and s.published_version = v.version_number
  where v.hotel_id = v_token.hotel_id
  order by v.version_number desc
  limit 1;

  if v_snapshot is null then
    v_snapshot :=
      private.day14_build_guide_snapshot(v_token.hotel_id);
  end if;

  select coalesce(
    jsonb_agg(x.item order by x.sort_order, x.item_key),
    '[]'::jsonb
  )
  into v_filtered_items
  from (
    select distinct on (
      item ->> 'section_id',
      item ->> 'item_key'
    )
      item,
      coalesce((item ->> 'sort_order')::integer, 0)
        as sort_order,
      item ->> 'item_key' as item_key,
      case item ->> 'scope_type'
        when 'room' then 3
        when 'room_type' then 2
        else 1
      end as scope_priority
    from jsonb_array_elements(
      coalesce(v_snapshot -> 'items', '[]'::jsonb)
    ) item
    where coalesce(
      (item ->> 'is_enabled')::boolean,
      true
    )
      and (
        item ->> 'scope_type' = 'hotel'
        or (
          item ->> 'scope_type' = 'room_type'
          and nullif(item ->> 'room_type_id', '')::uuid
            = v_room_type_id
        )
        or (
          item ->> 'scope_type' = 'room'
          and nullif(item ->> 'room_id', '')::uuid
            = v_token.room_id
        )
      )
    order by
      item ->> 'section_id',
      item ->> 'item_key',
      scope_priority desc
  ) x;

  select coalesce(
    jsonb_agg(
      item
      order by
        coalesce((item ->> 'sort_order')::integer, 0),
        item ->> 'media_key'
    ),
    '[]'::jsonb
  )
  into v_filtered_media
  from jsonb_array_elements(
    coalesce(v_snapshot -> 'media', '[]'::jsonb)
  ) item
  where coalesce(
    (item ->> 'is_active')::boolean,
    true
  )
    and (
      item ->> 'scope_type' = 'hotel'
      or (
        item ->> 'scope_type' = 'room_type'
        and nullif(item ->> 'room_type_id', '')::uuid
          = v_room_type_id
      )
      or (
        item ->> 'scope_type' = 'room'
        and nullif(item ->> 'room_id', '')::uuid
          = v_token.room_id
      )
    );

  select extract(
    hour from now() at time zone h.timezone
  )::integer
  into v_hour
  from public.hotels h
  where h.id = v_token.hotel_id;

  v_greeting_period :=
    case
      when v_hour between 5 and 11 then 'morning'
      when v_hour between 12 and 16 then 'afternoon'
      when v_hour between 17 and 21 then 'evening'
      else 'night'
    end;

  select jsonb_build_object(
    'hotel',
    jsonb_build_object(
      'hotel_name', h.hotel_name,
      'slug', h.slug,
      'location', h.location,
      'timezone', h.timezone,
      'currency_code', h.currency_code
    ),
    'hotel_info',
    jsonb_strip_nulls(
      jsonb_build_object(
        'hotel_name', coalesce(hi.hotel_name, h.hotel_name),
        'address', coalesce(hi.address, h.address, h.location),
        'reception_phone', hi.reception_phone,
        'emergency_phone', hi.emergency_phone,
        'checkin_time', hi.checkin_time,
        'checkout_time', hi.checkout_time,
        'breakfast_time', hi.breakfast_time,
        'wifi_name', hi.wifi_name,
        'wifi_password', hi.wifi_password,
        'hotel_rules', hi.hotel_rules,
        'about', hi.about,
        'google_review_url', hi.google_review_url,
        'reward_title', hi.reward_title,
        'reward_description', hi.reward_description,
        'reward_enabled', coalesce(hi.reward_enabled, false)
      )
    ),
    'guest_content',
    jsonb_build_object(
      'default_locale',
        v_snapshot #>> '{settings,default_locale}',
      'available_locales',
        coalesce(
          v_snapshot #> '{settings,enabled_locales}',
          '["en"]'::jsonb
        ),
      'translations',
        coalesce(
          v_snapshot -> 'legacy_content',
          '{}'::jsonb
        ),
      'amenities',
        coalesce(
          (
            select jsonb_agg(
              jsonb_strip_nulls(
                jsonb_build_object(
                  'id', a.id,
                  'name', a.name,
                  'description', a.description,
                  'instructions', a.instructions,
                  'icon', a.icon,
                  'sort_order', a.sort_order
                )
              )
              order by a.sort_order, a.name
            )
            from public.amenities a
            where a.hotel_id = h.id
              and a.is_active
              and a.guest_visible
          ),
          '[]'::jsonb
        ),
      'feedback_enabled', true
    ),
    'premium_guide',
    jsonb_build_object(
      'schema_version',
        coalesce(
          (v_snapshot ->> 'schema_version')::integer,
          1
        ),
      'settings',
        coalesce(v_snapshot -> 'settings', '{}'::jsonb),
      'sections',
        coalesce(v_snapshot -> 'sections', '[]'::jsonb),
      'items',
        v_filtered_items,
      'media',
        v_filtered_media,
      'payment_profile',
        coalesce(
          v_snapshot -> 'payment_profile',
          '{}'::jsonb
        ),
      'greetings',
        coalesce(v_snapshot -> 'greetings', '{}'::jsonb),
      'greeting_period',
        v_greeting_period,
      'storage_public_base',
        '/storage/v1/object/public/guest-guide-media/'
    ),
    'session',
    jsonb_build_object(
      'id', gs.id,
      'checkin_time', gs.checkin_time,
      'checkout_time', gs.checkout_time,
      'extended_until', gs.extended_until,
      'guest',
      jsonb_build_object(
        'id', g.id,
        'full_name', g.full_name
      ),
      'room',
      jsonb_build_object(
        'id', r.id,
        'room_number', r.room_number,
        'room_type', r.room_type,
        'room_type_id', r.room_type_id
      )
    ),
    'folio',
    coalesce(
      (
        select jsonb_build_object(
          'id', f.id,
          'currency_code', f.currency_code,
          'status', f.status,
          'charges_amount', f.charges_amount,
          'discount_amount', f.discount_amount,
          'tax_amount', f.tax_amount,
          'collection_amount', f.collection_amount,
          'refund_amount', f.refund_amount,
          'credit_amount', f.credit_amount,
          'balance_amount', f.balance_amount
        )
        from public.folios f
        where f.hotel_id = gs.hotel_id
          and f.guest_session_id = gs.id
        order by f.created_at desc
        limit 1
      ),
      '{}'::jsonb
    )
  )
  into v_response
  from public.guest_access_tokens t
  join public.hotels h
    on h.id = t.hotel_id
  join public.guest_sessions gs
    on gs.id = t.guest_session_id
   and gs.hotel_id = t.hotel_id
  join public.guests g
    on g.id = gs.guest_id
   and g.hotel_id = t.hotel_id
  join public.rooms r
    on r.id = t.room_id
   and r.hotel_id = t.hotel_id
  left join public.hotel_info hi
    on hi.hotel_id = t.hotel_id
  where t.id = v_token_id;

  return v_response;
end;
$function$;

-- ============================================================================
-- 16. INITIAL VERSION SNAPSHOT
-- ============================================================================

do $initial_publish$
declare
  v_hotel record;
  v_snapshot jsonb;
begin
  for v_hotel in
    select h.id
    from public.hotels h
  loop
    if not exists (
      select 1
      from public.guest_guide_versions v
      where v.hotel_id = v_hotel.id
    ) then
      v_snapshot :=
        private.day14_build_guide_snapshot(v_hotel.id);

      insert into public.guest_guide_versions (
        hotel_id,
        version_number,
        snapshot,
        publish_note
      )
      values (
        v_hotel.id,
        1,
        v_snapshot,
        'Initial Day 14 premium guide migration snapshot'
      );

      update public.guest_guide_settings
      set
        publish_status = 'published',
        published_version = 1,
        published_at = now(),
        updated_at = now()
      where hotel_id = v_hotel.id;
    end if;
  end loop;
end;
$initial_publish$;

-- ============================================================================
-- 17. FUNCTION ACLs
-- ============================================================================

revoke all on function public.get_guest_guide_builder(uuid)
from public, anon;

revoke all on function public.upsert_guest_guide_settings(uuid,jsonb)
from public, anon;

revoke all on function public.upsert_guest_guide_section(uuid,jsonb)
from public, anon;

revoke all on function public.upsert_guest_guide_item(uuid,jsonb)
from public, anon;

revoke all on function public.upsert_guest_guide_media(uuid,jsonb)
from public, anon;

revoke all on function public.upsert_guest_guide_greeting(uuid,jsonb)
from public, anon;

revoke all on function public.upsert_guest_guide_payment_profile(uuid,jsonb)
from public, anon;

revoke all on function public.publish_guest_guide(uuid,text)
from public, anon;

grant execute on function public.get_guest_guide_builder(uuid)
to authenticated;

grant execute on function public.upsert_guest_guide_settings(uuid,jsonb)
to authenticated;

grant execute on function public.upsert_guest_guide_section(uuid,jsonb)
to authenticated;

grant execute on function public.upsert_guest_guide_item(uuid,jsonb)
to authenticated;

grant execute on function public.upsert_guest_guide_media(uuid,jsonb)
to authenticated;

grant execute on function public.upsert_guest_guide_greeting(uuid,jsonb)
to authenticated;

grant execute on function public.upsert_guest_guide_payment_profile(uuid,jsonb)
to authenticated;

grant execute on function public.publish_guest_guide(uuid,text)
to authenticated;

revoke all on function public.resolve_premium_guest_guide(text,text)
from public, anon, authenticated;

grant execute on function public.resolve_premium_guest_guide(text,text)
to anon, authenticated;

revoke all on function public.record_guest_guide_event(
  text,text,text,text,uuid,text,jsonb
)
from public, anon, authenticated;

grant execute on function public.record_guest_guide_event(
  text,text,text,text,uuid,text,jsonb
)
to anon, authenticated;

commit;

-- ============================================================================
-- 18. ACCEPTANCE — 72 CHECKS
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_guest_guide_settings_table',
      to_regclass('public.guest_guide_settings') is not null,
      'Builder settings table exists.'
    ),
    (
      '02_guest_guide_sections_table',
      to_regclass('public.guest_guide_sections') is not null,
      'Guide sections table exists.'
    ),
    (
      '03_section_translations_table',
      to_regclass(
        'public.guest_guide_section_translations'
      ) is not null,
      'Section translations table exists.'
    ),
    (
      '04_guest_guide_items_table',
      to_regclass('public.guest_guide_items') is not null,
      'Scoped guide items table exists.'
    ),
    (
      '05_item_translations_table',
      to_regclass(
        'public.guest_guide_item_translations'
      ) is not null,
      'Item translations table exists.'
    ),
    (
      '06_guest_guide_media_table',
      to_regclass('public.guest_guide_media') is not null,
      'Guide media metadata table exists.'
    ),
    (
      '07_payment_profiles_table',
      to_regclass(
        'public.guest_guide_payment_profiles'
      ) is not null,
      'Payment profile table exists.'
    ),
    (
      '08_greetings_table',
      to_regclass('public.guest_guide_greetings') is not null,
      'Editable greeting table exists.'
    ),
    (
      '09_versions_table',
      to_regclass('public.guest_guide_versions') is not null,
      'Published version table exists.'
    ),
    (
      '10_events_table',
      to_regclass('public.guest_guide_events') is not null,
      'Guest guide event table exists.'
    ),
    (
      '11_media_bucket_exists',
      exists (
        select 1
        from storage.buckets
        where id = 'guest-guide-media'
      ),
      'Dedicated guest-guide media bucket exists.'
    ),
    (
      '12_media_bucket_public',
      coalesce(
        (
          select b.public
          from storage.buckets b
          where b.id = 'guest-guide-media'
        ),
        false
      ),
      'Guest-guide media bucket supports public media delivery.'
    ),
    (
      '13_media_bucket_size_limit',
      coalesce(
        (
          select b.file_size_limit = 8388608
          from storage.buckets b
          where b.id = 'guest-guide-media'
        ),
        false
      ),
      'Guest-guide media is limited to 8 MB per file.'
    ),
    (
      '14_media_insert_policy',
      exists (
        select 1
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname =
            'stayqr_guest_guide_media_insert'
      ),
      'Tenant-scoped media upload policy exists.'
    ),
    (
      '15_media_update_policy',
      exists (
        select 1
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname =
            'stayqr_guest_guide_media_update'
      ),
      'Tenant-scoped media update policy exists.'
    ),
    (
      '16_media_delete_policy',
      exists (
        select 1
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname =
            'stayqr_guest_guide_media_delete'
      ),
      'Tenant-scoped media delete policy exists.'
    ),
    (
      '17_settings_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'guest_guide_settings'
        ),
        false
      ),
      'Builder settings RLS is enabled.'
    ),
    (
      '18_sections_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'guest_guide_sections'
        ),
        false
      ),
      'Guide sections RLS is enabled.'
    ),
    (
      '19_items_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'guest_guide_items'
        ),
        false
      ),
      'Guide items RLS is enabled.'
    ),
    (
      '20_media_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'guest_guide_media'
        ),
        false
      ),
      'Guide media metadata RLS is enabled.'
    ),
    (
      '21_payment_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname =
              'guest_guide_payment_profiles'
        ),
        false
      ),
      'Payment profile RLS is enabled.'
    ),
    (
      '22_greetings_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'guest_guide_greetings'
        ),
        false
      ),
      'Greetings RLS is enabled.'
    ),
    (
      '23_versions_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'guest_guide_versions'
        ),
        false
      ),
      'Guide versions RLS is enabled.'
    ),
    (
      '24_events_rls',
      coalesce(
        (
          select c.relrowsecurity
          from pg_class c
          join pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'guest_guide_events'
        ),
        false
      ),
      'Guide events RLS is enabled.'
    ),
    (
      '25_anon_no_settings_read',
      not has_table_privilege(
        'anon',
        'public.guest_guide_settings',
        'SELECT'
      ),
      'Anonymous users cannot read builder settings directly.'
    ),
    (
      '26_anon_no_sections_read',
      not has_table_privilege(
        'anon',
        'public.guest_guide_sections',
        'SELECT'
      ),
      'Anonymous users cannot enumerate guide sections directly.'
    ),
    (
      '27_anon_no_items_read',
      not has_table_privilege(
        'anon',
        'public.guest_guide_items',
        'SELECT'
      ),
      'Anonymous users cannot enumerate guide items directly.'
    ),
    (
      '28_anon_no_media_table_read',
      not has_table_privilege(
        'anon',
        'public.guest_guide_media',
        'SELECT'
      ),
      'Anonymous users cannot enumerate media metadata directly.'
    ),
    (
      '29_anon_no_payment_read',
      not has_table_privilege(
        'anon',
        'public.guest_guide_payment_profiles',
        'SELECT'
      ),
      'Anonymous users cannot read payment profiles directly.'
    ),
    (
      '30_anon_no_builder_write',
      not (
        has_table_privilege(
          'anon',
          'public.guest_guide_settings',
          'INSERT'
        )
        or has_table_privilege(
          'anon',
          'public.guest_guide_sections',
          'INSERT'
        )
        or has_table_privilege(
          'anon',
          'public.guest_guide_items',
          'INSERT'
        )
        or has_table_privilege(
          'anon',
          'public.guest_guide_media',
          'INSERT'
        )
      ),
      'Anonymous users cannot directly modify builder data.'
    ),
    (
      '31_get_builder_rpc',
      to_regprocedure(
        'public.get_guest_guide_builder(uuid)'
      ) is not null,
      'Builder read RPC exists.'
    ),
    (
      '32_settings_rpc',
      to_regprocedure(
        'public.upsert_guest_guide_settings(uuid,jsonb)'
      ) is not null,
      'Settings RPC exists.'
    ),
    (
      '33_section_rpc',
      to_regprocedure(
        'public.upsert_guest_guide_section(uuid,jsonb)'
      ) is not null,
      'Section RPC exists.'
    ),
    (
      '34_item_rpc',
      to_regprocedure(
        'public.upsert_guest_guide_item(uuid,jsonb)'
      ) is not null,
      'Item RPC exists.'
    ),
    (
      '35_media_rpc',
      to_regprocedure(
        'public.upsert_guest_guide_media(uuid,jsonb)'
      ) is not null,
      'Media metadata RPC exists.'
    ),
    (
      '36_greeting_rpc',
      to_regprocedure(
        'public.upsert_guest_guide_greeting(uuid,jsonb)'
      ) is not null,
      'Greeting RPC exists.'
    ),
    (
      '37_payment_rpc',
      to_regprocedure(
        'public.upsert_guest_guide_payment_profile(uuid,jsonb)'
      ) is not null,
      'Payment profile RPC exists.'
    ),
    (
      '38_publish_rpc',
      to_regprocedure(
        'public.publish_guest_guide(uuid,text)'
      ) is not null,
      'Guide publish RPC exists.'
    ),
    (
      '39_event_rpc',
      to_regprocedure(
        'public.record_guest_guide_event(
          text,text,text,text,uuid,text,jsonb
        )'
      ) is not null,
      'Token-bound event RPC exists.'
    ),
    (
      '40_premium_resolver_rpc',
      to_regprocedure(
        'public.resolve_premium_guest_guide(text,text)'
      ) is not null,
      'Premium signed guest resolver exists.'
    ),
    (
      '41_anon_can_resolve_premium',
      has_function_privilege(
        'anon',
        'public.resolve_premium_guest_guide(text,text)',
        'EXECUTE'
      ),
      'Anonymous signed guest links can use premium resolver.'
    ),
    (
      '42_authenticated_can_resolve_premium',
      has_function_privilege(
        'authenticated',
        'public.resolve_premium_guest_guide(text,text)',
        'EXECUTE'
      ),
      'Authenticated browser profiles can use premium resolver.'
    ),
    (
      '43_anon_can_record_event',
      has_function_privilege(
        'anon',
        'public.record_guest_guide_event(
          text,text,text,text,uuid,text,jsonb
        )',
        'EXECUTE'
      ),
      'Anonymous signed guest links can record approved events.'
    ),
    (
      '44_authenticated_can_record_event',
      has_function_privilege(
        'authenticated',
        'public.record_guest_guide_event(
          text,text,text,text,uuid,text,jsonb
        )',
        'EXECUTE'
      ),
      'Authenticated browser profiles can record approved events.'
    ),
    (
      '45_old_guest_portal_retained',
      to_regprocedure(
        'public.resolve_guest_portal(text,text)'
      ) is not null,
      'Accepted Day 14 guest portal remains installed.'
    ),
    (
      '46_feedback_rpc_retained',
      to_regprocedure(
        'public.submit_guest_feedback(
          text,text,integer,text,boolean
        )'
      ) is not null,
      'Private feedback RPC remains installed.'
    ),
    (
      '47_review_rpc_retained',
      to_regprocedure(
        'public.record_guest_review_reward_action(
          text,text,text
        )'
      ) is not null,
      'Review/reward action RPC remains installed.'
    ),
    (
      '48_every_hotel_has_settings',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.guest_guide_settings s
          where s.hotel_id = h.id
        )
      ),
      'Every hotel has builder settings.'
    ),
    (
      '49_every_hotel_has_18_sections',
      not exists (
        select 1
        from public.hotels h
        where (
          select count(*)
          from public.guest_guide_sections s
          where s.hotel_id = h.id
        ) < 18
      ),
      'Every hotel has the 18 default guide sections.'
    ),
    (
      '50_every_hotel_has_12_greetings',
      not exists (
        select 1
        from public.hotels h
        where (
          select count(*)
          from public.guest_guide_greetings g
          where g.hotel_id = h.id
        ) <> 12
      ),
      'Every hotel has the 12 approved language greetings.'
    ),
    (
      '51_urdu_not_seeded',
      not exists (
        select 1
        from public.guest_guide_greetings
        where locale = 'ur'
      ),
      'Urdu is not part of the approved language scope.'
    ),
    (
      '52_every_hotel_has_payment_profile',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.guest_guide_payment_profiles p
          where p.hotel_id = h.id
        )
      ),
      'Every hotel has an editable payment profile.'
    ),
    (
      '53_every_hotel_has_published_version',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.guest_guide_versions v
          where v.hotel_id = h.id
        )
      ),
      'Every hotel has an initial published guide snapshot.'
    ),
    (
      '54_settings_published_version_valid',
      not exists (
        select 1
        from public.guest_guide_settings s
        where s.published_version < 1
          or not exists (
            select 1
            from public.guest_guide_versions v
            where v.hotel_id = s.hotel_id
              and v.version_number =
                s.published_version
          )
      ),
      'Published settings reference a real immutable version.'
    ),
    (
      '55_default_locale_enabled',
      not exists (
        select 1
        from public.guest_guide_settings
        where not (
          default_locale = any(enabled_locales)
        )
      ),
      'Every default locale is enabled.'
    ),
    (
      '56_enabled_locales_supported',
      not exists (
        select 1
        from public.guest_guide_settings
        where not (
          enabled_locales <@ array[
            'en','hi','mr','ta','te','bn',
            'gu','kn','ml','pa','or','as'
          ]::text[]
        )
      ),
      'Only approved locales are enabled.'
    ),
    (
      '57_no_expired_active_tokens',
      not exists (
        select 1
        from public.guest_access_tokens
        where status = 'active'
          and expires_at <= now()
      ),
      'Expired active-token drift was reconciled.'
    ),
    (
      '58_one_active_token_per_stay',
      not exists (
        select 1
        from public.guest_access_tokens
        where status = 'active'
        group by guest_session_id
        having count(*) > 1
      ),
      'At most one active token exists per stay.'
    ),
    (
      '59_media_path_tenant_check',
      not exists (
        select 1
        from public.guest_guide_media m
        where split_part(m.object_path, '/', 1)
          <> m.hotel_id::text
      ),
      'Every media path begins with its hotel UUID.'
    ),
    (
      '60_item_scope_integrity',
      not exists (
        select 1
        from public.guest_guide_items
        where not (
          (
            scope_type = 'hotel'
            and room_type_id is null
            and room_id is null
          )
          or (
            scope_type = 'room_type'
            and room_type_id is not null
            and room_id is null
          )
          or (
            scope_type = 'room'
            and room_type_id is null
            and room_id is not null
          )
        )
      ),
      'Guide item scope integrity holds.'
    ),
    (
      '61_media_scope_integrity',
      not exists (
        select 1
        from public.guest_guide_media
        where not (
          (
            scope_type = 'hotel'
            and room_type_id is null
            and room_id is null
          )
          or (
            scope_type = 'room_type'
            and room_type_id is not null
            and room_id is null
          )
          or (
            scope_type = 'room'
            and room_type_id is null
            and room_id is not null
          )
        )
      ),
      'Guide media scope integrity holds.'
    ),
    (
      '62_snapshot_builder_private',
      not has_function_privilege(
        'anon',
        'private.day14_build_guide_snapshot(uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'private.day14_build_guide_snapshot(uuid)',
        'EXECUTE'
      ),
      'Snapshot builder is private.'
    ),
    (
      '63_draft_helper_private',
      not has_function_privilege(
        'anon',
        'private.day14_mark_guide_draft(uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'private.day14_mark_guide_draft(uuid)',
        'EXECUTE'
      ),
      'Draft-state helper is private.'
    ),
    (
      '64_touch_helper_private',
      not has_function_privilege(
        'anon',
        'private.day14_builder_touch_updated_at()',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'private.day14_builder_touch_updated_at()',
        'EXECUTE'
      ),
      'Updated-at helper is private.'
    ),
    (
      '65_snapshot_contains_sections',
      not exists (
        select 1
        from public.guest_guide_versions v
        where jsonb_typeof(v.snapshot -> 'sections')
          <> 'array'
      ),
      'Published snapshots contain section arrays.'
    ),
    (
      '66_snapshot_contains_greetings',
      not exists (
        select 1
        from public.guest_guide_versions v
        where jsonb_typeof(v.snapshot -> 'greetings')
          <> 'object'
      ),
      'Published snapshots contain greeting objects.'
    ),
    (
      '67_snapshot_contains_media',
      not exists (
        select 1
        from public.guest_guide_versions v
        where jsonb_typeof(v.snapshot -> 'media')
          <> 'array'
      ),
      'Published snapshots contain media arrays.'
    ),
    (
      '68_snapshot_contains_payment',
      not exists (
        select 1
        from public.guest_guide_versions v
        where jsonb_typeof(
          v.snapshot -> 'payment_profile'
        ) <> 'object'
      ),
      'Published snapshots contain payment profiles.'
    ),
    (
      '69_room_type_inheritance_available',
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'rooms'
          and column_name = 'room_type_id'
      ),
      'Room-type inheritance remains available.'
    ),
    (
      '70_room_override_available',
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'guest_guide_items'
          and column_name = 'room_id'
      ),
      'Individual room overrides are supported.'
    ),
    (
      '71_time_greetings_present',
      not exists (
        select 1
        from public.guest_guide_greetings
        where nullif(trim(neutral_greeting), '') is null
          or nullif(trim(morning_greeting), '') is null
          or nullif(trim(afternoon_greeting), '') is null
          or nullif(trim(evening_greeting), '') is null
          or nullif(trim(night_greeting), '') is null
      ),
      'All language presets include five editable greetings.'
    ),
    (
      '72_no_arbitrary_code_columns',
      not exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name like 'guest_guide_%'
          and column_name in (
            'html',
            'custom_html',
            'javascript',
            'custom_javascript',
            'custom_css'
          )
      ),
      'The builder does not store arbitrary hotel code.'
    )
)
select test_name, passed, details
from checks
order by test_name;
