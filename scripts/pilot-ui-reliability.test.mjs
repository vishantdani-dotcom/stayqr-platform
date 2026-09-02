import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { getHotelDateKey, summarizeDashboardFoodOrders } from '../src/lib/dashboardAnalytics.js'

const hotelId = 'hotel-a'
const now = new Date('2026-09-02T16:00:00Z')
const options = { hotelId, now, timeZone: 'Asia/Kolkata' }
const order = (order_status, total_amount = 250, extra = {}) => ({
  hotel_id: hotelId, order_status, total_amount, created_at: now.toISOString(), ...extra,
})
const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')

test('cancelled pilot order is counted but contributes zero revenue', () => {
  assert.deepEqual(summarizeDashboardFoodOrders([order('cancelled')], options), { todayOrders: 1, todayRevenue: 0 })
})
test('only delivered orders contribute revenue, not any open stage', () => {
  const rows = ['pending', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'cancelled', 'delivered'].map((status) => order(status))
  assert.deepEqual(summarizeDashboardFoodOrders(rows, options), { todayOrders: 7, todayRevenue: 250 })
})
test('tenant isolation is retained in the summary', () => {
  assert.deepEqual(summarizeDashboardFoodOrders([order('delivered'), order('delivered', 900, { hotel_id: 'hotel-b' })], options), { todayOrders: 1, todayRevenue: 250 })
  assert.deepEqual(summarizeDashboardFoodOrders([order('delivered')], { ...options, hotelId: null }), { todayOrders: 0, todayRevenue: 0 })
})
test('hotel business date, not browser timezone, selects orders', () => {
  const rows = [order('delivered', 100, { created_at: '2026-09-01T18:29:59Z' }), order('delivered', 250, { created_at: '2026-09-01T18:30:00Z' })]
  assert.deepEqual(summarizeDashboardFoodOrders(rows, options), { todayOrders: 1, todayRevenue: 250 })
  assert.equal(getHotelDateKey('2026-09-02T01:00:00Z', 'America/New_York'), '2026-09-01')
})
test('invalid dates and amounts never inflate the tile', () => {
  const rows = [order('delivered', 'NaN'), order('delivered', Infinity), order('delivered', -500), order('delivered', 250, { created_at: 'invalid' })]
  assert.deepEqual(summarizeDashboardFoodOrders(rows, options), { todayOrders: 3, todayRevenue: 0 })
  assert.equal(getHotelDateKey(null), '')
  assert.equal(getHotelDateKey('invalid'), '')
  assert.equal(getHotelDateKey(now, 'invalid-zone'), '2026-09-02')
})
test('currency values are summed in cents', () => {
  assert.equal(summarizeDashboardFoodOrders([order('delivered', '0.1'), order('delivered', '0.2')], options).todayRevenue, 0.3)
})
test('affected admin screens use shared in-page dialogs and trusted RPCs', () => {
  for (const file of ['foodorders/FoodOrders.jsx', 'housekeeping/Housekeeping.jsx']) {
    const source = read(`src/pages/${file}`)
    assert.match(source, /import ActionDialog/)
    assert.doesNotMatch(source, /window\.(prompt|confirm)\(/)
    assert.match(source, /selectedHotel\?\.id !== hotel.id/)
    assert.doesNotMatch(source, /\.from\(['"](?:food_orders|housekeeping_tasks)['"]\)[\s\S]{0,200}\.(update|insert|delete)\(/)
  }
  const dialog = read('src/components/modals/ActionDialog.jsx')
  for (const contract of ['dialog.showModal()', 'dialog.close()', 'previousFocus.focus()', 'submitting.current', 'role="alert"', 'value.trim()', 'await onConfirm(normalized)', 'onCancel=']) assert.ok(dialog.includes(contract), contract)
})
test('invoice migration changes only the persisted-number return and preserves security', () => {
  const sql = read('supabase/migrations/202609020105_pilot_ui_reliability_REV1.sql')
  assert.match(sql, /returning id, invoice_number into created_invoice_id, created_invoice_number/)
  for (const contract of ['original_acl', 'original_owner', 'original_config', 'not p.prosecdef', 'exactly one invoice INSERT']) assert.ok(sql.includes(contract), contract)
  assert.doesNotMatch(sql, /(?:update|delete from)\s+public\.(?:invoices|payments|reservation_checkout_events)/i)
})
