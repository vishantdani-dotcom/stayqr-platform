import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const page = read('src/pages/invoices/Invoices.jsx')
// Execute the real rendered expressions, not a duplicate calculation.
const expressions = [...page.matchAll(/(?:invoice|item)\.taxable_amount\s*(?:\?\?|\|\|)\s*(?:invoice\.subtotal_amount|item\.amount)/g)].map(([expression]) => expression)
const evaluate = (expression, value, fallback) => vm.runInNewContext(expression, {
  invoice: { taxable_amount: value, subtotal_amount: fallback },
  item: { taxable_amount: value, amount: fallback },
})

test('all three taxable display expressions preserve a genuine zero', () => {
  assert.equal(expressions.length, 3)
  for (const expression of expressions) assert.equal(evaluate(expression, 0, 2500), 0)
})
test('a discount line does not replace zero taxable with its negative amount', () => {
  for (const expression of expressions) assert.equal(evaluate(expression, 0, -2500), 0)
})
test('legacy missing taxable fields still fall back, while numeric strings survive', () => {
  for (const expression of expressions) {
    assert.equal(evaluate(expression, null, 2500), 2500)
    assert.equal(evaluate(expression, undefined, 2500), 2500)
    assert.equal(evaluate(expression, '0.00', 2500), '0.00')
    assert.equal(evaluate(expression, 2000, 2500), 2000)
  }
})
test('live register balance and immutable preview remain separate truthful inputs', () => {
  assert.match(page, /liveBalance = Math\.max\(Number\(folio\.balance_amount/)
  assert.match(page, /label="Balance" value=\{invoice\.pending_amount\}/)
})
test('checkout patch uses approved adjustments and fails closed without weakening permissions', () => {
  const sql = read('supabase/migrations/202609030106_pilot_checkout_folio_consistency_REV1.sql')
  for (const contract of ['public.request_folio_discount', 'public.review_folio_discount',
    'private.day11_require_current_actor()', 'private.assert_reservation_write_access',
    'for update', 'original_acl', 'original_owner', 'original_config',
    'from public, anon, authenticated', 'checkout_folio.balance_amount <> 0',
    'expected_discount - folio_row.discount_amount', "'checkout_tax'"]) assert.ok(sql.includes(contract), contract)
  assert.doesNotMatch(sql, /(?:update|delete from)\s+public\.(?:invoices|invoice_items|folio_adjustments)/i)
  assert.doesNotMatch(sql, /insert into public\.(?:payment_collections|folio_collections)/i)
})
test('checkout asks for an auditable discount reason before submission', () => {
  const guestPage = read('src/pages/guests/Guests.jsx')
  assert.ok(guestPage.includes('settlementCalculation.discountAmount > 0 && !invoiceNotes.trim()'))
  assert.ok(guestPage.includes('discount reason required'))
})
