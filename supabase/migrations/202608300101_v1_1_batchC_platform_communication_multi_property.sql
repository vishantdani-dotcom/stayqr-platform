-- StayQR V1.1-C - Platform, Communication & Multi-Property
-- Additive/refinement migration on top of stayqr-v1.1-b-locked.
-- Provider secrets remain Edge Function environment variables.

begin;

create table if not exists public.whatsapp_channel_settings (
  hotel_id uuid primary key references public.hotels(id) on delete cascade,
  provider text not null default 'meta_cloud',
  channel_enabled boolean not null default false,
  transactional_enabled boolean not null default true,
  marketing_enabled boolean not null default false,
  failure_threshold integer not null default 3,
  cooldown_minutes integer not null default 15,
  updated_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint whatsapp_channel_settings_provider_v11c_check check (provider='meta_cloud'),
  constraint whatsapp_channel_settings_failure_v11c_check check (failure_threshold between 2 and 10),
  constraint whatsapp_channel_settings_cooldown_v11c_check check (cooldown_minutes between 5 and 60),
  constraint whatsapp_channel_settings_marketing_v11c_check check (not marketing_enabled or channel_enabled),
  constraint whatsapp_channel_settings_metadata_v11c_check check (jsonb_typeof(metadata)='object' and pg_column_size(metadata)<=8192)
);

create table if not exists public.whatsapp_delivery_health (
  hotel_id uuid primary key references public.hotels(id) on delete cascade,
  circuit_state text not null default 'closed',
  failure_streak integer not null default 0,
  success_streak integer not null default 0,
  opened_at timestamptz,
  cooldown_until timestamptz,
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_error_code text,
  last_error_message text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint whatsapp_delivery_health_state_v11c_check check (circuit_state in ('closed','open','half_open')),
  constraint whatsapp_delivery_health_failure_v11c_check check (failure_streak between 0 and 100000),
  constraint whatsapp_delivery_health_success_v11c_check check (success_streak between 0 and 100000),
  constraint whatsapp_delivery_health_metadata_v11c_check check (jsonb_typeof(metadata)='object' and pg_column_size(metadata)<=8192)
);

alter table public.support_access_sessions
  add column if not exists last_seen_at timestamptz,
  add column if not exists revoked_reason text;

update public.support_access_sessions
set status='expired', ended_at=coalesce(ended_at,now()), updated_at=now(),
    metadata=metadata||jsonb_build_object('v11c_expired_on_migration',true)
where status='active' and expires_at<=now();

with ranked as (
  select id,row_number() over(partition by platform_admin_user_id order by started_at desc,id desc) rn
  from public.support_access_sessions where status='active'
)
update public.support_access_sessions s
set status='revoked',ended_at=coalesce(ended_at,now()),revoked_reason='V1.1-C single-session hardening',updated_at=now(),
    metadata=metadata||jsonb_build_object('v11c_duplicate_session_revoked',true)
from ranked r where r.id=s.id and r.rn>1;

create unique index if not exists uq_v11c_support_one_active_admin
  on public.support_access_sessions(platform_admin_user_id)
  where status='active';

alter table public.whatsapp_channel_settings enable row level security;
alter table public.whatsapp_delivery_health enable row level security;

drop policy if exists whatsapp_channel_settings_select_v11c on public.whatsapp_channel_settings;
create policy whatsapp_channel_settings_select_v11c on public.whatsapp_channel_settings
for select to authenticated using (
  private.user_has_any_permission(hotel_id,array['guests.manage','hotel.manage','reports.view']::text[])
  or private.is_platform_admin()
);

drop policy if exists whatsapp_delivery_health_select_v11c on public.whatsapp_delivery_health;
create policy whatsapp_delivery_health_select_v11c on public.whatsapp_delivery_health
for select to authenticated using (
  private.user_has_any_permission(hotel_id,array['guests.manage','hotel.manage','reports.view']::text[])
  or private.is_platform_admin()
);

revoke all on public.whatsapp_channel_settings from anon, authenticated;
revoke all on public.whatsapp_delivery_health from anon, authenticated;
grant select on public.whatsapp_channel_settings to authenticated;
grant select on public.whatsapp_delivery_health to authenticated;
grant all on public.whatsapp_channel_settings to service_role;
grant all on public.whatsapp_delivery_health to service_role;

create or replace function public.upsert_v11c_whatsapp_channel_settings(p_hotel_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_enabled boolean:=coalesce((p_payload->>'channel_enabled')::boolean,false);
  v_transactional boolean:=coalesce((p_payload->>'transactional_enabled')::boolean,true);
  v_marketing boolean:=coalesce((p_payload->>'marketing_enabled')::boolean,false);
  v_threshold integer:=coalesce((p_payload->>'failure_threshold')::integer,3);
  v_cooldown integer:=coalesce((p_payload->>'cooldown_minutes')::integer,15);
  v_profile_ready boolean;
  v_template_ready boolean;
  v_row public.whatsapp_channel_settings%rowtype;
begin
  if v_actor is null then raise exception 'Authentication is required.'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Settings payload must be a JSON object.'; end if;
  if not private.user_has_any_permission(p_hotel_id,array['guests.manage','hotel.manage']::text[]) then raise exception 'WhatsApp channel settings access denied.'; end if;
  if v_threshold not between 2 and 10 then raise exception 'Failure threshold must be between 2 and 10.'; end if;
  if v_cooldown not between 5 and 60 then raise exception 'Cooldown must be between 5 and 60 minutes.'; end if;
  if v_marketing and not v_enabled then raise exception 'Marketing delivery cannot be enabled while the provider channel is disabled.'; end if;
  select exists(select 1 from public.hotel_whatsapp_provider_profiles p where p.hotel_id=p_hotel_id and p.provider='meta_cloud' and p.status='active') into v_profile_ready;
  select exists(select 1 from public.whatsapp_templates t where t.hotel_id=p_hotel_id and t.status='published' and t.provider_name='meta_cloud' and t.provider_status='approved') into v_template_ready;
  if v_enabled and (not v_profile_ready or not v_template_ready) then
    raise exception 'Automated WhatsApp remains locked until an active hotel-owned Meta sender and a provider-approved template are configured.';
  end if;
  insert into public.whatsapp_channel_settings(hotel_id,provider,channel_enabled,transactional_enabled,marketing_enabled,failure_threshold,cooldown_minutes,updated_by,metadata,created_at,updated_at)
  values(p_hotel_id,'meta_cloud',v_enabled,v_transactional,v_marketing,v_threshold,v_cooldown,v_actor,jsonb_build_object('source','v1.1-c-platform-hub'),now(),now())
  on conflict(hotel_id) do update set channel_enabled=excluded.channel_enabled,transactional_enabled=excluded.transactional_enabled,marketing_enabled=excluded.marketing_enabled,failure_threshold=excluded.failure_threshold,cooldown_minutes=excluded.cooldown_minutes,updated_by=v_actor,metadata=whatsapp_channel_settings.metadata||excluded.metadata,updated_at=now()
  returning * into v_row;
  insert into public.whatsapp_delivery_health(hotel_id,circuit_state,failure_streak,success_streak,metadata,updated_at)
  values(p_hotel_id,'closed',0,0,jsonb_build_object('source','v1.1-c'),now()) on conflict(hotel_id) do nothing;
  perform private.write_activity_log(p_hotel_id,'whatsapp.channel_settings_updated','hotel',p_hotel_id,'WhatsApp channel safety settings updated.',null,to_jsonb(v_row),jsonb_build_object('v1_1_batch','C'));
  return jsonb_build_object('ok',true,'settings',to_jsonb(v_row),'provider_ready',v_profile_ready,'template_ready',v_template_ready);
end;$$;
revoke all on function public.upsert_v11c_whatsapp_channel_settings(uuid,jsonb) from public,anon;
grant execute on function public.upsert_v11c_whatsapp_channel_settings(uuid,jsonb) to authenticated,service_role;

create or replace function public.get_v11c_multi_property_overview()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid(); v_result jsonb;
begin
  if v_actor is null then raise exception 'Authentication is required.'; end if;
  with access_ids as (
    select distinct s.hotel_id from public.staff s where s.auth_user_id=v_actor and s.status='active'
    union
    select distinct hu.hotel_id from public.hotel_users hu where hu.user_id=v_actor and hu.status='active'
  ), rows as (
    select h.id hotel_id,h.hotel_name,h.location,h.status,h.subscription_status,h.timezone,h.currency_code,
      (select count(*) from public.rooms r where r.hotel_id=h.id and r.is_active) total_rooms,
      (select count(*) from public.rooms r where r.hotel_id=h.id and r.is_active and r.status='available') available_rooms,
      (select count(*) from public.rooms r where r.hotel_id=h.id and r.is_active and r.status='occupied') occupied_rooms,
      (select count(*) from public.guest_sessions gs where gs.hotel_id=h.id and gs.status='active') active_guests,
      (select count(*) from public.folios f where f.hotel_id=h.id and f.status='open') open_folios,
      (select coalesce(sum(f.balance_amount),0) from public.folios f where f.hotel_id=h.id and f.status='open') open_balance,
      (select count(*) from public.reservations rv where rv.hotel_id=h.id and rv.arrival_date=current_date and rv.status in('confirmed','checked_in')) arrivals_today,
      (select count(*) from public.reservations rv where rv.hotel_id=h.id and rv.departure_date=current_date and rv.status in('confirmed','checked_in','checked_out')) departures_today
    from public.hotels h join access_ids a on a.hotel_id=h.id
    where h.status<>'archived'
  )
  select jsonb_build_object(
    'summary',jsonb_build_object('property_count',count(*),'total_rooms',coalesce(sum(total_rooms),0),'occupied_rooms',coalesce(sum(occupied_rooms),0),'open_balance',coalesce(sum(open_balance),0)),
    'properties',coalesce(jsonb_agg(to_jsonb(rows) order by hotel_name),'[]'::jsonb)
  ) into v_result from rows;
  return coalesce(v_result,jsonb_build_object('summary',jsonb_build_object('property_count',0,'total_rooms',0,'occupied_rooms',0,'open_balance',0),'properties','[]'::jsonb));
end;$$;
revoke all on function public.get_v11c_multi_property_overview() from public,anon;
grant execute on function public.get_v11c_multi_property_overview() to authenticated,service_role;

create or replace function public.get_v11c_platform_workspace(p_hotel_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid(); v_settings jsonb; v_health jsonb; v_provider jsonb; v_templates jsonb; v_deliveries jsonb;
begin
  if v_actor is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_hotel_access(p_hotel_id) then raise exception 'Platform Hub access denied for this hotel.'; end if;
  select to_jsonb(s) into v_settings from public.whatsapp_channel_settings s where s.hotel_id=p_hotel_id;
  if v_settings is null then v_settings:=jsonb_build_object('hotel_id',p_hotel_id,'channel_enabled',false,'transactional_enabled',true,'marketing_enabled',false,'failure_threshold',3,'cooldown_minutes',15); end if;
  select to_jsonb(h) into v_health from public.whatsapp_delivery_health h where h.hotel_id=p_hotel_id;
  if v_health is null then v_health:=jsonb_build_object('hotel_id',p_hotel_id,'circuit_state','closed','failure_streak',0,'success_streak',0); end if;
  select jsonb_build_object('provider',p.provider,'sender_display_name',p.sender_display_name,'status',p.status,'last_verified_at',p.last_verified_at) into v_provider from public.hotel_whatsapp_provider_profiles p where p.hotel_id=p_hotel_id;
  select jsonb_build_object('published',count(*) filter(where status='published'),'provider_approved',count(*) filter(where status='published' and provider_name='meta_cloud' and provider_status='approved'),'provider_pending',count(*) filter(where provider_status='pending')) into v_templates from public.whatsapp_templates where hotel_id=p_hotel_id;
  select jsonb_build_object('eligible',count(*) filter(where status='eligible'),'queued',count(*) filter(where status='queued'),'sent',count(*) filter(where status='sent'),'delivered',count(*) filter(where status='delivered'),'read',count(*) filter(where status='read'),'failed',count(*) filter(where status='failed'),'suppressed',count(*) filter(where status='suppressed')) into v_deliveries from public.guest_communication_recipients where hotel_id=p_hotel_id;
  return jsonb_build_object('hotel_id',p_hotel_id,'whatsapp',jsonb_build_object('settings',v_settings,'health',v_health,'provider',v_provider,'templates',coalesce(v_templates,'{}'::jsonb),'deliveries',coalesce(v_deliveries,'{}'::jsonb)),'multi_property',public.get_v11c_multi_property_overview(),'support_policy',jsonb_build_object('max_duration_minutes',120,'one_active_session_per_admin',true,'silent_impersonation',false,'expiry_extends_on_activity',false));
end;$$;
revoke all on function public.get_v11c_platform_workspace(uuid) from public,anon;
grant execute on function public.get_v11c_platform_workspace(uuid) to authenticated,service_role;

create or replace function public.start_safe_support_access(target_hotel_id uuid,reason text,duration_minutes integer default 60,requested_permissions text[] default array['read_only']::text[])
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  actor_user_id uuid:=private.require_platform_admin_20260728();
  session_row public.support_access_sessions%rowtype;
  normalized_permissions text[];
begin
  if target_hotel_id is null or nullif(trim(reason),'') is null or length(trim(reason))<12 or length(trim(reason))>500 then raise exception 'Support-access reason must contain 12 to 500 characters.'; end if;
  if duration_minutes is null or duration_minutes<5 or duration_minutes>120 then raise exception 'Support access duration must be between 5 and 120 minutes.'; end if;
  if not exists(select 1 from public.hotels h where h.id=target_hotel_id and h.status='active') then raise exception 'Support access requires an active hotel.'; end if;
  select array_agg(distinct permission_value order by permission_value) into normalized_permissions
  from unnest(coalesce(requested_permissions,array['read_only']::text[])) permission_value
  where permission_value in('read_only','hotel_configuration','subscription_support','ticket_support');
  if coalesce(cardinality(normalized_permissions),0)=0 then raise exception 'At least one approved support permission is required.'; end if;
  update public.support_access_sessions s set status='expired',ended_at=coalesce(ended_at,now()),updated_at=now(),metadata=metadata||jsonb_build_object('v11c_expired_before_start',true)
  where s.platform_admin_user_id=actor_user_id and s.status='active' and s.expires_at<=now();
  if exists(select 1 from public.support_access_sessions s where s.platform_admin_user_id=actor_user_id and s.status='active' and s.expires_at>now()) then raise exception 'End the current audited support session before starting another hotel session.'; end if;
  insert into public.support_access_sessions(hotel_id,platform_admin_user_id,reason,status,permissions,started_at,expires_at,last_seen_at,metadata,created_at,updated_at)
  values(target_hotel_id,actor_user_id,trim(reason),'active',normalized_permissions,now(),now()+make_interval(mins=>duration_minutes),now(),jsonb_build_object('v11c_policy',true,'max_duration_minutes',120),now(),now()) returning * into session_row;
  insert into public.support_access_events(session_id,hotel_id,event_type,actor_user_id,message,details,created_at)
  values(session_row.id,session_row.hotel_id,'support_access_started',actor_user_id,trim(reason),jsonb_build_object('permissions',session_row.permissions,'expires_at',session_row.expires_at,'v11c_policy',true),now());
  return jsonb_build_object('session',to_jsonb(session_row),'policy',jsonb_build_object('max_duration_minutes',120,'one_active_session_per_admin',true));
end;$$;

create or replace function public.touch_v11c_support_access(target_session_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_user_id uuid:=private.require_platform_admin_20260728(); session_row public.support_access_sessions%rowtype;
begin
  select * into session_row from public.support_access_sessions s where s.id=target_session_id and s.platform_admin_user_id=actor_user_id for update;
  if not found then raise exception 'Support-access session was not found.'; end if;
  if session_row.status='active' and session_row.expires_at<=now() then
    update public.support_access_sessions set status='expired',ended_at=coalesce(ended_at,now()),last_seen_at=now(),updated_at=now() where id=session_row.id returning * into session_row;
    insert into public.support_access_events(session_id,hotel_id,event_type,actor_user_id,message,details) values(session_row.id,session_row.hotel_id,'support_access_expired',actor_user_id,'Audited support access expired.',jsonb_build_object('expires_at',session_row.expires_at)) on conflict do nothing;
  elsif session_row.status='active' then
    update public.support_access_sessions set last_seen_at=now(),updated_at=now() where id=session_row.id returning * into session_row;
  end if;
  return jsonb_build_object('session',to_jsonb(session_row),'expiry_extended',false);
end;$$;
revoke all on function public.touch_v11c_support_access(uuid) from public,anon;
grant execute on function public.touch_v11c_support_access(uuid) to authenticated,service_role;

commit;
