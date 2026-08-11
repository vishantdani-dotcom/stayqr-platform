-- StayQR v1.0 — Day 19 Migration 067 REV1
-- Future-hotel Guest Guide bootstrap + current missing-hotel repair
-- Date: 2026-08-11
--
-- PURPOSE
--   * Fixes hotels created after Day 14 that received no premium Guest Guide scaffold.
--   * Seeds the Day 14 default settings/18 sections/English section copy/12 greetings/payment profile.
--   * Publishes an initial immutable guide snapshot when onboarding reaches COMPLETE.
--   * Repairs only hotels that are completely missing guest_guide_settings at migration time.
--   * Preserves every existing hotel that already has guest_guide_settings/customized guide data.
--
-- SAFETY
--   * Transactional and idempotent.
--   * No hotel/room/guest/reservation/payment/order/folio data is deleted or rewritten.
--   * Existing Guest Guide settings/sections/greetings/payment/version rows are not overwritten.
--   * Future hotel inserts receive only a draft scaffold; initial publish happens on onboarding completion.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608110067:day19-guest-guide-future-hotel-bootstrap-repair')
);

-- --------------------------------------------------------------------------
-- 0. PRE-FLIGHT
-- --------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('public.hotels') is null
     or to_regclass('public.hotel_onboarding') is null
     or to_regclass('public.guest_guide_settings') is null
     or to_regclass('public.guest_guide_sections') is null
     or to_regclass('public.guest_guide_section_translations') is null
     or to_regclass('public.guest_guide_greetings') is null
     or to_regclass('public.guest_guide_payment_profiles') is null
     or to_regclass('public.guest_guide_versions') is null
  then
    raise exception 'Migration 067 stopped: required Day 8/Day 14 tables are missing.';
  end if;

  if to_regprocedure('private.day14_build_guide_snapshot(uuid)') is null then
    raise exception 'Migration 067 stopped: Day 14 snapshot builder is missing.';
  end if;
end;
$preflight$;

-- --------------------------------------------------------------------------
-- 1. IDEMPOTENT DEFAULT-SCAFFOLD ENSURER
--    IMPORTANT: defaults are inserted only when the HOTEL HAS NO SETTINGS ROW.
--    This avoids restoring sections intentionally removed from an existing guide.
-- --------------------------------------------------------------------------
create or replace function private.ensure_guest_guide_foundation_20260811(
  p_hotel_id uuid,
  p_publish_if_needed boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_created_settings boolean := false;
  v_snapshot jsonb;
  v_latest_version integer;
  v_latest_published_at timestamptz;
begin
  if p_hotel_id is null
     or not exists (select 1 from public.hotels h where h.id = p_hotel_id)
  then
    raise exception 'Guest Guide foundation requires a valid hotel.';
  end if;

  if not exists (
    select 1
    from public.guest_guide_settings s
    where s.hotel_id = p_hotel_id
  ) then
    v_created_settings := true;

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
    values (
      p_hotel_id,
      'stayqr_luxury',
      'en',
      array['en']::text[],
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
    )
    on conflict (hotel_id) do nothing;

    with defaults(section_key, section_type, sort_order, label, title, subtitle) as (
      values
        ('hero','hero',10,'01 — Welcome','Welcome','Your secure digital companion for a comfortable stay.'),
        ('stay_overview','stay',20,'02 — Your Stay','Stay at a Glance','Room, timings and essential information.'),
        ('quick_access','actions',30,'03 — Quick Access','Your Digital Concierge','Everything you need, at your fingertips.'),
        ('wifi','wifi',40,'04 — Wi-Fi','Stay Connected','Secure hotel Wi-Fi details for your active stay.'),
        ('room_gallery','gallery',50,'05 — Your Room','Room Gallery','A visual introduction to your room.'),
        ('room_guide','instructions',60,'06 — Room Guide','Smart Room Instructions','AC, TV, remote, geyser, bathtub, safe and more.'),
        ('hotel_facilities','facilities',70,'07 — Facilities','Hotel Facilities','Explore the facilities available at the property.'),
        ('dining','dining',80,'08 — Dining','Dining & Room Service','Food timings, menu and ordering access.'),
        ('guest_services','services',90,'09 — Services','Guest Services','Request assistance from the appropriate hotel team.'),
        ('safety','safety',100,'10 — Safety','Safety & Emergency','Important safety information and emergency actions.'),
        ('important_contacts','contacts',110,'11 — Contacts','Important Contacts','Call, WhatsApp or email the hotel team.'),
        ('stay_connected','social',120,'12 — Stay Connected','Stay Connected','Connect with the hotel online.'),
        ('local_convenience','local',130,'13 — Local Convenience','Discover the Local Area','Nearby essentials and local experiences.'),
        ('payment','payment',140,'14 — Payment','Payment Assistance','View supported payment information and balance.'),
        ('feedback','feedback',150,'15 — Feedback','How Was Your Stay?','Share private feedback directly with the hotel.'),
        ('google_review','review',160,'16 — Review','Enjoyed Your Stay?','Share your experience through the hotel review page.'),
        ('policies','policies',170,'17 — Policies','Hotel Policies','Review the important terms for your stay.'),
        ('thank_you','closing',180,'18 — Thank You','Thank You for Staying With Us','We hope to welcome you again.')
    )
    insert into public.guest_guide_sections (
      hotel_id, section_key, section_type, sort_order, is_enabled, settings
    )
    select p_hotel_id, d.section_key, d.section_type, d.sort_order, true, '{}'::jsonb
    from defaults d
    on conflict (hotel_id, section_key) do nothing;

    with defaults(section_key, label, title, subtitle) as (
      values
        ('hero','01 — Welcome','Welcome','Your secure digital companion for a comfortable stay.'),
        ('stay_overview','02 — Your Stay','Stay at a Glance','Room, timings and essential information.'),
        ('quick_access','03 — Quick Access','Your Digital Concierge','Everything you need, at your fingertips.'),
        ('wifi','04 — Wi-Fi','Stay Connected','Secure hotel Wi-Fi details for your active stay.'),
        ('room_gallery','05 — Your Room','Room Gallery','A visual introduction to your room.'),
        ('room_guide','06 — Room Guide','Smart Room Instructions','AC, TV, remote, geyser, bathtub, safe and more.'),
        ('hotel_facilities','07 — Facilities','Hotel Facilities','Explore the facilities available at the property.'),
        ('dining','08 — Dining','Dining & Room Service','Food timings, menu and ordering access.'),
        ('guest_services','09 — Services','Guest Services','Request assistance from the appropriate hotel team.'),
        ('safety','10 — Safety','Safety & Emergency','Important safety information and emergency actions.'),
        ('important_contacts','11 — Contacts','Important Contacts','Call, WhatsApp or email the hotel team.'),
        ('stay_connected','12 — Stay Connected','Stay Connected','Connect with the hotel online.'),
        ('local_convenience','13 — Local Convenience','Discover the Local Area','Nearby essentials and local experiences.'),
        ('payment','14 — Payment','Payment Assistance','View supported payment information and balance.'),
        ('feedback','15 — Feedback','How Was Your Stay?','Share private feedback directly with the hotel.'),
        ('google_review','16 — Review','Enjoyed Your Stay?','Share your experience through the hotel review page.'),
        ('policies','17 — Policies','Hotel Policies','Review the important terms for your stay.'),
        ('thank_you','18 — Thank You','Thank You for Staying With Us','We hope to welcome you again.')
    )
    insert into public.guest_guide_section_translations (
      hotel_id, section_id, locale, label, title, subtitle
    )
    select s.hotel_id, s.id, 'en', d.label, d.title, d.subtitle
    from public.guest_guide_sections s
    join defaults d on d.section_key = s.section_key
    where s.hotel_id = p_hotel_id
    on conflict (section_id, locale) do nothing;

    with greeting_defaults(
      locale, language_name, native_name,
      neutral_greeting, morning_greeting, afternoon_greeting,
      evening_greeting, night_greeting, sort_order
    ) as (
      values
        ('en','English','English','Hello','Good morning','Good afternoon','Good evening','Good night',10),
        ('hi','Hindi','हिन्दी','नमस्ते','सुप्रभात','नमस्कार','शुभ संध्या','शुभ रात्रि',20),
        ('mr','Marathi','मराठी','नमस्कार','शुभ प्रभात','शुभ दुपार','शुभ संध्याकाळ','शुभ रात्री',30),
        ('ta','Tamil','தமிழ்','வணக்கம்','காலை வணக்கம்','மதிய வணக்கம்','மாலை வணக்கம்','இனிய இரவு',40),
        ('te','Telugu','తెలుగు','నమస్కారం','శుభోదయం','శుభ మధ్యాహ్నం','శుభ సాయంత్రం','శుభ రాత్రి',50),
        ('bn','Bengali','বাংলা','নমস্কার','সুপ্রভাত','শুভ অপরাহ্ণ','শুভ সন্ধ্যা','শুভ রাত্রি',60),
        ('gu','Gujarati','ગુજરાતી','નમસ્તે','સુપ્રભાત','શુભ બપોર','શુભ સાંજ','શુભ રાત્રિ',70),
        ('kn','Kannada','ಕನ್ನಡ','ನಮಸ್ಕಾರ','ಶುಭೋದಯ','ಶುಭ ಮಧ್ಯಾಹ್ನ','ಶುಭ ಸಂಜೆ','ಶುಭ ರಾತ್ರಿ',80),
        ('ml','Malayalam','മലയാളം','നമസ്കാരം','സുപ്രഭാതം','ശുഭ ഉച്ചതിരിഞ്ഞ്','ശുഭ സായാഹ്നം','ശുഭ രാത്രി',90),
        ('pa','Punjabi','ਪੰਜਾਬੀ','ਸਤ ਸ੍ਰੀ ਅਕਾਲ','ਸ਼ੁਭ ਸਵੇਰ','ਸ਼ੁਭ ਦੁਪਹਿਰ','ਸ਼ੁਭ ਸ਼ਾਮ','ਸ਼ੁਭ ਰਾਤ',100),
        ('or','Odia','ଓଡ଼ିଆ','ନମସ୍କାର','ସୁପ୍ରଭାତ','ଶୁଭ ଅପରାହ୍ନ','ଶୁଭ ସନ୍ଧ୍ୟା','ଶୁଭରାତ୍ରି',110),
        ('as','Assamese','অসমীয়া','নমস্কাৰ','সুপ্ৰভাত','শুভ দুপৰীয়া','শুভ সন্ধিয়া','শুভ ৰাত্ৰি',120)
    )
    insert into public.guest_guide_greetings (
      hotel_id, locale, language_name, native_name,
      neutral_greeting, morning_greeting, afternoon_greeting,
      evening_greeting, night_greeting, is_enabled, sort_order
    )
    select
      p_hotel_id,
      g.locale,
      g.language_name,
      g.native_name,
      g.neutral_greeting,
      g.morning_greeting,
      g.afternoon_greeting,
      g.evening_greeting,
      g.night_greeting,
      (g.locale = 'en'),
      g.sort_order
    from greeting_defaults g
    on conflict (hotel_id, locale) do nothing;

    insert into public.guest_guide_payment_profiles (hotel_id)
    values (p_hotel_id)
    on conflict (hotel_id) do nothing;
  end if;

  if p_publish_if_needed then
    select max(v.version_number)
    into v_latest_version
    from public.guest_guide_versions v
    where v.hotel_id = p_hotel_id;

    if v_latest_version is null then
      v_snapshot := private.day14_build_guide_snapshot(p_hotel_id);

      insert into public.guest_guide_versions (
        hotel_id, version_number, snapshot, publish_note
      )
      values (
        p_hotel_id,
        1,
        v_snapshot,
        'Initial premium guest guide bootstrap snapshot'
      )
      returning version_number, published_at
      into v_latest_version, v_latest_published_at;
    else
      select v.published_at
      into v_latest_published_at
      from public.guest_guide_versions v
      where v.hotel_id = p_hotel_id
        and v.version_number = v_latest_version;
    end if;

    update public.guest_guide_settings s
    set
      publish_status = 'published',
      published_version = v_latest_version,
      published_at = coalesce(v_latest_published_at, now()),
      updated_at = now()
    where s.hotel_id = p_hotel_id
      and (
        s.publish_status <> 'published'
        or s.published_version <> v_latest_version
        or s.published_at is null
      );
  end if;
end;
$function$;

revoke all on function private.ensure_guest_guide_foundation_20260811(uuid,boolean)
from public, anon, authenticated;

-- --------------------------------------------------------------------------
-- 2. FUTURE HOTEL INSERT: CREATE DRAFT SCAFFOLD IMMEDIATELY
-- --------------------------------------------------------------------------
create or replace function private.day19_guest_guide_seed_on_hotel_insert_20260811()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.ensure_guest_guide_foundation_20260811(new.id, false);
  return new;
end;
$function$;

revoke all on function private.day19_guest_guide_seed_on_hotel_insert_20260811()
from public, anon, authenticated;

drop trigger if exists day19_guest_guide_seed_on_hotel_insert_20260811
on public.hotels;

create trigger day19_guest_guide_seed_on_hotel_insert_20260811
after insert on public.hotels
for each row
execute function private.day19_guest_guide_seed_on_hotel_insert_20260811();

-- --------------------------------------------------------------------------
-- 3. ONBOARDING COMPLETE: CREATE INITIAL IMMUTABLE PUBLISHED VERSION
-- --------------------------------------------------------------------------
create or replace function private.day19_guest_guide_publish_on_onboarding_complete_20260811()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'complete' then
    if tg_op = 'INSERT' then
      perform private.ensure_guest_guide_foundation_20260811(new.hotel_id, true);
    elsif old.status is distinct from new.status then
      perform private.ensure_guest_guide_foundation_20260811(new.hotel_id, true);
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function private.day19_guest_guide_publish_on_onboarding_complete_20260811()
from public, anon, authenticated;

drop trigger if exists day19_guest_guide_publish_on_onboarding_complete_20260811
on public.hotel_onboarding;

create trigger day19_guest_guide_publish_on_onboarding_complete_20260811
after insert or update of status on public.hotel_onboarding
for each row
execute function private.day19_guest_guide_publish_on_onboarding_complete_20260811();

-- --------------------------------------------------------------------------
-- 4. ONE-TIME REPAIR FOR HOTELS COMPLETELY MISSING THE DAY 14 FOUNDATION
--    Existing configured Guest Guides are intentionally untouched.
-- --------------------------------------------------------------------------
do $repair$
declare
  v_hotel record;
begin
  for v_hotel in
    select h.id
    from public.hotels h
    where not exists (
      select 1
      from public.guest_guide_settings s
      where s.hotel_id = h.id
    )
    order by h.created_at, h.id
  loop
    perform private.ensure_guest_guide_foundation_20260811(v_hotel.id, true);
  end loop;
end;
$repair$;

-- --------------------------------------------------------------------------
-- 5. POST-MIGRATION ASSERTIONS
-- --------------------------------------------------------------------------
do $verify$
begin
  if exists (
    select 1
    from public.hotels h
    where not exists (
      select 1 from public.guest_guide_settings s where s.hotel_id = h.id
    )
  ) then
    raise exception 'Migration 067 failed: at least one hotel still lacks Guest Guide settings.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.hotels'::regclass
      and t.tgname = 'day19_guest_guide_seed_on_hotel_insert_20260811'
      and not t.tgisinternal
  ) then
    raise exception 'Migration 067 failed: future-hotel Guest Guide seed trigger is missing.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.hotel_onboarding'::regclass
      and t.tgname = 'day19_guest_guide_publish_on_onboarding_complete_20260811'
      and not t.tgisinternal
  ) then
    raise exception 'Migration 067 failed: onboarding-completion publish trigger is missing.';
  end if;
end;
$verify$;

commit;

-- --------------------------------------------------------------------------
-- 6. ACCEPTANCE RESULT — EXPECT ALL PASS
-- --------------------------------------------------------------------------
with target as (
  select h.id
  from public.hotels h
  where h.slug = 'anjaneya-stay-inn'
), checks(seq, check_name, passed) as (
  values
    (1, 'future_hotel_seed_trigger_present', exists (
      select 1 from pg_trigger t
      where t.tgrelid = 'public.hotels'::regclass
        and t.tgname = 'day19_guest_guide_seed_on_hotel_insert_20260811'
        and not t.tgisinternal
    )),
    (2, 'onboarding_publish_trigger_present', exists (
      select 1 from pg_trigger t
      where t.tgrelid = 'public.hotel_onboarding'::regclass
        and t.tgname = 'day19_guest_guide_publish_on_onboarding_complete_20260811'
        and not t.tgisinternal
    )),
    (3, 'anjaneya_settings_present', exists (
      select 1 from public.guest_guide_settings s join target t on t.id = s.hotel_id
    )),
    (4, 'anjaneya_18_sections_present', coalesce((
      select count(*) >= 18 from public.guest_guide_sections s join target t on t.id = s.hotel_id
    ), false)),
    (5, 'anjaneya_18_english_section_translations_present', coalesce((
      select count(*) >= 18
      from public.guest_guide_section_translations tr
      join target t on t.id = tr.hotel_id
      where tr.locale = 'en'
    ), false)),
    (6, 'anjaneya_12_greetings_present', coalesce((
      select count(*) = 12 from public.guest_guide_greetings g join target t on t.id = g.hotel_id
    ), false)),
    (7, 'anjaneya_payment_profile_present', exists (
      select 1 from public.guest_guide_payment_profiles p join target t on t.id = p.hotel_id
    )),
    (8, 'anjaneya_published_version_present', exists (
      select 1 from public.guest_guide_versions v join target t on t.id = v.hotel_id
    )),
    (9, 'anjaneya_settings_points_to_real_version', exists (
      select 1
      from public.guest_guide_settings s
      join target t on t.id = s.hotel_id
      join public.guest_guide_versions v
        on v.hotel_id = s.hotel_id
       and v.version_number = s.published_version
      where s.publish_status = 'published'
        and s.published_version >= 1
    )),
    (10, 'all_hotels_have_settings', not exists (
      select 1
      from public.hotels h
      where not exists (
        select 1 from public.guest_guide_settings s where s.hotel_id = h.id
      )
    ))
)
select seq, check_name, case when passed then 'PASS' else 'FAIL' end as result
from checks
order by seq;
