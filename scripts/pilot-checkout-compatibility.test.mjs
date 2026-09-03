import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { contracts, definitions, bodyHash, migrationSql, rollbackSql } from './lib/pilot-checkout-compatibility.mjs'
import { rehearsalSql } from './lib/pilot-checkout-rehearsal.mjs'
import { issuedCheckoutTotals } from '../src/lib/issuedCheckout.js'
const read = (path) => readFileSync(new URL(`../${path}`,import.meta.url),'utf8').replaceAll('\r','').trimEnd()
const invoice = { id:'invoice',hotel_id:'hotel',guest_session_id:'stay',folio_id:'folio',finalized_at:'2026-09-03',
  invoice_origin:'authoritative',metadata:{source:'folio'},subtotal_amount:2000,discount_amount:500,
  discount_type:'fixed',discount_value:500,tax_amount:240,tax_percent:12,total_amount:2240,paid_amount:0,pending_amount:2240 }
const folio = {id:'folio',hotel_id:'hotel',guest_session_id:'stay',charges_amount:2500,collection_amount:2240,refund_amount:0,balance_amount:0}
test('captured function definitions reproduce all reviewed database fingerprints',()=>{
  for(const env of ['production','staging']) for(const f of contracts[env].functions) assert.equal(bodyHash(f.definition),f.body_md5,f.name)
})
test('generated migration and both environment-specific rollback files are current',()=>{
  assert.equal(read('supabase/migrations/202609030107_pilot_routed_checkout_compatibility_REV1.sql'),migrationSql().trimEnd())
  for(const env of ['staging','production']) assert.equal(read(`supabase/rollback/202609030107_pilot_routed_checkout_${env.toUpperCase()}_ROLLBACK.sql`),rollbackSql(env).trimEnd())
})
test('public production router is preserved exactly',()=>{
  assert.equal(definitions['public.checkout_guest_session'],contracts.production.functions.find(f=>f.name==='public.checkout_guest_session').definition)
})
test('legacy new checkout retains predecessor safeguards and delegates issued invoices after charge checks',()=>{
  const sql=definitions['public.checkout_guest_session_day20_legacy']
  for(const text of ['DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1',
    'PILOT_CHECKOUT_FOLIO_CONSISTENCY_REV1','checkout_folio.balance_amount <> 0',
    'returning id, invoice_number into created_invoice_id, created_invoice_number',
    'private.assert_reservation_write_access(target_hotel_id)']) assert.ok(sql.includes(text),text)
  assert.ok(sql.indexOf('Existing immutable invoice no longer matches')<sql.indexOf('return private.day20_checkout_existing_invoice'))
})
test('issued checkout preserves invoice, money evidence, same-stay boundary and idempotency',()=>{
  const sql=definitions['private.day20_checkout_existing_invoice']
  assert.doesNotMatch(sql,/(?:insert into|update|delete from)\s+public\.(?:invoices|invoice_items|payments|payment_collections|folio_collections)\b/i)
  for(const text of ['folio_row.guest_session_id is distinct from target_guest_session_id','folio_row.balance_amount <> 0',
    'folio_row.collection_amount - folio_row.refund_amount <> invoice_total','to_jsonb(i) = to_jsonb(invoice_row)',
    "'already_checked_out', true","'amount_collected_at_checkout', 0",'private.pilot_prepare_checkout_folio']) assert.ok(sql.includes(text),text)
})
test('migration guards unknown bodies and keeps existing ownership, grants, defaults and search path',()=>{
  const sql=migrationSql()
  for(const text of ['Unknown checkout predecessor','Incomplete routed checkout predecessor','p.proacl is distinct from old.proacl',
    'p.proowner <> old.proowner','p.proconfig is distinct from old.proconfig','pg_get_expr(p.proargdefaults,0) is distinct from old.defaults']) assert.ok(sql.includes(text),text)
  assert.doesNotMatch(sql,/grant\s+(?:all|insert|update|delete)\b/i)
})
test('rehearsals are staging guarded, use actual authenticated role, restrict direct financial DML and roll back',()=>{
  for(const env of ['staging','production']) {
    const sql=rehearsalSql(env,true)
    assert.ok(sql.includes("slug='20e-test-hotel'"))
    assert.ok(sql.includes('revoke insert, update, delete on public.invoices from authenticated'))
    assert.ok(sql.includes("current_user <> 'authenticated'"))
    assert.match(sql,/rollback;\s*select 'PASS/)
    assert.doesNotMatch(sql,/^commit;/m)
  }
})
test('native issued invoices restore gross subtotal without subtracting discount twice',()=>{
  assert.deepEqual(issuedCheckoutTotals(invoice,folio,'hotel','stay'),{subtotal:2500,taxPercent:12,taxAmount:240,
    discountValue:500,discountAmount:500,grandTotal:2240,previouslyPaid:2240,amountToCollect:0,excessPaid:0})
})
test('checkout-format issued invoices already have gross subtotal',()=>{
  const i={...invoice,subtotal_amount:2500,metadata:{day13_checkout_compatibility:true}}
  assert.equal(issuedCheckoutTotals(i,folio,'hotel','stay').subtotal,2500)
})
test('zero-total invoices preserve zero and stale stored pending never drives another collection',()=>{
  const i={...invoice,subtotal_amount:0,discount_amount:2500,discount_value:2500,tax_amount:0,total_amount:0}
  const totals=issuedCheckoutTotals(i,{...folio,collection_amount:0},'hotel','stay')
  assert.equal(totals.grandTotal,0)
  assert.equal(totals.amountToCollect,0)
  assert.equal(issuedCheckoutTotals(invoice,folio,'hotel','stay').amountToCollect,0)
})
test('live refunds and underpayments affect preview without fabricating a payment',()=>{
  assert.equal(issuedCheckoutTotals(invoice,{...folio,refund_amount:500},'hotel','stay').amountToCollect,500)
  assert.equal(issuedCheckoutTotals(invoice,{...folio,collection_amount:1000},'hotel','stay').amountToCollect,1240)
})
test('preview rejects foreign hotel/stay/folio, unknown accounting formats and charge mismatch',()=>{
  for(const [i,f,h,s] of [[invoice,folio,'foreign','stay'],[invoice,folio,'hotel','foreign'],
    [invoice,{...folio,id:'foreign'},'hotel','stay'],[{...invoice,finalized_at:null},folio,'hotel','stay'],
    [{...invoice,metadata:{}},folio,'hotel','stay'],[invoice,{...folio,charges_amount:2600},'hotel','stay']])
    assert.throws(()=>issuedCheckoutTotals(i,f,h,s))
  assert.equal(issuedCheckoutTotals(null,null,'hotel','stay'),null)
})
test('issued preview retains exact mixed-rate tax totals and decimal amounts',()=>{
  const i={...invoice,subtotal_amount:'100.01',discount_amount:'10.01',discount_value:'10.01',tax_amount:'12.01',tax_percent:12.0088,total_amount:'112.02'}
  assert.equal(issuedCheckoutTotals(i,{...folio,charges_amount:'110.02',collection_amount:'112.02'},'hotel','stay').taxAmount,12.01)
})
test('checkout screen locks issued inputs, scopes reads and awaits current hotel before submitting',()=>{
  const page=read('src/pages/guests/Guests.jsx')
  for(const text of ['.eq("guest_session_id", session.id)','issuedCheckoutTotals(issuedInvoice, checkoutFolio, session.hotel_id, session.id)',
    'if ((await getCurrentHotel())?.id !== session.hotel_id)','if (settlementData?.issuedTotals) return settlementData.issuedTotals;',
    'disabled={Boolean(settlementData.issuedInvoice) || settlementLoading}',
    'if (settlementData.issuedInvoice && amountToCollect > 0)']) assert.ok(page.includes(text),text)
})
