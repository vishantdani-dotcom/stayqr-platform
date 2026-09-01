import { useCallback, useEffect, useState } from 'react'
import {
  invokeCashfreeRecurring,
  loadCommercialReadyWorkspace,
  submitOwnerBillingAction,
} from '../../lib/commercialReady'
import './OwnerBilling.css'

const ACTIVE_STATES = new Set(['active', 'authenticated', 'bank_approval_pending'])

export default function OwnerBilling({ hotel, staff, onNavigate }) {
  const [workspace, setWorkspace] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [notice, setNotice] = useState(null)
  const [reason, setReason] = useState('')
  const hotelId = hotel?.id || null

  const refresh = useCallback(async () => {
    if (!hotelId) return
    setLoading(true)
    try {
      setWorkspace(await loadCommercialReadyWorkspace(hotelId))
    } catch (error) {
      setNotice({ type: 'error', text: error.message })
    } finally {
      setLoading(false)
    }
  }, [hotelId])

  useEffect(() => { refresh() }, [refresh])

  const billing = workspace?.billing || {}
  const subscription = billing.subscription || null
  const plan = billing.plan || null
  const plans = billing.available_plans || []
  const provider = workspace?.providers?.cashfree_recurring || {}
  const support = workspace?.support || {}
  const requests = billing.owner_requests || []
  const autopayActive = ACTIVE_STATES.has(String(subscription?.autopay_status || '').toLowerCase())
  const canInvokeProvider = provider.status === 'active'

  const currentPlanRank = plans.findIndex((item) => item.id === subscription?.plan_id)

  async function action(actionName, payload = {}) {
    const actionReason = String(payload.reason || reason || '').trim()
    if (actionName === 'cancel' && actionReason.length < 3) {
      setNotice({ type: 'error', text: 'Enter a short cancellation reason.' })
      return
    }
    setBusy(actionName)
    setNotice(null)
    try {
      const request = await submitOwnerBillingAction({
        hotelId,
        action: actionName,
        planId: payload.planId || null,
        billingCycle: payload.billingCycle || subscription?.billing_cycle || 'monthly',
        reason: actionReason || `${actionName} requested by hotel owner`,
      })

      const providerActionRequired = ['enable_autopay', 'upgrade', 'downgrade', 'retry_payment'].includes(actionName)
      if (providerActionRequired && canInvokeProvider) {
        const providerAction = actionName === 'enable_autopay' ? 'create' : actionName
        const result = await invokeCashfreeRecurring({
          hotel_id: hotelId,
          action: providerAction,
          request_id: request?.request?.id,
          plan_id: payload.planId || null,
          billing_cycle: payload.billingCycle || subscription?.billing_cycle || 'monthly',
          reason: actionReason || null,
          customer: {
            name: staff?.full_name || hotel?.hotel_name || 'StayQR hotel owner',
            email: staff?.email || null,
            phone: staff?.phone || null,
          },
        })
        const authUrl = result?.authorization_url
        if (authUrl) window.location.assign(authUrl)
      }

      setReason('')
      setNotice({
        type: 'success',
        text: !providerActionRequired
          ? 'Billing action completed.'
          : canInvokeProvider
          ? 'Billing action submitted and synchronized with Cashfree.'
          : 'Billing action recorded. Cashfree recurring activation is still pending, so no AutoPay status was faked.',
      })
      await refresh()
    } catch (error) {
      setNotice({ type: 'error', text: error.message })
      await refresh()
    } finally {
      setBusy('')
    }
  }

  if (!hotelId) return <main className="owner-billing-page">Select a hotel to continue.</main>

  return (
    <main className="owner-billing-page">
      <header className="owner-billing-hero">
        <div><span>HOTEL OWNER BILLING</span><h1>Plan, payments &amp; AutoPay</h1><p>One clear view of your StayQR subscription and provider status.</p></div>
        <button type="button" onClick={refresh} disabled={loading}>Refresh</button>
      </header>

      {notice && <div className={`owner-billing-notice ${notice.type}`}>{notice.text}</div>}

      <section className="owner-billing-summary">
        <Summary label="Current plan" value={plan?.plan_name || 'Not assigned'} />
        <Summary label="Subscription" value={label(subscription?.status || hotel?.subscription_status || 'unknown')} />
        <Summary label="Billing" value={label(subscription?.billing_cycle || 'not configured')} />
        <Summary label="Next renewal" value={date(subscription?.next_charge_at || subscription?.current_period_end)} />
      </section>

      {loading ? <section className="owner-billing-card">Loading secure billing workspace…</section> : null}

      {!loading && (
        <section className="owner-billing-grid">
          <article className="owner-billing-card owner-billing-current">
            <div className="owner-billing-card-head"><div><span>SUBSCRIPTION</span><h2>{plan?.plan_name || 'StayQR plan'}</h2></div><Pill tone={subscription?.status === 'active' ? 'good' : 'warn'}>{label(subscription?.status || 'not configured')}</Pill></div>
            <div className="owner-billing-details">
              <Detail label="Price" value={money(subscription?.amount_minor, subscription?.currency_code)} />
              <Detail label="Trial ends" value={date(subscription?.trial_end || subscription?.end_date)} />
              <Detail label="Current period" value={`${date(subscription?.current_period_start)} – ${date(subscription?.current_period_end)}`} />
              <Detail label="Cancellation" value={subscription?.cancel_at_period_end ? 'Scheduled at period end' : 'Not scheduled'} />
            </div>
          </article>

          <article className="owner-billing-card">
            <div className="owner-billing-card-head"><div><span>CASHFREE RECURRING</span><h2>AutoPay mandate</h2></div><Pill tone={autopayActive ? 'good' : 'warn'}>{autopayActive ? 'ACTIVE' : label(subscription?.autopay_status || provider.status || 'pending')}</Pill></div>
            <p>{provider.status === 'active' ? 'Cashfree recurring capability is provider-enabled for this environment.' : 'Provider activation is pending. StayQR will not show AutoPay as active until Cashfree confirms the mandate.'}</p>
            <div className="owner-billing-details">
              <Detail label="Mandate" value={label(subscription?.mandate_status || 'not created')} />
              <Detail label="Last charge" value={label(subscription?.last_charge_status || 'none')} />
              <Detail label="Retry count" value={subscription?.recurring_retry_count ?? 0} />
              <Detail label="Provider environment" value={label(provider.environment || 'not configured')} />
            </div>
            <button type="button" disabled={Boolean(busy) || autopayActive} onClick={() => action('enable_autopay')}>{busy === 'enable_autopay' ? 'Starting…' : autopayActive ? 'AutoPay active' : 'Set up AutoPay'}</button>
            {subscription?.last_charge_status === 'failed' && <button className="secondary" type="button" disabled={Boolean(busy)} onClick={() => action('retry_payment')}>Retry failed payment</button>}
          </article>

          <article className="owner-billing-card owner-billing-plans">
            <span>AVAILABLE PLANS</span><h2>Change plan</h2>
            <div className="owner-plan-list">
              {plans.map((item, index) => {
                const current = item.id === subscription?.plan_id
                const direction = currentPlanRank < 0 || index > currentPlanRank ? 'upgrade' : 'downgrade'
                return <div key={item.id} className={current ? 'current' : ''}><div><strong>{item.plan_name}</strong><small>{moneyMajor(item.price_monthly, item.currency_code)} monthly · {moneyMajor(item.price_annual, item.currency_code)} yearly</small></div><button type="button" disabled={Boolean(busy) || current} onClick={() => action(direction, { planId: item.id })}>{current ? 'Current plan' : direction === 'upgrade' ? 'Upgrade' : 'Downgrade'}</button></div>
              })}
            </div>
          </article>

          <article className="owner-billing-card">
            <span>CANCELLATION &amp; REACTIVATION</span><h2>Subscription control</h2>
            <p>Cancellation is scheduled for the end of the paid period. Provider action is attempted only when Cashfree recurring is active.</p>
            <label>Reason<textarea value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Reason for cancellation" maxLength={500} /></label>
            <div className="owner-billing-actions"><button className="danger" type="button" disabled={Boolean(busy) || subscription?.cancel_at_period_end} onClick={() => action('cancel')}>Schedule cancellation</button>{subscription?.cancel_at_period_end && <button type="button" disabled={Boolean(busy)} onClick={() => action('reactivate', { reason: 'Owner withdrew scheduled cancellation' })}>Keep subscription</button>}</div>
          </article>

          <article className="owner-billing-card owner-billing-history">
            <span>PAYMENT &amp; REQUEST HISTORY</span><h2>Recent activity</h2>
            <div className="owner-history-list">
              {[...(billing.payment_history || []), ...requests].sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0)).slice(0, 12).map((item) => <div key={`${item.id}-${item.action || item.status}`}><div><strong>{label(item.action || item.event_type || 'payment')}</strong><small>{dateTime(item.created_at || item.occurred_at)}</small></div><Pill tone={['paid', 'completed', 'active'].includes(item.status) ? 'good' : item.status === 'failed' ? 'bad' : 'warn'}>{label(item.status)}</Pill></div>)}
              {(billing.payment_history || []).length === 0 && requests.length === 0 && <p>No billing activity yet.</p>}
            </div>
          </article>

          <article className="owner-billing-card owner-billing-support">
            <div><span>STAYQR SUPPORT</span><h2>24×7 assistance</h2><p>Critical incidents are accepted around the clock. After-hours escalation owner: {support.after_hours_owner || 'Founder'}.</p></div>
            <div className="owner-billing-actions">{support.whatsapp_url ? <a href={support.whatsapp_url} target="_blank" rel="noreferrer">WhatsApp support</a> : <button type="button" disabled>WhatsApp number pending configuration</button>}<button type="button" onClick={() => onNavigate?.('operationscenter', { initialTab: 'support', initialAction: 'create-ticket' })}>Open support ticket</button></div>
          </article>
        </section>
      )}
    </main>
  )
}

function Summary({ label: title, value }) { return <article><span>{title}</span><strong>{value}</strong></article> }
function Detail({ label: title, value }) { return <div><span>{title}</span><strong>{value ?? '—'}</strong></div> }
function Pill({ children, tone = 'warn' }) { return <strong className={`owner-pill ${tone}`}>{children || 'Unknown'}</strong> }
function label(value) { return String(value || 'unknown').replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()) }
function date(value) { if (!value) return 'Not set'; const parsed = new Date(value); return Number.isNaN(parsed.getTime()) ? 'Not set' : parsed.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) }
function dateTime(value) { if (!value) return 'Not set'; const parsed = new Date(value); return Number.isNaN(parsed.getTime()) ? 'Not set' : parsed.toLocaleString('en-IN') }
function money(valueMinor, currency = 'INR') { return new Intl.NumberFormat('en-IN', { style: 'currency', currency: currency || 'INR', maximumFractionDigits: 2 }).format(Number(valueMinor || 0) / 100) }
function moneyMajor(value, currency = 'INR') { return new Intl.NumberFormat('en-IN', { style: 'currency', currency: currency || 'INR', maximumFractionDigits: 0 }).format(Number(value || 0)) }
