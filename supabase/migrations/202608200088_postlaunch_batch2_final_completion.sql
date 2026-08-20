-- StayQR v1.1 Post-Launch Batch B — Final Completion
-- Items 5, 8, 11, 13, 14. Staging first. Production untouched.
-- Additive where possible; existing tenant/auth/token contracts remain authoritative.

-- ============================================================================
-- 1. Staff verified phone + hotel dashboard branding
-- ============================================================================

alter table public.staff
  add column if not exists phone_verified_at timestamptz;

alter table public.hotels
  add column if not exists cover_url text;

-- Backfill only where the staff phone already matches the Auth-confirmed phone.
update public.staff s
set phone_verified_at = u.phone_confirmed_at
from auth.users u
where s.auth_user_id = u.id
  and u.phone_confirmed_at is not null
  and nullif(regexp_replace(coalesce(s.phone, ''), '[^0-9]', '', 'g'), '') =
      nullif(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g'), '')
  and s.phone_verified_at is null;

create or replace function public.update_my_staff_profile(
  p_hotel_id uuid,
  p_full_name text,
  p_phone text,
  p_avatar_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_staff public.staff%rowtype;
  v_full_name text := nullif(btrim(p_full_name), '');
  v_phone text := nullif(btrim(p_phone), '');
  v_verified_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.';
  end if;

  select s.* into v_staff
  from public.staff s
  where s.hotel_id = p_hotel_id
    and s.auth_user_id = v_user_id
    and s.status = 'active'
  limit 1;

  if v_staff.id is null then
    raise exception 'An active staff profile was not found for this hotel.';
  end if;

  if v_full_name is null or char_length(v_full_name) > 120 then
    raise exception 'Full name must contain between 1 and 120 characters.';
  end if;

  if v_phone is not null and char_length(v_phone) > 24 then
    raise exception 'Phone number cannot exceed 24 characters.';
  end if;

  if p_avatar_path is not null and (
    private.storage_object_hotel_id(p_avatar_path) is distinct from p_hotel_id
    or split_part(p_avatar_path, '/', 2) <> v_user_id::text
  ) then
    raise exception 'Avatar path is outside the current staff scope.';
  end if;

  v_verified_at := case
    when nullif(regexp_replace(coalesce(v_staff.phone, ''), '[^0-9]', '', 'g'), '') =
         nullif(regexp_replace(coalesce(v_phone, ''), '[^0-9]', '', 'g'), '')
      then v_staff.phone_verified_at
    else null
  end;

  update public.staff
  set full_name = v_full_name,
      phone = v_phone,
      phone_verified_at = v_verified_at,
      avatar_path = p_avatar_path,
      updated_at = now()
  where id = v_staff.id;

  return jsonb_build_object(
    'id', v_staff.id,
    'hotel_id', p_hotel_id,
    'full_name', v_full_name,
    'phone', v_phone,
    'phone_verified_at', v_verified_at,
    'avatar_path', p_avatar_path
  );
end;
$$;

revoke all on function public.update_my_staff_profile(uuid,text,text,text) from public;
grant execute on function public.update_my_staff_profile(uuid,text,text,text) to authenticated;

create or replace function public.sync_my_verified_staff_phone(p_hotel_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_auth_phone text;
  v_confirmed_at timestamptz;
  v_staff_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.';
  end if;

  select u.phone, u.phone_confirmed_at
  into v_auth_phone, v_confirmed_at
  from auth.users u
  where u.id = v_user_id;

  if nullif(regexp_replace(coalesce(v_auth_phone, ''), '[^0-9]', '', 'g'), '') is null
     or v_confirmed_at is null then
    raise exception 'The authenticated phone number has not been verified.';
  end if;

  update public.staff s
  set phone = v_auth_phone,
      phone_verified_at = v_confirmed_at,
      updated_at = now()
  where s.hotel_id = p_hotel_id
    and s.auth_user_id = v_user_id
    and s.status = 'active'
  returning s.id into v_staff_id;

  if v_staff_id is null then
    raise exception 'An active staff profile was not found for this hotel.';
  end if;

  return jsonb_build_object(
    'staff_id', v_staff_id,
    'phone', v_auth_phone,
    'phone_verified_at', v_confirmed_at
  );
end;
$$;

revoke all on function public.sync_my_verified_staff_phone(uuid) from public;
grant execute on function public.sync_my_verified_staff_phone(uuid) to authenticated;

create or replace function public.update_hotel_branding(
  p_hotel_id uuid,
  p_logo_url text default null,
  p_cover_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_logo text := nullif(btrim(p_logo_url), '');
  v_cover text := nullif(btrim(p_cover_url), '');
  v_required_fragment text := '/storage/v1/object/public/guest-guide-media/' || p_hotel_id::text || '/';
begin
  if not private.user_has_permission(p_hotel_id, 'hotel.manage') then
    raise exception 'Hotel branding update denied.';
  end if;

  if v_logo is not null and position(v_required_fragment in v_logo) = 0 then
    raise exception 'Hotel logo must use the tenant-scoped StayQR media bucket.';
  end if;

  if v_cover is not null and position(v_required_fragment in v_cover) = 0 then
    raise exception 'Hotel cover must use the tenant-scoped StayQR media bucket.';
  end if;

  update public.hotels h
  set logo_url = v_logo,
      cover_url = v_cover,
      updated_at = now()
  where h.id = p_hotel_id;

  if not found then
    raise exception 'Hotel was not found.';
  end if;

  return jsonb_build_object(
    'hotel_id', p_hotel_id,
    'logo_url', v_logo,
    'cover_url', v_cover
  );
end;
$$;

revoke all on function public.update_hotel_branding(uuid,text,text) from public;
grant execute on function public.update_hotel_branding(uuid,text,text) to authenticated;

-- ============================================================================
-- 2. Unified guest/media library — images + controlled short videos
-- ============================================================================

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'guest-guide-media',
  'guest-guide-media',
  true,
  20971520,
  array['image/jpeg','image/png','image/webp','video/mp4','video/webm']
)
on conflict (id) do update
set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.guest_guide_media
  drop constraint if exists guest_guide_media_mime_type_check;

alter table public.guest_guide_media
  add constraint guest_guide_media_mime_type_check
  check (
    mime_type is null
    or mime_type = any(array[
      'image/jpeg'::text,
      'image/png'::text,
      'image/webp'::text,
      'video/mp4'::text,
      'video/webm'::text
    ])
  );

-- ============================================================================
-- 3. Permanent room QR + per-stay PIN challenge -> existing signed token
-- ============================================================================

create table if not exists public.room_qr_codes (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  public_code uuid not null default gen_random_uuid() unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_room_qr_codes_hotel_room
  on public.room_qr_codes(hotel_id, room_id);

create table if not exists public.room_qr_pin_challenges (
  id uuid primary key default gen_random_uuid(),
  room_qr_code_id uuid not null references public.room_qr_codes(public_code) on delete cascade,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  guest_session_id uuid not null references public.guest_sessions(id) on delete cascade,
  pin_hash text not null,
  status text not null default 'active',
  failed_attempts integer not null default 0,
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_attempt_at timestamptz,
  verified_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint room_qr_pin_status_check check (status = any(array['active','revoked','expired','locked'])),
  constraint room_qr_pin_failed_attempts_check check (failed_attempts between 0 and 5),
  constraint room_qr_pin_expiry_check check (expires_at > issued_at)
);

create unique index if not exists uq_room_qr_pin_active_room
  on public.room_qr_pin_challenges(room_id)
  where status = 'active';

create index if not exists idx_room_qr_pin_session
  on public.room_qr_pin_challenges(guest_session_id, status, expires_at desc);

alter table public.room_qr_codes enable row level security;
alter table public.room_qr_pin_challenges enable row level security;

revoke all on table public.room_qr_codes from public, anon;
revoke all on table public.room_qr_pin_challenges from public, anon;
grant select on table public.room_qr_codes to authenticated;
grant select on table public.room_qr_pin_challenges to authenticated;

-- Authenticated hotel staff can inspect only their hotel QR state. All writes use RPCs.
drop policy if exists stayqr_room_qr_codes_select on public.room_qr_codes;
create policy stayqr_room_qr_codes_select
on public.room_qr_codes for select to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

drop policy if exists stayqr_room_qr_pin_challenges_select on public.room_qr_pin_challenges;
create policy stayqr_room_qr_pin_challenges_select
on public.room_qr_pin_challenges for select to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

insert into public.room_qr_codes(room_id, hotel_id)
select r.id, r.hotel_id
from public.rooms r
where not exists (
  select 1 from public.room_qr_codes q where q.room_id = r.id
)
on conflict (room_id) do nothing;

create or replace function private.ensure_permanent_room_qr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.room_qr_codes(room_id, hotel_id)
  values (new.id, new.hotel_id)
  on conflict (room_id) do update
    set hotel_id = excluded.hotel_id,
        updated_at = now();
  return new;
end;
$$;

revoke all on function private.ensure_permanent_room_qr() from public;

drop trigger if exists stayqr_room_permanent_qr_seed on public.rooms;
create trigger stayqr_room_permanent_qr_seed
after insert or update of hotel_id on public.rooms
for each row execute function private.ensure_permanent_room_qr();

create or replace function private.sync_room_qr_pin_from_guest_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_id uuid;
  v_room_id uuid;
  v_status text;
  v_expiry timestamptz;
begin
  if tg_op = 'DELETE' then
    update public.room_qr_pin_challenges c
    set status = 'revoked',
        revoked_at = coalesce(c.revoked_at, now()),
        revocation_reason = coalesce(c.revocation_reason, 'Guest session deleted'),
        updated_at = now()
    where c.guest_session_id = old.id
      and c.status = 'active';
    return old;
  end if;

  v_session_id := new.id;
  v_room_id := new.room_id;
  v_status := new.status;
  v_expiry := coalesce(new.extended_until, new.checkout_time);

  -- A new/changed stay must never inherit a prior room PIN.
  update public.room_qr_pin_challenges c
  set status = case when c.expires_at <= now() then 'expired' else 'revoked' end,
      revoked_at = coalesce(c.revoked_at, now()),
      revocation_reason = coalesce(c.revocation_reason, 'Guest stay changed or ended'),
      updated_at = now()
  where c.status = 'active'
    and (
      -- Any prior stay occupying the room being activated must be invalidated.
      (c.room_id = v_room_id and c.guest_session_id <> v_session_id)
      -- A room move or stay-ending change invalidates the challenge that belongs
      -- to this guest session even when its previous room differs from NEW.room_id.
      or (
        c.guest_session_id = v_session_id
        and (
          c.room_id <> v_room_id
          or v_status <> 'active'
          or v_expiry <= now()
        )
      )
    );

  return new;
end;
$$;

revoke all on function private.sync_room_qr_pin_from_guest_session() from public;

drop trigger if exists stayqr_room_qr_pin_session_sync on public.guest_sessions;
create trigger stayqr_room_qr_pin_session_sync
after insert or update of status, room_id, hotel_id, guest_id, checkout_time, extended_until or delete
on public.guest_sessions
for each row execute function private.sync_room_qr_pin_from_guest_session();

create or replace function public.get_permanent_room_qr_links(p_hotel_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.user_has_permission(p_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to manage permanent room QR access.';
  end if;

  insert into public.room_qr_codes(room_id, hotel_id)
  select r.id, r.hotel_id
  from public.rooms r
  where r.hotel_id = p_hotel_id
    and not exists (select 1 from public.room_qr_codes q where q.room_id = r.id)
  on conflict (room_id) do nothing;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'room_id', r.id,
      'room_number', r.room_number,
      'room_type', r.room_type,
      'public_code', q.public_code,
      'permanent_path', '/room/' || q.public_code::text,
      'guest_session_id', gs.id,
      'guest_name', g.full_name,
      'stay_active', gs.id is not null,
      'stay_expires_at', coalesce(gs.extended_until, gs.checkout_time),
      'pin_status', coalesce(c.status, 'not_issued'),
      'pin_issued_at', c.issued_at,
      'pin_expires_at', c.expires_at,
      'pin_failed_attempts', coalesce(c.failed_attempts, 0)
    ) order by r.room_number
  ), '[]'::jsonb)
  into v_result
  from public.rooms r
  join public.room_qr_codes q on q.room_id = r.id and q.hotel_id = r.hotel_id and q.is_active
  left join lateral (
    select s.*
    from public.guest_sessions s
    where s.hotel_id = r.hotel_id
      and s.room_id = r.id
      and s.status = 'active'
      and coalesce(s.extended_until, s.checkout_time) > now()
    order by s.checkin_time desc
    limit 1
  ) gs on true
  left join public.guests g on g.id = gs.guest_id and g.hotel_id = r.hotel_id
  left join lateral (
    select challenge.*
    from public.room_qr_pin_challenges challenge
    where challenge.room_id = r.id
      and challenge.guest_session_id = gs.id
    order by challenge.issued_at desc
    limit 1
  ) c on true
  where r.hotel_id = p_hotel_id
    and r.is_active;

  return v_result;
end;
$$;

revoke all on function public.get_permanent_room_qr_links(uuid) from public;
grant execute on function public.get_permanent_room_qr_links(uuid) to authenticated;

create or replace function public.issue_permanent_room_qr_pin(
  p_hotel_id uuid,
  p_room_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_qr public.room_qr_codes%rowtype;
  v_session public.guest_sessions%rowtype;
  v_pin text;
  v_pin_number bigint;
  v_bytes bytea;
  v_expiry timestamptz;
begin
  if not private.user_has_permission(p_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to issue room QR access.';
  end if;

  select s.* into v_session
  from public.guest_sessions s
  where s.hotel_id = p_hotel_id
    and s.room_id = p_room_id
    and s.status = 'active'
    and coalesce(s.extended_until, s.checkout_time) > now()
  order by s.checkin_time desc
  limit 1;

  if v_session.id is null then
    raise exception 'A current checked-in stay is required before issuing a room PIN.';
  end if;

  insert into public.room_qr_codes(room_id, hotel_id)
  values (p_room_id, p_hotel_id)
  on conflict (room_id) do update
    set hotel_id = excluded.hotel_id,
        is_active = true,
        updated_at = now()
  returning * into v_qr;

  update public.room_qr_pin_challenges c
  set status = 'revoked',
      revoked_at = coalesce(c.revoked_at, now()),
      revocation_reason = coalesce(c.revocation_reason, 'PIN rotated by hotel staff'),
      updated_at = now()
  where c.room_id = p_room_id
    and c.status = 'active';

  -- Six-digit cryptographically-seeded PIN; only the bcrypt hash is persisted.
  v_bytes := extensions.gen_random_bytes(4);
  v_pin_number := (
    get_byte(v_bytes, 0)::bigint * 16777216 +
    get_byte(v_bytes, 1)::bigint * 65536 +
    get_byte(v_bytes, 2)::bigint * 256 +
    get_byte(v_bytes, 3)::bigint
  ) % 1000000;
  v_pin := lpad(v_pin_number::text, 6, '0');
  v_expiry := coalesce(v_session.extended_until, v_session.checkout_time);

  insert into public.room_qr_pin_challenges(
    room_qr_code_id,
    hotel_id,
    room_id,
    guest_session_id,
    pin_hash,
    status,
    failed_attempts,
    issued_by,
    expires_at
  ) values (
    v_qr.public_code,
    p_hotel_id,
    p_room_id,
    v_session.id,
    extensions.crypt(v_pin, extensions.gen_salt('bf', 8)),
    'active',
    0,
    v_user_id,
    v_expiry
  );

  return jsonb_build_object(
    'result', 'PERMANENT ROOM QR PIN ISSUED',
    'room_id', p_room_id,
    'guest_session_id', v_session.id,
    'public_code', v_qr.public_code,
    'permanent_path', '/room/' || v_qr.public_code::text,
    'pin', v_pin,
    'expires_at', v_expiry
  );
end;
$$;

revoke all on function public.issue_permanent_room_qr_pin(uuid,uuid) from public;
grant execute on function public.issue_permanent_room_qr_pin(uuid,uuid) to authenticated;

create or replace function public.get_room_qr_public_context(p_public_code uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select jsonb_build_object(
      'valid', true,
      'hotel_name', h.hotel_name,
      'room_number', r.room_number
    )
    from public.room_qr_codes q
    join public.rooms r on r.id = q.room_id and r.hotel_id = q.hotel_id
    join public.hotels h on h.id = q.hotel_id
    where q.public_code = p_public_code
      and q.is_active
      and r.is_active
      and h.status = 'active'
    limit 1
  ), jsonb_build_object('valid', false));
$$;

revoke all on function public.get_room_qr_public_context(uuid) from public;
grant execute on function public.get_room_qr_public_context(uuid) to anon, authenticated;

create or replace function public.resolve_permanent_room_qr(
  p_public_code uuid,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_challenge public.room_qr_pin_challenges%rowtype;
  v_hotel_slug text;
  v_token public.guest_access_tokens%rowtype;
  v_token_id uuid;
  v_rendered text;
  v_failures integer;
begin
  if coalesce(trim(p_pin), '') !~ '^[0-9]{6}$' then
    return jsonb_build_object('ok', false, 'error', 'Enter the 6-digit stay PIN.');
  end if;

  select c.* into v_challenge
  from public.room_qr_pin_challenges c
  join public.room_qr_codes q
    on q.public_code = c.room_qr_code_id
   and q.room_id = c.room_id
   and q.hotel_id = c.hotel_id
   and q.is_active
  join public.rooms r
    on r.id = c.room_id
   and r.hotel_id = c.hotel_id
   and r.is_active
  join public.hotels h
    on h.id = c.hotel_id
   and h.status = 'active'
  join public.guest_sessions s
    on s.id = c.guest_session_id
   and s.hotel_id = c.hotel_id
   and s.room_id = c.room_id
   and s.status = 'active'
   and coalesce(s.extended_until, s.checkout_time) > now()
  where q.public_code = p_public_code
    and c.status = 'active'
    and c.expires_at > now()
  order by c.issued_at desc
  limit 1
  for update of c;

  if v_challenge.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Room access is not active. Please contact reception.'
    );
  end if;

  if v_challenge.failed_attempts >= 5 then
    update public.room_qr_pin_challenges
    set status = 'locked', updated_at = now()
    where id = v_challenge.id;
    return jsonb_build_object('ok', false, 'error', 'Room access is locked. Please contact reception.');
  end if;

  if extensions.crypt(trim(p_pin), v_challenge.pin_hash) <> v_challenge.pin_hash then
    v_failures := least(5, v_challenge.failed_attempts + 1);
    update public.room_qr_pin_challenges
    set failed_attempts = v_failures,
        last_attempt_at = now(),
        status = case when v_failures >= 5 then 'locked' else status end,
        updated_at = now()
    where id = v_challenge.id;

    return jsonb_build_object(
      'ok', false,
      'error', case when v_failures >= 5
        then 'Room access is locked. Please contact reception.'
        else 'The stay PIN is incorrect.' end,
      'attempts_remaining', greatest(0, 5 - v_failures)
    );
  end if;

  select t.* into v_token
  from public.guest_access_tokens t
  where t.guest_session_id = v_challenge.guest_session_id
    and t.hotel_id = v_challenge.hotel_id
    and t.room_id = v_challenge.room_id
  order by t.issued_at desc, t.created_at desc
  limit 1;

  if v_token.id is null then
    v_token_id := private.issue_guest_access_token(v_challenge.guest_session_id, false, null);
    select t.* into v_token from public.guest_access_tokens t where t.id = v_token_id;
  end if;

  -- Manual revocation/expiry remains authoritative. Permanent QR cannot bypass it.
  if v_token.status <> 'active' or v_token.expires_at <= now() then
    return jsonb_build_object(
      'ok', false,
      'error', 'Guest access is unavailable. Please contact reception.'
    );
  end if;

  select h.slug into v_hotel_slug
  from public.hotels h
  where h.id = v_challenge.hotel_id;

  v_rendered := private.render_guest_access_token(v_token.id);

  update public.room_qr_pin_challenges
  set verified_at = now(),
      last_attempt_at = now(),
      updated_at = now()
  where id = v_challenge.id;

  return jsonb_build_object(
    'ok', true,
    'guest_path', '/guest/' || v_hotel_slug || '/' || v_rendered,
    'food_path', '/food/' || v_hotel_slug || '/' || v_rendered,
    'expires_at', least(v_challenge.expires_at, v_token.expires_at)
  );
end;
$$;

revoke all on function public.resolve_permanent_room_qr(uuid,text) from public;
grant execute on function public.resolve_permanent_room_qr(uuid,text) to anon, authenticated;

-- Keep the existing signed-token session trigger authoritative. This migration never weakens it.
