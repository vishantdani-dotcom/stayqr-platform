begin;

-- StayQR Front Desk Check-in Print Pack REV1
-- Scope: add an explicit immutable "print" event for sensitive guest documents.
-- No RLS, storage policy, notification, QR, billing, Restaurant, Housekeeping,
-- Dashboard, Guest Guide, or other product behavior is changed.

-- ---------------------------------------------------------------------------
-- 1. Extend the immutable audit action dictionary.
-- ---------------------------------------------------------------------------
alter table public.guest_document_access_audit
  drop constraint if exists guest_document_access_action_check;

alter table public.guest_document_access_audit
  add constraint guest_document_access_action_check
  check (action in (
    'view', 'download', 'print', 'review', 'delete', 'retention_purge'
  ));

-- ---------------------------------------------------------------------------
-- 2. Preserve the accepted sensitive-KYC permission boundary and add "print".
-- ---------------------------------------------------------------------------
create or replace function public.audit_guest_document_access(
  target_hotel_id uuid,
  target_document_id uuid,
  target_action text,
  target_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  doc public.guest_documents%rowtype;
  audit_id uuid;
  action_value text := lower(trim(coalesce(target_action,'')));
begin
  if actor_id is null then raise exception 'Authentication is required.'; end if;
  if not private.user_has_any_permission(
    target_hotel_id,
    array['guests.manage','checkin.manage','checkout.manage']::text[]
  ) then
    raise exception 'Private KYC access denied.';
  end if;
  if action_value not in ('view','download','print','review','delete','retention_purge') then
    raise exception 'Unsupported document access action.';
  end if;

  select * into doc
  from public.guest_documents gd
  where gd.hotel_id=target_hotel_id
    and gd.id=target_document_id
    and gd.deleted_at is null;

  if not found then raise exception 'Guest document not found.'; end if;

  insert into public.guest_document_access_audit(
    hotel_id,
    guest_id,
    guest_document_id,
    actor_user_id,
    action,
    reason
  ) values (
    target_hotel_id,
    doc.guest_id,
    doc.id,
    actor_id,
    action_value,
    nullif(trim(target_reason),'')
  )
  returning id into audit_id;

  return jsonb_build_object(
    'ok', true,
    'audit_id', audit_id,
    'storage_bucket', doc.storage_bucket,
    'storage_path', doc.storage_path
  );
end;
$$;

revoke all on function public.audit_guest_document_access(uuid,uuid,text,text)
from public, anon;

grant execute on function public.audit_guest_document_access(uuid,uuid,text,text)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Acceptance gates.
-- ---------------------------------------------------------------------------
do $acceptance$
declare
  constraint_definition text;
begin
  select pg_get_constraintdef(oid)
  into constraint_definition
  from pg_constraint
  where conname = 'guest_document_access_action_check'
    and conrelid = 'public.guest_document_access_audit'::regclass;

  if constraint_definition is null or constraint_definition not like '%print%' then
    raise exception 'Migration 120 acceptance failed: print audit action is not allowed.';
  end if;

  if to_regprocedure('public.audit_guest_document_access(uuid,uuid,text,text)') is null then
    raise exception 'Migration 120 acceptance failed: audit_guest_document_access is missing.';
  end if;

  if not has_function_privilege('authenticated', 'public.audit_guest_document_access(uuid,uuid,text,text)', 'EXECUTE') then
    raise exception 'Migration 120 acceptance failed: authenticated execute grant is missing.';
  end if;
end;
$acceptance$;

commit;

select jsonb_build_object(
  'status', 'CHECKIN_PRINT_PACK_AUDIT_REV1_PASSED',
  'print_action_allowed', exists(
    select 1
    from pg_constraint
    where conname='guest_document_access_action_check'
      and conrelid='public.guest_document_access_audit'::regclass
      and pg_get_constraintdef(oid) like '%print%'
  ),
  'audit_rpc_present', to_regprocedure('public.audit_guest_document_access(uuid,uuid,text,text)') is not null,
  'authenticated_execute', has_function_privilege('authenticated','public.audit_guest_document_access(uuid,uuid,text,text)','EXECUTE')
) as final_acceptance;
