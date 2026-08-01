-- StayQR Day 6 identity reconciliation and authorization verification
-- Run after migration 202607250012 using role postgres.

with tests(test_name, passed, details) as (
  values
    (
      '01_no_active_staff_without_auth',
      not exists (
        select 1 from public.staff
        where status in ('active', 'invited') and auth_user_id is null
      ),
      'Every active or invited staff profile is backed by a real Auth identity.'
    ),
    (
      '02_no_active_membership_without_auth',
      not exists (
        select 1 from public.hotel_users
        where status in ('active', 'invited') and user_id is null
      ),
      'Every active or invited compatibility membership is identity-backed.'
    ),
    (
      '03_linked_staff_auth_exists',
      not exists (
        select 1
        from public.staff s
        left join auth.users au on au.id = s.auth_user_id
        where s.auth_user_id is not null and au.id is null
      ),
      'No staff profile references a deleted Auth user.'
    ),
    (
      '04_linked_staff_email_matches_auth',
      not exists (
        select 1
        from public.staff s
        join auth.users au on au.id = s.auth_user_id
        where s.status in ('active', 'invited')
          and lower(s.email) <> lower(coalesce(au.email, ''))
      ),
      'Active and invited staff use the verified Auth email.'
    ),
    (
      '05_staff_membership_mirror_consistent',
      not exists (
        select 1
        from public.staff s
        left join public.hotel_users hu
          on hu.hotel_id = s.hotel_id
         and hu.user_id = s.auth_user_id
        where s.auth_user_id is not null
          and (
            hu.id is null
            or lower(hu.email) <> lower(s.email)
            or lower(replace(trim(hu.role), ' ', '_')) <>
               lower(replace(trim(s.role), ' ', '_'))
            or hu.status <> s.status
          )
      ),
      'hotel_users mirrors every linked staff identity, role and lifecycle state.'
    ),
    (
      '06_legacy_unlinked_profiles_quarantined',
      not exists (
        select 1 from public.staff
        where auth_user_id is null
          and (
            status <> 'inactive'
            or coalesce(identity_reconciliation_status, '') not in (
              'archived_unlinked', 'archived_missing_auth'
            )
          )
      ),
      'Legacy profiles remain preserved but cannot authenticate until invited.'
    ),
    (
      '07_active_identity_constraints',
      exists (
        select 1 from pg_constraint
        where conrelid = 'public.staff'::regclass
          and conname = 'staff_active_identity_required'
          and convalidated
      )
      and exists (
        select 1 from pg_constraint
        where conrelid = 'public.hotel_users'::regclass
          and conname = 'hotel_users_active_identity_required'
          and convalidated
      ),
      'Database constraints prevent active access without Auth mapping.'
    ),
    (
      '08_identity_event_ledger',
      to_regclass('public.staff_identity_events') is not null
      and coalesce((
        select relrowsecurity from pg_class
        where oid = 'public.staff_identity_events'::regclass
      ), false)
      and not has_table_privilege(
        'authenticated', 'public.staff_identity_events', 'INSERT'
      ),
      'Staff identity lifecycle events are durable, RLS protected and server-written.'
    ),
    (
      '09_staff_is_authoritative_access_source',
      position(
        'from public.hotel_users' in lower(
          pg_get_functiondef('private.user_has_hotel_access(uuid)'::regprocedure)
        )
      ) = 0
      and position(
        'from public.staff' in lower(
          pg_get_functiondef('private.user_has_hotel_access(uuid)'::regprocedure)
        )
      ) > 0,
      'Hotel access is resolved from authoritative staff identity, not a stale mirror.'
    ),
    (
      '10_staff_list_policy_is_permission_scoped',
      exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'staff'
          and policyname = 'stayqr_staff_select'
          and lower(coalesce(qual, '')) like '%staff.view%'
          and lower(coalesce(qual, '')) like '%auth_user_id%'
      ),
      'Staff can read their own identity; only staff.view can read the hotel list.'
    ),
    (
      '11_reservation_write_policy',
      exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'reservations'
          and policyname = 'stayqr_reservation_insert'
          and lower(coalesce(with_check, '')) like '%reservations.manage%'
      ),
      'Reservation writes are checked against reservations.manage.'
    ),
    (
      '12_payment_write_policy',
      exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'payments'
          and policyname = 'stayqr_tenant_insert'
          and lower(coalesce(with_check, '')) like '%payments.manage%'
      ),
      'Payment writes are checked against payments.manage.'
    ),
    (
      '13_invoice_write_policy',
      exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'invoices'
          and policyname = 'stayqr_tenant_insert'
          and lower(coalesce(with_check, '')) like '%invoices.manage%'
      ),
      'Invoice writes are checked against invoices.manage.'
    ),
    (
      '14_hotel_configuration_policy',
      exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'hotels'
          and policyname = 'stayqr_hotels_update'
          and lower(coalesce(qual, '')) like '%hotel.manage%'
          and lower(coalesce(with_check, '')) like '%hotel.manage%'
      ),
      'Hotel configuration changes require hotel.manage.'
    ),
    (
      '15_reception_permission_boundary',
      exists (
        select 1 from public.role_permissions
        where lower(role_name) = 'reception'
          and permission_key = 'reservations.manage'
      )
      and not exists (
        select 1 from public.role_permissions
        where lower(role_name) = 'reception'
          and permission_key in ('staff.manage', 'hotel.manage', 'invoices.manage')
      ),
      'Reception can operate reservations but cannot manage staff, hotel or invoices.'
    ),
    (
      '16_reconciliation_archive_preserved',
      to_regclass('private.day6_identity_reconciliation_archive_20260725')
        is not null,
      'All reconciled legacy identity rows have a private pre-change snapshot.'
    )
)
select test_name, passed, details
from tests
order by test_name;
