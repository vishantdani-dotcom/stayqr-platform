begin;

create or replace function public.get_room_qr_public_context(p_public_code uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select jsonb_strip_nulls(
      jsonb_build_object(
        'valid', true,
        'hotel_name', h.hotel_name,
        'room_number', r.room_number,
        'reception_phone', nullif(btrim(hi.reception_phone), '')
      )
    )
    from public.room_qr_codes q
    join public.rooms r
      on r.id = q.room_id
     and r.hotel_id = q.hotel_id
    join public.hotels h
      on h.id = q.hotel_id
    left join lateral (
      select info.reception_phone
      from public.hotel_info info
      where info.hotel_id = q.hotel_id
      limit 1
    ) hi on true
    where q.public_code = p_public_code
      and q.is_active
      and r.is_active
      and h.status = 'active'
    limit 1
  ), jsonb_build_object('valid', false));
$$;

revoke all on function public.get_room_qr_public_context(uuid) from public;
grant execute on function public.get_room_qr_public_context(uuid) to anon, authenticated;

select jsonb_build_object(
  'status', 'ROOM_QR_RECEPTION_CONTACT_REV1_PASSED',
  'public_context_rpc_present',
    to_regprocedure('public.get_room_qr_public_context(uuid)') is not null,
  'valid_qr_guard_preserved',
    position('q.is_active' in pg_get_functiondef(to_regprocedure('public.get_room_qr_public_context(uuid)'))) > 0
    and position('r.is_active' in pg_get_functiondef(to_regprocedure('public.get_room_qr_public_context(uuid)'))) > 0
    and position('h.status = ''active''' in pg_get_functiondef(to_regprocedure('public.get_room_qr_public_context(uuid)'))) > 0,
  'reception_phone_exposed',
    position('reception_phone' in pg_get_functiondef(to_regprocedure('public.get_room_qr_public_context(uuid)'))) > 0,
  'hotel_info_source',
    position('public.hotel_info' in pg_get_functiondef(to_regprocedure('public.get_room_qr_public_context(uuid)'))) > 0
) as final_acceptance;

commit;
