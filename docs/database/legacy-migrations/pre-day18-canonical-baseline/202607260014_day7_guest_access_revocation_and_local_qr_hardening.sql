-- StayQR v1.0
-- Day 7 Stage 2: persistent guest-access revocation and secure-link status
-- Run once in Supabase SQL Editor with role postgres after migration 013.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607260014:guest-access-revocation-hardening')
);

create schema if not exists private;
revoke all on schema private from public, anon;

-- --------------------------------------------------------------------------
-- 1. Preserve manual revocation across unrelated guest-session updates.
--
-- Migration 013 correctly revoked access, but its session trigger re-issued a
-- token on every otherwise-unrelated UPDATE. That could reactivate a manually
-- revoked QR after a normal stay record refresh. This replacement only issues
-- on INSERT or rotates when an access-defining stay field actually changes.
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
        'Guest stay access-defining details changed'
      );
    end if;
  else
    update public.guest_access_tokens
    set status = case when session_expiry <= now() then 'expired' else 'revoked' end,
        revoked_at = coalesce(revoked_at, now()),
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

revoke all on function private.sync_guest_access_from_session()
from public, anon, authenticated;

-- Trigger already exists after migration 013, but recreate it so this migration
-- remains deterministic if a partial development database is repaired.
drop trigger if exists guest_sessions_sync_guest_access
on public.guest_sessions;

create trigger guest_sessions_sync_guest_access
after insert or update or delete on public.guest_sessions
for each row execute function private.sync_guest_access_from_session();

-- --------------------------------------------------------------------------
-- 2. Return secure-link lifecycle status without silently reactivating a
--    manually revoked or expired token.
--
-- A token is auto-issued only when an active stay has no token history at all,
-- which safely recovers legacy active stays. Once a token has been revoked,
-- staff must explicitly rotate/activate a new token.
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
  latest_token_id uuid;
  latest_token_status text;
  latest_token_expires_at timestamptz;
  latest_token_issued_at timestamptz;
  latest_token_last_used_at timestamptz;
  latest_token_use_count bigint;
  latest_revocation_reason text;
  token_history_exists boolean;
  rendered_token text;
begin
  if not private.user_has_permission(target_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to manage guest access.';
  end if;

  -- Keep metadata honest even when no guest request arrives after expiry.
  update public.guest_access_tokens
  set status = 'expired',
      revoked_at = coalesce(revoked_at, now()),
      revocation_reason = coalesce(
        nullif(trim(revocation_reason), ''),
        'Signed guest access expired'
      ),
      updated_at = now()
  where hotel_id = target_hotel_id
    and status = 'active'
    and expires_at <= now();

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
    latest_token_id := null;
    latest_token_status := null;
    latest_token_expires_at := null;
    latest_token_issued_at := null;
    latest_token_last_used_at := null;
    latest_token_use_count := 0;
    latest_revocation_reason := null;
    token_history_exists := false;
    rendered_token := null;

    if room_row.guest_session_id is not null then
      select
        t.id,
        t.status,
        t.expires_at,
        t.issued_at,
        t.last_used_at,
        t.use_count,
        t.revocation_reason
      into
        latest_token_id,
        latest_token_status,
        latest_token_expires_at,
        latest_token_issued_at,
        latest_token_last_used_at,
        latest_token_use_count,
        latest_revocation_reason
      from public.guest_access_tokens t
      where t.guest_session_id = room_row.guest_session_id
        and t.hotel_id = target_hotel_id
        and t.room_id = room_row.room_id
      order by t.issued_at desc, t.created_at desc
      limit 1;

      token_history_exists := latest_token_id is not null;

      -- Recovery path for an active legacy stay that has never had a token.
      -- A revoked/expired token is intentionally NOT replaced here.
      if not token_history_exists then
        latest_token_id := private.issue_guest_access_token(
          room_row.guest_session_id,
          false,
          null
        );

        select
          t.status,
          t.expires_at,
          t.issued_at,
          t.last_used_at,
          t.use_count,
          t.revocation_reason
        into
          latest_token_status,
          latest_token_expires_at,
          latest_token_issued_at,
          latest_token_last_used_at,
          latest_token_use_count,
          latest_revocation_reason
        from public.guest_access_tokens t
        where t.id = latest_token_id;
      end if;

      if latest_token_status = 'active'
         and latest_token_expires_at > now() then
        rendered_token := private.render_guest_access_token(latest_token_id);
      end if;
    end if;

    result := result || jsonb_build_array(
      jsonb_build_object(
        'room_id', room_row.room_id,
        'room_number', room_row.room_number,
        'room_type', room_row.room_type,
        'guest_session_id', room_row.guest_session_id,
        'guest_name', room_row.guest_name,
        -- Legacy compatibility field. It now means an active stay exists.
        'active', room_row.guest_session_id is not null,
        'stay_active', room_row.guest_session_id is not null,
        'access_active', rendered_token is not null,
        'access_status', case
          when room_row.guest_session_id is null then 'no_active_stay'
          when rendered_token is not null then 'active'
          when latest_token_status = 'revoked' then 'revoked'
          when latest_token_status = 'expired' then 'expired'
          else 'not_issued'
        end,
        'expires_at', coalesce(room_row.extended_until, room_row.checkout_time),
        'token_expires_at', latest_token_expires_at,
        'token_issued_at', latest_token_issued_at,
        'token_last_used_at', latest_token_last_used_at,
        'token_use_count', coalesce(latest_token_use_count, 0),
        'revocation_reason', latest_revocation_reason,
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

revoke all on function public.get_guest_access_links(uuid) from public, anon;
grant execute on function public.get_guest_access_links(uuid) to authenticated;

comment on function public.get_guest_access_links(uuid) is
  'Returns hotel-scoped signed guest links. Manual revocation persists until explicit token rotation.';

commit;
