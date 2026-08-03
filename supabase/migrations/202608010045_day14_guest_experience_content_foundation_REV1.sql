-- StayQR v1.0 — Day 14 Migration 045 REV1
-- Guest experience content, private feedback, multilingual readiness and review/reward audit
-- Date: 2026-08-01
--
-- Preserves the accepted Day 7 signed/rotating/revocable guest-token lifecycle.
-- Adds:
--   1. Multilingual hotel guest-content storage.
--   2. Private token-bound guest feedback with follow-up consent.
--   3. Token-bound Google-review/reward action audit.
--   4. Hotel content read/write RPCs.
--   5. Extended guest portal response containing safe translations and amenities.
--
-- Safety:
--   * No hotel business rows are deleted.
--   * Existing public.hotel_info remains the authoritative legacy/default profile source.
--   * Anonymous users receive no direct table access.
--   * Guest writes are accepted only through signed active-stay RPCs.
--   * Hotel content writes require hotel.manage permission.

begin;

create schema if not exists private;

-- --------------------------------------------------------------------------
-- 1. Multilingual hotel guest content
-- --------------------------------------------------------------------------

create table if not exists public.hotel_guest_content (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  locale text not null,
  content jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hotel_guest_content_locale_format
    check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  constraint hotel_guest_content_json_object
    check (jsonb_typeof(content) = 'object'),
  constraint hotel_guest_content_size
    check (pg_column_size(content) <= 65536),
  constraint uq_hotel_guest_content_locale
    unique (hotel_id, locale)
);

create index if not exists idx_hotel_guest_content_hotel_active
on public.hotel_guest_content (hotel_id, is_active, locale);

-- Seed an English content record for every hotel without overwriting future edits.
insert into public.hotel_guest_content (
  hotel_id,
  locale,
  content,
  is_active
)
select
  h.id,
  'en',
  jsonb_strip_nulls(
    jsonb_build_object(
      'hotel_name', coalesce(hi.hotel_name, h.hotel_name),
      'address', coalesce(hi.address, h.address, h.location),
      'about', hi.about,
      'wifi_name', hi.wifi_name,
      'wifi_password', hi.wifi_password,
      'checkin_time', hi.checkin_time,
      'checkout_time', hi.checkout_time,
      'breakfast_time', hi.breakfast_time,
      'reception_phone', hi.reception_phone,
      'emergency_phone', hi.emergency_phone,
      'hotel_rules', hi.hotel_rules,
      'google_review_url', hi.google_review_url,
      'reward_enabled', coalesce(hi.reward_enabled, false),
      'reward_title', hi.reward_title,
      'reward_description', hi.reward_description,
      'welcome_title', 'Welcome to ' || coalesce(hi.hotel_name, h.hotel_name),
      'welcome_message', 'Everything you need during your stay, in one secure place.'
    )
  ),
  true
from public.hotels h
left join public.hotel_info hi
  on hi.hotel_id = h.id
on conflict (hotel_id, locale) do nothing;

-- --------------------------------------------------------------------------
-- 2. Private guest feedback
-- --------------------------------------------------------------------------

create table if not exists public.guest_feedback (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  guest_session_id uuid not null
    references public.guest_sessions(id) on delete cascade,
  guest_access_token_id uuid
    references public.guest_access_tokens(id) on delete set null,
  rating integer not null
    check (rating between 1 and 5),
  message text,
  consent_to_follow_up boolean not null default false,
  status text not null default 'new'
    check (status in ('new', 'reviewed', 'resolved', 'closed')),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint guest_feedback_message_length
    check (message is null or char_length(message) <= 4000),
  constraint uq_guest_feedback_session
    unique (guest_session_id)
);

create index if not exists idx_guest_feedback_hotel_status_submitted
on public.guest_feedback (hotel_id, status, submitted_at desc);

-- --------------------------------------------------------------------------
-- 3. Google review/reward action audit
-- --------------------------------------------------------------------------

create table if not exists public.guest_review_rewards (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  guest_session_id uuid not null
    references public.guest_sessions(id) on delete cascade,
  guest_access_token_id uuid
    references public.guest_access_tokens(id) on delete set null,
  action text not null
    check (
      action in (
        'review_opened',
        'reward_viewed',
        'reward_requested',
        'reward_redeemed',
        'reward_declined'
      )
    ),
  status text not null default 'recorded'
    check (status in ('recorded', 'approved', 'redeemed', 'declined')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references auth.users(id) on delete set null,
  constraint uq_guest_review_reward_session_action
    unique (guest_session_id, action)
);

create index if not exists idx_guest_review_rewards_hotel_created
on public.guest_review_rewards (hotel_id, created_at desc);

-- --------------------------------------------------------------------------
-- 4. Updated-at helper
-- --------------------------------------------------------------------------

create or replace function private.day14_touch_updated_at()
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

drop trigger if exists hotel_guest_content_touch_updated_at
on public.hotel_guest_content;

create trigger hotel_guest_content_touch_updated_at
before update on public.hotel_guest_content
for each row execute function private.day14_touch_updated_at();

drop trigger if exists guest_feedback_touch_updated_at
on public.guest_feedback;

create trigger guest_feedback_touch_updated_at
before update on public.guest_feedback
for each row execute function private.day14_touch_updated_at();

revoke all on function private.day14_touch_updated_at()
from public, anon, authenticated;

-- --------------------------------------------------------------------------
-- 5. RLS and direct-access boundary
-- --------------------------------------------------------------------------

alter table public.hotel_guest_content enable row level security;
alter table public.guest_feedback enable row level security;
alter table public.guest_review_rewards enable row level security;

drop policy if exists stayqr_day14_hotel_guest_content_select
on public.hotel_guest_content;

create policy stayqr_day14_hotel_guest_content_select
on public.hotel_guest_content
for select
to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

drop policy if exists stayqr_day14_guest_feedback_select
on public.guest_feedback;

create policy stayqr_day14_guest_feedback_select
on public.guest_feedback
for select
to authenticated
using (
  private.user_has_permission(hotel_id, 'hotel.manage')
  or private.user_has_permission(hotel_id, 'service.manage')
);

drop policy if exists stayqr_day14_guest_feedback_update
on public.guest_feedback;

create policy stayqr_day14_guest_feedback_update
on public.guest_feedback
for update
to authenticated
using (
  private.user_has_permission(hotel_id, 'hotel.manage')
  or private.user_has_permission(hotel_id, 'service.manage')
)
with check (
  private.user_has_permission(hotel_id, 'hotel.manage')
  or private.user_has_permission(hotel_id, 'service.manage')
);

drop policy if exists stayqr_day14_guest_review_rewards_select
on public.guest_review_rewards;

create policy stayqr_day14_guest_review_rewards_select
on public.guest_review_rewards
for select
to authenticated
using (
  private.user_has_permission(hotel_id, 'hotel.manage')
  or private.user_has_permission(hotel_id, 'service.manage')
);

drop policy if exists stayqr_day14_guest_review_rewards_update
on public.guest_review_rewards;

create policy stayqr_day14_guest_review_rewards_update
on public.guest_review_rewards
for update
to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'))
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

revoke all on public.hotel_guest_content from public, anon, authenticated;
revoke all on public.guest_feedback from public, anon, authenticated;
revoke all on public.guest_review_rewards from public, anon, authenticated;

grant select on public.hotel_guest_content to authenticated;
grant select, update on public.guest_feedback to authenticated;
grant select, update on public.guest_review_rewards to authenticated;

-- --------------------------------------------------------------------------
-- 6. Hotel content editor RPCs
-- --------------------------------------------------------------------------

create or replace function public.get_hotel_guest_content(
  p_hotel_id uuid,
  p_locale text default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_locale text := coalesce(nullif(trim(p_locale), ''), 'en');
  v_result jsonb;
begin
  if not private.user_has_permission(p_hotel_id, 'hotel.manage') then
    raise exception 'Guest content access denied.';
  end if;

  if v_locale !~ '^[a-z]{2}(-[A-Z]{2})?$' then
    raise exception 'Invalid locale.';
  end if;

  select jsonb_build_object(
    'hotel_id', h.id,
    'locale', v_locale,
    'base_profile', jsonb_strip_nulls(
      jsonb_build_object(
        'hotel_name', coalesce(hi.hotel_name, h.hotel_name),
        'address', coalesce(hi.address, h.address, h.location),
        'about', hi.about,
        'wifi_name', hi.wifi_name,
        'wifi_password', hi.wifi_password,
        'checkin_time', hi.checkin_time,
        'checkout_time', hi.checkout_time,
        'breakfast_time', hi.breakfast_time,
        'reception_phone', hi.reception_phone,
        'emergency_phone', hi.emergency_phone,
        'hotel_rules', hi.hotel_rules,
        'google_review_url', hi.google_review_url,
        'reward_enabled', coalesce(hi.reward_enabled, false),
        'reward_title', hi.reward_title,
        'reward_description', hi.reward_description
      )
    ),
    'content', coalesce(hgc.content, '{}'::jsonb),
    'is_active', coalesce(hgc.is_active, true),
    'available_locales', coalesce(
      (
        select jsonb_agg(c.locale order by c.locale)
        from public.hotel_guest_content c
        where c.hotel_id = h.id
          and c.is_active
      ),
      '[]'::jsonb
    ),
    'amenities', coalesce(
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
    )
  )
  into v_result
  from public.hotels h
  left join public.hotel_info hi
    on hi.hotel_id = h.id
  left join public.hotel_guest_content hgc
    on hgc.hotel_id = h.id
   and hgc.locale = v_locale
  where h.id = p_hotel_id;

  if v_result is null then
    raise exception 'Hotel was not found.';
  end if;

  return v_result;
end;
$function$;

create or replace function public.upsert_hotel_guest_content(
  p_hotel_id uuid,
  p_locale text,
  p_content jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_locale text := coalesce(nullif(trim(p_locale), ''), 'en');
  v_row public.hotel_guest_content%rowtype;
begin
  if not private.user_has_permission(p_hotel_id, 'hotel.manage') then
    raise exception 'Guest content update denied.';
  end if;

  if not exists (
    select 1 from public.hotels h where h.id = p_hotel_id
  ) then
    raise exception 'Hotel was not found.';
  end if;

  if v_locale !~ '^[a-z]{2}(-[A-Z]{2})?$' then
    raise exception 'Invalid locale.';
  end if;

  if p_content is null or jsonb_typeof(p_content) <> 'object' then
    raise exception 'Guest content must be a JSON object.';
  end if;

  if pg_column_size(p_content) > 65536 then
    raise exception 'Guest content exceeds the 64 KB limit.';
  end if;

  insert into public.hotel_guest_content (
    hotel_id,
    locale,
    content,
    is_active,
    updated_by
  )
  values (
    p_hotel_id,
    v_locale,
    p_content,
    true,
    auth.uid()
  )
  on conflict (hotel_id, locale)
  do update set
    content = excluded.content,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now()
  returning *
  into v_row;

  return jsonb_build_object(
    'result', 'GUEST CONTENT SAVED',
    'hotel_id', v_row.hotel_id,
    'locale', v_row.locale,
    'content', v_row.content,
    'updated_at', v_row.updated_at
  );
end;
$function$;

revoke all on function public.get_hotel_guest_content(uuid,text)
from public, anon;

revoke all on function public.upsert_hotel_guest_content(uuid,text,jsonb)
from public, anon;

grant execute on function public.get_hotel_guest_content(uuid,text)
to authenticated;

grant execute on function public.upsert_hotel_guest_content(uuid,text,jsonb)
to authenticated;

-- --------------------------------------------------------------------------
-- 7. Token-bound private guest feedback RPC
-- --------------------------------------------------------------------------

create or replace function public.submit_guest_feedback(
  p_hotel_slug text,
  p_access_token text,
  p_rating integer,
  p_message text,
  p_consent_to_follow_up boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token_id uuid;
  v_token public.guest_access_tokens%rowtype;
  v_feedback public.guest_feedback%rowtype;
  v_message text := nullif(trim(coalesce(p_message, '')), '');
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5.';
  end if;

  if v_message is not null and char_length(v_message) > 4000 then
    raise exception 'Feedback message exceeds 4000 characters.';
  end if;

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

  insert into public.guest_feedback (
    hotel_id,
    guest_session_id,
    guest_access_token_id,
    rating,
    message,
    consent_to_follow_up,
    status,
    submitted_at
  )
  values (
    v_token.hotel_id,
    v_token.guest_session_id,
    v_token.id,
    p_rating,
    v_message,
    coalesce(p_consent_to_follow_up, false),
    'new',
    now()
  )
  on conflict (guest_session_id)
  do update set
    guest_access_token_id = excluded.guest_access_token_id,
    rating = excluded.rating,
    message = excluded.message,
    consent_to_follow_up = excluded.consent_to_follow_up,
    status = 'new',
    submitted_at = now(),
    reviewed_at = null,
    reviewed_by = null,
    updated_at = now()
  returning *
  into v_feedback;

  return jsonb_build_object(
    'result', 'FEEDBACK RECEIVED',
    'feedback_id', v_feedback.id,
    'rating', v_feedback.rating,
    'submitted_at', v_feedback.submitted_at
  );
end;
$function$;

revoke all on function public.submit_guest_feedback(text,text,integer,text,boolean)
from public, authenticated;

grant execute on function public.submit_guest_feedback(text,text,integer,text,boolean)
to anon;

-- --------------------------------------------------------------------------
-- 8. Token-bound review/reward action audit RPC
-- --------------------------------------------------------------------------

create or replace function public.record_guest_review_reward_action(
  p_hotel_slug text,
  p_access_token text,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token_id uuid;
  v_token public.guest_access_tokens%rowtype;
  v_action text := lower(trim(coalesce(p_action, '')));
  v_row public.guest_review_rewards%rowtype;
begin
  if v_action not in (
    'review_opened',
    'reward_viewed',
    'reward_requested',
    'reward_redeemed',
    'reward_declined'
  ) then
    raise exception 'Unsupported review or reward action.';
  end if;

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

  insert into public.guest_review_rewards (
    hotel_id,
    guest_session_id,
    guest_access_token_id,
    action,
    status
  )
  values (
    v_token.hotel_id,
    v_token.guest_session_id,
    v_token.id,
    v_action,
    case
      when v_action = 'reward_redeemed' then 'redeemed'
      when v_action = 'reward_declined' then 'declined'
      else 'recorded'
    end
  )
  on conflict (guest_session_id, action)
  do update set
    guest_access_token_id = excluded.guest_access_token_id
  returning *
  into v_row;

  return jsonb_build_object(
    'result', 'ACTION RECORDED',
    'action_id', v_row.id,
    'action', v_row.action,
    'status', v_row.status,
    'created_at', v_row.created_at
  );
end;
$function$;

revoke all on function public.record_guest_review_reward_action(text,text,text)
from public, authenticated;

grant execute on function public.record_guest_review_reward_action(text,text,text)
to anon;

-- --------------------------------------------------------------------------
-- 9. Extend the existing signed guest portal response
-- --------------------------------------------------------------------------

create or replace function public.resolve_guest_portal(
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
  v_response jsonb;
begin
  v_token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if v_token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select jsonb_build_object(
    'hotel', jsonb_build_object(
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
      )
      || coalesce(
        (
          select c.content
          from public.hotel_guest_content c
          where c.hotel_id = h.id
            and c.locale = 'en'
            and c.is_active
          limit 1
        ),
        '{}'::jsonb
      ),
    'guest_content', jsonb_build_object(
      'default_locale', 'en',
      'available_locales', coalesce(
        (
          select jsonb_agg(c.locale order by c.locale)
          from public.hotel_guest_content c
          where c.hotel_id = h.id
            and c.is_active
        ),
        '[]'::jsonb
      ),
      'translations', coalesce(
        (
          select jsonb_object_agg(c.locale, c.content)
          from public.hotel_guest_content c
          where c.hotel_id = h.id
            and c.is_active
        ),
        '{}'::jsonb
      ),
      'amenities', coalesce(
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
    'session', jsonb_build_object(
      'id', gs.id,
      'checkin_time', gs.checkin_time,
      'checkout_time', gs.checkout_time,
      'extended_until', gs.extended_until,
      'guests', jsonb_build_object(
        'full_name', g.full_name
      ),
      'rooms', jsonb_build_object(
        'id', r.id,
        'room_number', r.room_number,
        'room_type', r.room_type
      )
    )
  )
  into v_response
  from public.guest_access_tokens t
  join public.hotels h
    on h.id = t.hotel_id
  join public.guest_sessions gs
    on gs.id = t.guest_session_id
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

revoke all on function public.resolve_guest_portal(text,text)
from public, authenticated;

grant execute on function public.resolve_guest_portal(text,text)
to anon;

-- --------------------------------------------------------------------------
-- 10. Migration acceptance helper — 40 structural/security checks
-- --------------------------------------------------------------------------

create or replace function private.day14_migration_045_acceptance_rev1()
returns table (
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
begin
  return query
  select '01_hotel_guest_content_table',
    to_regclass('public.hotel_guest_content') is not null,
    'Multilingual hotel guest-content table exists.';

  return query
  select '02_guest_feedback_table',
    to_regclass('public.guest_feedback') is not null,
    'Private guest feedback table exists.';

  return query
  select '03_guest_review_rewards_table',
    to_regclass('public.guest_review_rewards') is not null,
    'Review/reward audit table exists.';

  return query
  select '04_hotel_content_locale_column',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'hotel_guest_content'
        and column_name = 'locale'
    ),
    'Locale column exists.';

  return query
  select '05_hotel_content_json_column',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'hotel_guest_content'
        and column_name = 'content'
        and udt_name = 'jsonb'
    ),
    'Content JSONB column exists.';

  return query
  select '06_feedback_rating_column',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_feedback'
        and column_name = 'rating'
    ),
    'Feedback rating column exists.';

  return query
  select '07_feedback_consent_column',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_feedback'
        and column_name = 'consent_to_follow_up'
    ),
    'Feedback follow-up consent column exists.';

  return query
  select '08_reward_action_column',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'guest_review_rewards'
        and column_name = 'action'
    ),
    'Review/reward action column exists.';

  return query
  select '09_hotel_content_unique_locale',
    to_regclass('public.uq_hotel_guest_content_locale') is not null
    or exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname = 'hotel_guest_content'
        and c.contype = 'u'
    ),
    'One content row per hotel/locale is enforced.';

  return query
  select '10_feedback_unique_session',
    exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname = 'guest_feedback'
        and c.contype = 'u'
    ),
    'One current feedback record per guest stay is enforced.';

  return query
  select '11_reward_unique_action',
    exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname = 'guest_review_rewards'
        and c.contype = 'u'
    ),
    'Duplicate review/reward actions are prevented.';

  return query
  select '12_hotel_content_rls',
    c.relrowsecurity,
    'RLS is enabled on hotel_guest_content.'
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'hotel_guest_content';

  return query
  select '13_guest_feedback_rls',
    c.relrowsecurity,
    'RLS is enabled on guest_feedback.'
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'guest_feedback';

  return query
  select '14_guest_review_rewards_rls',
    c.relrowsecurity,
    'RLS is enabled on guest_review_rewards.'
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'guest_review_rewards';

  return query
  select '15_anon_no_hotel_content_read',
    not has_table_privilege('anon', 'public.hotel_guest_content', 'SELECT'),
    'Anonymous users cannot directly read content rows.';

  return query
  select '16_anon_no_hotel_content_write',
    not (
      has_table_privilege('anon', 'public.hotel_guest_content', 'INSERT')
      or has_table_privilege('anon', 'public.hotel_guest_content', 'UPDATE')
      or has_table_privilege('anon', 'public.hotel_guest_content', 'DELETE')
    ),
    'Anonymous users cannot directly write content rows.';

  return query
  select '17_anon_no_feedback_read',
    not has_table_privilege('anon', 'public.guest_feedback', 'SELECT'),
    'Anonymous users cannot directly read private feedback.';

  return query
  select '18_anon_no_feedback_write',
    not (
      has_table_privilege('anon', 'public.guest_feedback', 'INSERT')
      or has_table_privilege('anon', 'public.guest_feedback', 'UPDATE')
      or has_table_privilege('anon', 'public.guest_feedback', 'DELETE')
    ),
    'Anonymous users cannot directly write feedback.';

  return query
  select '19_anon_no_reward_read',
    not has_table_privilege('anon', 'public.guest_review_rewards', 'SELECT'),
    'Anonymous users cannot directly read reward audit rows.';

  return query
  select '20_anon_no_reward_write',
    not (
      has_table_privilege('anon', 'public.guest_review_rewards', 'INSERT')
      or has_table_privilege('anon', 'public.guest_review_rewards', 'UPDATE')
      or has_table_privilege('anon', 'public.guest_review_rewards', 'DELETE')
    ),
    'Anonymous users cannot directly write reward audit rows.';

  return query
  select '21_get_hotel_content_function',
    to_regprocedure('public.get_hotel_guest_content(uuid,text)') is not null,
    'Hotel content read RPC exists.';

  return query
  select '22_upsert_hotel_content_function',
    to_regprocedure('public.upsert_hotel_guest_content(uuid,text,jsonb)') is not null,
    'Hotel content write RPC exists.';

  return query
  select '23_submit_feedback_function',
    to_regprocedure('public.submit_guest_feedback(text,text,integer,text,boolean)') is not null,
    'Signed private feedback RPC exists.';

  return query
  select '24_record_reward_action_function',
    to_regprocedure('public.record_guest_review_reward_action(text,text,text)') is not null,
    'Signed review/reward audit RPC exists.';

  return query
  select '25_resolve_guest_portal_retained',
    to_regprocedure('public.resolve_guest_portal(text,text)') is not null,
    'Existing signed guest portal resolver remains installed.';

  return query
  select '26_get_guest_links_retained',
    to_regprocedure('public.get_guest_access_links(uuid)') is not null,
    'Existing hotel QR/link inventory remains installed.';

  return query
  select '27_rotate_token_retained',
    to_regprocedure('public.rotate_guest_access_token(uuid,uuid,text)') is not null,
    'Existing token rotation remains installed.';

  return query
  select '28_revoke_token_retained',
    to_regprocedure('public.revoke_guest_access_token(uuid,uuid,text)') is not null,
    'Existing token revocation remains installed.';

  return query
  select '29_anon_can_resolve_portal',
    has_function_privilege(
      'anon',
      'public.resolve_guest_portal(text,text)',
      'EXECUTE'
    ),
    'Anonymous guest browser can execute only the signed portal resolver.';

  return query
  select '30_anon_can_submit_feedback',
    has_function_privilege(
      'anon',
      'public.submit_guest_feedback(text,text,integer,text,boolean)',
      'EXECUTE'
    ),
    'Anonymous guest browser can submit token-bound feedback.';

  return query
  select '31_anon_can_record_reward_action',
    has_function_privilege(
      'anon',
      'public.record_guest_review_reward_action(text,text,text)',
      'EXECUTE'
    ),
    'Anonymous guest browser can record token-bound review/reward actions.';

  return query
  select '32_anon_cannot_get_hotel_content_admin',
    not has_function_privilege(
      'anon',
      'public.get_hotel_guest_content(uuid,text)',
      'EXECUTE'
    ),
    'Anonymous users cannot execute the hotel content editor read RPC.';

  return query
  select '33_anon_cannot_upsert_hotel_content',
    not has_function_privilege(
      'anon',
      'public.upsert_hotel_guest_content(uuid,text,jsonb)',
      'EXECUTE'
    ),
    'Anonymous users cannot execute the hotel content editor write RPC.';

  return query
  select '34_authenticated_can_get_hotel_content',
    has_function_privilege(
      'authenticated',
      'public.get_hotel_guest_content(uuid,text)',
      'EXECUTE'
    ),
    'Authenticated hotel users can execute the protected content read RPC.';

  return query
  select '35_authenticated_can_upsert_hotel_content',
    has_function_privilege(
      'authenticated',
      'public.upsert_hotel_guest_content(uuid,text,jsonb)',
      'EXECUTE'
    ),
    'Authenticated hotel users can execute the protected content write RPC.';

  select count(*)
  into v_count
  from public.hotels h
  where not exists (
    select 1
    from public.hotel_guest_content c
    where c.hotel_id = h.id
      and c.locale = 'en'
  );

  return query
  select '36_every_hotel_has_english_content',
    v_count = 0,
    format('%s hotel(s) are missing an English content row.', v_count);

  select count(*)
  into v_count
  from (
    select guest_session_id
    from public.guest_access_tokens
    where status = 'active'
    group by guest_session_id
    having count(*) > 1
  ) duplicate_tokens;

  return query
  select '37_one_active_token_per_stay_retained',
    v_count = 0,
    format('%s stay(s) have duplicate active tokens.', v_count);

  select count(*)
  into v_count
  from public.guest_access_tokens
  where status = 'active'
    and expires_at <= now();

  return query
  select '38_no_expired_active_tokens',
    v_count = 0,
    format('%s active token(s) are expired.', v_count);

  return query
  select '39_amenities_rls_retained',
    c.relrowsecurity,
    'Existing amenities RLS remains enabled.'
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'amenities';

  return query
  select '40_anon_no_direct_amenity_write',
    not (
      has_table_privilege('anon', 'public.amenities', 'INSERT')
      or has_table_privilege('anon', 'public.amenities', 'UPDATE')
      or has_table_privilege('anon', 'public.amenities', 'DELETE')
    ),
    'Existing amenities remain protected from anonymous direct writes.';
end;
$function$;

revoke all on function private.day14_migration_045_acceptance_rev1()
from public, anon, authenticated;

commit;

select test_name, passed, details
from private.day14_migration_045_acceptance_rev1()
order by test_name;
