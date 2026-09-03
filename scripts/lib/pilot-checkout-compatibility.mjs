import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'

const root = new URL('../../', import.meta.url)
const read = (path) => readFileSync(new URL(path, root), 'utf8').replaceAll('\r', '')
export const contracts = JSON.parse(read('supabase/compatibility/pilot-checkout-contracts-rev1.json'))
const source = (env, name) => contracts[env].functions.find((item) => item.name === name)
const replaceOnce = (text, before, after) => {
  assert.equal(text.split(before).length - 1, 1, `Expected exactly one anchor: ${before}`)
  return text.replace(before, after)
}
// Match PostgreSQL trim(text), which strips spaces but preserves newlines.
export const bodyHash = (definition) => createHash('md5').update(definition.split('AS $function$')[1].split('$function$')[0].replace(/^ +| +$/g, '')).digest('hex')
const signature = '(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'
const helperSignature = '(uuid,uuid,numeric,numeric,numeric,numeric,text)'
const names = ['public.checkout_guest_session', 'public.checkout_guest_session_day20_legacy', 'private.day20_checkout_existing_invoice', 'private.pilot_prepare_checkout_folio']
const sig = (name) => name + (name === names[3] ? helperSignature : signature)
const migration106 = read('supabase/migrations/202609030106_pilot_checkout_folio_consistency_REV1.sql')
const prepare = migration106.match(/prepare_block constant text := \$block\$([\s\S]*?)\$block\$;/)[1]
const finish = migration106.match(/finish_block constant text := \$block\$([\s\S]*?)\$block\$;/)[1]

let legacy = source('production', names[1]).definition
legacy = replaceOnce(legacy, '  session_row public.guest_sessions%rowtype;', '  session_row public.guest_sessions%rowtype;\n  checkout_folio public.folios%rowtype;')
legacy = replaceOnce(legacy, ') returning id into created_invoice_id;', ') returning id, invoice_number into created_invoice_id, created_invoice_number;')
legacy = replaceOnce(legacy, '  if existing_invoice.id is null then\n    created_invoice_number := format(', prepare + '  if existing_invoice.id is null then\n    created_invoice_number := format(')
legacy = replaceOnce(legacy, '  update public.guest_sessions', finish + '  update public.guest_sessions')
// Keep direct-call charge compatibility checks, then share the immutable-invoice path.
legacy = replaceOnce(legacy, '    room_amount := coalesce(existing_invoice.room_amount, 0);', `    -- PILOT_ROUTED_CHECKOUT_COMPATIBILITY_REV1: direct legacy calls reuse the guarded issued-invoice path.
    return private.day20_checkout_existing_invoice(
      target_hotel_id, target_guest_session_id, tax_percent, discount_type, discount_value,
      remaining_payment_collected, settlement_payment_method, settlement_transaction_reference,
      invoice_notes, allow_excess_paid);

    room_amount := coalesce(existing_invoice.room_amount, 0);`)

let issued = source('production', names[2]).definition
issued = replaceOnce(issued, '  invoice_total numeric(12,2);', '  invoice_total numeric(12,2);\n  issued_gross_subtotal numeric(14,2);')
issued = replaceOnce(issued, '  -- ----------------------------------------------------------\n  -- Stay duration', `  -- PILOT_ROUTED_CHECKOUT_COMPATIBILITY_REV1
  -- Preserve the issued invoice and prove that its SAME-STAY ledger agrees.
  -- Day13 checkout invoices store gross subtotal; native Day12 folio invoices
  -- store the post-discount taxable subtotal. Never subtract the discount twice.
  if invoice_row.metadata ->> 'day13_checkout_compatibility' = 'true' then
    issued_gross_subtotal := invoice_row.subtotal_amount;
  elsif invoice_row.invoice_origin = 'authoritative' and invoice_row.metadata ->> 'source' = 'folio' then
    issued_gross_subtotal := invoice_row.subtotal_amount + invoice_row.discount_amount;
  else
    raise exception 'Unknown issued invoice accounting format. Review Folio & Settlement before checkout.';
  end if;
  if folio_row.guest_session_id is distinct from target_guest_session_id
     or folio_row.status = 'voided'
     or invoice_row.subtotal_amount is null or invoice_row.tax_amount is null
     or invoice_row.discount_amount is null or invoice_row.total_amount is null
     or invoice_row.total_amount <> issued_gross_subtotal + invoice_row.tax_amount - invoice_row.discount_amount
     or folio_row.charges_amount <> issued_gross_subtotal then
    raise exception 'Issued invoice and same-stay folio charges differ. Review Folio & Settlement before checkout.';
  end if;
  if folio_row.refund_amount = 0 and folio_row.credit_amount = 0 then
    folio_row := private.pilot_prepare_checkout_folio(
      target_hotel_id, target_guest_session_id, issued_gross_subtotal,
      invoice_row.tax_amount, invoice_row.discount_amount, folio_row.collection_amount, invoice_notes);
  end if;
  -- Existing reconciled refunds remain valid. Credits, excess funds or conflicting
  -- adjustments require their own workflow; this checkout never invents a collection.
  if folio_row.id <> invoice_row.folio_id or folio_row.balance_amount <> 0
     or folio_row.charges_amount <> issued_gross_subtotal
     or folio_row.tax_amount <> invoice_row.tax_amount
     or folio_row.discount_amount <> invoice_row.discount_amount
     or folio_row.credit_amount <> 0
     or folio_row.collection_amount - folio_row.refund_amount <> invoice_total then
    raise exception 'Issued invoice and live folio do not reconcile. Review refunds, credits or adjustments before checkout.';
  end if;

  -- ----------------------------------------------------------
  -- Stay duration`)
issued = replaceOnce(issued, '  -- ----------------------------------------------------------\n  -- Complete stay', `  -- Verify operational triggers did not synthesize collections or alter invoice evidence.
  if not exists (select 1 from public.folios f where f.hotel_id = target_hotel_id
      and f.id = invoice_row.folio_id and f.guest_session_id = target_guest_session_id
      and f.balance_amount = 0 and f.charges_amount = folio_row.charges_amount
      and f.tax_amount = folio_row.tax_amount and f.discount_amount = folio_row.discount_amount
      and f.collection_amount = folio_row.collection_amount
      and f.refund_amount = folio_row.refund_amount and f.credit_amount = folio_row.credit_amount)
     or not exists (select 1 from public.invoices i where i.hotel_id = target_hotel_id
       and i.id = invoice_row.id and to_jsonb(i) = to_jsonb(invoice_row)) then
    raise exception 'Issued invoice or settlement evidence changed during checkout. No changes saved.';
  end if;

  -- ----------------------------------------------------------
  -- Complete stay`)
issued = replaceOnce(issued, "      'already_checked_out', true,", `      'already_checked_out', true,
      'existing_invoice_reused', true,
      'grand_total', invoice_row.total_amount,
      'previously_paid', coalesce((existing_event.settlement_snapshot ->> 'authoritative_net_collection')::numeric,
        (existing_event.settlement_snapshot ->> 'previously_paid')::numeric, 0),
      'amount_collected_at_checkout', 0,
      'room_number', existing_event.settlement_snapshot ->> 'room_number',
      'reservation_id', existing_event.reservation_id,
      'reservation_room_id', existing_event.reservation_room_id,
      'housekeeping_task_id', existing_event.settlement_snapshot ->> 'housekeeping_task_id',`)

export const definitions = {
  [names[0]]: source('production', names[0]).definition,
  [names[1]]: legacy,
  [names[2]]: issued,
  [names[3]]: source('staging', names[3]).definition,
}
export const hashes = Object.fromEntries(names.map((name) => [name, bodyHash(definitions[name])]))
const quoted = (text) => "'" + text.replaceAll("'", "''") + "'"
const snapshotValues = names.map((name) => `(${quoted(sig(name))})`).join(',\n    ')
const sqlDefinition = (name) => `${definitions[name].trim()};`
export function migrationSql() {
  const guards = names.map((name) => {
    const predecessor = source('production', name)
    const flat = source('staging', name)
    const allowed = [...new Set([predecessor?.body_md5, flat?.body_md5, hashes[name]].filter(Boolean))]
    return `  if exists (select 1 from pg_proc where oid = to_regprocedure(${quoted(sig(name))})
    and md5(trim(replace(prosrc,chr(13),''))) not in (${allowed.map(quoted).join(',')})) then
    raise exception 'Unknown checkout predecessor: ${name}. No changes applied.';
  end if;`
  }).join('\n')
  return `-- Generated from reviewed production contracts; see scripts/lib/pilot-checkout-compatibility.mjs.
-- Supports known flat staging and routed production shapes only. No historical data correction.
-- Apply only to the explicitly approved environment; do NOT blanket-push old migrations 105/106.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('stayqr:202609030107:checkout-compatibility'));
create temporary table pilot_checkout_security_snapshot on commit drop as
  select p.oid, p.proacl, p.proowner, p.proconfig, p.prosecdef, pg_get_expr(p.proargdefaults,0) as defaults
  from pg_proc p where p.oid in (select to_regprocedure(s) from (values
    ${snapshotValues}) as targets(s));
do $preflight$
begin
  if to_regprocedure(${quoted(sig(names[0]))}) is null then raise exception 'Checkout entry point missing.'; end if;
${guards}
  if exists (select 1 from pilot_checkout_security_snapshot where not prosecdef
    or proowner <> 'postgres'::regrole or proconfig is distinct from array['search_path=""']) then
    raise exception 'Unexpected checkout security contract. No changes applied.';
  end if;
  if (to_regprocedure(${quoted(sig(names[1]))}) is null) <> (to_regprocedure(${quoted(sig(names[2]))}) is null) then
    raise exception 'Incomplete routed checkout predecessor.';
  end if;
end;
$preflight$;

${sqlDefinition(names[3])}
${sqlDefinition(names[2])}
${sqlDefinition(names[1])}
${sqlDefinition(names[0])}

-- Existing function grants remain exactly as captured; new delegates get least privilege.
do $security$
declare target record;
begin
  for target in select * from (values
    ${snapshotValues}) as targets(s) loop
    if not exists (select 1 from pilot_checkout_security_snapshot where oid = to_regprocedure(target.s)) then
      execute format('revoke all on function %s from public, anon, authenticated, service_role', target.s);
      if target.s = ${quoted(sig(names[1]))} then
        execute format('grant execute on function %s to authenticated, service_role', target.s);
      end if;
    end if;
  end loop;
  if exists (select 1 from pilot_checkout_security_snapshot old join pg_proc p on p.oid=old.oid
    where p.proacl is distinct from old.proacl or p.proowner <> old.proowner
      or p.proconfig is distinct from old.proconfig or p.prosecdef <> old.prosecdef
      or pg_get_expr(p.proargdefaults,0) is distinct from old.defaults) then
    raise exception 'Checkout permissions, ownership, defaults or search path changed; rolling back.';
  end if;
  if has_function_privilege('anon', ${quoted(sig(names[3]))}, 'EXECUTE')
    or has_function_privilege('authenticated', ${quoted(sig(names[3]))}, 'EXECUTE')
    or has_function_privilege('authenticated', ${quoted(sig(names[2]))}, 'EXECUTE') then
    raise exception 'Private checkout helpers must not be browser-callable.';
  end if;
end;
$security$;
commit;
`
}

export function rollbackSql(environment) {
  assert.ok(['staging','production'].includes(environment))
  const before = contracts[environment].functions
  return `-- ${environment.toUpperCase()} code-only rollback. Explicit approval required outside rollback-only rehearsal.
-- Never deletes historical discounts, invoices or collections.
begin;
set local lock_timeout = '10s';
do $guard$
begin
${names.map((name) => `  if (select md5(trim(replace(prosrc,chr(13),''))) from pg_proc where oid=to_regprocedure(${quoted(sig(name))})) is distinct from ${quoted(hashes[name])} then
    raise exception 'Unknown rollback source: ${name}';
  end if;`).join('\n')}
end;
$guard$;
${before.map((item) => item.definition.trim()+';').join('\n')}
${names.filter((name) => !before.some((item) => item.name===name)).map((name) => `drop function ${sig(name)};`).join('\n')}
commit;
`
}
