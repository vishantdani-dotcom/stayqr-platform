-- ============================================================================
-- StayQR v1.0
-- Migration: 202607260013_day7_guest_access_and_rls_foundation
-- Revision: 3 (food_order_items tenant-column compatibility and full schema guards)
-- Date: 26 July 2026
--
-- PURPOSE
--   1. Remove anonymous direct-table access from the production API.
--   2. Replace room-number guest URLs with signed, rotating, revocable tokens.
--   3. Expose guest capabilities only through narrowly scoped RPCs.
--   4. Harden the previously guest-compatible tables with authenticated RLS.
--   5. Install private, hotel-folder-scoped Supabase Storage policies.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607260013_day7_guest_access_and_rls_foundation')
);

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

-- --------------------------------------------------------------------------
-- 0. Schema compatibility guard: tenant-scope food order line items
-- --------------------------------------------------------------------------
-- The source schema historically stored hotel_id on food_orders, but not on
-- food_order_items. Day 7 guest RPCs and RLS require every line item to carry
-- the same authoritative hotel scope as its parent order and menu item.

do $$
begin
  if to_regclass('public.hotels') is null
     or to_regclass('public.food_orders') is null
     or to_regclass('public.food_order_items') is null
     or to_regclass('public.menu_items') is null then
    raise exception 'Day 7 requires hotels, food_orders, food_order_items and menu_items.';
  end if;
end
$$;

alter table public.food_order_items
  add column if not exists hotel_id uuid;

-- Reject orphaned legacy rows before attempting a tenant backfill.
do $$
begin
  if exists (
    select 1
    from public.food_order_items foi
    left join public.food_orders fo on fo.id = foi.order_id
    where fo.id is null
  ) then
    raise exception 'Day 7 cannot tenant-scope food_order_items because an orphaned order_id exists.';
  end if;

  if exists (
    select 1
    from public.food_order_items foi
    left join public.menu_items mi on mi.id = foi.menu_item_id
    where mi.id is null
  ) then
    raise exception 'Day 7 cannot tenant-scope food_order_items because an orphaned menu_item_id exists.';
  end if;
end
$$;

update public.food_order_items foi
set hotel_id = fo.hotel_id
from public.food_orders fo
where fo.id = foi.order_id
  and foi.hotel_id is null;

-- Refuse silent cross-hotel data repair. Existing rows must agree with both
-- their parent food order and their menu item before constraints are installed.
do $$
begin
  if exists (
    select 1
    from public.food_order_items foi
    join public.food_orders fo on fo.id = foi.order_id
    where foi.hotel_id is null
       or foi.hotel_id <> fo.hotel_id
  ) then
    raise exception 'Day 7 found a food_order_items row whose hotel does not match its parent order.';
  end if;

  if exists (
    select 1
    from public.food_order_items foi
    join public.menu_items mi on mi.id = foi.menu_item_id
    where foi.hotel_id <> mi.hotel_id
  ) then
    raise exception 'Day 7 found a food_order_items row whose hotel does not match its menu item.';
  end if;
end
$$;

alter table public.food_order_items
  alter column hotel_id set not null;

create index if not exists idx_food_order_items_hotel_order
on public.food_order_items (hotel_id, order_id);

create index if not exists idx_food_order_items_hotel_menu_item
on public.food_order_items (hotel_id, menu_item_id);

create or replace function private.enforce_food_order_item_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  order_hotel_id uuid;
  menu_hotel_id uuid;
begin
  select fo.hotel_id
  into order_hotel_id
  from public.food_orders fo
  where fo.id = new.order_id;

  if order_hotel_id is null then
    raise exception 'Food order line item references an unavailable order.';
  end if;

  select mi.hotel_id
  into menu_hotel_id
  from public.menu_items mi
  where mi.id = new.menu_item_id;

  if menu_hotel_id is null then
    raise exception 'Food order line item references an unavailable menu item.';
  end if;

  new.hotel_id := coalesce(new.hotel_id, order_hotel_id);

  if new.hotel_id <> order_hotel_id or new.hotel_id <> menu_hotel_id then
    raise exception 'Food order line item cannot cross hotel ownership.';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_food_order_item_tenant()
from public, anon, authenticated;

drop trigger if exists food_order_items_enforce_tenant
on public.food_order_items;

create trigger food_order_items_enforce_tenant
before insert or update of hotel_id, order_id, menu_item_id
on public.food_order_items
for each row execute function private.enforce_food_order_item_tenant();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'food_order_items_hotel_fkey'
      and conrelid = 'public.food_order_items'::regclass
  ) then
    alter table public.food_order_items
      add constraint food_order_items_hotel_fkey
      foreign key (hotel_id)
      references public.hotels(id)
      on delete cascade;
  end if;
end
$$;

-- --------------------------------------------------------------------------
-- 1. Private signing keys and public token metadata
-- --------------------------------------------------------------------------

create table if not exists private.guest_access_signing_keys (
  id uuid primary key default gen_random_uuid(),
  secret bytea not null,
  status text not null default 'active'
    check (status in ('active', 'retired')),
  created_at timestamptz not null default now(),
  retired_at timestamptz
);

create unique index if not exists uq_guest_access_one_active_signing_key
on private.guest_access_signing_keys ((status))
where status = 'active';

insert into private.guest_access_signing_keys (secret, status)
select extensions.gen_random_bytes(32), 'active'
where not exists (
  select 1
  from private.guest_access_signing_keys
  where status = 'active'
);

revoke all on private.guest_access_signing_keys from public, anon, authenticated;

create table if not exists public.guest_access_tokens (
  id uuid primary key default gen_random_uuid(),
  token_nonce uuid not null default gen_random_uuid(),
  signing_key_id uuid not null
    references private.guest_access_signing_keys(id) on delete restrict,
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  room_id uuid not null
    references public.rooms(id) on delete cascade,
  guest_session_id uuid not null
    references public.guest_sessions(id) on delete cascade,
  token_version integer not null default 1,
  status text not null default 'active'
    check (status in ('active', 'revoked', 'expired')),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz,
  use_count bigint not null default 0,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revocation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint guest_access_expiry_after_issue check (expires_at > issued_at)
);

create unique index if not exists uq_guest_access_token_nonce
on public.guest_access_tokens (token_nonce);

create unique index if not exists uq_guest_access_one_active_session_token
on public.guest_access_tokens (guest_session_id)
where status = 'active';

create index if not exists idx_guest_access_hotel_room_status
on public.guest_access_tokens (hotel_id, room_id, status);

create index if not exists idx_guest_access_expiry
on public.guest_access_tokens (expires_at)
where status = 'active';

alter table public.guest_access_tokens enable row level security;

drop policy if exists stayqr_guest_access_tokens_select
on public.guest_access_tokens;

drop policy if exists stayqr_guest_access_tokens_manage
on public.guest_access_tokens;

create policy stayqr_guest_access_tokens_select
on public.guest_access_tokens
for select
to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

create policy stayqr_guest_access_tokens_manage
on public.guest_access_tokens
for all
to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'))
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

revoke all on public.guest_access_tokens from public, anon;
grant select, insert, update, delete on public.guest_access_tokens to authenticated;

-- --------------------------------------------------------------------------
-- 2. Token signing, issuance and verification
-- --------------------------------------------------------------------------

create or replace function private.guest_access_payload(
  target_token public.guest_access_tokens
)
returns text
language sql
immutable
set search_path = ''
as $$
  select concat_ws(
    '|',
    target_token.token_nonce::text,
    target_token.hotel_id::text,
    target_token.room_id::text,
    target_token.guest_session_id::text,
    target_token.token_version::text,
    extract(epoch from target_token.issued_at)::bigint::text,
    extract(epoch from target_token.expires_at)::bigint::text
  );
$$;

create or replace function private.render_guest_access_token(
  target_token_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  token_row public.guest_access_tokens%rowtype;
  key_secret bytea;
  signature text;
begin
  select t.*
  into token_row
  from public.guest_access_tokens t
  where t.id = target_token_id;

  if not found then
    raise exception 'Guest access token could not be rendered.';
  end if;

  select k.secret
  into key_secret
  from private.guest_access_signing_keys k
  where k.id = token_row.signing_key_id;

  if not found then
    raise exception 'Guest access signing key is unavailable.';
  end if;

  signature := encode(
    extensions.hmac(
      convert_to(private.guest_access_payload(token_row), 'UTF8'),
      key_secret,
      'sha256'
    ),
    'hex'
  );

  return token_row.token_nonce::text || '.' || signature;
end;
$$;

create or replace function private.issue_guest_access_token(
  target_guest_session_id uuid,
  force_rotation boolean default false,
  rotation_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_row public.guest_sessions%rowtype;
  active_key_id uuid;
  existing_token_id uuid;
  stay_expiry timestamptz;
  new_token_id uuid;
begin
  select gs.*
  into session_row
  from public.guest_sessions gs
  join public.hotels h on h.id = gs.hotel_id
  join public.rooms r
    on r.id = gs.room_id
   and r.hotel_id = gs.hotel_id
  where gs.id = target_guest_session_id
    and gs.status = 'active'
    and h.status = 'active'
  for update of gs;

  if not found then
    raise exception 'Guest access requires an active hotel stay.';
  end if;

  stay_expiry := coalesce(session_row.extended_until, session_row.checkout_time);

  if stay_expiry is null or stay_expiry <= now() then
    raise exception 'Guest access requires a future stay expiry.';
  end if;

  select t.id
  into existing_token_id
  from public.guest_access_tokens t
  where t.guest_session_id = session_row.id
    and t.status = 'active'
    and t.expires_at > now()
  order by t.issued_at desc
  limit 1
  for update;

  if existing_token_id is not null and not force_rotation then
    return existing_token_id;
  end if;

  update public.guest_access_tokens
  set status = 'revoked',
      revoked_at = now(),
      revoked_by = auth.uid(),
      revocation_reason = coalesce(
        nullif(trim(rotation_reason), ''),
        'Superseded by a new signed guest access token'
      ),
      updated_at = now()
  where guest_session_id = session_row.id
    and status = 'active';

  select id
  into active_key_id
  from private.guest_access_signing_keys
  where status = 'active'
  order by created_at desc
  limit 1;

  if active_key_id is null then
    raise exception 'Guest access signing key is unavailable.';
  end if;

  insert into public.guest_access_tokens (
    signing_key_id,
    hotel_id,
    room_id,
    guest_session_id,
    expires_at
  )
  values (
    active_key_id,
    session_row.hotel_id,
    session_row.room_id,
    session_row.id,
    stay_expiry
  )
  returning id into new_token_id;

  return new_token_id;
end;
$$;

create or replace function private.resolve_guest_access_token(
  p_hotel_slug text,
  p_access_token text,
  mark_used boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_parts text[];
  supplied_nonce uuid;
  supplied_signature text;
  token_row public.guest_access_tokens%rowtype;
  key_secret bytea;
  expected_signature text;
begin
  token_parts := string_to_array(coalesce(trim(p_access_token), ''), '.');

  if array_length(token_parts, 1) <> 2 then
    return null;
  end if;

  begin
    supplied_nonce := token_parts[1]::uuid;
  exception when others then
    return null;
  end;

  supplied_signature := lower(token_parts[2]);

  if supplied_signature !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  select t.*
  into token_row
  from public.guest_access_tokens t
  join private.guest_access_signing_keys k
    on k.id = t.signing_key_id
  join public.hotels h
    on h.id = t.hotel_id
  join public.rooms r
    on r.id = t.room_id
   and r.hotel_id = t.hotel_id
  join public.guest_sessions gs
    on gs.id = t.guest_session_id
   and gs.hotel_id = t.hotel_id
   and gs.room_id = t.room_id
  where t.token_nonce = supplied_nonce
    and t.status = 'active'
    and t.expires_at > now()
    and lower(h.slug) = lower(trim(p_hotel_slug))
    and h.status = 'active'
    and gs.status = 'active'
    and coalesce(gs.extended_until, gs.checkout_time) > now();

  if not found then
    return null;
  end if;

  select k.secret
  into key_secret
  from private.guest_access_signing_keys k
  where k.id = token_row.signing_key_id;

  if not found then
    return null;
  end if;

  expected_signature := encode(
    extensions.hmac(
      convert_to(private.guest_access_payload(token_row), 'UTF8'),
      key_secret,
      'sha256'
    ),
    'hex'
  );

  if extensions.digest(convert_to(expected_signature, 'UTF8'), 'sha256') <>
     extensions.digest(convert_to(supplied_signature, 'UTF8'), 'sha256') then
    return null;
  end if;

  if mark_used then
    update public.guest_access_tokens
    set last_used_at = now(),
        use_count = use_count + 1,
        updated_at = now()
    where id = token_row.id;
  end if;

  return token_row.id;
end;
$$;

revoke all on function private.guest_access_payload(public.guest_access_tokens) from public, anon, authenticated;
revoke all on function private.render_guest_access_token(uuid) from public, anon, authenticated;
revoke all on function private.issue_guest_access_token(uuid,boolean,text) from public, anon, authenticated;
revoke all on function private.resolve_guest_access_token(text,text,boolean) from public, anon, authenticated;

-- --------------------------------------------------------------------------
-- 3. Token lifecycle follows the authoritative guest session
-- --------------------------------------------------------------------------

create or replace function private.sync_guest_access_from_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_expiry timestamptz;
begin
  if tg_op = 'DELETE' then
    update public.guest_access_tokens
    set status = 'revoked',
        revoked_at = now(),
        revocation_reason = 'Guest session deleted',
        updated_at = now()
    where guest_session_id = old.id
      and status = 'active';
    return old;
  end if;

  session_expiry := coalesce(new.extended_until, new.checkout_time);

  if new.status = 'active' and session_expiry > now() then
    if tg_op = 'INSERT' then
      perform private.issue_guest_access_token(new.id, false, null);
    elsif old.status is distinct from new.status
       or old.hotel_id is distinct from new.hotel_id
       or old.room_id is distinct from new.room_id
       or old.guest_id is distinct from new.guest_id
       or old.checkout_time is distinct from new.checkout_time
       or old.extended_until is distinct from new.extended_until then
      perform private.issue_guest_access_token(
        new.id,
        true,
        'Guest stay details changed'
      );
    else
      perform private.issue_guest_access_token(new.id, false, null);
    end if;
  else
    update public.guest_access_tokens
    set status = case when session_expiry <= now() then 'expired' else 'revoked' end,
        revoked_at = now(),
        revocation_reason = case
          when session_expiry <= now() then 'Guest stay expired'
          else 'Guest stay is no longer active'
        end,
        updated_at = now()
    where guest_session_id = new.id
      and status = 'active';
  end if;

  return new;
end;
$$;

revoke all on function private.sync_guest_access_from_session() from public, anon, authenticated;

drop trigger if exists guest_sessions_sync_guest_access
on public.guest_sessions;

create trigger guest_sessions_sync_guest_access
after insert or update or delete on public.guest_sessions
for each row execute function private.sync_guest_access_from_session();

-- Seed one token for every currently active, non-expired stay.
do $$
declare
  session_id uuid;
begin
  for session_id in
    select gs.id
    from public.guest_sessions gs
    where gs.status = 'active'
      and coalesce(gs.extended_until, gs.checkout_time) > now()
  loop
    perform private.issue_guest_access_token(session_id, false, null);
  end loop;
end
$$;

-- --------------------------------------------------------------------------
-- 4. Authenticated staff RPCs for secure link administration
-- --------------------------------------------------------------------------

create or replace function public.get_guest_access_links(
  target_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb := '[]'::jsonb;
  room_row record;
  token_id uuid;
  rendered_token text;
begin
  if not private.user_has_permission(target_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to manage guest access.';
  end if;

  for room_row in
    select
      r.id as room_id,
      r.room_number,
      r.room_type,
      h.slug as hotel_slug,
      gs.id as guest_session_id,
      gs.checkout_time,
      gs.extended_until,
      g.full_name as guest_name
    from public.rooms r
    join public.hotels h on h.id = r.hotel_id
    left join lateral (
      select active_session.*
      from public.guest_sessions active_session
      where active_session.hotel_id = r.hotel_id
        and active_session.room_id = r.id
        and active_session.status = 'active'
        and coalesce(active_session.extended_until, active_session.checkout_time) > now()
      order by active_session.checkin_time desc
      limit 1
    ) gs on true
    left join public.guests g
      on g.id = gs.guest_id
     and g.hotel_id = r.hotel_id
    where r.hotel_id = target_hotel_id
    order by r.room_number
  loop
    token_id := null;
    rendered_token := null;

    if room_row.guest_session_id is not null then
      token_id := private.issue_guest_access_token(
        room_row.guest_session_id,
        false,
        null
      );
      rendered_token := private.render_guest_access_token(token_id);
    end if;

    result := result || jsonb_build_array(
      jsonb_build_object(
        'room_id', room_row.room_id,
        'room_number', room_row.room_number,
        'room_type', room_row.room_type,
        'guest_session_id', room_row.guest_session_id,
        'guest_name', room_row.guest_name,
        'active', room_row.guest_session_id is not null,
        'expires_at', coalesce(room_row.extended_until, room_row.checkout_time),
        'guest_path', case
          when rendered_token is null then null
          else '/guest/' || room_row.hotel_slug || '/' || rendered_token
        end,
        'food_path', case
          when rendered_token is null then null
          else '/food/' || room_row.hotel_slug || '/' || rendered_token
        end
      )
    );
  end loop;

  return result;
end;
$$;

create or replace function public.rotate_guest_access_token(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  rotation_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  rendered_token text;
  hotel_slug text;
begin
  if not private.user_has_permission(target_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to rotate guest access.';
  end if;

  if not exists (
    select 1
    from public.guest_sessions gs
    where gs.id = target_guest_session_id
      and gs.hotel_id = target_hotel_id
      and gs.status = 'active'
  ) then
    raise exception 'The selected active stay does not belong to this hotel.';
  end if;

  token_id := private.issue_guest_access_token(
    target_guest_session_id,
    true,
    coalesce(nullif(trim(rotation_reason), ''), 'Manual guest access rotation')
  );

  rendered_token := private.render_guest_access_token(token_id);

  select slug into hotel_slug
  from public.hotels
  where id = target_hotel_id;

  return jsonb_build_object(
    'result', 'GUEST ACCESS ROTATED',
    'guest_path', '/guest/' || hotel_slug || '/' || rendered_token,
    'food_path', '/food/' || hotel_slug || '/' || rendered_token
  );
end;
$$;

create or replace function public.revoke_guest_access_token(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  revocation_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_count integer;
begin
  if not private.user_has_permission(target_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to revoke guest access.';
  end if;

  update public.guest_access_tokens
  set status = 'revoked',
      revoked_at = now(),
      revoked_by = auth.uid(),
      revocation_reason = coalesce(
        nullif(trim(revocation_reason), ''),
        'Manual guest access revocation'
      ),
      updated_at = now()
  where hotel_id = target_hotel_id
    and guest_session_id = target_guest_session_id
    and status = 'active';

  get diagnostics affected_count = row_count;

  return jsonb_build_object(
    'result', 'GUEST ACCESS REVOKED',
    'revoked_tokens', affected_count
  );
end;
$$;

revoke all on function public.get_guest_access_links(uuid) from public, anon;
revoke all on function public.rotate_guest_access_token(uuid,uuid,text) from public, anon;
revoke all on function public.revoke_guest_access_token(uuid,uuid,text) from public, anon;

grant execute on function public.get_guest_access_links(uuid) to authenticated;
grant execute on function public.rotate_guest_access_token(uuid,uuid,text) to authenticated;
grant execute on function public.revoke_guest_access_token(uuid,uuid,text) to authenticated;

-- --------------------------------------------------------------------------
-- 5. Token-authorized guest RPCs. No direct anonymous table reads/writes.
-- --------------------------------------------------------------------------

create or replace function public.resolve_guest_portal(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  response jsonb;
begin
  token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if token_id is null then
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
    'hotel_info', jsonb_build_object(
      'hotel_name', coalesce(hi.hotel_name, h.hotel_name),
      'address', coalesce(hi.address, h.location),
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
    ),
    'session', jsonb_build_object(
      'checkin_time', gs.checkin_time,
      'checkout_time', gs.checkout_time,
      'extended_until', gs.extended_until,
      'guests', jsonb_build_object(
        'full_name', g.full_name
      ),
      'rooms', jsonb_build_object(
        'room_number', r.room_number,
        'room_type', r.room_type
      )
    )
  )
  into response
  from public.guest_access_tokens t
  join public.hotels h on h.id = t.hotel_id
  join public.guest_sessions gs on gs.id = t.guest_session_id
  join public.guests g
    on g.id = gs.guest_id
   and g.hotel_id = t.hotel_id
  join public.rooms r
    on r.id = t.room_id
   and r.hotel_id = t.hotel_id
  left join public.hotel_info hi on hi.hotel_id = t.hotel_id
  where t.id = token_id;

  return response;
end;
$$;

create or replace function public.get_guest_service_requests(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  result jsonb;
begin
  token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', sr.id,
        'request_type', sr.request_type,
        'request_details', sr.request_details,
        'status', sr.status,
        'priority', sr.priority,
        'estimated_minutes', sr.estimated_minutes,
        'estimated_arrival_time', sr.estimated_arrival_time,
        'created_at', sr.created_at,
        'accepted_at', sr.accepted_at,
        'started_at', sr.started_at,
        'completed_at', sr.completed_at
      )
      order by sr.created_at desc
    ),
    '[]'::jsonb
  )
  into result
  from public.guest_access_tokens t
  join public.guest_sessions gs on gs.id = t.guest_session_id
  left join public.service_requests sr
    on sr.hotel_id = t.hotel_id
   and sr.room_id = t.room_id
   and sr.guest_id = gs.guest_id
  where t.id = token_id
    and sr.id is not null;

  return coalesce(result, '[]'::jsonb);
end;
$$;

create or replace function public.create_guest_service_request(
  p_hotel_slug text,
  p_access_token text,
  p_request_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  token_row public.guest_access_tokens%rowtype;
  guest_id uuid;
  room_number text;
  normalized_type text;
  request_id uuid;
begin
  token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  normalized_type := trim(coalesce(p_request_type, ''));

  if normalized_type <> all(array[
    'Housekeeping', 'Water', 'Towel', 'Fresh Towels',
    'Checkout Request', 'Toiletries', 'Extra Blanket',
    'Maintenance', 'Laundry'
  ]) then
    raise exception 'This service request type is not allowed.';
  end if;

  select t.*
  into token_row
  from public.guest_access_tokens t
  where t.id = token_id;

  if not found then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select gs.guest_id, r.room_number
  into guest_id, room_number
  from public.guest_sessions gs
  join public.rooms r
    on r.id = token_row.room_id
   and r.hotel_id = token_row.hotel_id
  where gs.id = token_row.guest_session_id
    and gs.hotel_id = token_row.hotel_id
    and gs.room_id = token_row.room_id;

  if not found then
    raise exception 'The guest stay linked to this access token is unavailable.';
  end if;

  if exists (
    select 1
    from public.service_requests sr
    where sr.hotel_id = token_row.hotel_id
      and sr.room_id = token_row.room_id
      and sr.guest_id = guest_id
      and sr.request_type = normalized_type
      and sr.status not in ('completed', 'cancelled')
  ) then
    raise exception 'This service request is already active.';
  end if;

  if (
    select count(*)
    from public.service_requests sr
    where sr.hotel_id = token_row.hotel_id
      and sr.room_id = token_row.room_id
      and sr.guest_id = guest_id
      and sr.created_at > now() - interval '1 minute'
  ) >= 5 then
    raise exception 'Too many service requests were submitted. Please wait and try again.';
  end if;

  insert into public.service_requests (
    hotel_id,
    room_id,
    guest_id,
    request_type,
    request_details,
    status,
    priority
  )
  values (
    token_row.hotel_id,
    token_row.room_id,
    guest_id,
    normalized_type,
    normalized_type || ' requested from Room ' || room_number,
    'pending',
    case when normalized_type = 'Checkout Request' then 'high' else 'normal' end
  )
  returning id into request_id;

  insert into public.notifications (
    hotel_id,
    room_id,
    guest_id,
    type,
    title,
    message,
    is_read
  )
  values (
    token_row.hotel_id,
    token_row.room_id,
    guest_id,
    'service_request',
    normalized_type || ' Request',
    'Room ' || room_number || ' requested ' || normalized_type,
    false
  );

  return jsonb_build_object(
    'result', 'SERVICE REQUEST CREATED',
    'request_id', request_id
  );
end;
$$;

create or replace function public.get_guest_food_menu(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  result jsonb;
begin
  token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', mi.id,
        'item_name', mi.item_name,
        'description', mi.description,
        'price', mi.price,
        'image_url', mi.image_url,
        'category', coalesce(mc.name, mi.category)
      )
      order by coalesce(mc.name, mi.category), mi.item_name
    ),
    '[]'::jsonb
  )
  into result
  from public.guest_access_tokens t
  join public.menu_items mi
    on mi.hotel_id = t.hotel_id
   and mi.is_available = true
  left join public.menu_categories mc
    on mc.id = mi.category_id
   and mc.hotel_id = t.hotel_id
  where t.id = token_id;

  return result;
end;
$$;

create or replace function public.get_guest_food_orders(
  p_hotel_slug text,
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  result jsonb;
begin
  token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select coalesce(
    jsonb_agg(order_json order by order_created_at desc),
    '[]'::jsonb
  )
  into result
  from (
    select
      fo.created_at as order_created_at,
      jsonb_build_object(
        'id', fo.id,
        'total_amount', fo.total_amount,
        'payment_status', fo.payment_status,
        'order_status', fo.order_status,
        'created_at', fo.created_at,
        'estimated_minutes', fo.estimated_minutes,
        'estimated_delivery_time', fo.estimated_delivery_time,
        'delivered_at', fo.delivered_at,
        'food_order_items', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'quantity', foi.quantity,
              'price', foi.price,
              'menu_items', jsonb_build_object(
                'item_name', mi.item_name
              )
            )
            order by mi.item_name
          )
          from public.food_order_items foi
          join public.menu_items mi
            on mi.id = foi.menu_item_id
           and mi.hotel_id = fo.hotel_id
          where foi.order_id = fo.id
            and foi.hotel_id = fo.hotel_id
        ), '[]'::jsonb)
      ) as order_json
    from public.guest_access_tokens t
    join public.guest_sessions gs on gs.id = t.guest_session_id
    join public.food_orders fo
      on fo.hotel_id = t.hotel_id
     and fo.room_id = t.room_id
     and fo.guest_id = gs.guest_id
    where t.id = token_id
  ) orders;

  return result;
end;
$$;

create or replace function public.place_guest_food_order(
  p_hotel_slug text,
  p_access_token text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  token_row public.guest_access_tokens%rowtype;
  guest_id uuid;
  room_number text;
  requested_count integer;
  matched_count integer;
  total_quantity integer;
  order_total numeric(12,2);
  order_id uuid;
begin
  token_id := private.resolve_guest_access_token(
    p_hotel_slug,
    p_access_token,
    true
  );

  if token_id is null then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 20 then
    raise exception 'The food order must contain between 1 and 20 menu items.';
  end if;

  select t.*
  into token_row
  from public.guest_access_tokens t
  where t.id = token_id;

  if not found then
    raise exception 'This guest access link is invalid or expired.';
  end if;

  select gs.guest_id, r.room_number
  into guest_id, room_number
  from public.guest_sessions gs
  join public.rooms r
    on r.id = token_row.room_id
   and r.hotel_id = token_row.hotel_id
  where gs.id = token_row.guest_session_id
    and gs.hotel_id = token_row.hotel_id
    and gs.room_id = token_row.room_id;

  if not found then
    raise exception 'The guest stay linked to this access token is unavailable.';
  end if;

  with requested as (
    select
      item.menu_item_id,
      sum(item.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as item(
      menu_item_id uuid,
      quantity integer
    )
    group by item.menu_item_id
  ), validated as (
    select r.menu_item_id, r.quantity, mi.price
    from requested r
    join public.menu_items mi
      on mi.id = r.menu_item_id
     and mi.hotel_id = token_row.hotel_id
     and mi.is_available = true
    where r.quantity between 1 and 20
  )
  select
    (select count(*) from requested),
    count(*),
    coalesce(sum(quantity), 0),
    coalesce(sum(price * quantity), 0)
  into requested_count, matched_count, total_quantity, order_total
  from validated;

  if requested_count <> matched_count then
    raise exception 'One or more menu items are invalid, unavailable or have an invalid quantity.';
  end if;

  if total_quantity > 50 then
    raise exception 'The food order quantity is too large.';
  end if;

  if (
    select count(*)
    from public.food_orders fo
    where fo.hotel_id = token_row.hotel_id
      and fo.room_id = token_row.room_id
      and fo.guest_id = guest_id
      and fo.created_at > now() - interval '1 minute'
  ) >= 3 then
    raise exception 'Too many food orders were submitted. Please wait and try again.';
  end if;

  insert into public.food_orders (
    hotel_id,
    room_id,
    guest_id,
    total_amount,
    payment_status,
    order_status
  )
  values (
    token_row.hotel_id,
    token_row.room_id,
    guest_id,
    order_total,
    'pending',
    'pending'
  )
  returning id into order_id;

  insert into public.food_order_items (
    hotel_id,
    order_id,
    menu_item_id,
    quantity,
    price
  )
  select
    token_row.hotel_id,
    order_id,
    requested.menu_item_id,
    requested.quantity,
    mi.price
  from (
    select
      item.menu_item_id,
      sum(item.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as item(
      menu_item_id uuid,
      quantity integer
    )
    group by item.menu_item_id
  ) requested
  join public.menu_items mi
    on mi.id = requested.menu_item_id
   and mi.hotel_id = token_row.hotel_id
   and mi.is_available = true;

  insert into public.notifications (
    hotel_id,
    room_id,
    guest_id,
    type,
    title,
    message,
    is_read
  )
  values (
    token_row.hotel_id,
    token_row.room_id,
    guest_id,
    'food_order',
    'New Food Order',
    'Room ' || room_number || ' placed a food order for ' || order_total::text,
    false
  );

  return jsonb_build_object(
    'result', 'FOOD ORDER CREATED',
    'order_id', order_id,
    'total_amount', order_total
  );
end;
$$;

-- Remove implicit PUBLIC function execution before granting the six guest RPCs.
revoke execute on function public.resolve_guest_portal(text,text) from public;
revoke execute on function public.get_guest_service_requests(text,text) from public;
revoke execute on function public.create_guest_service_request(text,text,text) from public;
revoke execute on function public.get_guest_food_menu(text,text) from public;
revoke execute on function public.get_guest_food_orders(text,text) from public;
revoke execute on function public.place_guest_food_order(text,text,jsonb) from public;

grant execute on function public.resolve_guest_portal(text,text) to anon, authenticated;
grant execute on function public.get_guest_service_requests(text,text) to anon, authenticated;
grant execute on function public.create_guest_service_request(text,text,text) to anon, authenticated;
grant execute on function public.get_guest_food_menu(text,text) to anon, authenticated;
grant execute on function public.get_guest_food_orders(text,text) to anon, authenticated;
grant execute on function public.place_guest_food_order(text,text,jsonb) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 6. Remove every legacy anonymous table policy and direct table grant
-- --------------------------------------------------------------------------

do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and (
        'anon' = any(roles)
        or 'public' = any(roles)
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end
$$;

revoke all on all tables in schema public from public, anon;
revoke all on all sequences in schema public from public, anon;

-- Authenticated users retain table privileges, with access constrained by RLS.
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Re-grant only the six approved anonymous guest RPCs after broad revocation.
revoke execute on all functions in schema public from public, anon;
grant execute on function public.resolve_guest_portal(text,text) to anon, authenticated;
grant execute on function public.get_guest_service_requests(text,text) to anon, authenticated;
grant execute on function public.create_guest_service_request(text,text,text) to anon, authenticated;
grant execute on function public.get_guest_food_menu(text,text) to anon, authenticated;
grant execute on function public.get_guest_food_orders(text,text) to anon, authenticated;
grant execute on function public.place_guest_food_order(text,text,jsonb) to anon, authenticated;

-- Existing internal RPCs use explicit authenticated grants from prior migrations.

-- --------------------------------------------------------------------------
-- 7. Authenticated RLS for the former anonymous compatibility tables
-- --------------------------------------------------------------------------

do $$
declare
  target_table text;
  policy_row record;
begin
  foreach target_table in array array[
    'rooms', 'guests', 'guest_sessions', 'hotel_info', 'feedback',
    'menu_categories', 'menu_items', 'food_orders', 'food_order_items',
    'service_requests', 'notifications'
  ]
  loop
    execute format('alter table public.%I enable row level security', target_table);

    for policy_row in
      select policyname
      from pg_policies
      where schemaname = 'public'
        and tablename = target_table
    loop
      execute format(
        'drop policy if exists %I on public.%I',
        policy_row.policyname,
        target_table
      );
    end loop;
  end loop;
end
$$;

-- Rooms
create policy stayqr_day7_rooms_select
on public.rooms for select to authenticated
using (private.user_has_permission(hotel_id, 'rooms.view'));
create policy stayqr_day7_rooms_insert
on public.rooms for insert to authenticated
with check (private.user_has_permission(hotel_id, 'rooms.manage'));
create policy stayqr_day7_rooms_update
on public.rooms for update to authenticated
using (private.user_has_permission(hotel_id, 'rooms.manage'))
with check (private.user_has_permission(hotel_id, 'rooms.manage'));
create policy stayqr_day7_rooms_delete
on public.rooms for delete to authenticated
using (private.user_has_permission(hotel_id, 'rooms.manage'));

-- Guests
create policy stayqr_day7_guests_select
on public.guests for select to authenticated
using (private.user_has_permission(hotel_id, 'guests.view'));
create policy stayqr_day7_guests_insert
on public.guests for insert to authenticated
with check (private.user_has_permission(hotel_id, 'guests.manage'));
create policy stayqr_day7_guests_update
on public.guests for update to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'))
with check (private.user_has_permission(hotel_id, 'guests.manage'));
create policy stayqr_day7_guests_delete
on public.guests for delete to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'));

-- Guest sessions
create policy stayqr_day7_guest_sessions_select
on public.guest_sessions for select to authenticated
using (private.user_has_any_permission(
  hotel_id,
  array['guests.view', 'checkin.manage', 'checkout.manage']
));
create policy stayqr_day7_guest_sessions_insert
on public.guest_sessions for insert to authenticated
with check (private.user_has_any_permission(
  hotel_id,
  array['guests.manage', 'checkin.manage']
));
create policy stayqr_day7_guest_sessions_update
on public.guest_sessions for update to authenticated
using (private.user_has_any_permission(
  hotel_id,
  array['guests.manage', 'checkin.manage', 'checkout.manage']
))
with check (private.user_has_any_permission(
  hotel_id,
  array['guests.manage', 'checkin.manage', 'checkout.manage']
));
create policy stayqr_day7_guest_sessions_delete
on public.guest_sessions for delete to authenticated
using (private.user_has_permission(hotel_id, 'guests.manage'));

-- Hotel profile
create policy stayqr_day7_hotel_info_select
on public.hotel_info for select to authenticated
using (private.user_has_hotel_access(hotel_id));
create policy stayqr_day7_hotel_info_insert
on public.hotel_info for insert to authenticated
with check (private.user_has_permission(hotel_id, 'hotel.manage'));
create policy stayqr_day7_hotel_info_update
on public.hotel_info for update to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'))
with check (private.user_has_permission(hotel_id, 'hotel.manage'));
create policy stayqr_day7_hotel_info_delete
on public.hotel_info for delete to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

-- Feedback
create policy stayqr_day7_feedback_select
on public.feedback for select to authenticated
using (private.user_has_permission(hotel_id, 'services.view'));
create policy stayqr_day7_feedback_insert
on public.feedback for insert to authenticated
with check (private.user_has_permission(hotel_id, 'services.manage'));
create policy stayqr_day7_feedback_update
on public.feedback for update to authenticated
using (private.user_has_permission(hotel_id, 'services.manage'))
with check (private.user_has_permission(hotel_id, 'services.manage'));
create policy stayqr_day7_feedback_delete
on public.feedback for delete to authenticated
using (private.user_has_permission(hotel_id, 'services.manage'));

-- Menu configuration
create policy stayqr_day7_menu_categories_select
on public.menu_categories for select to authenticated
using (private.user_has_any_permission(hotel_id, array['foodorders.view', 'menu.manage']));
create policy stayqr_day7_menu_categories_manage
on public.menu_categories for all to authenticated
using (private.user_has_permission(hotel_id, 'menu.manage'))
with check (private.user_has_permission(hotel_id, 'menu.manage'));

create policy stayqr_day7_menu_items_select
on public.menu_items for select to authenticated
using (private.user_has_any_permission(hotel_id, array['foodorders.view', 'menu.manage']));
create policy stayqr_day7_menu_items_manage
on public.menu_items for all to authenticated
using (private.user_has_permission(hotel_id, 'menu.manage'))
with check (private.user_has_permission(hotel_id, 'menu.manage'));

-- Food orders
create policy stayqr_day7_food_orders_select
on public.food_orders for select to authenticated
using (private.user_has_permission(hotel_id, 'foodorders.view'));
create policy stayqr_day7_food_orders_manage
on public.food_orders for all to authenticated
using (private.user_has_permission(hotel_id, 'foodorders.manage'))
with check (private.user_has_permission(hotel_id, 'foodorders.manage'));

create policy stayqr_day7_food_order_items_select
on public.food_order_items for select to authenticated
using (private.user_has_permission(hotel_id, 'foodorders.view'));
create policy stayqr_day7_food_order_items_manage
on public.food_order_items for all to authenticated
using (private.user_has_permission(hotel_id, 'foodorders.manage'))
with check (private.user_has_permission(hotel_id, 'foodorders.manage'));

-- Service requests
create policy stayqr_day7_service_requests_select
on public.service_requests for select to authenticated
using (private.user_has_permission(hotel_id, 'services.view'));
create policy stayqr_day7_service_requests_manage
on public.service_requests for all to authenticated
using (private.user_has_permission(hotel_id, 'services.manage'))
with check (private.user_has_permission(hotel_id, 'services.manage'));

-- Notifications are internal; guests create them only through security-definer RPCs.
create policy stayqr_day7_notifications_select
on public.notifications for select to authenticated
using (private.user_has_hotel_access(hotel_id));
create policy stayqr_day7_notifications_insert
on public.notifications for insert to authenticated
with check (private.user_has_hotel_access(hotel_id));
create policy stayqr_day7_notifications_update
on public.notifications for update to authenticated
using (private.user_has_hotel_access(hotel_id))
with check (private.user_has_hotel_access(hotel_id));
create policy stayqr_day7_notifications_delete
on public.notifications for delete to authenticated
using (private.user_has_hotel_access(hotel_id));

-- Every public tenant table must have RLS enabled.
do $$
declare
  tenant_table record;
begin
  for tenant_table in
    select distinct c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'hotel_id'
  loop
    execute format(
      'alter table public.%I enable row level security',
      tenant_table.table_name
    );
  end loop;
end
$$;

-- --------------------------------------------------------------------------
-- 8. Private Supabase Storage buckets and hotel-folder policies
-- --------------------------------------------------------------------------

create or replace function private.storage_object_hotel_id(object_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  first_folder text;
begin
  first_folder := split_part(coalesce(object_name, ''), '/', 1);

  begin
    return first_folder::uuid;
  exception when others then
    return null;
  end;
end;
$$;

revoke all on function private.storage_object_hotel_id(text) from public, anon, authenticated;

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
  )
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

do $$
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
$$;

drop policy if exists stayqr_hotel_assets_select on storage.objects;
drop policy if exists stayqr_hotel_assets_insert on storage.objects;
drop policy if exists stayqr_hotel_assets_update on storage.objects;
drop policy if exists stayqr_hotel_assets_delete on storage.objects;
drop policy if exists stayqr_guest_documents_select on storage.objects;
drop policy if exists stayqr_guest_documents_insert on storage.objects;
drop policy if exists stayqr_guest_documents_update on storage.objects;
drop policy if exists stayqr_guest_documents_delete on storage.objects;

create policy stayqr_hotel_assets_select
on storage.objects for select to authenticated
using (
  bucket_id = 'hotel-assets'
  and private.user_has_hotel_access(private.storage_object_hotel_id(name))
);
create policy stayqr_hotel_assets_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'hotel-assets'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);
create policy stayqr_hotel_assets_update
on storage.objects for update to authenticated
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
on storage.objects for delete to authenticated
using (
  bucket_id = 'hotel-assets'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'hotel.manage'
  )
);

create policy stayqr_guest_documents_select
on storage.objects for select to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.view'
  )
);
create policy stayqr_guest_documents_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
);
create policy stayqr_guest_documents_update
on storage.objects for update to authenticated
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
on storage.objects for delete to authenticated
using (
  bucket_id = 'guest-documents'
  and private.user_has_permission(
    private.storage_object_hotel_id(name),
    'guests.manage'
  )
);

-- --------------------------------------------------------------------------
-- 9. Final migration assertions
-- --------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and ('anon' = any(roles) or 'public' = any(roles))
  ) then
    raise exception 'Day 7 hardening failed: an anonymous table policy remains.';
  end if;

  if exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee = 'anon'
  ) then
    raise exception 'Day 7 hardening failed: anonymous direct-table grants remain.';
  end if;

  if exists (
    select 1
    from information_schema.columns c
    join pg_class pc on pc.relname = c.table_name
    join pg_namespace pn on pn.oid = pc.relnamespace
    where c.table_schema = 'public'
      and c.column_name = 'hotel_id'
      and pn.nspname = 'public'
      and pc.relkind in ('r', 'p')
      and not pc.relrowsecurity
  ) then
    raise exception 'Day 7 hardening failed: a tenant table does not have RLS enabled.';
  end if;

  if to_regprocedure('public.resolve_guest_portal(text,text)') is null
     or to_regprocedure('public.place_guest_food_order(text,text,jsonb)') is null
     or to_regprocedure('public.get_guest_access_links(uuid)') is null then
    raise exception 'Day 7 hardening failed: guest access RPCs are incomplete.';
  end if;

  if exists (
    select 1
    from public.guest_access_tokens t
    join public.guest_sessions gs on gs.id = t.guest_session_id
    where t.hotel_id <> gs.hotel_id
       or t.room_id <> gs.room_id
  ) then
    raise exception 'Day 7 hardening failed: a guest token crosses stay ownership.';
  end if;
end
$$;

commit;

-- Supabase may display one blank pg_advisory_xact_lock row. That is expected.
