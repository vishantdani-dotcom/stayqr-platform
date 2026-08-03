-- StayQR v1.0 — Day 14 Migration 050 REV1
-- Final full-language, official brand and renderer polish
-- Date: 2026-08-03
-- Expected result: 32 rows, all passed = true.

begin;

-- Mark the final renderer and official StayQR brand asset in the published builder settings.
update public.guest_guide_settings
set
  branding = coalesce(branding, '{}'::jsonb)
    || jsonb_build_object(
      'renderer_version', 'apex_signature_full_language_rev5',
      'official_stayqr_logo', '/assets/stayqr-official-logo.png',
      'stayqr_label', 'Powered by StayQR',
      'stayqr_tagline', 'Simplifying check-in',
      'full_language_locales', jsonb_build_array('en','hi','mr','ta')
    ),
  publish_status = 'draft',
  draft_revision = draft_revision + 1,
  updated_at = now();

-- Ensure the approved core languages are enabled whenever their content exists.
update public.guest_guide_settings s
set enabled_locales = (
  select array_agg(distinct locale order by locale)
  from unnest(
    s.enabled_locales || array['en']::text[] || coalesce((
      select array_agg(c.locale)
      from public.hotel_guest_content c
      where c.hotel_id = s.hotel_id
        and c.is_active
        and c.locale = any(array['hi','mr','ta']::text[])
    ), array[]::text[])
  ) locale
  where locale = any(array['en','hi','mr','ta','te','bn','gu','kn','ml','pa','or','as']::text[])
), updated_at = now();

-- Complete translated room-instruction content for the commonly enabled languages.
with translated(item_key, locale, title, description, instructions, button_label) as (
  values
  ('air_conditioner','hi','एयर कंडीशनर','AC और रिमोट का सुरक्षित उपयोग करें।',
    '["AC रिमोट का पावर बटन दबाएँ।","Cool मोड चुनें।","तापमान 22°C से 24°C के बीच रखें।","हवा की दिशा के लिए Swing का उपयोग करें।","AC काम न करे तो रिसेप्शन से संपर्क करें।"]'::jsonb,'निर्देश देखें'),
  ('television_remote','hi','टेलीविज़न और रिमोट','टीवी, सेट-टॉप बॉक्स और रिमोट का उपयोग करें।',
    '["टीवी और सेट-टॉप बॉक्स चालू करें।","सही HDMI/इनपुट चुनें।","रिमोट से चैनल या ऐप चुनें।","उपयोग के बाद रिमोट कमरे में रखें।","सिग्नल न हो तो रिसेप्शन से संपर्क करें।"]'::jsonb,'निर्देश देखें'),
  ('hot_water_geyser','hi','गर्म पानी और गीजर','गर्म पानी या गीजर का सुरक्षित उपयोग करें।',
    '["ज़रूरत होने पर ही गीजर चालू करें।","पानी गर्म होने तक प्रतीक्षा करें।","तापमान सावधानी से जाँचें।","उपयोग के बाद गीजर बंद करें।","गर्म पानी न मिले तो रिसेप्शन से संपर्क करें।"]'::jsonb,'निर्देश देखें'),
  ('bathtub_controls','hi','बाथटब','बाथटब नियंत्रण का सुरक्षित उपयोग करें।',
    '["भरने से पहले ड्रेन प्लग जाँचें।","गुनगुना पानी भरें और तापमान जाँचें।","बच्चों को अकेला न छोड़ें।","उपयोग के बाद पानी निकाल दें।","समस्या हो तो रिसेप्शन से संपर्क करें।"]'::jsonb,'निर्देश देखें'),
  ('safe_locker','hi','सेफ लॉकर','सेफ लॉकर का उपयोग और रीसेट करें।',
    '["कोड सेट करते समय सेफ का दरवाज़ा खुला रखें।","अपना कोड दर्ज करके पुष्टि करें।","सामान रखने से पहले कोड जाँचें।","कोड किसी से साझा न करें।","सेफ लॉक हो जाए तो रिसेप्शन से संपर्क करें।"]'::jsonb,'निर्देश देखें'),

  ('air_conditioner','mr','एअर कंडिशनर','AC आणि रिमोट सुरक्षितपणे वापरा.',
    '["AC रिमोटवरील पॉवर बटण दाबा.","Cool मोड निवडा.","तापमान 22°C ते 24°C दरम्यान ठेवा.","हवेची दिशा बदलण्यासाठी Swing वापरा.","AC चालू न झाल्यास रिसेप्शनशी संपर्क करा."]'::jsonb,'सूचना पहा'),
  ('television_remote','mr','टेलिव्हिजन आणि रिमोट','टीव्ही, सेट-टॉप बॉक्स आणि रिमोट वापरा.',
    '["टीव्ही आणि सेट-टॉप बॉक्स चालू करा.","योग्य HDMI/इनपुट निवडा.","रिमोटवरून चॅनेल किंवा अॅप निवडा.","वापरानंतर रिमोट खोलीतच ठेवा.","सिग्नल नसल्यास रिसेप्शनशी संपर्क करा."]'::jsonb,'सूचना पहा'),
  ('hot_water_geyser','mr','गरम पाणी आणि गीझर','गरम पाणी किंवा गीझर सुरक्षितपणे वापरा.',
    '["गरज असेल तेव्हाच गीझर चालू करा.","पाणी गरम होईपर्यंत थांबा.","पाण्याचे तापमान काळजीपूर्वक तपासा.","वापरानंतर गीझर बंद करा.","गरम पाणी नसल्यास रिसेप्शनशी संपर्क करा."]'::jsonb,'सूचना पहा'),
  ('bathtub_controls','mr','बाथटब','बाथटब नियंत्रण सुरक्षितपणे वापरा.',
    '["पाणी भरण्यापूर्वी ड्रेन प्लग तपासा.","कोमट पाणी भरा आणि तापमान तपासा.","लहान मुलांना एकटे सोडू नका.","वापरानंतर पाणी काढून टाका.","समस्या असल्यास रिसेप्शनशी संपर्क करा."]'::jsonb,'सूचना पहा'),
  ('safe_locker','mr','सेफ लॉकर','सेफ लॉकर वापरा आणि रीसेट करा.',
    '["कोड सेट करताना सेफचे दार उघडे ठेवा.","आपला कोड टाकून पुष्टी करा.","मौल्यवान वस्तू ठेवण्यापूर्वी कोड तपासा.","कोड इतरांना सांगू नका.","सेफ लॉक झाल्यास रिसेप्शनशी संपर्क करा."]'::jsonb,'सूचना पहा'),

  ('air_conditioner','ta','ஏர் கண்டிஷனர்','AC மற்றும் ரிமோட்டை பாதுகாப்பாக பயன்படுத்தவும்.',
    '["AC ரிமோட்டில் பவர் பொத்தானை அழுத்தவும்.","Cool முறையைத் தேர்ந்தெடுக்கவும்.","வெப்பநிலையை 22°C முதல் 24°C வரை அமைக்கவும்.","காற்றுத் திசைக்கு Swing பயன்படுத்தவும்.","AC இயங்கவில்லை என்றால் ரிசப்ஷனை தொடர்புகொள்ளவும்."]'::jsonb,'வழிமுறை பார்க்க'),
  ('television_remote','ta','டிவி மற்றும் ரிமோட்','டிவி, செட்-டாப் பாக்ஸ் மற்றும் ரிமோட்டை பயன்படுத்தவும்.',
    '["டிவி மற்றும் செட்-டாப் பாக்ஸை இயக்கவும்.","சரியான HDMI/இன்புட் தேர்ந்தெடுக்கவும்.","ரிமோட்டில் சேனல் அல்லது பயன்பாட்டைத் தேர்ந்தெடுக்கவும்.","பயன்பாட்டின் பின் ரிமோட்டை அறையில் வைக்கவும்.","சிக்னல் இல்லையெனில் ரிசப்ஷனை தொடர்புகொள்ளவும்."]'::jsonb,'வழிமுறை பார்க்க'),
  ('hot_water_geyser','ta','சூடுநீர் மற்றும் கீசர்','சூடுநீர் அல்லது கீசரை பாதுகாப்பாக பயன்படுத்தவும்.',
    '["தேவையான போது மட்டும் கீசரை இயக்கவும்.","தண்ணீர் சூடாகும் வரை காத்திருக்கவும்.","வெப்பநிலையை கவனமாகச் சரிபார்க்கவும்.","பயன்பாட்டின் பின் கீசரை அணைக்கவும்.","சூடுநீர் இல்லையெனில் ரிசப்ஷனை தொடர்புகொள்ளவும்."]'::jsonb,'வழிமுறை பார்க்க'),
  ('bathtub_controls','ta','பாத் டப்','பாத் டப் கட்டுப்பாடுகளை பாதுகாப்பாக பயன்படுத்தவும்.',
    '["நிரப்புவதற்கு முன் டிரெயின் பிளக்கைச் சரிபார்க்கவும்.","சூடான தண்ணீரை நிரப்பி வெப்பநிலையைச் சரிபார்க்கவும்.","குழந்தைகளை தனியாக விட வேண்டாம்.","பயன்பாட்டின் பின் தண்ணீரை வெளியேற்றவும்.","சிக்கல் இருந்தால் ரிசப்ஷனை தொடர்புகொள்ளவும்."]'::jsonb,'வழிமுறை பார்க்க'),
  ('safe_locker','ta','பாதுகாப்புப் பெட்டி','பாதுகாப்புப் பெட்டியை பயன்படுத்தி மீட்டமைக்கவும்.',
    '["குறியீட்டை அமைக்கும் போது கதவை திறந்தே வைத்திருக்கவும்.","உங்கள் குறியீட்டை உள்ளிட்டு உறுதிசெய்யவும்.","மதிப்புள்ள பொருட்களை வைக்கும் முன் குறியீட்டைச் சோதிக்கவும்.","குறியீட்டை பகிர வேண்டாம்.","சேஃப் பூட்டப்பட்டால் ரிசப்ஷனை தொடர்புகொள்ளவும்."]'::jsonb,'வழிமுறை பார்க்க')
), target as (
  select i.hotel_id, i.id item_id, t.*
  from public.guest_guide_items i
  join translated t on t.item_key = i.item_key
)
insert into public.guest_guide_item_translations(
  hotel_id,item_id,locale,title,description,instructions,button_label,metadata
)
select hotel_id,item_id,locale,title,description,instructions,button_label,
  jsonb_build_object('source','day14_rev5_curated_translation')
from target
on conflict (item_id,locale) do update set
  title = excluded.title,
  description = excluded.description,
  instructions = excluded.instructions,
  button_label = excluded.button_label,
  metadata = coalesce(public.guest_guide_item_translations.metadata,'{}'::jsonb)
    || excluded.metadata,
  updated_at = now();

commit;

with checks(test_name,passed,details) as (
  values
  ('01_settings_table',to_regclass('public.guest_guide_settings') is not null,'Guide settings exist.'),
  ('02_item_translations_table',to_regclass('public.guest_guide_item_translations') is not null,'Item translations exist.'),
  ('03_official_logo_configured',not exists(select 1 from public.guest_guide_settings where branding->>'official_stayqr_logo' <> '/assets/stayqr-official-logo.png'),'Official StayQR logo is configured.'),
  ('04_rev5_renderer_marker',not exists(select 1 from public.guest_guide_settings where branding->>'renderer_version' <> 'apex_signature_full_language_rev5'),'REV5 renderer is configured.'),
  ('05_stayqr_tagline',not exists(select 1 from public.guest_guide_settings where branding->>'stayqr_tagline' <> 'Simplifying check-in'),'Official tagline is configured.'),
  ('06_urdu_not_enabled',not exists(select 1 from public.guest_guide_settings where 'ur'=any(enabled_locales)),'Urdu remains excluded.'),
  ('07_default_locale_enabled',not exists(select 1 from public.guest_guide_settings where not(default_locale=any(enabled_locales))),'Default locale remains enabled.'),
  ('08_hindi_ac_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='air_conditioner' and tr.locale='hi' and jsonb_array_length(tr.instructions)>=5),'Hindi AC instructions exist.'),
  ('09_marathi_ac_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='air_conditioner' and tr.locale='mr' and jsonb_array_length(tr.instructions)>=5),'Marathi AC instructions exist.'),
  ('10_tamil_ac_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='air_conditioner' and tr.locale='ta' and jsonb_array_length(tr.instructions)>=5),'Tamil AC instructions exist.'),
  ('11_hindi_tv_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='television_remote' and tr.locale='hi' and jsonb_array_length(tr.instructions)>=5),'Hindi TV instructions exist.'),
  ('12_marathi_tv_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='television_remote' and tr.locale='mr' and jsonb_array_length(tr.instructions)>=5),'Marathi TV instructions exist.'),
  ('13_tamil_tv_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='television_remote' and tr.locale='ta' and jsonb_array_length(tr.instructions)>=5),'Tamil TV instructions exist.'),
  ('14_hindi_geyser_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='hot_water_geyser' and tr.locale='hi'),'Hindi geyser translation exists.'),
  ('15_marathi_geyser_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='hot_water_geyser' and tr.locale='mr'),'Marathi geyser translation exists.'),
  ('16_tamil_geyser_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='hot_water_geyser' and tr.locale='ta'),'Tamil geyser translation exists.'),
  ('17_hindi_safe_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='safe_locker' and tr.locale='hi'),'Hindi safe translation exists.'),
  ('18_marathi_safe_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='safe_locker' and tr.locale='mr'),'Marathi safe translation exists.'),
  ('19_tamil_safe_translation',exists(select 1 from public.guest_guide_item_translations tr join public.guest_guide_items i on i.id=tr.item_id where i.item_key='safe_locker' and tr.locale='ta'),'Tamil safe translation exists.'),
  ('20_all_instruction_arrays',not exists(select 1 from public.guest_guide_item_translations where instructions is not null and jsonb_typeof(instructions)<>'array'),'All instructions are arrays.'),
  ('21_no_expired_active_tokens',not exists(select 1 from public.guest_access_tokens where status='active' and expires_at<=now()),'No expired active token remains.'),
  ('22_one_active_token_per_stay',not exists(select 1 from public.guest_access_tokens where status='active' group by guest_session_id having count(*)>1),'At most one active token exists per stay.'),
  ('23_premium_resolver_retained',to_regprocedure('public.resolve_premium_guest_guide(text,text)') is not null,'Premium resolver remains installed.'),
  ('24_anon_premium_execute',has_function_privilege('anon','public.resolve_premium_guest_guide(text,text)','EXECUTE'),'Anonymous signed links can resolve.'),
  ('25_authenticated_premium_execute',has_function_privilege('authenticated','public.resolve_premium_guest_guide(text,text)','EXECUTE'),'Authenticated browser profiles can resolve.'),
  ('26_feedback_rpc_retained',to_regprocedure('public.submit_guest_feedback(text,text,integer,text,boolean)') is not null,'Feedback RPC remains installed.'),
  ('27_review_rpc_retained',to_regprocedure('public.record_guest_review_reward_action(text,text,text)') is not null,'Review RPC remains installed.'),
  ('28_media_table_retained',to_regclass('public.guest_guide_media') is not null,'Media metadata remains installed.'),
  ('29_payment_profile_retained',to_regclass('public.guest_guide_payment_profiles') is not null,'Payment profile remains installed.'),
  ('30_builder_is_draft',not exists(select 1 from public.guest_guide_settings where publish_status<>'draft'),'REV5 changes require review and publish.'),
  ('31_no_arbitrary_code_columns',not exists(select 1 from information_schema.columns where table_schema='public' and table_name like 'guest_guide_%' and column_name in ('html','custom_html','javascript','custom_javascript','custom_css')),'No arbitrary hotel code storage exists.'),
  ('32_security_helper_retained',to_regprocedure('private.resolve_guest_access_token(text,text,boolean)') is not null,'Signed token resolver remains installed.')
)
select test_name,passed,details from checks order by test_name;
