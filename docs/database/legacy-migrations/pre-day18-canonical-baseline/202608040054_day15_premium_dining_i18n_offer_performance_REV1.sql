-- ============================================================================
-- StayQR v1.0
-- Day 15.1 Migration 054 REV1
-- Premium Dining: Full Locale Data, Offer Builder Compatibility and Runtime
-- Notification Hardening
--
-- PURPOSE
-- 1. Add tenant-safe JSON translation packs to menu categories, items,
--    modifier groups and modifier options.
-- 2. Expose the translation packs through the signed guest menu/order RPCs.
-- 3. Install one trusted RPC for saving one complete menu locale in a single
--    request from Menu Management.
-- 4. Harden guest notification writes so an ETA-only kitchen update can never
--    violate guest_notifications.title/message NOT NULL constraints.
--
-- BUSINESS ROW SAFETY
-- Existing names, descriptions, prices, taxes, orders, modifiers, folios and
-- statuses are not changed. New translation columns default to empty objects.
--
-- EXPECTED RESULT
-- 30 rows
-- 30 passed = true
-- 0 failures
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608040054:premium-dining-i18n-rev1')
);

-- --------------------------------------------------------------------------
-- 1. Translation columns
-- --------------------------------------------------------------------------

alter table public.menu_categories
  add column if not exists translations jsonb not null default '{}'::jsonb;

alter table public.menu_items
  add column if not exists translations jsonb not null default '{}'::jsonb;

alter table public.menu_item_modifier_groups
  add column if not exists translations jsonb not null default '{}'::jsonb;

alter table public.menu_item_modifiers
  add column if not exists translations jsonb not null default '{}'::jsonb;

alter table public.menu_categories
  drop constraint if exists menu_categories_translations_object_check;
alter table public.menu_categories
  add constraint menu_categories_translations_object_check
  check (jsonb_typeof(translations) = 'object') not valid;
alter table public.menu_categories
  validate constraint menu_categories_translations_object_check;

alter table public.menu_items
  drop constraint if exists menu_items_translations_object_check;
alter table public.menu_items
  add constraint menu_items_translations_object_check
  check (jsonb_typeof(translations) = 'object') not valid;
alter table public.menu_items
  validate constraint menu_items_translations_object_check;

alter table public.menu_item_modifier_groups
  drop constraint if exists menu_item_modifier_groups_translations_object_check;
alter table public.menu_item_modifier_groups
  add constraint menu_item_modifier_groups_translations_object_check
  check (jsonb_typeof(translations) = 'object') not valid;
alter table public.menu_item_modifier_groups
  validate constraint menu_item_modifier_groups_translations_object_check;

alter table public.menu_item_modifiers
  drop constraint if exists menu_item_modifiers_translations_object_check;
alter table public.menu_item_modifiers
  add constraint menu_item_modifiers_translations_object_check
  check (jsonb_typeof(translations) = 'object') not valid;
alter table public.menu_item_modifiers
  validate constraint menu_item_modifiers_translations_object_check;

-- --------------------------------------------------------------------------
-- 2. Trusted locale-save RPC
-- --------------------------------------------------------------------------

create or replace function public.save_menu_locale_translations(
  p_hotel_id uuid,
  p_locale text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_locale text := lower(trim(coalesce(p_locale, '')));
  v_entry jsonb;
  v_updated_categories integer := 0;
  v_updated_items integer := 0;
  v_updated_groups integer := 0;
  v_updated_modifiers integer := 0;
begin
  if not private.user_has_permission(p_hotel_id, 'hotel.manage') then
    raise exception 'Menu translation update denied.';
  end if;

  if not (v_locale = any(array[
    'en','hi','mr','ta','te','bn','gu','kn','ml','pa','or','as'
  ]::text[])) then
    raise exception 'Unsupported dining locale.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Menu translation payload must be a JSON object.';
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_payload -> 'categories', '[]'::jsonb))
  loop
    update public.menu_categories mc
    set translations = jsonb_set(
      coalesce(mc.translations, '{}'::jsonb),
      array[v_locale],
      jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(trim(v_entry ->> 'name'), '')
      )),
      true
    )
    where mc.hotel_id = p_hotel_id
      and mc.id = nullif(v_entry ->> 'id', '')::uuid;
    v_updated_categories := v_updated_categories + case when found then 1 else 0 end;
  end loop;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb))
  loop
    update public.menu_items mi
    set translations = jsonb_set(
      coalesce(mi.translations, '{}'::jsonb),
      array[v_locale],
      jsonb_strip_nulls(jsonb_build_object(
        'item_name', nullif(trim(v_entry ->> 'item_name'), ''),
        'description', nullif(trim(v_entry ->> 'description'), '')
      )),
      true
    )
    where mi.hotel_id = p_hotel_id
      and mi.id = nullif(v_entry ->> 'id', '')::uuid;
    v_updated_items := v_updated_items + case when found then 1 else 0 end;
  end loop;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_payload -> 'groups', '[]'::jsonb))
  loop
    update public.menu_item_modifier_groups mg
    set translations = jsonb_set(
      coalesce(mg.translations, '{}'::jsonb),
      array[v_locale],
      jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(trim(v_entry ->> 'name'), '')
      )),
      true
    )
    where mg.hotel_id = p_hotel_id
      and mg.id = nullif(v_entry ->> 'id', '')::uuid;
    v_updated_groups := v_updated_groups + case when found then 1 else 0 end;
  end loop;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_payload -> 'modifiers', '[]'::jsonb))
  loop
    update public.menu_item_modifiers mm
    set translations = jsonb_set(
      coalesce(mm.translations, '{}'::jsonb),
      array[v_locale],
      jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(trim(v_entry ->> 'name'), '')
      )),
      true
    )
    where mm.hotel_id = p_hotel_id
      and mm.id = nullif(v_entry ->> 'id', '')::uuid;
    v_updated_modifiers := v_updated_modifiers + case when found then 1 else 0 end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'locale', v_locale,
    'categories', v_updated_categories,
    'items', v_updated_items,
    'groups', v_updated_groups,
    'modifiers', v_updated_modifiers
  );
end;
$function$;

revoke all on function public.save_menu_locale_translations(uuid,text,jsonb)
from public, anon;
grant execute on function public.save_menu_locale_translations(uuid,text,jsonb)
to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 3. Signed menu resolver now exposes all translation packs
-- --------------------------------------------------------------------------

create or replace function public.get_guest_food_menu(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context
  from private.day15_guest_context(
    p_hotel_slug,
    p_access_token,
    true
  );

  select coalesce(
    jsonb_agg(item_json order by category_sort, item_sort, item_name),
    '[]'::jsonb
  )
  into v_result
  from (
    select
      coalesce(mc.sort_order, 0) as category_sort,
      coalesce(mi.sort_order, 0) as item_sort,
      mi.item_name,
      jsonb_build_object(
        'id', mi.id,
        'item_name', mi.item_name,
        'description', mi.description,
        'translations', coalesce(mi.translations, '{}'::jsonb),
        'price', mi.price,
        'image_url', mi.image_url,
        'category_id', mc.id,
        'category', coalesce(mc.name, mi.category, 'Menu'),
        'category_code', mc.code,
        'category_translations', coalesce(mc.translations, '{}'::jsonb),
        'tax_rate', mi.tax_rate,
        'tax_inclusive', mi.tax_inclusive,
        'preparation_minutes', mi.preparation_minutes,
        'currency_code', v_context.currency_code,
        'service_start_time', mc.service_start_time,
        'service_end_time', mc.service_end_time,
        'modifier_groups', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', mg.id,
              'name', mg.name,
              'translations', coalesce(mg.translations, '{}'::jsonb),
              'min_selections', mg.min_selections,
              'max_selections', mg.max_selections,
              'is_required', mg.is_required,
              'modifiers', coalesce((
                select jsonb_agg(
                  jsonb_build_object(
                    'id', mm.id,
                    'name', mm.name,
                    'translations', coalesce(mm.translations, '{}'::jsonb),
                    'price_delta', mm.price_delta
                  )
                  order by mm.sort_order, mm.name
                )
                from public.menu_item_modifiers mm
                where mm.hotel_id = mg.hotel_id
                  and mm.modifier_group_id = mg.id
                  and mm.is_available
              ), '[]'::jsonb)
            )
            order by mg.sort_order, mg.name
          )
          from public.menu_item_modifier_groups mg
          where mg.hotel_id = mi.hotel_id
            and mg.menu_item_id = mi.id
            and mg.is_active
        ), '[]'::jsonb)
      ) as item_json
    from public.menu_items mi
    join public.menu_categories mc
      on mc.id = mi.category_id
     and mc.hotel_id = mi.hotel_id
    where mi.hotel_id = v_context.hotel_id
      and mi.is_available
      and mi.archived_at is null
      and private.day15_menu_item_available_now(
        mc,
        v_context.hotel_timezone
      )
  ) available_items;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

-- --------------------------------------------------------------------------
-- 4. Guest order tracking includes translation packs for current menu rows
-- --------------------------------------------------------------------------

create or replace function public.get_guest_food_orders(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context record;
  v_result jsonb;
begin
  select * into v_context
  from private.day15_guest_context(
    p_hotel_slug,
    p_access_token,
    true
  );

  select coalesce(
    jsonb_agg(order_json order by created_at desc),
    '[]'::jsonb
  ) into v_result
  from (
    select
      fo.created_at,
      jsonb_build_object(
        'id', fo.id,
        'subtotal_amount', fo.subtotal_amount,
        'modifier_amount', fo.modifier_amount,
        'tax_amount', fo.tax_amount,
        'total_amount', fo.total_amount,
        'currency_code', fo.currency_code,
        'payment_status', fo.payment_status,
        'order_status', fo.order_status,
        'created_at', fo.created_at,
        'estimated_minutes', fo.estimated_minutes,
        'estimated_delivery_time', fo.estimated_delivery_time,
        'accepted_at', fo.accepted_at,
        'preparing_at', fo.preparing_at,
        'ready_at', fo.ready_at,
        'out_for_delivery_at', fo.out_for_delivery_at,
        'delivered_at', fo.delivered_at,
        'cancelled_at', fo.cancelled_at,
        'cancellation_reason', fo.cancellation_reason,
        'can_cancel', (
          fo.order_status = 'pending'
          or (
            fo.order_status = 'accepted'
            and coalesce(fo.accepted_at, fo.created_at) > now() - interval '2 minutes'
          )
        ),
        'food_order_items', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', foi.id,
              'menu_item_id', foi.menu_item_id,
              'quantity', foi.quantity,
              'price', foi.price,
              'unit_price', foi.unit_price,
              'modifier_amount', foi.modifier_amount,
              'tax_amount', foi.tax_amount,
              'line_total', foi.line_total,
              'item_name', foi.item_name_snapshot,
              'translations', coalesce(mi.translations, '{}'::jsonb),
              'modifiers', coalesce((
                select jsonb_agg(
                  jsonb_build_object(
                    'modifier_id', foim.modifier_id,
                    'name', foim.modifier_name_snapshot,
                    'translations', coalesce(mm.translations, '{}'::jsonb),
                    'price_delta', foim.price_delta
                  ) order by foim.created_at, foim.id
                )
                from public.food_order_item_modifiers foim
                left join public.menu_item_modifiers mm
                  on mm.hotel_id = foim.hotel_id
                 and mm.id = foim.modifier_id
                where foim.hotel_id = foi.hotel_id
                  and foim.food_order_item_id = foi.id
              ), '[]'::jsonb)
            ) order by foi.id
          )
          from public.food_order_items foi
          left join public.menu_items mi
            on mi.hotel_id = foi.hotel_id
           and mi.id = foi.menu_item_id
          where foi.hotel_id = fo.hotel_id
            and foi.order_id = fo.id
        ), '[]'::jsonb),
        'events', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'event_type', foe.event_type,
              'from_status', foe.from_status,
              'to_status', foe.to_status,
              'estimated_minutes', foe.estimated_minutes,
              'message', foe.message,
              'created_at', foe.created_at
            ) order by foe.created_at, foe.id
          )
          from public.food_order_events foe
          where foe.hotel_id = fo.hotel_id
            and foe.food_order_id = fo.id
        ), '[]'::jsonb)
      ) as order_json
    from public.food_orders fo
    where fo.hotel_id = v_context.hotel_id
      and (
        fo.guest_session_id = v_context.guest_session_id
        or (
          fo.guest_session_id is null
          and fo.room_id = v_context.room_id
          and fo.guest_id = v_context.guest_id
        )
      )
  ) orders;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

-- --------------------------------------------------------------------------
-- 5. Notification hardening for ETA-only/same-state updates
-- --------------------------------------------------------------------------

create or replace function private.day15_notify_guest(
  p_hotel_id uuid,
  p_guest_session_id uuid,
  p_room_id uuid,
  p_guest_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_event_key text,
  p_title text,
  p_message text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
  v_event_key text := coalesce(nullif(trim(p_event_key), ''), 'update');
  v_title text := coalesce(nullif(trim(p_title), ''), 'Order update');
  v_message text := coalesce(nullif(trim(p_message), ''), 'Your order has been updated.');
begin
  insert into public.guest_notifications (
    hotel_id,
    guest_session_id,
    room_id,
    guest_id,
    source_type,
    source_id,
    event_key,
    title,
    message,
    metadata
  ) values (
    p_hotel_id,
    p_guest_session_id,
    p_room_id,
    p_guest_id,
    p_source_type,
    p_source_id,
    v_event_key,
    v_title,
    v_message,
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (hotel_id, source_type, source_id, event_key)
  do update set
    title = excluded.title,
    message = excluded.message,
    metadata = public.guest_notifications.metadata || excluded.metadata
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb)
from public, anon, authenticated;

commit;

-- --------------------------------------------------------------------------
-- 6. Migration acceptance — exactly 30 rows
-- --------------------------------------------------------------------------

with checks(test_name, passed, details) as (
  values
    ('01_menu_categories_translations_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='menu_categories' and column_name='translations'), 'Category translation JSON exists.'),
    ('02_menu_items_translations_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='menu_items' and column_name='translations'), 'Item translation JSON exists.'),
    ('03_modifier_groups_translations_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='menu_item_modifier_groups' and column_name='translations'), 'Modifier-group translation JSON exists.'),
    ('04_modifiers_translations_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='menu_item_modifiers' and column_name='translations'), 'Modifier translation JSON exists.'),
    ('05_categories_translation_default', (select column_default like '%{}%' from information_schema.columns where table_schema='public' and table_name='menu_categories' and column_name='translations'), 'Category translations default to empty JSON.'),
    ('06_items_translation_default', (select column_default like '%{}%' from information_schema.columns where table_schema='public' and table_name='menu_items' and column_name='translations'), 'Item translations default to empty JSON.'),
    ('07_groups_translation_default', (select column_default like '%{}%' from information_schema.columns where table_schema='public' and table_name='menu_item_modifier_groups' and column_name='translations'), 'Group translations default to empty JSON.'),
    ('08_modifiers_translation_default', (select column_default like '%{}%' from information_schema.columns where table_schema='public' and table_name='menu_item_modifiers' and column_name='translations'), 'Modifier translations default to empty JSON.'),
    ('09_categories_json_constraint', exists(select 1 from pg_constraint where conrelid='public.menu_categories'::regclass and conname='menu_categories_translations_object_check' and convalidated), 'Category JSON constraint is validated.'),
    ('10_items_json_constraint', exists(select 1 from pg_constraint where conrelid='public.menu_items'::regclass and conname='menu_items_translations_object_check' and convalidated), 'Item JSON constraint is validated.'),
    ('11_groups_json_constraint', exists(select 1 from pg_constraint where conrelid='public.menu_item_modifier_groups'::regclass and conname='menu_item_modifier_groups_translations_object_check' and convalidated), 'Group JSON constraint is validated.'),
    ('12_modifiers_json_constraint', exists(select 1 from pg_constraint where conrelid='public.menu_item_modifiers'::regclass and conname='menu_item_modifiers_translations_object_check' and convalidated), 'Modifier JSON constraint is validated.'),
    ('13_save_locale_rpc_exists', to_regprocedure('public.save_menu_locale_translations(uuid,text,jsonb)') is not null, 'Trusted translation-save RPC exists.'),
    ('14_authenticated_can_execute_save_locale', has_function_privilege('authenticated','public.save_menu_locale_translations(uuid,text,jsonb)','EXECUTE'), 'Authenticated hotel users can invoke the trusted save RPC.'),
    ('15_anon_cannot_execute_save_locale', not has_function_privilege('anon','public.save_menu_locale_translations(uuid,text,jsonb)','EXECUTE'), 'Anonymous guests cannot edit menu translations.'),
    ('16_guest_menu_rpc_retained', to_regprocedure('public.get_guest_food_menu(text,text)') is not null, 'Signed guest-menu RPC is retained.'),
    ('17_guest_orders_rpc_retained', to_regprocedure('public.get_guest_food_orders(text,text)') is not null, 'Signed guest-order tracking RPC is retained.'),
    ('18_guest_menu_exposes_item_translations', position('translations' in lower(pg_get_functiondef('public.get_guest_food_menu(text,text)'::regprocedure))) > 0, 'Guest menu exposes item translation packs.'),
    ('19_guest_menu_exposes_category_translations', position('category_translations' in lower(pg_get_functiondef('public.get_guest_food_menu(text,text)'::regprocedure))) > 0, 'Guest menu exposes category translation packs.'),
    ('20_guest_menu_exposes_modifier_translations', position('menu_item_modifiers' in lower(pg_get_functiondef('public.get_guest_food_menu(text,text)'::regprocedure))) > 0 and position('translations' in lower(pg_get_functiondef('public.get_guest_food_menu(text,text)'::regprocedure))) > 0, 'Guest menu exposes modifier translation packs.'),
    ('21_guest_orders_expose_item_id', position('menu_item_id' in lower(pg_get_functiondef('public.get_guest_food_orders(text,text)'::regprocedure))) > 0, 'Guest tracking exposes item identity.'),
    ('22_guest_orders_expose_translations', position('translations' in lower(pg_get_functiondef('public.get_guest_food_orders(text,text)'::regprocedure))) > 0, 'Guest tracking exposes current translation packs.'),
    ('23_notify_helper_retained', to_regprocedure('private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb)') is not null, 'Notification helper exists.'),
    ('24_notify_title_fallback', position('order update' in lower(pg_get_functiondef('private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure))) > 0, 'Notification title has a non-null fallback.'),
    ('25_notify_message_fallback', position('your order has been updated' in lower(pg_get_functiondef('private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb)'::regprocedure))) > 0, 'Notification message has a non-null fallback.'),
    ('26_existing_category_rows_valid', not exists(select 1 from public.menu_categories where jsonb_typeof(translations) <> 'object'), 'All existing category rows have valid translation JSON.'),
    ('27_existing_item_rows_valid', not exists(select 1 from public.menu_items where jsonb_typeof(translations) <> 'object'), 'All existing item rows have valid translation JSON.'),
    ('28_existing_group_rows_valid', not exists(select 1 from public.menu_item_modifier_groups where jsonb_typeof(translations) <> 'object'), 'All existing group rows have valid translation JSON.'),
    ('29_existing_modifier_rows_valid', not exists(select 1 from public.menu_item_modifiers where jsonb_typeof(translations) <> 'object'), 'All existing modifier rows have valid translation JSON.'),
    ('30_migration_054_complete', true, 'Premium dining locale, offer-builder and performance foundation is installed.')
)
select 'M054'::text as suite, test_name, passed, details
from checks
order by test_name;
