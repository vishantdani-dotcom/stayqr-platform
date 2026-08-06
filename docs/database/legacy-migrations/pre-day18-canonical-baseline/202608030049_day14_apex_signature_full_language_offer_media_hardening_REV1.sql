-- StayQR v1.0 — Day 14 Migration 049 REV1
-- Apex Signature Renderer: Full-Language, Offer and Device-Media Hardening
-- Date: 2026-08-03
--
-- PURPOSE
--   * establish full-guide language mode with English fallback
--   * seed editable offer-banner defaults below the hero
--   * preserve/highlight StayQR platform branding
--   * backfill uploaded AC/TV/geyser/bathtub/safe media to matching
--     room-instruction items where possible
--   * mark affected guides as draft so hotels explicitly review/publish REV4
--
-- No guest, reservation, folio, payment, feedback or service-request row is
-- created or deleted by this migration.
--
-- EXPECTED RESULT: 28/28 passed.

begin;

create index if not exists idx_guest_guide_media_item
on public.guest_guide_media (hotel_id, item_id)
where item_id is not null and is_active;

with defaults as (
  select jsonb_build_object(
    'enabled', true,
    'badge', 'Limited Offer',
    'title', 'Make Your Stay More Rewarding',
    'description', 'Ask reception about today''s guest benefit.',
    'button_label', 'View Offer',
    'action_type', 'section',
    'action_value', 'google_review',
    'image_media_id', null,
    'translations', jsonb_build_object(
      'en', jsonb_build_object(
        'badge', 'Limited Offer',
        'title', 'Make Your Stay More Rewarding',
        'description', 'Ask reception about today''s guest benefit.',
        'button_label', 'View Offer'
      ),
      'hi', jsonb_build_object(
        'badge', 'सीमित ऑफर',
        'title', 'अपने प्रवास को और खास बनाएं',
        'description', 'आज के अतिथि लाभ के बारे में रिसेप्शन से पूछें।',
        'button_label', 'ऑफर देखें'
      ),
      'mr', jsonb_build_object(
        'badge', 'मर्यादित ऑफर',
        'title', 'आपला मुक्काम आणखी खास करा',
        'description', 'आजच्या अतिथी लाभाबद्दल रिसेप्शनला विचारा.',
        'button_label', 'ऑफर पहा'
      ),
      'ta', jsonb_build_object(
        'badge', 'வரையறுக்கப்பட்ட சலுகை',
        'title', 'உங்கள் தங்கலை மேலும் சிறப்பாக்குங்கள்',
        'description', 'இன்றைய விருந்தினர் சலுகையை வரவேற்பில் கேளுங்கள்.',
        'button_label', 'சலுகையைப் பார்க்கவும்'
      )
    )
  ) as offer
), prepared as (
  select
    s.hotel_id,
    d.offer,
    coalesce(s.branding, '{}'::jsonb) as old_branding,
    coalesce(s.branding -> 'offer', '{}'::jsonb) as old_offer,
    coalesce(s.branding -> 'offer' -> 'translations', '{}'::jsonb)
      as old_translations
  from public.guest_guide_settings s
  cross join defaults d
)
update public.guest_guide_settings s
set
  branding = jsonb_set(
    jsonb_set(
      p.old_branding,
      '{show_stayqr_branding}',
      coalesce(p.old_branding -> 'show_stayqr_branding', 'true'::jsonb),
      true
    ),
    '{offer}',
    (
      p.offer
      || p.old_offer
      || jsonb_build_object(
        'translations',
        (p.offer -> 'translations') || p.old_translations
      )
    ),
    true
  ),
  navigation = coalesce(s.navigation, '{}'::jsonb)
    || jsonb_build_object(
      'renderer', 'stayqr_apex_signature_rev4',
      'language_mode', 'full_guide',
      'translation_fallback', 'en',
      'visible_save_feedback', true,
      'device_media_fallback', true
    ),
  publish_status = 'draft',
  draft_revision = s.draft_revision + 1,
  updated_at = now()
from prepared p
where p.hotel_id = s.hotel_id;

with category_map(category, item_key) as (
  values
    ('ac', 'air_conditioner'),
    ('ac_remote', 'air_conditioner'),
    ('tv', 'television_remote'),
    ('tv_remote', 'television_remote'),
    ('geyser', 'hot_water_geyser'),
    ('bathtub', 'bathtub_controls'),
    ('safe', 'safe_locker')
), candidates as (
  select distinct on (m.id)
    m.id as media_id,
    i.id as item_id
  from public.guest_guide_media m
  join category_map cm
    on cm.category = m.category
  join public.guest_guide_items i
    on i.hotel_id = m.hotel_id
   and i.item_key = cm.item_key
   and i.scope_type = m.scope_type
   and i.room_type_id is not distinct from m.room_type_id
   and i.room_id is not distinct from m.room_id
   and i.is_enabled
  where m.item_id is null
    and m.is_active
  order by m.id, i.updated_at desc, i.created_at desc
)
update public.guest_guide_media m
set
  item_id = c.item_id,
  updated_at = now()
from candidates c
where c.media_id = m.id;

commit;

with checks(test_name, passed, details) as (
  values
    ('01_settings_table', to_regclass('public.guest_guide_settings') is not null, 'Guest-guide settings exist.'),
    ('02_media_table', to_regclass('public.guest_guide_media') is not null, 'Guest-guide media exists.'),
    ('03_items_table', to_regclass('public.guest_guide_items') is not null, 'Guest-guide items exist.'),
    ('04_offer_present', not exists (select 1 from public.guest_guide_settings where branding -> 'offer' is null), 'Every hotel has an editable offer object.'),
    ('05_offer_is_object', not exists (select 1 from public.guest_guide_settings where jsonb_typeof(branding -> 'offer') <> 'object'), 'Offer configuration is a JSON object.'),
    ('06_offer_enabled_present', not exists (select 1 from public.guest_guide_settings where branding #> '{offer,enabled}' is null), 'Offer visibility is configurable.'),
    ('07_offer_title_present', not exists (select 1 from public.guest_guide_settings where nullif(trim(branding #>> '{offer,title}'), '') is null), 'Offer title is present.'),
    ('08_offer_description_present', not exists (select 1 from public.guest_guide_settings where nullif(trim(branding #>> '{offer,description}'), '') is null), 'Offer description is present.'),
    ('09_offer_action_present', not exists (select 1 from public.guest_guide_settings where nullif(trim(branding #>> '{offer,action_type}'), '') is null), 'Offer action is configurable.'),
    ('10_offer_english_translation', not exists (select 1 from public.guest_guide_settings where branding #> '{offer,translations,en}' is null), 'English offer translation exists.'),
    ('11_offer_hindi_translation', not exists (select 1 from public.guest_guide_settings where branding #> '{offer,translations,hi}' is null), 'Hindi offer translation exists.'),
    ('12_offer_marathi_translation', not exists (select 1 from public.guest_guide_settings where branding #> '{offer,translations,mr}' is null), 'Marathi offer translation exists.'),
    ('13_offer_tamil_translation', not exists (select 1 from public.guest_guide_settings where branding #> '{offer,translations,ta}' is null), 'Tamil offer translation exists.'),
    ('14_full_language_mode', not exists (select 1 from public.guest_guide_settings where navigation ->> 'language_mode' <> 'full_guide'), 'All hotels use full-guide language mode.'),
    ('15_english_fallback', not exists (select 1 from public.guest_guide_settings where navigation ->> 'translation_fallback' <> 'en'), 'English remains the safe translation fallback.'),
    ('16_rev4_renderer_marker', not exists (select 1 from public.guest_guide_settings where navigation ->> 'renderer' <> 'stayqr_apex_signature_rev4'), 'REV4 renderer marker is installed.'),
    ('17_visible_save_feedback', not exists (select 1 from public.guest_guide_settings where coalesce((navigation ->> 'visible_save_feedback')::boolean, false) is not true), 'Visible save feedback is enabled.'),
    ('18_device_media_fallback', not exists (select 1 from public.guest_guide_settings where coalesce((navigation ->> 'device_media_fallback')::boolean, false) is not true), 'Device-media fallback is enabled.'),
    ('19_stayqr_branding_key', not exists (select 1 from public.guest_guide_settings where branding -> 'show_stayqr_branding' is null), 'StayQR branding preference is explicit.'),
    ('20_urdu_not_enabled', not exists (select 1 from public.guest_guide_settings where 'ur' = any(enabled_locales)), 'Urdu is excluded from enabled languages.'),
    ('21_media_item_index', exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_guest_guide_media_item'), 'Instruction-media lookup index exists.'),
    ('22_no_cross_hotel_media_item', not exists (select 1 from public.guest_guide_media m join public.guest_guide_items i on i.id = m.item_id where i.hotel_id <> m.hotel_id), 'Media-item links remain tenant-correct.'),
    ('23_ac_media_backfill_complete', not exists (select 1 from public.guest_guide_media m where m.is_active and m.item_id is null and m.category in ('ac','ac_remote') and exists (select 1 from public.guest_guide_items i where i.hotel_id=m.hotel_id and i.item_key='air_conditioner' and i.scope_type=m.scope_type and i.room_type_id is not distinct from m.room_type_id and i.room_id is not distinct from m.room_id)), 'Matchable AC media is linked.'),
    ('24_tv_media_backfill_complete', not exists (select 1 from public.guest_guide_media m where m.is_active and m.item_id is null and m.category in ('tv','tv_remote') and exists (select 1 from public.guest_guide_items i where i.hotel_id=m.hotel_id and i.item_key='television_remote' and i.scope_type=m.scope_type and i.room_type_id is not distinct from m.room_type_id and i.room_id is not distinct from m.room_id)), 'Matchable TV media is linked.'),
    ('25_other_device_media_backfill_complete', not exists (select 1 from public.guest_guide_media m where m.is_active and m.item_id is null and m.category in ('geyser','bathtub','safe') and exists (select 1 from public.guest_guide_items i where i.hotel_id=m.hotel_id and i.item_key = case m.category when 'geyser' then 'hot_water_geyser' when 'bathtub' then 'bathtub_controls' when 'safe' then 'safe_locker' end and i.scope_type=m.scope_type and i.room_type_id is not distinct from m.room_type_id and i.room_id is not distinct from m.room_id)), 'Other matchable device media is linked.'),
    ('26_premium_resolver_retained', to_regprocedure('public.resolve_premium_guest_guide(text,text)') is not null, 'Signed premium resolver remains installed.'),
    ('27_publish_rpc_retained', to_regprocedure('public.publish_guest_guide(uuid,text)') is not null, 'Draft-to-publish RPC remains installed.'),
    ('28_anon_no_builder_write', not has_table_privilege('anon','public.guest_guide_settings','UPDATE') and not has_table_privilege('anon','public.guest_guide_media','UPDATE'), 'Anonymous guests cannot modify builder data.')
)
select test_name, passed, details
from checks
order by test_name;
