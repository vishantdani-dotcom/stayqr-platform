-- StayQR Day 6 final authentication, staff identity and permission gate
-- Run after Audit 033. Required result: 20 rows, every passed = true.

create temporary table if not exists day6_final_gate_results (
  test_name text primary key,
  passed boolean not null,
  details text not null
);

truncate table day6_final_gate_results;

do $$
declare
  context_row private.day6_final_acceptance_context_20260725%rowtype;
  reception_permission_count integer;
begin
  select *
  into context_row
  from private.day6_final_acceptance_context_20260725
  where context_key = 'day6-final';

  if context_row.context_key is null then
    raise exception 'Run Audit 033 before the Day 6 final gate.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    context_row.reception_auth_user_id::text,
    false
  );
  perform set_config('request.jwt.claim.role', 'authenticated', false);

  insert into day6_final_gate_results values
    (
      '01_reception_hotel_access',
      private.user_has_hotel_access(context_row.hotel_id),
      'The active Reception identity can access only its assigned hotel.'
    ),
    (
      '02_reception_reservation_permission',
      private.user_has_permission(context_row.hotel_id, 'reservations.manage'),
      'Reception can perform its allowed reservation operations.'
    ),
    (
      '03_reception_staff_management_denied',
      not private.user_has_permission(context_row.hotel_id, 'staff.manage'),
      'Reception cannot invite, edit, suspend or activate staff.'
    ),
    (
      '04_reception_hotel_management_denied',
      not private.user_has_permission(context_row.hotel_id, 'hotel.manage'),
      'Reception cannot change hotel configuration.'
    ),
    (
      '05_reception_invoice_management_denied',
      not private.user_has_permission(context_row.hotel_id, 'invoices.manage'),
      'Reception may view allowed invoices but cannot manage invoice records.'
    ),
    (
      '06_reception_other_hotel_denied',
      context_row.other_hotel_id is null
      or not private.user_has_hotel_access(context_row.other_hotel_id),
      'The Reception identity has no cross-hotel access.'
    );

  select count(*)
  into reception_permission_count
  from public.get_my_hotel_permissions(context_row.hotel_id);

  insert into day6_final_gate_results values
    (
      '07_reception_permission_set',
      reception_permission_count = 15,
      'Reception receives the exact canonical 15-permission set.'
    );

  perform set_config(
    'request.jwt.claim.sub',
    context_row.platform_admin_user_id::text,
    false
  );

  insert into day6_final_gate_results values
    (
      '08_platform_admin_staff_management',
      private.user_has_permission(context_row.hotel_id, 'staff.manage'),
      'The active Platform Admin can manage staff in the selected hotel.'
    ),
    (
      '09_platform_admin_other_hotel_access',
      context_row.other_hotel_id is null
      or private.user_has_hotel_access(context_row.other_hotel_id),
      'The Platform Admin retains controlled multi-property access.'
    );
end
$$;

insert into day6_final_gate_results values
  (
    '10_test_identity_exactly_once',
    (
      select count(*) = 1
      from public.staff s
      join private.day6_final_acceptance_context_20260725 context
        on context.reception_staff_id = s.id
      where context.context_key = 'day6-final'
    ),
    'The controlled Reception identity exists exactly once in staff.'
  ),
  (
    '11_auth_identity_active_and_verified',
    exists (
      select 1
      from private.day6_final_acceptance_context_20260725 context
      join auth.users au on au.id = context.reception_auth_user_id
      where context.context_key = 'day6-final'
        and au.email_confirmed_at is not null
        and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
    ),
    'The controlled Reception Auth identity is verified, active and unbanned.'
  ),
  (
    '12_staff_membership_single_mirror',
    (
      select count(*) = 1
      from private.day6_final_acceptance_context_20260725 context
      join public.hotel_users hu
        on hu.hotel_id = context.hotel_id
       and hu.user_id = context.reception_auth_user_id
      where context.context_key = 'day6-final'
        and hu.status = 'active'
        and lower(replace(trim(hu.role), ' ', '_')) = 'reception'
    ),
    'Exactly one active compatibility membership mirrors the Reception staff row.'
  ),
  (
    '13_no_active_unlinked_identity',
    not exists (
      select 1 from public.staff
      where status in ('active', 'invited') and auth_user_id is null
    )
    and not exists (
      select 1 from public.hotel_users
      where status in ('active', 'invited') and user_id is null
    ),
    'No active or invited access exists without a real Auth identity.'
  ),
  (
    '14_no_duplicate_hotel_identity',
    not exists (
      select hotel_id, auth_user_id
      from public.staff
      where auth_user_id is not null
      group by hotel_id, auth_user_id
      having count(*) > 1
    )
    and not exists (
      select hotel_id, user_id
      from public.hotel_users
      where user_id is not null
      group by hotel_id, user_id
      having count(*) > 1
    ),
    'No duplicate staff or membership identity exists within a hotel.'
  ),
  (
    '15_verified_email_consistency',
    not exists (
      select 1
      from public.staff s
      join auth.users au on au.id = s.auth_user_id
      where s.status in ('active', 'invited')
        and lower(s.email) <> lower(coalesce(au.email, ''))
    ),
    'Every active staff email matches its verified Supabase Auth identity.'
  ),
  (
    '16_staff_membership_consistency',
    not exists (
      select 1
      from public.staff s
      left join public.hotel_users hu
        on hu.hotel_id = s.hotel_id
       and hu.user_id = s.auth_user_id
      where s.auth_user_id is not null
        and (
          hu.id is null
          or hu.status <> s.status
          or lower(replace(trim(hu.role), ' ', '_')) <>
             lower(replace(trim(s.role), ' ', '_'))
        )
    ),
    'The authoritative staff lifecycle and compatibility membership cannot drift.'
  ),
  (
    '17_identity_event_trace',
    exists (
      select 1
      from private.day6_final_acceptance_context_20260725 context
      join public.staff_identity_events event
        on event.staff_id = context.reception_staff_id
      where context.context_key = 'day6-final'
        and event.event_type in ('reconciled', 'invited', 'linked', 'activated')
    ),
    'The controlled identity has a durable server-side lifecycle event.'
  ),
  (
    '18_direct_identity_writes_blocked',
    not has_table_privilege('authenticated', 'public.staff', 'INSERT')
    and not has_table_privilege('authenticated', 'public.staff', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.staff', 'DELETE')
    and not has_table_privilege('authenticated', 'public.hotel_users', 'INSERT')
    and not has_table_privilege('authenticated', 'public.hotel_users', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.hotel_users', 'DELETE'),
    'Browser clients cannot bypass the trusted staff identity workflow.'
  ),
  (
    '19_action_level_rls_installed',
    exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'reservations'
        and policyname = 'stayqr_reservation_insert'
        and lower(coalesce(with_check, '')) like '%reservations.manage%'
    )
    and exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'invoices'
        and policyname = 'stayqr_tenant_insert'
        and lower(coalesce(with_check, '')) like '%invoices.manage%'
    )
    and exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'staff'
        and policyname = 'stayqr_staff_select'
        and lower(coalesce(qual, '')) like '%staff.view%'
    ),
    'Sensitive database actions are protected by the canonical permission matrix.'
  ),
  (
    '20_identity_reconciliation_complete',
    to_regclass('private.day6_identity_reconciliation_archive_20260725') is not null
    and not exists (
      select 1
      from public.staff
      where auth_user_id is null
        and status <> 'inactive'
    ),
    'Legacy identities are linked or preserved as inactive archived profiles.'
  )
on conflict (test_name) do update
set passed = excluded.passed, details = excluded.details;

select test_name, passed, details
from day6_final_gate_results
order by test_name;
