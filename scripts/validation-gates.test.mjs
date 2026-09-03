import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateCommercialSources } from './day9-commercial-source-check.mjs'
import { resolveMarketingRoot } from './lib/marketing-root.mjs'

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const read = (file) => readFileSync(join(sourceRoot, file), 'utf8')
const sources = {
  appSource: read('src/App.jsx'),
  pageSource: read('src/pages/superadmin/SuperAdmin.jsx'),
  apiSource: read('src/lib/commercialControl.js'),
}

test('current pilot contract passes without the retired Cashfree recovery variable', () => {
  assert.ok(!sources.pageSource.includes('requiresPaymentRecovery'))
  const result = validateCommercialSources(sources)
  assert.deepEqual(result.failures, [])
  assert.equal(result.requiredCount, 29)
  assert.equal(result.forbiddenCount, 9)
})

const mutations = [
  ['default recovery', 'pageSource', "const defaultAction = 'manual-payment'", "const defaultAction = 'renew'", 'default recovery action'],
  ['hotel isolation', 'pageSource', 'recordManualSubscriptionPayment(hotel.id, {', 'recordManualSubscriptionPayment(otherHotel.id, {', 'selected hotel'],
  ['positive received amount', 'pageSource', 'if (amountMinor <= 0)', 'if (false)', 'positive received amount'],
  ['required receipt', 'pageSource', 'if (paymentReference.trim().length < 3)', 'if (false)', 'receipt reference'],
  ['receipt payload', 'pageSource', 'payment_reference: paymentReference.trim(),', 'payment_reference: null,', 'receipt, paid time and idempotency key'],
  ['controlled RPC', 'apiSource', "'record_manual_subscription_payment',", "'uncontrolled_manual_payment',", 'controlled RPC'],
  ['renew lifecycle eligibility', 'pageSource', "['active', 'past_due', 'suspended'].includes(lifecycle)", "['active', 'past_due', 'suspended', 'expired'].includes(lifecycle)", 'Renewal eligibility'],
  ['renew submission guard', 'pageSource', "action === 'renew' && canRenew", "action === 'renew'", 'lifecycle-guarded on submission'],
  ['renew UI guard', 'pageSource', '{canRenew && <option value="renew">', '{true && <option value="renew">', 'lifecycle-guarded in the UI'],
  ['reactivation lifecycle guard', 'pageSource', "{lifecycle === 'suspended' && (", '{true && (', 'limited to suspended'],
  ['existing support boundary', 'apiSource', "'start_safe_support_access',", "'uncontrolled_support_access',", 'Safe-support start RPC'],
  ['Cashfree invoked from manual action', 'pageSource', 'result = await recordManualSubscriptionPayment(hotel.id, {', 'await createCashfreePaymentLink({})\n        result = await recordManualSubscriptionPayment(hotel.id, {', 'manual-payment recovery calls Cashfree'],
]

for (const [name, field, before, after, expectedFailure] of mutations) {
  test(`commercial gate rejects missing/unsafe ${name}`, () => {
    assert.ok(sources[field].includes(before), `mutation target exists: ${before}`)
    const changed = { ...sources, [field]: sources[field].replace(before, after) }
    assert.ok(validateCommercialSources(changed).failures.some((failure) => failure.includes(expectedFailure)))
  })
}

for (const table of ['hotel_subscriptions', 'subscription_payment_links', 'subscription_events', 'webhook_events', 'subscription_manual_payments']) {
  test(`commercial gate still rejects browser writes to ${table}`, () => {
    const changed = { ...sources, apiSource: `${sources.apiSource}\nsupabase.from('${table}').insert({})` }
    assert.ok(validateCommercialSources(changed).failures.some((failure) => failure.startsWith('Unsafe source detected: direct browser write')))
  })
}

for (const secret of ['service_role', 'CASHFREE_CLIENT_SECRET', 'CASHFREE_CLIENT_ID']) {
  test(`commercial gate still rejects browser credential marker ${secret}`, () => {
    const changed = { ...sources, apiSource: `${sources.apiSource}\nconst unsafe = '${secret}'` }
    assert.ok(validateCommercialSources(changed).failures.some((failure) => failure.startsWith('Unsafe source detected:')))
  })
}

const layoutRoot = resolve('validation-test-layout', '01_SOURCE', 'stayqr-platform')
const sibling = resolve(layoutRoot, '..', 'marketing')
const batch = resolve(layoutRoot, '..', '..', '10_POSTLAUNCH_BATCH_A', 'Marketing_BATCH_A')
const custom = resolve('custom-marketing-source')
const complete = (root) => [root, join(root, 'stayqr.in_current.html'), join(root, 'DEPLOY_stayqr.in/index.html')]
const available = (...paths) => (target) => new Set(paths).has(target)

test('marketing resolver retains the original sibling layout', () => {
  assert.equal(resolveMarketingRoot(layoutRoot, '', available(...complete(sibling))), sibling)
})

test('marketing resolver supports the consolidated Batch A layout', () => {
  assert.equal(resolveMarketingRoot(layoutRoot, '', available(...complete(batch))), batch)
})

test('explicit marketing source wins over either default', () => {
  assert.equal(resolveMarketingRoot(layoutRoot, custom, available(...complete(custom), ...complete(sibling), ...complete(batch))), custom)
})

test('existing sibling takes precedence over the Batch A bundle', () => {
  assert.equal(resolveMarketingRoot(layoutRoot, '', available(...complete(sibling), ...complete(batch))), sibling)
})

test('a missing explicit source fails without silently falling back', () => {
  assert.throws(() => resolveMarketingRoot(layoutRoot, custom, available(...complete(batch))), /No fallback was used/)
})

test('an incomplete sibling source fails instead of picking a passing bundle', () => {
  assert.throws(() => resolveMarketingRoot(layoutRoot, '', available(sibling, join(sibling, 'stayqr.in_current.html'), ...complete(batch))), /DEPLOY_stayqr.in\/index.html/)
})

test('a missing marketing source remains a hard failure with setup instructions', () => {
  assert.throws(() => resolveMarketingRoot(layoutRoot, '', available()), /Marketing source not found\. Set STAYQR_MARKETING_ROOT/)
})

test('an incomplete explicitly configured source is rejected', () => {
  assert.throws(() => resolveMarketingRoot(layoutRoot, custom, available(custom, join(custom, 'DEPLOY_stayqr.in/index.html'))), /Required file\(s\) missing: stayqr.in_current.html/)
})
