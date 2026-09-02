-- Restores only the pre-patch return clause. Does not alter historical records.
begin;
do $rollback$
declare
  definition text := pg_get_functiondef('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure);
  old_clause constant text := ') returning id into created_invoice_id;';
  new_clause constant text := ') returning id, invoice_number into created_invoice_id, created_invoice_number;';
begin
  if position(new_clause in definition) = 0 and position(old_clause in definition) > 0 then return; end if;
  if (length(definition) - length(replace(definition, new_clause, ''))) / length(new_clause) <> 1 then
    raise exception 'Unexpected checkout definition; rollback not applied.';
  end if;
  execute replace(definition, new_clause, old_clause);
end;
$rollback$;
commit;
