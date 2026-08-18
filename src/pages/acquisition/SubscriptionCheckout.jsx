import { useEffect, useState } from 'react'
import logo from '../../assets/stayqr-logo.png'
import { clearTenantContextCache } from '../../lib/tenantContext'
import {
  createSelfServiceCheckout,
  fetchPublicSubscriptionPlans,
  getMyAcquisitionIntent,
  getOrCreateAcquisitionRequestId,
  getRememberedAcquisitionIntent,
  rememberAcquisitionIntent,
  resetAcquisitionRequest,
  startSelfServiceTrial,
} from '../../lib/acquisition'
import './SubscriptionCheckout.css'

const STATUS_POLLING = new Set(['creating', 'issued', 'paid', 'provisioning'])

function querySelection() {
  const params = new URLSearchParams(window.location.search)
  return {
    plan: String(params.get('plan') || 'growth').toLowerCase(),
    billing: params.get('billing') === 'annual' ? 'annual' : 'monthly',
    mode: params.get('mode') === 'trial' ? 'trial' : 'paid',
    intent: params.get('intent'),
  }
}

function formatMoney(amount, currency = 'INR') {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency,
    maximumFractionDigits: 0,
  }).format(Number(amount || 0))
}

async function fetchAcquisitionIntent(intentId, userId) {
  const targetId = intentId || getRememberedAcquisitionIntent(userId)
  return getMyAcquisitionIntent(targetId || null)
}

export default function SubscriptionCheckout({ session, routeMode = 'checkout' }) {
  const user = session?.user
  const userId = user?.id || ''
  const [initial] = useState(() => querySelection())
  const [plans, setPlans] = useState([])
  const [planId, setPlanId] = useState('')
  const [billingCycle, setBillingCycle] = useState(initial.billing)
  const [acquisitionMode, setAcquisitionMode] = useState(initial.mode)
  const [hotelName, setHotelName] = useState('')
  const [ownerName, setOwnerName] = useState(user?.user_metadata?.full_name || '')
  const [phone, setPhone] = useState('')
  const [accepted, setAccepted] = useState(false)
  const [intent, setIntent] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const selectedPlan = plans.find((plan) => plan.id === planId) || null
  const statusMode = routeMode !== 'checkout'

  useEffect(() => {
    let cancelled = false

    async function initialize() {
      setLoading(true)
      setError('')
      try {
        const rows = await fetchPublicSubscriptionPlans()
        if (cancelled) return
        setPlans(rows)
        const requested = rows.find(
          (plan) => String(plan.plan_code || '').toLowerCase() === initial.plan
        )
        setPlanId(requested?.id || rows[0]?.id || '')
      } catch (loadError) {
        if (!cancelled) {
          setError(loadError?.message || 'StayQR could not load the public plans.')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    initialize()
    return () => { cancelled = true }
  }, [initial.plan])

  async function loadIntent() {
    if (!statusMode || !userId) return null
    const nextIntent = await fetchAcquisitionIntent(initial.intent, userId)
    setIntent(nextIntent)
    return nextIntent
  }

  useEffect(() => {
    if (!statusMode || !userId) return undefined
    let cancelled = false
    let timer = null

    async function refresh() {
      try {
        const nextIntent = await fetchAcquisitionIntent(initial.intent, userId)
        if (cancelled) return
        setIntent(nextIntent)
        if (nextIntent && STATUS_POLLING.has(nextIntent.status)) {
          timer = window.setTimeout(refresh, 3500)
        }
      } catch (loadError) {
        if (!cancelled) {
          setError(loadError?.message || 'StayQR could not verify the checkout status.')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    setLoading(true)
    refresh()
    return () => {
      cancelled = true
      if (timer) window.clearTimeout(timer)
    }
  }, [initial.intent, statusMode, userId])

  function updateSelection(next = {}) {
    const nextPlan = next.planId || planId
    const nextBilling = next.billingCycle || billingCycle
    const nextMode = next.acquisitionMode || acquisitionMode
    const plan = plans.find((row) => row.id === nextPlan)
    const params = new URLSearchParams({
      plan: String(plan?.plan_code || 'starter').toLowerCase(),
      billing: nextBilling,
      mode: nextMode,
    })
    window.history.replaceState(null, '', `/checkout?${params.toString()}`)
  }

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')

    if (!selectedPlan) {
      setError('Select an available StayQR plan.')
      return
    }
    if (!accepted) {
      setError('Accept the Terms and Subscription Policy to continue.')
      return
    }

    const signature = `${acquisitionMode}:${selectedPlan.id}:${billingCycle}`
    const requestId = getOrCreateAcquisitionRequestId(user.id, signature)
    const payload = {
      request_id: requestId,
      plan_id: selectedPlan.id,
      billing_cycle: billingCycle,
      hotel_name: hotelName,
      owner_name: ownerName,
      phone,
    }

    setBusy(true)
    try {
      if (acquisitionMode === 'trial') {
        const result = await startSelfServiceTrial(payload)
        rememberAcquisitionIntent(user.id, result?.id || requestId)
        resetAcquisitionRequest(user.id)
        clearTenantContextCache()
        window.location.replace('/setup')
        return
      }

      const result = await createSelfServiceCheckout(payload)
      const nextIntent = result?.intent
      rememberAcquisitionIntent(user.id, nextIntent?.id || requestId)
      if (['paid', 'provisioning', 'completed'].includes(nextIntent?.status)) {
        window.location.assign(`/checkout/success?intent=${nextIntent.id}`)
        return
      }
      if (!nextIntent?.provider_url) {
        throw new Error(
          nextIntent?.failure_reason ||
          'This checkout does not have an active Cashfree payment URL. Start a new checkout.'
        )
      }
      window.location.assign(nextIntent.provider_url)
    } catch (submitError) {
      if (submitError?.restartAllowed) resetAcquisitionRequest(user.id)
      setError(submitError?.message || 'StayQR could not start the selected plan.')
      setBusy(false)
    }
  }

  function startNewCheckout() {
    resetAcquisitionRequest(user?.id)
    const planCode = String(intent?.plan?.plan_code || 'growth').toLowerCase()
    const billing = intent?.billing_cycle || 'monthly'
    window.location.assign(`/checkout?plan=${encodeURIComponent(planCode)}&billing=${billing}&mode=paid`)
  }

  if (loading) {
    return <CheckoutShell><div className="acquisition-state"><span className="acquisition-spinner" /><h1>Loading secure checkout…</h1><p>Confirming plans and your account.</p></div></CheckoutShell>
  }

  if (statusMode) {
    return (
      <CheckoutShell>
        <CheckoutStatus
          intent={intent}
          error={error}
          onRefresh={loadIntent}
          onStartNew={startNewCheckout}
        />
      </CheckoutShell>
    )
  }

  const price = selectedPlan
    ? billingCycle === 'annual'
      ? selectedPlan.price_annual
      : selectedPlan.price_monthly
    : 0

  return (
    <CheckoutShell>
      <header className="acquisition-heading">
        <span>Self-service hotel activation</span>
        <h1>Choose your StayQR plan</h1>
        <p>Use one verified owner account for payment, hotel setup and future sign-in.</p>
      </header>

      {error && <div className="acquisition-alert" role="alert">{error}</div>}

      <form className="acquisition-form" onSubmit={handleSubmit}>
        <section aria-labelledby="plan-heading">
          <div className="acquisition-section-title">
            <div><span>Step 1</span><h2 id="plan-heading">Select a plan</h2></div>
            <div className="acquisition-toggle" aria-label="Billing cycle">
              {['monthly', 'annual'].map((cycle) => (
                <button
                  key={cycle}
                  type="button"
                  className={billingCycle === cycle ? 'active' : ''}
                  onClick={() => {
                    setBillingCycle(cycle)
                    updateSelection({ billingCycle: cycle })
                  }}
                >
                  {cycle === 'monthly' ? 'Monthly' : 'Yearly'}
                </button>
              ))}
            </div>
          </div>

          <div className="acquisition-plans">
            {plans.map((plan) => {
              const planPrice = billingCycle === 'annual' ? plan.price_annual : plan.price_monthly
              return (
                <button
                  key={plan.id}
                  type="button"
                  className={`acquisition-plan ${planId === plan.id ? 'selected' : ''}`}
                  onClick={() => {
                    setPlanId(plan.id)
                    updateSelection({ planId: plan.id })
                  }}
                  aria-pressed={planId === plan.id}
                >
                  <span>{plan.plan_name}</span>
                  <strong>{formatMoney(planPrice, plan.currency_code)}</strong>
                  <small>/{billingCycle === 'annual' ? 'year' : 'month'} · up to {plan.max_rooms} rooms</small>
                </button>
              )
            })}
          </div>
        </section>

        <section aria-labelledby="activation-heading">
          <div className="acquisition-section-title">
            <div><span>Step 2</span><h2 id="activation-heading">Choose how to start</h2></div>
          </div>
          <div className="acquisition-start-options">
            <label className={acquisitionMode === 'paid' ? 'selected' : ''}>
              <input
                type="radio"
                name="mode"
                value="paid"
                checked={acquisitionMode === 'paid'}
                onChange={() => {
                  setAcquisitionMode('paid')
                  updateSelection({ acquisitionMode: 'paid' })
                }}
              />
              <span><strong>Activate now</strong><small>Pay securely with Cashfree. Your paid cycle starts after verified payment.</small></span>
            </label>
            <label className={acquisitionMode === 'trial' ? 'selected' : ''}>
              <input
                type="radio"
                name="mode"
                value="trial"
                checked={acquisitionMode === 'trial'}
                onChange={() => {
                  setAcquisitionMode('trial')
                  updateSelection({ acquisitionMode: 'trial' })
                }}
              />
              <span><strong>Start 14-day trial</strong><small>No payment today. One trial is available per new hotel account.</small></span>
            </label>
          </div>
        </section>

        <section aria-labelledby="hotel-heading">
          <div className="acquisition-section-title">
            <div><span>Step 3</span><h2 id="hotel-heading">Confirm owner and hotel</h2></div>
          </div>
          <div className="acquisition-fields">
            <label>Hotel name<input value={hotelName} onChange={(event) => setHotelName(event.target.value)} minLength="2" maxLength="160" required autoComplete="organization" /></label>
            <label>Hotel owner name<input value={ownerName} onChange={(event) => setOwnerName(event.target.value)} minLength="2" maxLength="120" required autoComplete="name" /></label>
            <label>Mobile number<input value={phone} onChange={(event) => setPhone(event.target.value)} inputMode="tel" required autoComplete="tel" placeholder="10-digit Indian mobile" /></label>
            <label>Verified account email<input value={user?.email || ''} readOnly aria-readonly="true" /></label>
          </div>
        </section>

        <div className="acquisition-summary">
          <div>
            <span>{selectedPlan?.plan_name || 'StayQR plan'} · {billingCycle === 'annual' ? 'Yearly' : 'Monthly'}</span>
            <strong>{acquisitionMode === 'trial' ? '₹0 today' : formatMoney(price, selectedPlan?.currency_code)}</strong>
            <small>{acquisitionMode === 'trial' ? '14-day trial; payment is not collected now.' : 'Taxes may be added where legally applicable.'}</small>
          </div>
          <label className="acquisition-consent">
            <input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} required />
            <span>I accept the <a href="/terms" target="_blank" rel="noreferrer">Terms</a>, <a href="/subscription-policy" target="_blank" rel="noreferrer">Subscription Policy</a> and <a href="/privacy" target="_blank" rel="noreferrer">Privacy Policy</a>.</span>
          </label>
          <button type="submit" className="acquisition-submit" disabled={busy || !selectedPlan}>
            {busy ? 'Starting securely…' : acquisitionMode === 'trial' ? 'Start 14-day trial' : 'Continue to Cashfree'}
          </button>
          <p>Payments are activated only after StayQR receives a verified Cashfree webhook. Do not close the Cashfree confirmation screen early.</p>
        </div>
      </form>
    </CheckoutShell>
  )
}

function CheckoutStatus({ intent, error, onRefresh, onStartNew }) {
  if (error) return <div className="acquisition-state error"><h1>We could not verify checkout</h1><p>{error}</p><button type="button" onClick={onRefresh}>Try again</button></div>
  if (!intent) return <div className="acquisition-state"><h1>No checkout found</h1><p>Start a new plan selection with this account.</p><button type="button" onClick={onStartNew}>Choose a plan</button></div>

  if (intent.status === 'completed') {
    return <div className="acquisition-state success"><span className="acquisition-state-icon">✓</span><h1>Your StayQR hotel is active</h1><p>{intent.plan?.plan_name} is ready for {intent.hotel_name}. Continue with hotel profile and operational setup.</p><button type="button" onClick={() => window.location.assign('/setup')}>Continue hotel setup</button></div>
  }

  if (['failed', 'expired', 'cancelled'].includes(intent.status)) {
    return <div className="acquisition-state error"><span className="acquisition-state-icon">!</span><h1>Checkout needs attention</h1><p>{intent.failure_reason || `This Cashfree checkout is ${intent.status}. No hotel was activated.`}</p><button type="button" onClick={onStartNew}>Start a new checkout</button></div>
  }

  if (intent.status === 'issued' && intent.provider_url) {
    return <div className="acquisition-state"><span className="acquisition-state-icon">₹</span><h1>Payment is not completed</h1><p>Your secure Cashfree checkout for {intent.plan?.plan_name} is still available.</p><button type="button" onClick={() => window.location.assign(intent.provider_url)}>Continue to Cashfree</button><button type="button" className="secondary" onClick={onRefresh}>Refresh status</button></div>
  }

  return <div className="acquisition-state"><span className="acquisition-spinner" /><h1>Confirming your payment</h1><p>Cashfree has returned control to StayQR. We are waiting for the signed payment confirmation; your hotel will activate automatically.</p><button type="button" className="secondary" onClick={onRefresh}>Refresh now</button></div>
}

function CheckoutShell({ children }) {
  return (
    <main className="acquisition-page">
      <a className="acquisition-brand" href="https://stayqr.in" aria-label="StayQR home">
        <img src={logo} alt="StayQR" />
      </a>
      <div className="acquisition-shell">{children}</div>
      <footer>Secure account and plan activation · <a href="/support">Support</a> · <a href="/legal">Legal &amp; Policies</a></footer>
    </main>
  )
}
