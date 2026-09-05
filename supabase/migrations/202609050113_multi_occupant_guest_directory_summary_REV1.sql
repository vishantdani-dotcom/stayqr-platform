begin;

-- StayQR Multi-Occupant Guest Directory REV7
-- Makes Guest 360 summaries companion-aware without creating duplicate stays.
-- A stay belongs to a guest when the guest is either the primary guest_session guest
-- or a persisted guest_companions member of that same hotel-scoped guest_session.

create or replace function public.get_guest_360_directory(target_hotel_id uuid)
returns table (
  guest_id uuid,
  full_name text,
  phone text,
  email text,
  preferred_language text,
  nationality text,
  country_of_residence text,
  identity_verification_status text,
  created_at timestamptz,
  updated_at timestamptz,
  total_stays bigint,
  completed_stays bigint,
  active_session_id uuid,
  active_room_number text,
  active_checkin timestamptz,
  active_checkout timestamptz,
  last_stay_at timestamptz,
  document_count bigint,
  verified_document boolean,
  whatsapp_transactional_consent boolean,
  whatsapp_marketing_consent boolean,
  kyc_capture_consent boolean,
  aadhaar_offline_consent boolean,
  whatsapp_suppressed boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with stay_memberships as (
    select
      gs.id as guest_session_id,
      gs.hotel_id,
      gs.guest_id,
      gs.room_id,
      gs.status,
      gs.checkin_time,
      gs.checkout_time,
      gs.extended_until
    from public.guest_sessions gs
    where gs.hotel_id = target_hotel_id

    union

    select
      gs.id as guest_session_id,
      gs.hotel_id,
      gc.guest_id,
      gs.room_id,
      gs.status,
      gs.checkin_time,
      gs.checkout_time,
      gs.extended_until
    from public.guest_companions gc
    join public.guest_sessions gs
      on gs.hotel_id = gc.hotel_id
     and gs.id = gc.guest_session_id
    where gc.hotel_id = target_hotel_id
  ), sessions as (
    select
      sm.guest_id,
      count(*)::bigint as total_stays,
      count(*) filter (where sm.status <> 'active')::bigint as completed_stays,
      max(sm.checkin_time) as last_stay_at
    from stay_memberships sm
    group by sm.guest_id
  ), active_stay as (
    select distinct on (sm.guest_id)
      sm.guest_id,
      sm.guest_session_id as session_id,
      r.room_number,
      sm.checkin_time,
      coalesce(sm.extended_until, sm.checkout_time) as checkout_time
    from stay_memberships sm
    left join public.rooms r
      on r.id = sm.room_id
     and r.hotel_id = sm.hotel_id
    where sm.status = 'active'
    order by sm.guest_id, sm.checkin_time desc, sm.guest_session_id desc
  ), docs as (
    select
      gd.guest_id,
      count(*)::bigint as document_count,
      bool_or(gd.verification_status = 'verified') as verified_document
    from public.guest_documents gd
    where gd.hotel_id = target_hotel_id
      and gd.deleted_at is null
    group by gd.guest_id
  )
  select
    g.id,
    g.full_name,
    g.phone,
    g.email,
    g.preferred_language,
    g.nationality,
    g.country_of_residence,
    g.identity_verification_status,
    g.created_at,
    g.updated_at,
    coalesce(s.total_stays, 0),
    coalesce(s.completed_stays, 0),
    a.session_id,
    a.room_number,
    a.checkin_time,
    a.checkout_time,
    s.last_stay_at,
    coalesce(d.document_count, 0),
    coalesce(d.verified_document, false),
    exists(
      select 1
      from public.guest_consents c
      where c.hotel_id = target_hotel_id
        and c.guest_id = g.id
        and c.purpose = 'whatsapp_transactional'
        and c.status = 'granted'
        and c.revoked_at is null
    ),
    exists(
      select 1
      from public.guest_consents c
      where c.hotel_id = target_hotel_id
        and c.guest_id = g.id
        and c.purpose = 'whatsapp_marketing'
        and c.status = 'granted'
        and c.revoked_at is null
    ),
    exists(
      select 1
      from public.guest_consents c
      where c.hotel_id = target_hotel_id
        and c.guest_id = g.id
        and c.purpose = 'kyc_capture'
        and c.status = 'granted'
        and c.revoked_at is null
    ),
    exists(
      select 1
      from public.guest_consents c
      where c.hotel_id = target_hotel_id
        and c.guest_id = g.id
        and c.purpose = 'aadhaar_offline_verification'
        and c.status = 'granted'
        and c.revoked_at is null
    ),
    exists(
      select 1
      from public.guest_communication_suppressions x
      where x.hotel_id = target_hotel_id
        and x.guest_id = g.id
        and x.channel = 'whatsapp'
        and x.active = true
    )
  from public.guests g
  left join sessions s on s.guest_id = g.id
  left join active_stay a on a.guest_id = g.id
  left join docs d on d.guest_id = g.id
  where g.hotel_id = target_hotel_id
    and private.user_has_permission(target_hotel_id, 'guests.view')
  order by g.updated_at desc;
$$;

revoke all on function public.get_guest_360_directory(uuid) from public, anon;
grant execute on function public.get_guest_360_directory(uuid) to authenticated, service_role;

comment on function public.get_guest_360_directory(uuid) is
  'StayQR Guest 360 directory summary. Counts both primary and companion stay memberships, deduplicated by guest_session.';

create or replace function public.get_guest_communication_audience(target_hotel_id uuid)
returns table(
  guest_id uuid,
  full_name text,
  phone_e164 text,
  transactional_consent boolean,
  marketing_consent boolean,
  suppressed boolean,
  suppression_reason text,
  active_room text
)
language sql
stable
security definer
set search_path = ''
as $$
  with active_memberships as (
    select
      gs.guest_id,
      gs.id as guest_session_id,
      gs.room_id,
      gs.checkin_time
    from public.guest_sessions gs
    where gs.hotel_id = target_hotel_id
      and gs.status = 'active'

    union

    select
      gc.guest_id,
      gs.id as guest_session_id,
      gs.room_id,
      gs.checkin_time
    from public.guest_companions gc
    join public.guest_sessions gs
      on gs.hotel_id = gc.hotel_id
     and gs.id = gc.guest_session_id
    where gc.hotel_id = target_hotel_id
      and gs.status = 'active'
  ), active_room_by_guest as (
    select distinct on (am.guest_id)
      am.guest_id,
      r.room_number
    from active_memberships am
    left join public.rooms r
      on r.hotel_id = target_hotel_id
     and r.id = am.room_id
    order by am.guest_id, am.checkin_time desc, am.guest_session_id desc
  )
  select
    g.id,
    g.full_name,
    case
      when regexp_replace(coalesce(g.phone, ''), '\D', '', 'g') ~ '^[0-9]{10}$'
        then '+91' || regexp_replace(g.phone, '\D', '', 'g')
      when regexp_replace(coalesce(g.phone, ''), '\D', '', 'g') ~ '^[1-9][0-9]{7,14}$'
        then '+' || regexp_replace(g.phone, '\D', '', 'g')
      else null
    end,
    exists(
      select 1 from public.guest_consents c
      where c.hotel_id = target_hotel_id
        and c.guest_id = g.id
        and c.purpose = 'whatsapp_transactional'
        and c.status = 'granted'
        and c.revoked_at is null
    ),
    exists(
      select 1 from public.guest_consents c
      where c.hotel_id = target_hotel_id
        and c.guest_id = g.id
        and c.purpose = 'whatsapp_marketing'
        and c.status = 'granted'
        and c.revoked_at is null
    ),
    exists(
      select 1 from public.guest_communication_suppressions s
      where s.hotel_id = target_hotel_id
        and s.guest_id = g.id
        and s.channel = 'whatsapp'
        and s.active = true
    ),
    (
      select s.reason
      from public.guest_communication_suppressions s
      where s.hotel_id = target_hotel_id
        and s.guest_id = g.id
        and s.channel = 'whatsapp'
        and s.active = true
      order by s.created_at desc
      limit 1
    ),
    ar.room_number
  from public.guests g
  left join active_room_by_guest ar on ar.guest_id = g.id
  where g.hotel_id = target_hotel_id
    and private.user_has_permission(target_hotel_id, 'guests.manage')
  order by g.full_name;
$$;

revoke all on function public.get_guest_communication_audience(uuid) from public, anon;
grant execute on function public.get_guest_communication_audience(uuid) to authenticated, service_role;

comment on function public.get_guest_communication_audience(uuid) is
  'StayQR guest communication audience with companion-aware active-room status.';

commit;
