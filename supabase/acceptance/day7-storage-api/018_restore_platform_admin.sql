-- ============================================================================
-- StayQR v1.0
-- Day 7 SQL 018 — Restore Platform Admin After Storage API Isolation
--
-- PURPOSE
-- Restores the Platform Admin, staff and compatibility hotel membership state
-- snapshotted by SQL 017 after the browser reports:
--   isolation-complete / 20 of 20 passed
--
-- IMPORTANT
-- - Run this before clicking "3. Finalize & Clean Up" in the browser.
-- - The browser's Storage evidence remains in localStorage and is not changed.
-- - SQL 019 will remove the temporary database audit context and helper after
--   final evidence has been downloaded.
--
-- Run once in Supabase SQL Editor with role: postgres.
-- Expected: one row and every boolean value = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:day7:storage-api-audit:sql018:20260727')
);

do $restore_actor$
declare
  context_row private.day7_storage_api_audit_context_20260727%rowtype;
  admin_snapshot public.platform_admins%rowtype;
  staff_snapshot public.staff%rowtype;
  membership_snapshot public.hotel_users%rowtype;
  snapshot_item jsonb;
  snapshot_staff_ids uuid[] := array[]::uuid[];
  snapshot_membership_ids uuid[] := array[]::uuid[];
begin
  select *
  into context_row
  from private.day7_storage_api_audit_context_20260727
  where context_key = 'day7-storage-api'
  for update;

  if not found then
    raise exception
      'SQL 018 cannot continue: SQL 017 audit context was not found.';
  end if;

  if context_row.phase <> 'owner-active' then
    raise exception
      'SQL 018 expected phase owner-active, but found %. Do not rerun blindly.',
      context_row.phase;
  end if;

  -- Restore the Platform Admin row from its SQL 017 snapshot.
  select *
  into admin_snapshot
  from jsonb_populate_record(
    null::public.platform_admins,
    context_row.platform_admin_snapshot
  );

  update public.platform_admins pa
  set
    display_name = admin_snapshot.display_name,
    status = admin_snapshot.status,
    updated_at = now()
  where pa.user_id = context_row.actor_user_id;

  if not found then
    insert into public.platform_admins (
      user_id,
      display_name,
      status,
      created_at,
      updated_at
    ) values (
      admin_snapshot.user_id,
      admin_snapshot.display_name,
      admin_snapshot.status,
      coalesce(admin_snapshot.created_at, now()),
      now()
    );
  end if;

  -- Restore every snapshotted authoritative staff profile. Updating staff also
  -- resynchronizes the compatibility hotel_users mirror through the locked
  -- Day 6 trigger.
  for snapshot_item in
    select value
    from jsonb_array_elements(context_row.staff_snapshots)
  loop
    select *
    into staff_snapshot
    from jsonb_populate_record(null::public.staff, snapshot_item);

    snapshot_staff_ids := array_append(snapshot_staff_ids, staff_snapshot.id);

    update public.staff s
    set
      hotel_id = staff_snapshot.hotel_id,
      full_name = staff_snapshot.full_name,
      email = staff_snapshot.email,
      phone = staff_snapshot.phone,
      role = staff_snapshot.role,
      status = staff_snapshot.status,
      auth_user_id = staff_snapshot.auth_user_id,
      invited_at = staff_snapshot.invited_at,
      invitation_sent_at = staff_snapshot.invitation_sent_at,
      accepted_at = staff_snapshot.accepted_at,
      disabled_at = staff_snapshot.disabled_at,
      created_by = staff_snapshot.created_by,
      updated_by = staff_snapshot.updated_by,
      identity_reconciliation_status =
        staff_snapshot.identity_reconciliation_status,
      identity_reconciliation_note =
        staff_snapshot.identity_reconciliation_note,
      identity_reconciled_at =
        staff_snapshot.identity_reconciled_at,
      updated_at = now()
    where s.id = staff_snapshot.id;

    if not found then
      raise exception
        'SQL 018 cannot restore missing staff snapshot row %.',
        staff_snapshot.id;
    end if;
  end loop;

  -- Remove only audit-created compatibility memberships that did not exist in
  -- the SQL 017 snapshot. Normally this deletes zero rows.
  for snapshot_item in
    select value
    from jsonb_array_elements(context_row.hotel_user_snapshots)
  loop
    select *
    into membership_snapshot
    from jsonb_populate_record(null::public.hotel_users, snapshot_item);

    snapshot_membership_ids :=
      array_append(snapshot_membership_ids, membership_snapshot.id);
  end loop;

  if cardinality(snapshot_membership_ids) > 0 then
    delete from public.hotel_users hu
    where hu.user_id = context_row.actor_user_id
      and not (hu.id = any(snapshot_membership_ids));
  else
    delete from public.hotel_users hu
    where hu.user_id = context_row.actor_user_id;
  end if;

  -- Restore all original compatibility membership values.
  for snapshot_item in
    select value
    from jsonb_array_elements(context_row.hotel_user_snapshots)
  loop
    select *
    into membership_snapshot
    from jsonb_populate_record(null::public.hotel_users, snapshot_item);

    update public.hotel_users hu
    set
      hotel_id = membership_snapshot.hotel_id,
      full_name = membership_snapshot.full_name,
      email = membership_snapshot.email,
      role = membership_snapshot.role,
      user_id = membership_snapshot.user_id,
      status = membership_snapshot.status,
      invited_at = membership_snapshot.invited_at,
      accepted_at = membership_snapshot.accepted_at,
      disabled_at = membership_snapshot.disabled_at,
      identity_reconciliation_status =
        membership_snapshot.identity_reconciliation_status,
      identity_reconciliation_note =
        membership_snapshot.identity_reconciliation_note,
      identity_reconciled_at =
        membership_snapshot.identity_reconciled_at,
      updated_at = now()
    where hu.id = membership_snapshot.id;

    if not found then
      insert into public.hotel_users (
        id,
        hotel_id,
        full_name,
        email,
        role,
        user_id,
        status,
        created_at,
        updated_at,
        invited_at,
        accepted_at,
        disabled_at,
        identity_reconciliation_status,
        identity_reconciliation_note,
        identity_reconciled_at
      ) values (
        membership_snapshot.id,
        membership_snapshot.hotel_id,
        membership_snapshot.full_name,
        membership_snapshot.email,
        membership_snapshot.role,
        membership_snapshot.user_id,
        membership_snapshot.status,
        coalesce(membership_snapshot.created_at, now()),
        now(),
        membership_snapshot.invited_at,
        membership_snapshot.accepted_at,
        membership_snapshot.disabled_at,
        membership_snapshot.identity_reconciliation_status,
        membership_snapshot.identity_reconciliation_note,
        membership_snapshot.identity_reconciled_at
      );
    end if;
  end loop;

  update private.day7_storage_api_audit_context_20260727
  set
    phase = 'isolation-complete',
    updated_at = now()
  where context_key = 'day7-storage-api';
end;
$restore_actor$;

commit;

with context as (
  select *
  from private.day7_storage_api_audit_context_20260727
  where context_key = 'day7-storage-api'
),
snapshot_staff as (
  select *
  from context,
       jsonb_to_recordset(context.staff_snapshots)
       as snap(
         id uuid,
         hotel_id uuid,
         role text,
         status text,
         auth_user_id uuid,
         disabled_at timestamptz
       )
),
snapshot_memberships as (
  select *
  from context,
       jsonb_to_recordset(context.hotel_user_snapshots)
       as snap(
         id uuid,
         hotel_id uuid,
         role text,
         status text,
         user_id uuid,
         disabled_at timestamptz
       )
)
select
  context.phase,
  context.actor_email,
  exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = context.actor_user_id
      and pa.status =
        (context.platform_admin_snapshot ->> 'status')
  ) as platform_admin_restored,
  not exists (
    select 1
    from snapshot_staff snap
    left join public.staff s on s.id = snap.id
    where s.id is null
       or s.hotel_id is distinct from snap.hotel_id
       or s.role::text is distinct from snap.role
       or s.status is distinct from snap.status
       or s.auth_user_id is distinct from snap.auth_user_id
       or s.disabled_at is distinct from snap.disabled_at
  ) as staff_snapshot_restored,
  not exists (
    select 1
    from snapshot_memberships snap
    left join public.hotel_users hu on hu.id = snap.id
    where hu.id is null
       or hu.hotel_id is distinct from snap.hotel_id
       or hu.role::text is distinct from snap.role
       or hu.status is distinct from snap.status
       or hu.user_id is distinct from snap.user_id
       or hu.disabled_at is distinct from snap.disabled_at
  ) as hotel_memberships_restored,
  not exists (
    select 1
    from public.staff s
    where s.auth_user_id = context.actor_user_id
      and s.status = 'active'
      and not exists (
        select 1
        from snapshot_staff snap
        where snap.id = s.id
          and snap.status = 'active'
      )
  ) as no_temporary_active_staff_access
from context;
