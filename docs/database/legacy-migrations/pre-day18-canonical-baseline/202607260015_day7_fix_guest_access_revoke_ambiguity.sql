-- ============================================================================
-- StayQR v1.0
-- Day 7 Migration 015
-- Fix: guest access revocation RPC ambiguous revocation_reason reference
--
-- Root cause:
--   public.revoke_guest_access_token(...) has an input parameter named
--   revocation_reason and updates a table column with the same name.
--   PostgreSQL therefore raises:
--     42702: column reference "revocation_reason" is ambiguous
--
-- Repair:
--   Keep the public RPC signature and named argument unchanged for the
--   frontend, but reference the third input parameter positionally as $3.
--
-- Run once in Supabase SQL Editor with role postgres.
-- Safe: replaces one function only; no guest token is changed by this migration.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607260015:fix-guest-access-revoke-ambiguity')
);

create or replace function public.revoke_guest_access_token(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  revocation_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_count integer;
begin
  if not private.user_has_permission(target_hotel_id, 'hotel.manage') then
    raise exception 'You do not have permission to revoke guest access.';
  end if;

  if not exists (
    select 1
    from public.guest_sessions gs
    where gs.id = target_guest_session_id
      and gs.hotel_id = target_hotel_id
  ) then
    raise exception 'The selected stay does not belong to this hotel.';
  end if;

  update public.guest_access_tokens
  set status = 'revoked',
      revoked_at = coalesce(revoked_at, now()),
      revoked_by = auth.uid(),
      revocation_reason = coalesce(
        nullif(trim($3), ''),
        'Manual guest access revocation'
      ),
      updated_at = now()
  where hotel_id = target_hotel_id
    and guest_session_id = target_guest_session_id
    and status = 'active';

  get diagnostics affected_count = row_count;

  return jsonb_build_object(
    'result', 'GUEST ACCESS REVOKED',
    'revoked_tokens', affected_count
  );
end;
$$;

revoke all on function public.revoke_guest_access_token(uuid,uuid,text)
from public, anon;

grant execute on function public.revoke_guest_access_token(uuid,uuid,text)
to authenticated;

comment on function public.revoke_guest_access_token(uuid,uuid,text) is
  'Hotel-scoped manual guest-access revocation. Uses positional parameter reference to avoid column-name ambiguity.';

commit;
