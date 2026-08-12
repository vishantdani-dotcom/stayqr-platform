-- StayQR v1.0 — Day 20 Migration 070 REV1
-- Gate 20A-3: Guest Guide publication-aware QR readiness hardening
-- Date: 2026-08-12
--
-- PURPOSE
--   * QR readiness is TRUE only when the guest-access infrastructure exists
--     AND the hotel has an immutable published Premium Guest Guide version.
--   * Initial onboarding publication remains automatic and cannot deadlock:
--     when every non-QR readiness item is green, refresh publishes the initial
--     guide snapshot (only when no published version exists), then recomputes.
--   * Existing hotels with a previously published version remain QR-ready even
--     when newer draft edits are pending publication.
--   * The anonymous Premium Guest Guide resolver becomes fail-closed: it never
--     renders the current live draft when no published version exists.
--
-- SAFETY
--   * Transactional.
--   * No deletes.
--   * No guest/reservation/payment/folio/order business rows are rewritten.
--   * Existing immutable Guest Guide versions are preserved.
--   * Day 19 locked baseline files are not modified; this is a forward migration.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

SELECT pg_advisory_xact_lock(
  hashtext('stayqr:202608120070:day20-guest-guide-publication-readiness')
);

-- --------------------------------------------------------------------------
-- 0. PRE-FLIGHT
-- --------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.hotel_onboarding') IS NULL
     OR to_regclass('public.guest_guide_settings') IS NULL
     OR to_regclass('public.guest_guide_versions') IS NULL
     OR to_regclass('public.guest_access_tokens') IS NULL
  THEN
    RAISE EXCEPTION
      'Day 20 Migration 070 stopped: required onboarding/Guest Guide tables are missing.';
  END IF;

  IF to_regprocedure('private.ensure_guest_guide_foundation_20260811(uuid,boolean)') IS NULL
     OR to_regprocedure('private.compute_hotel_onboarding_readiness(uuid)') IS NULL
     OR to_regprocedure('public.refresh_hotel_onboarding_readiness(uuid)') IS NULL
     OR to_regprocedure('public.resolve_premium_guest_guide(text,text)') IS NULL
  THEN
    RAISE EXCEPTION
      'Day 20 Migration 070 stopped: required Day 8/Day 14/Day 19 functions are missing.';
  END IF;
END;
$preflight$;


-- --------------------------------------------------------------------------
-- 1. AUTHORITATIVE PUBLISHED-VERSION PREDICATE
--    IMPORTANT: publish_status may legitimately be 'draft' after edits while
--    an earlier immutable version is still what guests see. Therefore readiness
--    keys off the referenced immutable version, not the current draft flag.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.day20_guest_guide_has_published_version_20260812(
  p_hotel_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.guest_guide_settings s
    JOIN public.guest_guide_versions v
      ON v.hotel_id = s.hotel_id
     AND v.version_number = s.published_version
    WHERE s.hotel_id = p_hotel_id
      AND s.published_version >= 1
  );
$function$;

REVOKE ALL ON FUNCTION private.day20_guest_guide_has_published_version_20260812(uuid)
FROM PUBLIC, anon, authenticated;


-- --------------------------------------------------------------------------
-- 2. QR READINESS NOW REQUIRES A REAL PUBLISHED VERSION
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "private"."compute_hotel_onboarding_readiness"("target_hotel_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  hotel_details_ready boolean := false;
  owner_ready boolean := false;
  settings_ready boolean := false;
  room_types_ready boolean := false;
  floors_ready boolean := false;
  rooms_ready boolean := false;
  rates_ready boolean := false;
  amenities_ready boolean := false;
  request_categories_ready boolean := false;
  menu_ready boolean := false;
  invoice_ready boolean := false;
  subscription_ready boolean := false;
  qr_ready boolean := false;
  all_ready boolean := false;
  missing_items text[];
begin
  if target_hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = target_hotel_id
     )
  then
    raise exception 'Unknown hotel.';
  end if;

  select
    nullif(trim(h.hotel_name), '') is not null
    and nullif(trim(h.slug), '') is not null
    and nullif(trim(h.timezone), '') is not null
    and h.currency_code ~ '^[A-Z]{3}$'
    and exists (
      select 1
      from public.hotel_info hi
      where hi.hotel_id = h.id
    )
  into hotel_details_ready
  from public.hotels h
  where h.id = target_hotel_id;

  select exists (
    select 1
    from public.staff s
    where s.hotel_id = target_hotel_id
      and s.status = 'active'
      and s.auth_user_id is not null
      and lower(replace(trim(s.role::text), ' ', '_')) = 'owner'
  )
  into owner_ready;

  select exists (
    select 1
    from public.hotel_settings hs
    where hs.hotel_id = target_hotel_id
  )
  into settings_ready;

  select exists (
    select 1
    from public.room_types rt
    where rt.hotel_id = target_hotel_id
      and rt.is_active
  )
  into room_types_ready;

  select exists (
    select 1
    from public.floors f
    where f.hotel_id = target_hotel_id
      and f.is_active
  )
  into floors_ready;

  select
    exists (
      select 1
      from public.rooms r
      where r.hotel_id = target_hotel_id
    )
    and not exists (
      select 1
      from public.rooms r
      where r.hotel_id = target_hotel_id
        and (r.room_type_id is null or r.floor_id is null)
    )
  into rooms_ready;

  select
    room_types_ready
    and not exists (
      select 1
      from public.room_types rt
      where rt.hotel_id = target_hotel_id
        and rt.is_active
        and not exists (
          select 1
          from public.rate_plans rp
          where rp.hotel_id = rt.hotel_id
            and rp.room_type_id = rt.id
            and rp.is_active
        )
    )
  into rates_ready;

  if to_regclass('public.amenities') is not null then
    execute
      'select exists (
         select 1
         from public.amenities a
         where a.hotel_id = $1
           and a.is_active
       )'
    into amenities_ready
    using target_hotel_id;
  end if;

  if to_regclass('public.service_request_types') is not null then
    execute
      'select exists (
         select 1
         from public.service_request_types srt
         where srt.hotel_id = $1
           and srt.is_active
       )'
    into request_categories_ready
    using target_hotel_id;
  end if;

  select
    exists (
      select 1
      from public.menu_categories mc
      where mc.hotel_id = target_hotel_id
    )
    and exists (
      select 1
      from public.menu_items mi
      where mi.hotel_id = target_hotel_id
    )
  into menu_ready;

  select exists (
    select 1
    from public.invoice_number_sequences ins
    where ins.hotel_id = target_hotel_id
      and ins.sequence_year = extract(year from now())::integer
  )
  into invoice_ready;

  select exists (
    select 1
    from public.hotel_subscriptions hsub
    where hsub.hotel_id = target_hotel_id
      and hsub.status in ('trial', 'trialing', 'active', 'past_due')
      and (
        hsub.end_date is null
        or hsub.end_date > now()
        or hsub.status = 'past_due'
      )
  )
  into subscription_ready;

  qr_ready :=
    rooms_ready
    and to_regclass('public.guest_access_tokens') is not null
    and to_regprocedure('public.get_guest_access_links(uuid)') is not null
    and to_regprocedure('public.resolve_guest_portal(text,text)') is not null
    and private.day20_guest_guide_has_published_version_20260812(target_hotel_id);

  missing_items := array_remove(array[
    case when not hotel_details_ready then 'hotel_details' end,
    case when not owner_ready then 'owner_identity' end,
    case when not settings_ready then 'hotel_settings' end,
    case when not room_types_ready then 'room_types' end,
    case when not floors_ready then 'floors' end,
    case when not rooms_ready then 'rooms' end,
    case when not rates_ready then 'rates' end,
    case when not amenities_ready then 'amenities' end,
    case when not request_categories_ready then 'request_categories' end,
    case when not menu_ready then 'menu' end,
    case when not invoice_ready then 'invoice_numbering' end,
    case when not subscription_ready then 'subscription' end,
    case when not qr_ready then 'qr_readiness' end
  ], null);

  all_ready := coalesce(cardinality(missing_items), 0) = 0;

  return jsonb_build_object(
    'ready', all_ready,
    'checklist', jsonb_build_object(
      'hotel_details', hotel_details_ready,
      'owner_identity', owner_ready,
      'settings', settings_ready,
      'room_types', room_types_ready,
      'floors', floors_ready,
      'rooms', rooms_ready,
      'rates', rates_ready,
      'amenities', amenities_ready,
      'request_categories', request_categories_ready,
      'menu', menu_ready,
      'invoice', invoice_ready,
      'subscription', subscription_ready,
      'qr_ready', qr_ready
    ),
    'missing', to_jsonb(coalesce(missing_items, '{}'::text[])),
    'generated_at', now()
  );
end;
$_$;


ALTER FUNCTION "private"."compute_hotel_onboarding_readiness"("target_hotel_id" "uuid") OWNER TO "postgres";


-- --------------------------------------------------------------------------
-- 3. REFRESH CAN SAFELY CREATE THE INITIAL PUBLISHED VERSION
--    This avoids a readiness deadlock: publication happens only after every
--    non-QR gate is green and only if the hotel has never published a version.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "public"."refresh_hotel_onboarding_readiness"("target_hotel_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  actor_user_id uuid := (select auth.uid());
  readiness jsonb;
  non_qr_ready boolean := false;
  is_ready boolean;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
    or exists (
      select 1
      from public.hotel_onboarding ho
      where ho.hotel_id = target_hotel_id
        and ho.owner_user_id = actor_user_id
    )
  ) then
    raise exception 'Hotel configuration access denied.';
  end if;

  readiness := private.compute_hotel_onboarding_readiness(target_hotel_id);

  non_qr_ready :=
    coalesce((readiness -> 'checklist' ->> 'hotel_details')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'owner_identity')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'settings')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'room_types')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'floors')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'rooms')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'rates')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'amenities')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'request_categories')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'menu')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'invoice')::boolean, false)
    and coalesce((readiness -> 'checklist' ->> 'subscription')::boolean, false);

  if non_qr_ready
     and not private.day20_guest_guide_has_published_version_20260812(target_hotel_id)
  then
    perform private.ensure_guest_guide_foundation_20260811(
      target_hotel_id,
      true
    );
    readiness := private.compute_hotel_onboarding_readiness(target_hotel_id);
  end if;

  is_ready := coalesce((readiness ->> 'ready')::boolean, false);

  update public.hotel_onboarding ho
  set
    readiness_state = readiness,
    status = case when is_ready then 'complete' else 'in_progress' end,
    current_step = case when is_ready then 'complete' else ho.current_step end,
    completed_at = case when is_ready then coalesce(ho.completed_at, now()) else null end,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id;

  if not found then
    raise exception 'Hotel onboarding state is missing.';
  end if;

  return readiness;
end;
$$;


ALTER FUNCTION "public"."refresh_hotel_onboarding_readiness"("target_hotel_id" "uuid") OWNER TO "postgres";


-- --------------------------------------------------------------------------
-- 4. PREMIUM GUEST GUIDE MUST NEVER FALL BACK TO LIVE DRAFT CONTENT
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "public"."resolve_premium_guest_guide"("p_hotel_slug" "text", "p_access_token" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    raise exception 'Guest Guide is not published yet.';
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
$$;


ALTER FUNCTION "public"."resolve_premium_guest_guide"("p_hotel_slug" "text", "p_access_token" "text") OWNER TO "postgres";


-- --------------------------------------------------------------------------
-- 5. POST-MIGRATION ASSERTIONS
-- --------------------------------------------------------------------------
DO $verify$
DECLARE
  v_compute text;
  v_refresh text;
  v_resolver text;
BEGIN
  SELECT lower(pg_get_functiondef('private.compute_hotel_onboarding_readiness(uuid)'::regprocedure))
  INTO v_compute;

  SELECT lower(pg_get_functiondef('public.refresh_hotel_onboarding_readiness(uuid)'::regprocedure))
  INTO v_refresh;

  SELECT lower(pg_get_functiondef('public.resolve_premium_guest_guide(text,text)'::regprocedure))
  INTO v_resolver;

  IF position('day20_guest_guide_has_published_version_20260812' in v_compute) = 0 THEN
    RAISE EXCEPTION
      'Day 20 Migration 070 verification failed: QR readiness does not require a published Guest Guide version.';
  END IF;

  IF position('ensure_guest_guide_foundation_20260811' in v_refresh) = 0
     OR position('non_qr_ready' in v_refresh) = 0
  THEN
    RAISE EXCEPTION
      'Day 20 Migration 070 verification failed: readiness refresh cannot publish the initial guide safely.';
  END IF;

  IF position('guest guide is not published yet' in v_resolver) = 0 THEN
    RAISE EXCEPTION
      'Day 20 Migration 070 verification failed: premium resolver is not fail-closed for unpublished guides.';
  END IF;

  IF position('v_snapshot := private.day14_build_guide_snapshot' in v_resolver) > 0 THEN
    RAISE EXCEPTION
      'Day 20 Migration 070 verification failed: premium resolver still exposes a live draft fallback.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hotel_onboarding ho
    WHERE ho.status = 'complete'
      AND NOT private.day20_guest_guide_has_published_version_20260812(ho.hotel_id)
  ) THEN
    RAISE EXCEPTION
      'Day 20 Migration 070 verification failed: a completed hotel has no immutable published Guest Guide version.';
  END IF;
END;
$verify$;


COMMIT;
