-- StayQR v1.0 — Day 13 Migration 039 REV1
-- Room inventory governance: floor/type/room edit/archive/import and availability hardening.
begin;

do $preflight$
declare
  missing text;
begin
  select string_agg(name, ', ' order by name)
  into missing
  from (
    values
      ('public.rooms', to_regclass('public.rooms') is not null),
      ('public.room_types', to_regclass('public.room_types') is not null),
      ('public.floors', to_regclass('public.floors') is not null),
      ('public.housekeeping_tasks', to_regclass('public.housekeeping_tasks') is not null),
      ('public.room_inventory_allocations', to_regclass('public.room_inventory_allocations') is not null),
      ('private.day11_require_current_actor()', to_regprocedure('private.day11_require_current_actor()') is not null),
      ('private.day11_valid_auth_actor(uuid)', to_regprocedure('private.day11_valid_auth_actor(uuid)') is not null),
      ('private.user_has_any_permission(uuid,text[])', to_regprocedure('private.user_has_any_permission(uuid,text[])') is not null),
      ('public.get_available_rooms(uuid,date,date,uuid)', to_regprocedure('public.get_available_rooms(uuid,date,date,uuid)') is not null),
      ('public.get_reservation_available_rooms(uuid,date,date,uuid,uuid)', to_regprocedure('public.get_reservation_available_rooms(uuid,date,date,uuid,uuid)') is not null),
      ('public.get_room_type_availability(uuid,date,date)', to_regprocedure('public.get_room_type_availability(uuid,date,date)') is not null),
      ('private.calendar_room_is_available(uuid,uuid,date,date,uuid,uuid)', to_regprocedure('private.calendar_room_is_available(uuid,uuid,date,date,uuid,uuid)') is not null)
  ) required(name, ok)
  where not ok;

  if missing is not null then
    raise exception 'Migration 039 prerequisites missing: %', missing;
  end if;

  if to_regclass('public.room_status_events') is not null
     or to_regclass('public.room_import_batches') is not null
     or to_regclass('public.room_import_rows') is not null
     or exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='rooms' and column_name='is_active'
     )
  then
    raise exception 'Migration 039 appears installed. Do not rerun REV1.';
  end if;

  if (
    select count(*) from public.rooms
    where hotel_id='77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
  ) <> 12 then
    raise exception 'VD Stay Inn room baseline is not 12.';
  end if;

  if (
    select coalesce(sum(balance_amount),0) from public.folios
    where hotel_id='77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
  ) <> 22785 then
    raise exception 'Day 12 locked balance is not INR 22785.';
  end if;
end;
$preflight$;

alter table public.rooms
  add column is_active boolean not null default true,
  add column archived_at timestamptz,
  add column archived_by uuid references auth.users(id) on delete set null,
  add column archive_reason text,
  add column updated_at timestamptz not null default now(),
  add column updated_by uuid references auth.users(id) on delete set null,
  add column status_changed_at timestamptz not null default now(),
  add column status_changed_by uuid references auth.users(id) on delete set null,
  add column metadata jsonb not null default '{}'::jsonb,
  add constraint rooms_day13_metadata_object check (jsonb_typeof(metadata)='object'),
  add constraint rooms_day13_archive_check check (
    is_active or (
      archived_at is not null
      and nullif(trim(archive_reason),'') is not null
      and status='out_of_order'
    )
  );

alter table public.room_types
  add column created_by uuid references auth.users(id) on delete set null,
  add column updated_by uuid references auth.users(id) on delete set null,
  add column archived_at timestamptz,
  add column archived_by uuid references auth.users(id) on delete set null,
  add column archive_reason text,
  add column metadata jsonb not null default '{}'::jsonb,
  add constraint room_types_day13_metadata_object check (jsonb_typeof(metadata)='object'),
  add constraint room_types_day13_archive_check check (
    is_active or (
      archived_at is not null
      and nullif(trim(archive_reason),'') is not null
    )
  );

alter table public.floors
  add column archived_at timestamptz,
  add column archived_by uuid references auth.users(id) on delete set null,
  add column archive_reason text,
  add column metadata jsonb not null default '{}'::jsonb,
  add constraint floors_day13_metadata_object check (jsonb_typeof(metadata)='object'),
  add constraint floors_day13_archive_check check (
    is_active or (
      archived_at is not null
      and nullif(trim(archive_reason),'') is not null
    )
  );

create index idx_rooms_hotel_active_status
  on public.rooms(hotel_id,is_active,status,room_number);
create index idx_rooms_hotel_archived
  on public.rooms(hotel_id,archived_at desc) where not is_active;

create table public.room_status_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  room_id uuid not null,
  previous_status text,
  new_status text not null,
  previous_is_active boolean,
  new_is_active boolean not null,
  reason text,
  source text not null default 'database',
  request_id text,
  actor_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint room_status_events_room_fkey
    foreign key (hotel_id,room_id) references public.rooms(hotel_id,id) on delete restrict,
  constraint room_status_events_status_check check (
    new_status in ('available','occupied','cleaning','maintenance','out_of_order')
    and (
      previous_status is null
      or previous_status in ('available','occupied','cleaning','maintenance','out_of_order')
    )
  ),
  constraint room_status_events_source_check check (
    source in ('database','room_rpc','archive_rpc','import','checkin','checkout','housekeeping','maintenance')
  ),
  constraint room_status_events_metadata_check check (jsonb_typeof(metadata)='object')
);
create unique index uq_room_status_events_request
  on public.room_status_events(hotel_id,request_id) where request_id is not null;
create index idx_room_status_events_room_time
  on public.room_status_events(hotel_id,room_id,occurred_at desc);

create table public.room_import_batches (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  request_id text not null,
  status text not null default 'processing',
  requested_rows integer not null,
  inserted_rows integer not null default 0,
  source_name text,
  requested_by uuid not null references auth.users(id) on delete restrict,
  completed_at timestamptz,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint room_import_batches_status_check check (status in ('processing','completed','failed')),
  constraint room_import_batches_count_check check (requested_rows>0 and inserted_rows>=0 and inserted_rows<=requested_rows),
  constraint room_import_batches_summary_check check (jsonb_typeof(summary)='object')
);
create unique index uq_room_import_batches_hotel_id_id on public.room_import_batches(hotel_id,id);
create unique index uq_room_import_batches_request on public.room_import_batches(hotel_id,request_id);

create table public.room_import_rows (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  batch_id uuid not null,
  row_number integer not null,
  room_id uuid not null,
  room_number text not null,
  floor_id uuid not null,
  room_type_id uuid not null,
  initial_status text not null,
  source_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint room_import_rows_batch_fkey
    foreign key (hotel_id,batch_id) references public.room_import_batches(hotel_id,id) on delete cascade,
  constraint room_import_rows_room_fkey
    foreign key (hotel_id,room_id) references public.rooms(hotel_id,id) on delete restrict,
  constraint room_import_rows_floor_fkey
    foreign key (hotel_id,floor_id) references public.floors(hotel_id,id) on delete restrict,
  constraint room_import_rows_type_fkey
    foreign key (hotel_id,room_type_id) references public.room_types(hotel_id,id) on delete restrict,
  constraint room_import_rows_status_check check (initial_status in ('available','cleaning','maintenance','out_of_order')),
  constraint room_import_rows_payload_check check (jsonb_typeof(source_payload)='object')
);
create unique index uq_room_import_rows_batch_row
  on public.room_import_rows(hotel_id,batch_id,row_number);

alter table public.room_status_events enable row level security;
alter table public.room_import_batches enable row level security;
alter table public.room_import_rows enable row level security;

create policy stayqr_room_status_events_select on public.room_status_events
for select to authenticated using (
  private.user_has_any_permission(hotel_id,array['rooms.view','rooms.manage','housekeeping.view','housekeeping.manage','reservations.view','reservations.manage']::text[])
);
create policy stayqr_room_import_batches_select on public.room_import_batches
for select to authenticated using (
  private.user_has_any_permission(hotel_id,array['rooms.view','rooms.manage','hotel.manage']::text[])
);
create policy stayqr_room_import_rows_select on public.room_import_rows
for select to authenticated using (
  private.user_has_any_permission(hotel_id,array['rooms.view','rooms.manage','hotel.manage']::text[])
);

create or replace function private.day13_require_room_manager(h uuid)
returns uuid
language plpgsql security definer set search_path=''
as $function$
begin
  if h is null then raise exception 'Hotel ID is required.'; end if;
  if not private.user_has_any_permission(
    h,array['rooms.manage','hotel.manage','superadmin.manage']::text[]
  ) then raise exception 'Room inventory management access denied.'; end if;
  return private.day11_require_current_actor();
end;
$function$;

create or replace function private.day13_normalize_room_number(v text)
returns text
language sql immutable security invoker set search_path=''
as $function$
  select nullif(upper(regexp_replace(trim(coalesce(v,'')),'\s+','','g')),'');
$function$;

create or replace function private.day13_room_commitments(h uuid,r uuid)
returns jsonb
language sql stable security definer set search_path=''
as $function$
  select jsonb_build_object(
    'active_stays',(select count(*) from public.guest_sessions g where g.hotel_id=h and g.room_id=r and g.status='active'),
    'active_or_future_allocations',(select count(*) from public.room_inventory_allocations a where a.hotel_id=h and a.room_id=r and a.status='active' and a.ends_on>current_date),
    'active_blocks',(select count(*) from public.room_blocks b where b.hotel_id=h and b.room_id=r and b.status='active' and b.end_date>current_date),
    'pending_housekeeping',(select count(*) from public.housekeeping_tasks t where t.hotel_id=h and t.room_id=r and coalesce(t.status,'pending') not in ('completed','cancelled','inspected','ready'))
  );
$function$;

create or replace function private.day13_touch()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  new.updated_at:=now();
  new.updated_by:=coalesce(private.day11_valid_auth_actor(auth.uid()),new.updated_by,old.updated_by);
  return new;
end;
$function$;

create trigger rooms_day13_touch before update on public.rooms
for each row execute function private.day13_touch();
create trigger room_types_day13_touch before update on public.room_types
for each row execute function private.day13_touch();
create trigger floors_day13_touch before update on public.floors
for each row execute function private.day13_touch();

create or replace function private.day13_sync_room_reference()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare fa boolean; ta boolean; tn text;
begin
  new.room_number:=private.day13_normalize_room_number(new.room_number);
  if new.room_number is null then raise exception 'Room number is required.'; end if;
  select f.is_active into fa from public.floors f where f.hotel_id=new.hotel_id and f.id=new.floor_id;
  if fa is distinct from true then raise exception 'Room requires an active floor.'; end if;
  select t.is_active,t.name into ta,tn from public.room_types t where t.hotel_id=new.hotel_id and t.id=new.room_type_id;
  if ta is distinct from true then raise exception 'Room requires an active room type.'; end if;
  new.room_type:=tn;
  return new;
end;
$function$;

create trigger rooms_day13_reference_sync
before insert or update of hotel_id,room_number,floor_id,room_type_id on public.rooms
for each row execute function private.day13_sync_room_reference();

create or replace function private.day13_record_room_event()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare req text; src text; rsn text;
begin
  if tg_op='UPDATE' and new.status is not distinct from old.status
     and new.is_active is not distinct from old.is_active then return new; end if;
  req:=nullif(current_setting('stayqr.day13_request_id',true),'');
  src:=coalesce(nullif(current_setting('stayqr.day13_event_source',true),''),'database');
  if src not in ('database','room_rpc','archive_rpc','import','checkin','checkout','housekeeping','maintenance') then src:='database'; end if;
  rsn:=coalesce(nullif(current_setting('stayqr.day13_status_reason',true),''),nullif(new.metadata->>'last_status_reason',''));
  insert into public.room_status_events(
    hotel_id,room_id,previous_status,new_status,previous_is_active,new_is_active,
    reason,source,request_id,actor_id,metadata
  ) values (
    new.hotel_id,new.id,case when tg_op='INSERT' then null else old.status end,new.status,
    case when tg_op='INSERT' then null else old.is_active end,new.is_active,
    rsn,src,req,private.day11_valid_auth_actor(auth.uid()),
    jsonb_build_object('room_number',new.room_number,'floor_id',new.floor_id,'room_type_id',new.room_type_id)
  )
  on conflict (hotel_id,request_id) where request_id is not null do nothing;
  return new;
end;
$function$;

create trigger rooms_day13_status_event
after insert or update of status,is_active on public.rooms
for each row execute function private.day13_record_room_event();

create or replace function public.upsert_floor(
  h uuid, floor_id_value uuid, code_value text, name_value text,
  floor_number_value integer, description_value text, sort_order_value integer,
  active_value boolean, request_id_value text
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; row_value public.floors%rowtype; req text;
begin
  actor:=private.day13_require_room_manager(h);
  req:=nullif(trim(request_id_value),'');
  if req is null or length(req)<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  if coalesce(active_value,true)=false then raise exception 'Use archive_floor to deactivate a floor.'; end if;
  if nullif(trim(code_value),'') is null or nullif(trim(name_value),'') is null then raise exception 'Floor code and name are required.'; end if;
  if floor_id_value is null then
    insert into public.floors(hotel_id,name,code,floor_number,description,sort_order,is_active,created_by,updated_by,metadata)
    values(h,trim(name_value),upper(trim(code_value)),floor_number_value,nullif(trim(description_value),''),coalesce(sort_order_value,0),coalesce(active_value,true),actor,actor,jsonb_build_object('request_id',req))
    returning * into row_value;
  else
    update public.floors set
      name=trim(name_value),code=upper(trim(code_value)),floor_number=floor_number_value,
      description=nullif(trim(description_value),''),sort_order=coalesce(sort_order_value,sort_order),
      is_active=coalesce(active_value,is_active),
      archived_at=case when coalesce(active_value,is_active) then null else archived_at end,
      archived_by=case when coalesce(active_value,is_active) then null else archived_by end,
      archive_reason=case when coalesce(active_value,is_active) then null else archive_reason end,
      updated_by=actor,metadata=metadata||jsonb_build_object('request_id',req)
    where hotel_id=h and id=floor_id_value returning * into row_value;
    if row_value.id is null then raise exception 'Floor was not found.'; end if;
  end if;
  return jsonb_build_object('ok',true,'floor',to_jsonb(row_value));
end;
$function$;

create or replace function public.archive_floor(h uuid, floor_id_value uuid, reason_value text, request_id_value text)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; row_value public.floors%rowtype; c integer;
begin
  actor:=private.day13_require_room_manager(h);
  if nullif(trim(request_id_value),'') is null or length(trim(request_id_value))<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  if nullif(trim(reason_value),'') is null then raise exception 'Archive reason is required.'; end if;
  select * into row_value from public.floors where hotel_id=h and id=floor_id_value for update;
  if not found then raise exception 'Floor was not found.'; end if;
  if not row_value.is_active then return jsonb_build_object('ok',true,'idempotent',true,'floor',to_jsonb(row_value)); end if;
  select count(*) into c from public.rooms where hotel_id=h and floor_id=floor_id_value and is_active;
  if c>0 then raise exception 'Floor cannot be archived while % active room(s) remain.',c; end if;
  update public.floors set is_active=false,archived_at=now(),archived_by=actor,
    archive_reason=trim(reason_value),updated_by=actor,
    metadata=metadata||jsonb_build_object('archive_request_id',request_id_value)
  where hotel_id=h and id=floor_id_value returning * into row_value;
  return jsonb_build_object('ok',true,'idempotent',false,'floor',to_jsonb(row_value));
end;
$function$;

create or replace function public.upsert_room_type(
  h uuid, type_id_value uuid, code_value text, name_value text, description_value text,
  base_occupancy_value integer, max_adults_value integer, max_children_value integer,
  max_occupancy_value integer, base_rate_value numeric, extra_adult_rate_value numeric,
  extra_child_rate_value numeric, sort_order_value integer, active_value boolean,
  request_id_value text
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; row_value public.room_types%rowtype; req text;
begin
  actor:=private.day13_require_room_manager(h);
  req:=nullif(trim(request_id_value),'');
  if req is null or length(req)<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  if coalesce(active_value,true)=false then raise exception 'Use archive_room_type to deactivate a room type.'; end if;
  if nullif(trim(code_value),'') is null or nullif(trim(name_value),'') is null then raise exception 'Room-type code and name are required.'; end if;
  if type_id_value is null then
    insert into public.room_types(
      hotel_id,name,code,description,base_occupancy,max_adults,max_children,max_occupancy,
      base_rate,extra_adult_rate,extra_child_rate,is_active,sort_order,created_by,updated_by,metadata
    ) values(
      h,trim(name_value),upper(trim(code_value)),nullif(trim(description_value),''),
      coalesce(base_occupancy_value,1),coalesce(max_adults_value,2),coalesce(max_children_value,1),
      coalesce(max_occupancy_value,3),coalesce(base_rate_value,0),coalesce(extra_adult_rate_value,0),
      coalesce(extra_child_rate_value,0),coalesce(active_value,true),coalesce(sort_order_value,0),
      actor,actor,jsonb_build_object('request_id',req)
    ) returning * into row_value;
  else
    update public.room_types set
      name=trim(name_value),code=upper(trim(code_value)),description=nullif(trim(description_value),''),
      base_occupancy=coalesce(base_occupancy_value,base_occupancy),
      max_adults=coalesce(max_adults_value,max_adults),max_children=coalesce(max_children_value,max_children),
      max_occupancy=coalesce(max_occupancy_value,max_occupancy),base_rate=coalesce(base_rate_value,base_rate),
      extra_adult_rate=coalesce(extra_adult_rate_value,extra_adult_rate),
      extra_child_rate=coalesce(extra_child_rate_value,extra_child_rate),
      sort_order=coalesce(sort_order_value,sort_order),is_active=coalesce(active_value,is_active),
      archived_at=case when coalesce(active_value,is_active) then null else archived_at end,
      archived_by=case when coalesce(active_value,is_active) then null else archived_by end,
      archive_reason=case when coalesce(active_value,is_active) then null else archive_reason end,
      updated_by=actor,metadata=metadata||jsonb_build_object('request_id',req)
    where hotel_id=h and id=type_id_value returning * into row_value;
    if row_value.id is null then raise exception 'Room type was not found.'; end if;
  end if;
  update public.rooms
  set room_type=row_value.name, updated_by=actor
  where hotel_id=h and room_type_id=row_value.id
    and room_type is distinct from row_value.name;

  return jsonb_build_object('ok',true,'room_type',to_jsonb(row_value));
end;
$function$;

create or replace function public.archive_room_type(h uuid, type_id_value uuid, reason_value text, request_id_value text)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; row_value public.room_types%rowtype; c integer;
begin
  actor:=private.day13_require_room_manager(h);
  if nullif(trim(request_id_value),'') is null or length(trim(request_id_value))<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  if nullif(trim(reason_value),'') is null then raise exception 'Archive reason is required.'; end if;
  select * into row_value from public.room_types where hotel_id=h and id=type_id_value for update;
  if not found then raise exception 'Room type was not found.'; end if;
  if not row_value.is_active then return jsonb_build_object('ok',true,'idempotent',true,'room_type',to_jsonb(row_value)); end if;
  select count(*) into c from public.rooms where hotel_id=h and room_type_id=type_id_value and is_active;
  if c>0 then raise exception 'Room type cannot be archived while % active room(s) remain.',c; end if;
  update public.room_types set is_active=false,archived_at=now(),archived_by=actor,
    archive_reason=trim(reason_value),updated_by=actor,
    metadata=metadata||jsonb_build_object('archive_request_id',request_id_value)
  where hotel_id=h and id=type_id_value returning * into row_value;
  return jsonb_build_object('ok',true,'idempotent',false,'room_type',to_jsonb(row_value));
end;
$function$;

create or replace function public.upsert_room(
  h uuid, room_id_value uuid, room_number_value text, floor_id_value uuid,
  type_id_value uuid, initial_status_value text, metadata_value jsonb, request_id_value text
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; row_value public.rooms%rowtype; cm jsonb; req text; nr text;
begin
  actor:=private.day13_require_room_manager(h);
  req:=nullif(trim(request_id_value),'');
  if req is null or length(req)<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  nr:=private.day13_normalize_room_number(room_number_value);
  if nr is null then raise exception 'Room number is required.'; end if;
  if initial_status_value is not null and initial_status_value not in ('available','cleaning','maintenance','out_of_order')
    then raise exception 'Room create/edit cannot directly set occupied status.'; end if;
  perform set_config('stayqr.day13_request_id',req,true);
  perform set_config('stayqr.day13_event_source','room_rpc',true);
  if room_id_value is null then
    insert into public.rooms(
      hotel_id,room_number,room_type_id,floor_id,status,is_active,updated_by,status_changed_by,metadata
    ) values(
      h,nr,type_id_value,floor_id_value,coalesce(initial_status_value,'available'),true,actor,actor,
      coalesce(metadata_value,'{}'::jsonb)||jsonb_build_object('create_request_id',req)
    ) returning * into row_value;
  else
    select * into row_value from public.rooms where hotel_id=h and id=room_id_value for update;
    if not found then raise exception 'Room was not found.'; end if;
    if not row_value.is_active then raise exception 'Archived room cannot be edited.'; end if;
    cm:=private.day13_room_commitments(h,room_id_value);
    if (floor_id_value is distinct from row_value.floor_id or type_id_value is distinct from row_value.room_type_id)
       and (((cm->>'active_stays')::int)>0 or ((cm->>'active_or_future_allocations')::int)>0)
    then raise exception 'Floor or room type cannot change while active/future commitments remain.'; end if;
    update public.rooms set room_number=nr,floor_id=floor_id_value,room_type_id=type_id_value,
      updated_by=actor,metadata=metadata||coalesce(metadata_value,'{}'::jsonb)||jsonb_build_object('update_request_id',req)
    where hotel_id=h and id=room_id_value returning * into row_value;
  end if;
  return jsonb_build_object('ok',true,'room',to_jsonb(row_value));
end;
$function$;

create or replace function public.transition_room_status(
  h uuid, room_id_value uuid, new_status_value text, reason_value text,
  source_value text, request_id_value text
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; row_value public.rooms%rowtype; cm jsonb; req text; allowed boolean; ev public.room_status_events%rowtype;
begin
  actor:=private.day13_require_room_manager(h);
  req:=nullif(trim(request_id_value),'');
  if req is null or length(req)<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  if new_status_value not in ('available','occupied','cleaning','maintenance','out_of_order') then raise exception 'Invalid room status.'; end if;
  select * into ev from public.room_status_events where hotel_id=h and request_id=req;
  if ev.id is not null then
    select * into row_value from public.rooms where hotel_id=h and id=ev.room_id;
    return jsonb_build_object('ok',true,'idempotent',true,'room',to_jsonb(row_value),'event',to_jsonb(ev));
  end if;
  select * into row_value from public.rooms where hotel_id=h and id=room_id_value for update;
  if not found then raise exception 'Room was not found.'; end if;
  if not row_value.is_active then raise exception 'Archived room status cannot change.'; end if;
  if row_value.status=new_status_value then return jsonb_build_object('ok',true,'idempotent',true,'room',to_jsonb(row_value)); end if;
  allowed:=case row_value.status
    when 'available' then new_status_value in ('occupied','cleaning','maintenance','out_of_order')
    when 'occupied' then new_status_value in ('cleaning','maintenance','out_of_order')
    when 'cleaning' then new_status_value in ('available','maintenance','out_of_order')
    when 'maintenance' then new_status_value in ('available','cleaning','out_of_order')
    when 'out_of_order' then new_status_value in ('available','cleaning','maintenance')
    else false end;
  if not allowed then raise exception 'Room status transition % -> % is not allowed.',row_value.status,new_status_value; end if;
  cm:=private.day13_room_commitments(h,room_id_value);
  if new_status_value='occupied' and ((cm->>'active_stays')::int)=0 then raise exception 'Occupied status requires an active guest stay.'; end if;
  if new_status_value='available' then
    if ((cm->>'active_stays')::int)>0 then raise exception 'Active guest stay prevents available status.'; end if;
    if ((cm->>'active_blocks')::int)>0 then raise exception 'Active room block prevents available status.'; end if;
    if ((cm->>'pending_housekeeping')::int)>0 then raise exception 'Pending housekeeping prevents available status.'; end if;
  end if;
  if new_status_value in ('maintenance','out_of_order') and ((cm->>'active_stays')::int)>0
    then raise exception 'Occupied room cannot enter maintenance/out-of-order through this RPC.'; end if;
  if new_status_value in ('maintenance','out_of_order') and nullif(trim(reason_value),'') is null
    then raise exception 'Maintenance/out-of-order status requires a reason.'; end if;
  perform set_config('stayqr.day13_request_id',req,true);
  perform set_config('stayqr.day13_event_source',case when source_value in ('room_rpc','checkin','checkout','housekeeping','maintenance') then source_value else 'room_rpc' end,true);
  perform set_config('stayqr.day13_status_reason',coalesce(trim(reason_value),''),true);
  update public.rooms set status=new_status_value,status_changed_at=now(),status_changed_by=actor,updated_by=actor,
    metadata=metadata||jsonb_build_object('last_status_reason',nullif(trim(reason_value),''),'last_status_request_id',req)
  where hotel_id=h and id=room_id_value returning * into row_value;
  select * into ev from public.room_status_events where hotel_id=h and request_id=req;
  return jsonb_build_object('ok',true,'idempotent',false,'room',to_jsonb(row_value),'event',to_jsonb(ev));
end;
$function$;

create or replace function public.archive_room(h uuid, room_id_value uuid, reason_value text, request_id_value text)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; row_value public.rooms%rowtype; cm jsonb; req text;
begin
  actor:=private.day13_require_room_manager(h);
  req:=nullif(trim(request_id_value),'');
  if req is null or length(req)<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  if nullif(trim(reason_value),'') is null then raise exception 'Archive reason is required.'; end if;
  select * into row_value from public.rooms where hotel_id=h and id=room_id_value for update;
  if not found then raise exception 'Room was not found.'; end if;
  if not row_value.is_active then return jsonb_build_object('ok',true,'idempotent',true,'room',to_jsonb(row_value)); end if;
  cm:=private.day13_room_commitments(h,room_id_value);
  if ((cm->>'active_stays')::int)>0 or ((cm->>'active_or_future_allocations')::int)>0 or ((cm->>'active_blocks')::int)>0
    then raise exception 'Room cannot be archived while active/future commitments remain.'; end if;
  perform set_config('stayqr.day13_request_id',req,true);
  perform set_config('stayqr.day13_event_source','archive_rpc',true);
  perform set_config('stayqr.day13_status_reason',trim(reason_value),true);
  update public.rooms set is_active=false,status='out_of_order',archived_at=now(),archived_by=actor,
    archive_reason=trim(reason_value),status_changed_at=now(),status_changed_by=actor,updated_by=actor,
    metadata=metadata||jsonb_build_object('archive_request_id',req,'last_status_reason',trim(reason_value))
  where hotel_id=h and id=room_id_value returning * into row_value;
  return jsonb_build_object('ok',true,'idempotent',false,'room',to_jsonb(row_value));
end;
$function$;

create or replace function public.import_rooms(
  h uuid, rows_value jsonb, source_name_value text, request_id_value text
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid; req text; batch public.room_import_batches%rowtype; n integer; dup integer; exist_count integer;
  rec record; floor_value uuid; type_value uuid; room_value uuid; inserted integer:=0;
begin
  actor:=private.day13_require_room_manager(h);
  req:=nullif(trim(request_id_value),'');
  if req is null or length(req)<8 then raise exception 'A request ID of at least eight characters is required.'; end if;
  select * into batch from public.room_import_batches where hotel_id=h and request_id=req;
  if batch.id is not null then
    return jsonb_build_object('ok',true,'idempotent',true,'batch',to_jsonb(batch),
      'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.row_number) from public.room_import_rows x where x.hotel_id=h and x.batch_id=batch.id),'[]'::jsonb));
  end if;
  if jsonb_typeof(rows_value)<>'array' then raise exception 'Import rows must be a JSON array.'; end if;
  n:=jsonb_array_length(rows_value);
  if n<1 or n>100 then raise exception 'Room import requires 1 to 100 rows.'; end if;
  select count(*) into dup from (
    select private.day13_normalize_room_number(e.value->>'room_number') nr
    from jsonb_array_elements(rows_value) e(value)
    group by private.day13_normalize_room_number(e.value->>'room_number')
    having count(*)>1 or private.day13_normalize_room_number(e.value->>'room_number') is null
  ) q;
  if dup>0 then raise exception 'Import contains blank or duplicate room numbers.'; end if;
  select count(*) into exist_count
  from jsonb_array_elements(rows_value) e(value)
  join public.rooms r on r.hotel_id=h and r.room_number=private.day13_normalize_room_number(e.value->>'room_number');
  if exist_count>0 then raise exception 'Import contains % room number(s) already present in the hotel.',exist_count; end if;

  insert into public.room_import_batches(hotel_id,request_id,requested_rows,source_name,requested_by,summary)
  values(h,req,n,nullif(trim(source_name_value),''),actor,jsonb_build_object('atomic',true))
  returning * into batch;
  perform set_config('stayqr.day13_event_source','import',true);

  for rec in
    select ordinality::int row_number,value payload
    from jsonb_array_elements(rows_value) with ordinality
  loop
    floor_value:=nullif(rec.payload->>'floor_id','')::uuid;
    if floor_value is null then
      select id into floor_value from public.floors
      where hotel_id=h and is_active and upper(code)=upper(trim(rec.payload->>'floor_code')) limit 1;
    end if;
    type_value:=nullif(rec.payload->>'room_type_id','')::uuid;
    if type_value is null then
      select id into type_value from public.room_types
      where hotel_id=h and is_active and upper(code)=upper(trim(rec.payload->>'room_type_code')) limit 1;
    end if;
    if floor_value is null then raise exception 'Import row % cannot resolve active floor.',rec.row_number; end if;
    if type_value is null then raise exception 'Import row % cannot resolve active room type.',rec.row_number; end if;
    if coalesce(nullif(rec.payload->>'status',''),'available') not in ('available','cleaning','maintenance','out_of_order')
      then raise exception 'Import row % has invalid initial status.',rec.row_number; end if;

    perform set_config('stayqr.day13_request_id',req||':row:'||rec.row_number::text,true);
    insert into public.rooms(hotel_id,room_number,room_type_id,floor_id,status,is_active,updated_by,status_changed_by,metadata)
    values(h,private.day13_normalize_room_number(rec.payload->>'room_number'),type_value,floor_value,
      coalesce(nullif(rec.payload->>'status',''),'available'),true,actor,actor,
      jsonb_build_object('import_batch_id',batch.id,'import_request_id',req,'source_payload',rec.payload))
    returning id into room_value;

    insert into public.room_import_rows(hotel_id,batch_id,row_number,room_id,room_number,floor_id,room_type_id,initial_status,source_payload)
    values(h,batch.id,rec.row_number,room_value,private.day13_normalize_room_number(rec.payload->>'room_number'),
      floor_value,type_value,coalesce(nullif(rec.payload->>'status',''),'available'),rec.payload);
    inserted:=inserted+1;
  end loop;

  update public.room_import_batches set status='completed',inserted_rows=inserted,completed_at=now(),
    summary=summary||jsonb_build_object('inserted_rows',inserted)
  where hotel_id=h and id=batch.id returning * into batch;

  return jsonb_build_object('ok',true,'idempotent',false,'batch',to_jsonb(batch),
    'rows',(select jsonb_agg(to_jsonb(x) order by x.row_number) from public.room_import_rows x where x.hotel_id=h and x.batch_id=batch.id));
end;
$function$;

create or replace function public.get_room_inventory_workspace(h uuid)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
begin
  if not private.user_has_any_permission(
    h,array['rooms.view','rooms.manage','housekeeping.view','housekeeping.manage','reservations.view','reservations.manage']::text[]
  ) then raise exception 'Room inventory access denied.'; end if;
  return jsonb_build_object(
    'floors',coalesce((select jsonb_agg(to_jsonb(f) order by f.sort_order,f.floor_number nulls last,f.name) from public.floors f where f.hotel_id=h),'[]'::jsonb),
    'room_types',coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order,t.name) from public.room_types t where t.hotel_id=h),'[]'::jsonb),
    'rooms',coalesce((
      select jsonb_agg(to_jsonb(r)||jsonb_build_object(
        'floor_name',f.name,'floor_code',f.code,'room_type_name',t.name,'room_type_code',t.code,
        'commitments',private.day13_room_commitments(h,r.id)
      ) order by f.sort_order,nullif(regexp_replace(r.room_number,'[^0-9]','','g'),'')::int nulls last,r.room_number)
      from public.rooms r join public.floors f on f.hotel_id=r.hotel_id and f.id=r.floor_id
      join public.room_types t on t.hotel_id=r.hotel_id and t.id=r.room_type_id where r.hotel_id=h
    ),'[]'::jsonb),
    'status_events',coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (
      select * from public.room_status_events where hotel_id=h order by occurred_at desc limit 200
    ) q),'[]'::jsonb),
    'imports',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select * from public.room_import_batches where hotel_id=h order by created_at desc limit 50
    ) q),'[]'::jsonb)
  );
end;
$function$;

create or replace function private.calendar_room_is_available(
  target_hotel_id uuid,target_room_id uuid,target_start_date date,target_end_date date,
  exclude_reservation_room_id uuid default null,exclude_room_block_id uuid default null
) returns boolean
language sql stable security definer set search_path=''
as $function$
  select target_hotel_id is not null and target_room_id is not null
    and target_start_date is not null and target_end_date is not null and target_end_date>target_start_date
    and exists(
      select 1 from public.rooms r
      join public.floors f on f.hotel_id=r.hotel_id and f.id=r.floor_id and f.is_active
      join public.room_types t on t.hotel_id=r.hotel_id and t.id=r.room_type_id and t.is_active
      where r.hotel_id=target_hotel_id and r.id=target_room_id and r.is_active
        and r.status not in ('maintenance','out_of_order')
    )
    and not exists(
      select 1 from public.room_inventory_allocations a
      where a.hotel_id=target_hotel_id and a.room_id=target_room_id and a.status='active'
        and a.stay_dates&&daterange(target_start_date,target_end_date,'[)')
        and (exclude_reservation_room_id is null or a.reservation_room_id is distinct from exclude_reservation_room_id)
        and (exclude_room_block_id is null or a.room_block_id is distinct from exclude_room_block_id)
    );
$function$;

create or replace function public.get_available_rooms(
  target_hotel_id uuid,target_arrival_date date,target_departure_date date,target_room_type_id uuid default null
) returns table(
  room_id uuid,room_number text,room_type_id uuid,room_type_name text,room_status text,
  max_adults integer,max_children integer,max_occupancy integer,standard_rate numeric,
  active_rate_plan_id uuid,active_rate_plan_name text
)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if not private.user_has_hotel_access(target_hotel_id) then raise exception 'Hotel access denied.'; end if;
  if target_arrival_date is null or target_departure_date is null or target_departure_date<=target_arrival_date
    then raise exception 'Departure date must be after arrival date.'; end if;
  if target_departure_date-target_arrival_date>365 then raise exception 'Availability searches are limited to 365 nights.'; end if;
  return query
  select r.id,r.room_number,t.id,t.name,r.status,t.max_adults,t.max_children,t.max_occupancy,
    coalesce(rp.base_rate,t.base_rate)::numeric,rp.id,rp.name
  from public.rooms r
  join public.floors f on f.id=r.floor_id and f.hotel_id=r.hotel_id and f.is_active
  join public.room_types t on t.id=r.room_type_id and t.hotel_id=r.hotel_id and t.is_active
  left join lateral(
    select p.* from public.rate_plans p where p.hotel_id=r.hotel_id and p.room_type_id=r.room_type_id and p.is_active
    order by p.priority,p.created_at limit 1
  ) rp on true
  join public.hotels h on h.id=r.hotel_id
  where r.hotel_id=target_hotel_id and r.is_active
    and (target_room_type_id is null or r.room_type_id=target_room_type_id)
    and r.status not in ('maintenance','out_of_order')
    and not(r.status='cleaning' and target_arrival_date<=(now() at time zone h.timezone)::date)
    and not exists(
      select 1 from public.room_inventory_allocations a
      where a.hotel_id=r.hotel_id and a.room_id=r.id and a.status='active'
        and a.stay_dates&&daterange(target_arrival_date,target_departure_date,'[)')
    )
  order by t.sort_order,nullif(regexp_replace(r.room_number,'[^0-9]','','g'),'')::int nulls last,r.room_number;
end;
$function$;

create or replace function public.get_reservation_available_rooms(
  target_hotel_id uuid,target_arrival_date date,target_departure_date date,
  target_room_type_id uuid default null,exclude_reservation_id uuid default null
) returns table(
  room_id uuid,room_number text,room_type_id uuid,room_type_name text,room_status text,
  max_adults integer,max_children integer,max_occupancy integer,standard_rate numeric,
  active_rate_plan_id uuid,active_rate_plan_name text
)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if not private.user_has_hotel_access(target_hotel_id) then raise exception 'Hotel access denied.'; end if;
  if target_arrival_date is null or target_departure_date is null or target_departure_date<=target_arrival_date
    then raise exception 'Departure date must be after arrival date.'; end if;
  if target_departure_date-target_arrival_date>365 then raise exception 'Availability searches are limited to 365 nights.'; end if;
  return query
  select r.id,r.room_number,t.id,t.name,r.status,t.max_adults,t.max_children,t.max_occupancy,
    coalesce(rp.base_rate,t.base_rate)::numeric,rp.id,rp.name
  from public.rooms r
  join public.floors f on f.id=r.floor_id and f.hotel_id=r.hotel_id and f.is_active
  join public.room_types t on t.id=r.room_type_id and t.hotel_id=r.hotel_id and t.is_active
  left join lateral(
    select p.* from public.rate_plans p where p.hotel_id=r.hotel_id and p.room_type_id=r.room_type_id and p.is_active
    order by p.priority,p.created_at limit 1
  ) rp on true
  join public.hotels h on h.id=r.hotel_id
  where r.hotel_id=target_hotel_id and r.is_active
    and (target_room_type_id is null or r.room_type_id=target_room_type_id)
    and r.status not in ('maintenance','out_of_order')
    and not(r.status='cleaning' and target_arrival_date<=(now() at time zone h.timezone)::date)
    and not exists(
      select 1 from public.room_inventory_allocations a
      where a.hotel_id=r.hotel_id and a.room_id=r.id and a.status='active'
        and a.stay_dates&&daterange(target_arrival_date,target_departure_date,'[)')
        and not(
          exclude_reservation_id is not null and a.allocation_type='reservation'
          and exists(select 1 from public.reservation_rooms x where x.id=a.reservation_room_id and x.hotel_id=target_hotel_id and x.reservation_id=exclude_reservation_id)
        )
    )
  order by t.sort_order,nullif(regexp_replace(r.room_number,'[^0-9]','','g'),'')::int nulls last,r.room_number;
end;
$function$;

create or replace function public.get_room_type_availability(
  target_hotel_id uuid,target_arrival_date date,target_departure_date date
) returns table(
  room_type_id uuid,room_type_name text,total_rooms bigint,available_rooms bigint,
  standard_rate numeric,active_rate_plan_id uuid,active_rate_plan_name text
)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if not private.user_has_hotel_access(target_hotel_id) then raise exception 'Hotel access denied.'; end if;
  if target_arrival_date is null or target_departure_date is null or target_departure_date<=target_arrival_date
    then raise exception 'Departure date must be after arrival date.'; end if;
  return query
  with av as(select * from public.get_available_rooms(target_hotel_id,target_arrival_date,target_departure_date,null))
  select t.id,t.name,count(r.id)::bigint,count(av.room_id)::bigint,coalesce(rp.base_rate,t.base_rate)::numeric,rp.id,rp.name
  from public.room_types t
  left join public.rooms r on r.hotel_id=t.hotel_id and r.room_type_id=t.id and r.is_active
    and exists(select 1 from public.floors f where f.hotel_id=r.hotel_id and f.id=r.floor_id and f.is_active)
  left join av on av.room_id=r.id
  left join lateral(
    select p.* from public.rate_plans p where p.hotel_id=t.hotel_id and p.room_type_id=t.id and p.is_active
    order by p.priority,p.created_at limit 1
  ) rp on true
  where t.hotel_id=target_hotel_id and t.is_active
  group by t.id,t.name,t.sort_order,t.base_rate,rp.id,rp.name,rp.base_rate
  order by t.sort_order,t.name;
end;
$function$;

revoke all on public.room_status_events,public.room_import_batches,public.room_import_rows from public,anon,authenticated;
grant select on public.room_status_events,public.room_import_batches,public.room_import_rows to authenticated;
grant all on public.room_status_events,public.room_import_batches,public.room_import_rows to service_role;

revoke all on function private.day13_require_room_manager(uuid) from public,anon,authenticated;
revoke all on function private.day13_normalize_room_number(text) from public,anon,authenticated;
revoke all on function private.day13_room_commitments(uuid,uuid) from public,anon,authenticated;
grant execute on function private.day13_require_room_manager(uuid),private.day13_normalize_room_number(text),private.day13_room_commitments(uuid,uuid) to service_role;

revoke all on function public.upsert_floor(uuid,uuid,text,text,integer,text,integer,boolean,text) from public,anon;
revoke all on function public.archive_floor(uuid,uuid,text,text) from public,anon;
revoke all on function public.upsert_room_type(uuid,uuid,text,text,text,integer,integer,integer,integer,numeric,numeric,numeric,integer,boolean,text) from public,anon;
revoke all on function public.archive_room_type(uuid,uuid,text,text) from public,anon;
revoke all on function public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text) from public,anon;
revoke all on function public.transition_room_status(uuid,uuid,text,text,text,text) from public,anon;
revoke all on function public.archive_room(uuid,uuid,text,text) from public,anon;
revoke all on function public.import_rooms(uuid,jsonb,text,text) from public,anon;
revoke all on function public.get_room_inventory_workspace(uuid) from public,anon;

grant execute on function public.upsert_floor(uuid,uuid,text,text,integer,text,integer,boolean,text) to authenticated,service_role;
grant execute on function public.archive_floor(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.upsert_room_type(uuid,uuid,text,text,text,integer,integer,integer,integer,numeric,numeric,numeric,integer,boolean,text) to authenticated,service_role;
grant execute on function public.archive_room_type(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.upsert_room(uuid,uuid,text,uuid,uuid,text,jsonb,text) to authenticated,service_role;
grant execute on function public.transition_room_status(uuid,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.archive_room(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.import_rooms(uuid,jsonb,text,text) to authenticated,service_role;
grant execute on function public.get_room_inventory_workspace(uuid) to authenticated,service_role;

comment on table public.room_status_events is 'Immutable Day 13 room status/archive history.';
comment on table public.room_import_batches is 'Atomic and idempotent bulk-room import evidence.';
comment on function public.import_rooms(uuid,jsonb,text,text) is 'Atomically imports 1–100 rooms; existing subscription room-limit trigger remains authoritative.';
comment on function public.get_available_rooms(uuid,date,date,uuid) is 'Excludes archived rooms/floors/types, maintenance/out-of-order, same-day cleaning, and allocated rooms.';

commit;
