begin;

-- StayQR Final Product Freeze REV9
-- Auto-activated permanent room QR: one physical QR per room, zero PIN friction.
-- Existing signed/rotating/revocable guest-access tokens remain authoritative.

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
      'auto_access_enabled', true,
      'guest_session_id', gs.id,
      'guest_name', g.full_name,
      'occupant_count', case when gs.id is null then 0 else 1 + coalesce(gc.companion_count, 0) end,
      'stay_active', gs.id is not null,
      'stay_expires_at', coalesce(gs.extended_until, gs.checkout_time),
      'access_active', coalesce(t.status = 'active' and t.expires_at > now(), false),
      'access_status', case
        when gs.id is null then 'inactive'
        when t.id is null then 'not_issued'
        when t.status = 'active' and t.expires_at > now() then 'active'
        when t.expires_at <= now() then 'expired'
        else t.status
      end,
      'access_expires_at', t.expires_at,
      'revocation_reason', t.revocation_reason
    ) order by r.room_number
  ), '[]'::jsonb)
  into v_result
  from public.rooms r
  join public.room_qr_codes q
    on q.room_id = r.id
   and q.hotel_id = r.hotel_id
   and q.is_active
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
  left join public.guests g
    on g.id = gs.guest_id
   and g.hotel_id = r.hotel_id
  left join lateral (
    select count(*)::integer as companion_count
    from public.guest_companions companion
    where companion.hotel_id = r.hotel_id
      and companion.guest_session_id = gs.id
  ) gc on true
  left join lateral (
    select token.*
    from public.guest_access_tokens token
    where token.guest_session_id = gs.id
      and token.hotel_id = r.hotel_id
      and token.room_id = r.id
    order by token.issued_at desc, token.created_at desc
    limit 1
  ) t on true
  where r.hotel_id = p_hotel_id
    and r.is_active;

  return v_result;
end;
$$;

revoke all on function public.get_permanent_room_qr_links(uuid) from public;
grant execute on function public.get_permanent_room_qr_links(uuid) to authenticated;

-- New zero-PIN resolver. A permanent room QR is a high-entropy physical credential.
-- It resolves only while the room has a current active stay and the signed token is active.
create or replace function public.resolve_permanent_room_qr(p_public_code uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.guest_sessions%rowtype;
  v_hotel_slug text;
  v_token public.guest_access_tokens%rowtype;
  v_token_id uuid;
  v_rendered text;
  v_stay_expiry timestamptz;
begin
  select s, h.slug
  into v_session, v_hotel_slug
  from public.room_qr_codes q
  join public.rooms r
    on r.id = q.room_id
   and r.hotel_id = q.hotel_id
   and r.is_active
  join public.hotels h
    on h.id = q.hotel_id
   and h.status = 'active'
  join lateral (
    select current_stay.*
    from public.guest_sessions current_stay
    where current_stay.hotel_id = q.hotel_id
      and current_stay.room_id = q.room_id
      and current_stay.status = 'active'
      and coalesce(current_stay.extended_until, current_stay.checkout_time) > now()
    order by current_stay.checkin_time desc
    limit 1
  ) s on true
  where q.public_code = p_public_code
    and q.is_active
  limit 1;

  if v_session.id is null then
    return jsonb_build_object(
      'ok', false,
      'state', 'inactive',
      'error', 'Guest access is currently inactive. Please contact reception.'
    );
  end if;

  v_stay_expiry := coalesce(v_session.extended_until, v_session.checkout_time);

  select token.*
  into v_token
  from public.guest_access_tokens token
  where token.guest_session_id = v_session.id
    and token.hotel_id = v_session.hotel_id
    and token.room_id = v_session.room_id
  order by token.issued_at desc, token.created_at desc
  limit 1;

  -- The normal check-in trigger issues this token automatically. This fallback only
  -- repairs a missing token; it never bypasses a manual revoke/expiry state.
  if v_token.id is null then
    v_token_id := private.issue_guest_access_token(v_session.id, false, null);
    select token.*
    into v_token
    from public.guest_access_tokens token
    where token.id = v_token_id;
  end if;

  if v_token.status <> 'active' or v_token.expires_at <= now() or v_stay_expiry <= now() then
    return jsonb_build_object(
      'ok', false,
      'state', case when v_token.expires_at <= now() or v_stay_expiry <= now() then 'expired' else v_token.status end,
      'error', 'Guest access is unavailable. Please contact reception.'
    );
  end if;

  v_rendered := private.render_guest_access_token(v_token.id);

  return jsonb_build_object(
    'ok', true,
    'state', 'active',
    'guest_path', '/guest/' || v_hotel_slug || '/' || v_rendered,
    'food_path', '/food/' || v_hotel_slug || '/' || v_rendered,
    'expires_at', least(v_stay_expiry, v_token.expires_at)
  );
end;
$$;

revoke all on function public.resolve_permanent_room_qr(uuid) from public;
grant execute on function public.resolve_permanent_room_qr(uuid) to anon, authenticated;

-- Exceptional security control: replace a compromised/lost physical room QR.
create or replace function public.regenerate_permanent_room_qr(
  p_hotel_id uuid,
  p_room_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_code uuid;
  v_new_code uuid := gen_random_uuid();
  v_room_number text;
begin
  if not private.user_has_permission(p_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to regenerate room QR access.';
  end if;

  select q.public_code, r.room_number
  into v_old_code, v_room_number
  from public.room_qr_codes q
  join public.rooms r
    on r.id = q.room_id
   and r.hotel_id = q.hotel_id
  where q.hotel_id = p_hotel_id
    and q.room_id = p_room_id
    and r.is_active
  for update of q;

  if v_old_code is null then
    raise exception 'The selected room QR could not be found.';
  end if;

  -- Legacy PIN rows point at public_code and are no longer part of the default flow.
  delete from public.room_qr_pin_challenges
  where hotel_id = p_hotel_id
    and room_id = p_room_id;

  update public.room_qr_codes
  set public_code = v_new_code,
      is_active = true,
      updated_at = now()
  where hotel_id = p_hotel_id
    and room_id = p_room_id;

  perform private.write_activity_log(
    p_hotel_id,
    'guest_access.permanent_room_qr_regenerated',
    'room',
    p_room_id,
    'Permanent room QR regenerated after an explicit staff confirmation.',
    jsonb_build_object('public_code', v_old_code),
    jsonb_build_object('public_code', v_new_code),
    jsonb_build_object('room_number', v_room_number, 'source', 'qr_guides')
  );

  return jsonb_build_object(
    'result', 'PERMANENT ROOM QR REGENERATED',
    'room_id', p_room_id,
    'room_number', v_room_number,
    'public_code', v_new_code,
    'permanent_path', '/room/' || v_new_code::text
  );
end;
$$;

revoke all on function public.regenerate_permanent_room_qr(uuid,uuid) from public, anon;
grant execute on function public.regenerate_permanent_room_qr(uuid,uuid) to authenticated;

commit;
