-- Pilot UI reliability: return the persisted, trigger-assigned invoice number.
-- New checkouts only. Historical invoices/evidence, grants, actor checks and
-- payment calculations are deliberately unchanged. Apply to staging first.
begin;

do $migration$
declare
  target_oid oid := to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)');
  original_definition text;
  patched_definition text;
  old_clause constant text := ') returning id into created_invoice_id;';
  new_clause constant text := ') returning id, invoice_number into created_invoice_id, created_invoice_number;';
  original_acl aclitem[];
  original_owner oid;
  original_config text[];
begin
  if target_oid is null then raise exception 'Required checkout function is missing.'; end if;
  select pg_get_functiondef(p.oid), p.proacl, p.proowner, p.proconfig
    into original_definition, original_acl, original_owner, original_config
    from pg_proc p where p.oid = target_oid and p.prosecdef;
  if original_definition is null then raise exception 'Checkout security-definer contract is missing.'; end if;

  if position(new_clause in original_definition) > 0 then
    raise notice 'Pilot UI invoice reference correction is already applied.';
    return;
  end if;
  if (length(original_definition) - length(replace(original_definition, old_clause, ''))) / length(old_clause) <> 1 then
    raise exception 'Checkout definition changed: expected exactly one invoice INSERT return clause. No changes applied.';
  end if;
  patched_definition := replace(original_definition, old_clause, new_clause);
  execute patched_definition;

  if exists (
    select 1 from pg_proc p where p.oid = target_oid
      and (p.proacl is distinct from original_acl or p.proowner <> original_owner
        or p.proconfig is distinct from original_config or not p.prosecdef)
  ) then raise exception 'Checkout permissions or security configuration changed; rolling back.'; end if;
end;
$migration$;

commit;
