begin;

create temporary table postlaunch_batch2_acceptance (
  gate_no integer primary key,
  gate_name text not null,
  passed boolean not null,
  evidence text not null
) on commit drop;

insert into postlaunch_batch2_acceptance values
  (1, 'staff avatar column exists',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'staff' and column_name = 'avatar_path'
    ),
    'public.staff.avatar_path'),
  (2, 'staff avatar bucket is private',
    exists (
      select 1 from storage.buckets
      where id = 'staff-avatars' and public is false and file_size_limit = 5242880
    ),
    'private 5 MB staff-avatars bucket'),
  (3, 'staff avatar MIME types are constrained',
    exists (
      select 1 from storage.buckets
      where id = 'staff-avatars'
        and allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']::text[]
    ),
    'jpeg/png/webp only'),
  (4, 'staff avatar policies are complete',
    (
      select count(*) = 4
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname like 'stayqr_staff_avatars_%'
    ),
    'select/insert/update/delete policies'),
  (5, 'staff profile RPC exists',
    to_regprocedure('public.update_my_staff_profile(uuid,text,text,text)') is not null,
    'tenant-explicit self-profile RPC'),
  (6, 'staff profile RPC is authenticated only',
    has_function_privilege('authenticated', 'public.update_my_staff_profile(uuid,text,text,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.update_my_staff_profile(uuid,text,text,text)', 'EXECUTE'),
    'authenticated execute; anon denied'),
  (7, 'platform metrics RPC exists',
    to_regprocedure('public.get_postlaunch_batch2_platform_metrics()') is not null,
    'platform metrics RPC'),
  (8, 'platform metrics RPC is authenticated only',
    has_function_privilege('authenticated', 'public.get_postlaunch_batch2_platform_metrics()', 'EXECUTE')
      and not has_function_privilege('anon', 'public.get_postlaunch_batch2_platform_metrics()', 'EXECUTE'),
    'authenticated execute; anon denied');

select gate_no, gate_name, passed, evidence
from postlaunch_batch2_acceptance
order by gate_no;

do $$
declare
  failed_count integer;
begin
  select count(*) into failed_count
  from postlaunch_batch2_acceptance
  where not passed;

  if failed_count <> 0 then
    raise exception 'POSTLAUNCH_BATCH2_DATABASE_ACCEPTANCE: FAIL (% failed)', failed_count;
  end if;

  raise notice 'POSTLAUNCH_BATCH2_DATABASE_ACCEPTANCE: PASS (8/8)';
end;
$$;

rollback;
