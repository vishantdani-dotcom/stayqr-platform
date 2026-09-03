-- Code rollback only. Do not remove approved historical discount evidence.
-- Supplied for explicit rollback approval; not part of the normal rollout.
begin;
set local lock_timeout = '10s';
do $rollback$
declare
  target_oid oid := 'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure;
  definition text;
  original_acl aclitem[];
  original_owner oid;
  original_config text[];
  start_at integer;
  end_at integer;
  marker text;
  anchor text;
begin
  select pg_get_functiondef(oid), proacl, proowner, proconfig into definition, original_acl, original_owner, original_config
    from pg_proc where oid = target_oid and prosecdef;
  if definition is null then raise exception 'Checkout security contract missing.'; end if;
  if position('PILOT_CHECKOUT_FOLIO_CONSISTENCY_REV1' in definition) = 0 then
    raise exception 'Expected correction not found; no rollback applied.';
  end if;
  for marker, anchor in select * from (values
    ('  -- PILOT_CHECKOUT_FOLIO_CONSISTENCY_REV1', '  created_invoice_number := format('),
    ('  -- The invoice claims no pending amount: prove the live ledger agrees.', '  update public.guest_sessions')
  ) as blocks(marker, anchor) loop
    if (length(definition) - length(replace(definition, marker, ''))) / length(marker) <> 1 then
      raise exception 'Unknown rollback source shape.';
    end if;
    start_at := position(marker in definition);
    end_at := position(anchor in definition);
    if start_at = 0 or end_at <= start_at then raise exception 'Rollback anchors missing or out of order.'; end if;
    definition := overlay(definition placing '' from start_at for end_at - start_at);
  end loop;
  definition := replace(definition, E'\n  checkout_folio public.folios%rowtype;', '');
  if position('checkout_folio' in definition) > 0 then raise exception 'Unexpected helper references remain.'; end if;
  execute definition;
  if exists (select 1 from pg_proc where oid = target_oid
    and (proacl is distinct from original_acl or proowner <> original_owner
      or proconfig is distinct from original_config or not prosecdef)) then
    raise exception 'Rollback changed checkout security; aborted.';
  end if;
end;
$rollback$;
drop function private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text);
commit;
