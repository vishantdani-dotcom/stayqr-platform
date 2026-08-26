-- StayQR post-launch Batch B: platform visibility, staff self-profile and private avatar storage.
-- Staging first. This migration does not modify the locked Day 20 migration sequence.

alter table public.staff
  add column if not exists avatar_path text;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'staff-avatars',
  'staff-avatars',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists stayqr_staff_avatars_select on storage.objects;
create policy stayqr_staff_avatars_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'staff-avatars'
  and private.user_has_hotel_access(private.storage_object_hotel_id(name))
  and split_part(name, '/', 2) = (select auth.uid())::text
);

drop policy if exists stayqr_staff_avatars_insert on storage.objects;
create policy stayqr_staff_avatars_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'staff-avatars'
  and private.user_has_hotel_access(private.storage_object_hotel_id(name))
  and split_part(name, '/', 2) = (select auth.uid())::text
);

drop policy if exists stayqr_staff_avatars_update on storage.objects;
create policy stayqr_staff_avatars_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'staff-avatars'
  and private.user_has_hotel_access(private.storage_object_hotel_id(name))
  and split_part(name, '/', 2) = (select auth.uid())::text
)
with check (
  bucket_id = 'staff-avatars'
  and private.user_has_hotel_access(private.storage_object_hotel_id(name))
  and split_part(name, '/', 2) = (select auth.uid())::text
);

drop policy if exists stayqr_staff_avatars_delete on storage.objects;
create policy stayqr_staff_avatars_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'staff-avatars'
  and private.user_has_hotel_access(private.storage_object_hotel_id(name))
  and split_part(name, '/', 2) = (select auth.uid())::text
);

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
begin
  if v_user_id is null then
    raise exception 'Authentication is required.';
  end if;

  select s.*
    into v_staff
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

  update public.staff
  set full_name = v_full_name,
      phone = v_phone,
      avatar_path = p_avatar_path,
      updated_at = now()
  where id = v_staff.id;

  return jsonb_build_object(
    'id', v_staff.id,
    'hotel_id', p_hotel_id,
    'full_name', v_full_name,
    'phone', v_phone,
    'avatar_path', p_avatar_path
  );
end;
$$;

revoke all on function public.update_my_staff_profile(uuid, text, text, text) from public;
grant execute on function public.update_my_staff_profile(uuid, text, text, text) to authenticated;

create or replace function public.get_postlaunch_batch2_platform_metrics()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_admin() then
    raise exception 'Platform administrator access is required.';
  end if;

  return jsonb_build_object(
    'total_hotels', (select count(*) from public.hotels),
    'active_hotels', (select count(*) from public.hotels where status = 'active'),
    'total_guests', (select count(*) from public.guests),
    'active_stays', (select count(*) from public.guest_sessions where status = 'active'),
    'document_scans', (select count(*) from public.guest_documents where deleted_at is null),
    'reservations', (select count(*) from public.reservations),
    'rooms', (select count(*) from public.rooms where is_active is true),
    'staff', (select count(*) from public.staff)
  );
end;
$$;

revoke all on function public.get_postlaunch_batch2_platform_metrics() from public;
grant execute on function public.get_postlaunch_batch2_platform_metrics() to authenticated;
