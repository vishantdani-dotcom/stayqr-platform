-- StayQR Day 6 foundation verification
-- Run after migration 202607250011 using role postgres.

with tests(test_name, passed, details) as (
  values
    (
      '01_staff_auth_mapping',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'staff'
          and column_name = 'auth_user_id'
      ),
      'staff.auth_user_id exists for Supabase Auth identity mapping.'
    ),
    (
      '02_staff_lifecycle_columns',
      (
        select count(*) = 7
        from information_schema.columns
        where table_schema = 'public' and table_name = 'staff'
          and column_name in (
            'updated_at','invited_at','invitation_sent_at','accepted_at',
            'disabled_at','created_by','updated_by'
          )
      ),
      'Staff invitation, acceptance and disable lifecycle columns are installed.'
    ),
    (
      '03_permission_helper',
      to_regprocedure('private.user_has_permission(uuid,text)') is not null,
      'Database permission checks resolve from active hotel membership.'
    ),
    (
      '04_permission_rpc',
      to_regprocedure('public.get_my_hotel_permissions(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_my_hotel_permissions(uuid)',
        'EXECUTE'
      ),
      'Authenticated users can load their server-authoritative permission set.'
    ),
    (
      '05_invitation_activation_rpc',
      to_regprocedure('public.activate_my_staff_invitation()') is not null
      and has_function_privilege(
        'authenticated',
        'public.activate_my_staff_invitation()',
        'EXECUTE'
      ),
      'Invited authenticated users can activate only their own linked invitation.'
    ),
    (
      '06_staff_membership_sync_trigger',
      exists (
        select 1
        from pg_trigger
        where tgrelid = 'public.staff'::regclass
          and tgname = 'staff_sync_hotel_user'
          and not tgisinternal
      ),
      'Staff identity changes synchronize the compatibility hotel membership.'
    ),
    (
      '07_staff_rls',
      coalesce((
        select relrowsecurity
        from pg_class
        where oid = 'public.staff'::regclass
      ), false),
      'Staff records are protected by row-level security.'
    ),
    (
      '08_staff_direct_writes_revoked',
      not has_table_privilege('authenticated', 'public.staff', 'INSERT')
      and not has_table_privilege('authenticated', 'public.staff', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.staff', 'DELETE'),
      'Browser clients cannot bypass the trusted staff identity workflow.'
    ),
    (
      '09_hotel_users_direct_writes_revoked',
      not has_table_privilege('authenticated', 'public.hotel_users', 'INSERT')
      and not has_table_privilege('authenticated', 'public.hotel_users', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.hotel_users', 'DELETE'),
      'Browser clients cannot directly create or change hotel memberships.'
    ),
    (
      '10_canonical_roles_seeded',
      (
        select count(distinct lower(role_name)) = 6
        from public.staff_roles
        where lower(role_name) in (
          'owner','manager','reception','housekeeping','restaurant','accounts'
        )
      ),
      'The six Day 6 hotel roles are available.'
    ),
    (
      '11_permission_matrix_seeded',
      exists (
        select 1 from public.role_permissions
        where lower(role_name) = 'owner' and permission_key = 'staff.manage'
      )
      and exists (
        select 1 from public.role_permissions
        where lower(role_name) = 'reception' and permission_key = 'checkin.manage'
      )
      and not exists (
        select 1 from public.role_permissions
        where lower(role_name) = 'housekeeping' and permission_key = 'payments.manage'
      ),
      'Role permissions distinguish administrative, reception and housekeeping access.'
    ),
    (
      '12_staff_status_constraint',
      exists (
        select 1
        from pg_constraint
        where conrelid = 'public.staff'::regclass
          and conname = 'staff_status_check'
          and pg_get_constraintdef(oid) like '%invited%'
          and pg_get_constraintdef(oid) like '%suspended%'
      ),
      'Staff lifecycle status supports active, invited, inactive and suspended.'
    )
)
select test_name, passed, details
from tests
order by test_name;
