import { useCallback, useEffect, useState } from 'react'
import {
  loadCommercialReadyWorkspace,
  submitOwnerBillingAction,
} from '../../lib/commercialReady'
import './OwnerBilling.css'

export default function OwnerBilling({ hotel, onNavigate }) {
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
      setNotice({ type: 'error', text: error.message || 'Unable to load subscription details.' })
    } finally {
      setLoading(false)
    }
  }, [hotelId])

  useEffect(() => { void refresh() }, [refresh])

  const billing = workspace?.billing || {}
  const subscription = billing.subscription || null
  const plan = billing.plan || null
  const plans = billing.available_plans || []
  const requests = billing.owner_requests || []
  const manualPayments = billing.manual_payments || []
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
      await submitOwnerBillingAction({
        hotelId,
        action: actionName,
        planId: payload.planId || null,
        billingCycle: payload.billingCycle || subscription?.billing_cycle || 'monthly',
        reason: actionReason || `${actionName} requested by hotel owner`,
      })

      setReason('')
      setNotice({
        type: 'success',
        text: ['upgrade', 'downgrade'].includes(actionName)
          ? 'Plan-change request recorded. StayQR will confirm the billing update with you.'
          : actionName === 'cancel'
            ? 'Cancellation is scheduled for the end of the current paid period.'
            : actionName === 'reactivate'
              ? 'Scheduled cancellation removed.'
              : 'Billing request recorded.',
      })
      await refresh()
    } catch (error) {
      setNotice({ type: 'error', text: error.message || 'Unable to update subscription.' })
      await refresh()
    } finally {
      setBusy('')
    }
  }

  if (!hotelId) return <main className="owner-billing-page">Select a hotel to continue.</main>

  const paidThrough = subscription?.next_charge_at || subscription?.current_period_end
  const lastManualPayment = manualPayments[0] || null

  return (
    <main className="owner-billing-page">
      <header className="owner-billing-hero">
        <div>
          <span>SUBSCRIPTION &amp; BILLING</span>
          <h1>Plan &amp; payment record</h1>
          <p>Review your StayQR plan, paid-through date, payment history and subscription requests.</p>
        </div>
        <button type="button" onClick={refresh} disabled={loading}>Refresh</button>
      </header>

      {notice && <div className={`owner-billing-notice ${notice.type}`}>{notice.text}</div>}

      <section className="owner-billing-summary">
        <Summary label="Current plan" value={plan?.plan_name || 'Not assigned'} />
        <Summary label="Subscription" value={label(subscription?.status || hotel?.subscription_status || 'unknown')} />
        <Summary label="Billing cycle" value={label(subscription?.billing_cycle || 'not configured')} />
        <Summary label="Paid through" value={date(paidThrough)} />
      </section>

      {loading ? <section className="owner-billing-card">Loading billing details…</section> : null}

      {!loading && (
        <section className="owner-billing-grid">
          <article className="owner-billing-card owner-billing-current">
            <div className="owner-billing-card-head">
              <div><span>CURRENT SUBSCRIPTION</span><h2>{plan?.plan_name || 'StayQR plan'}</h2></div>
              <Pill tone={subscription?.status === 'active' ? 'good' : 'warn'}>{label(subscription?.status || 'not configured')}</Pill>
            </div>
            <div className="owner-billing-details">
              <Detail label="Price" value={money(subscription?.amount_minor, subscription?.currency_code)} />
              <Detail label="Trial ends" value={date(subscription?.trial_end || subscription?.end_date)} />
              <Detail label="Current period" value={`${date(subscription?.current_period_start)} – ${date(subscription?.current_period_end)}`} />
              <Detail label="Collection mode" value="Manual / offline billing" />
              <Detail label="Cancellation" value={subscription?.cancel_at_period_end ? 'Scheduled at period end' : 'Not scheduled'} />
            </div>
          </article>

          <article className="owner-billing-card">
            <div className="owner-billing-card-head">
              <div><span>PAYMENT RECORD</span><h2>Manual billing</h2></div>
              <Pill tone="good">ACTIVE</Pill>
            </div>
            <p>StayQR records confirmed offline payments and keeps your subscription paid-through date visible here. Online AutoPay is not required for launch.</p>
            <div className="owner-billing-details">
              <Detail label="Last payment" value={dateTime(lastManualPayment?.paid_at || subscription?.last_payment_at)} />
              <Detail label="Payment method" value={label(lastManualPayment?.payment_method || 'offline')} />
              <Detail label="Receipt / reference" value={lastManualPayment?.payment_reference || 'Recorded by StayQR'} />
              <Detail label="Online AutoPay" value="Upcoming" />
            </div>
          </article>

          <article className="owner-billing-card owner-billing-plans">
            <span>AVAILABLE PLANS</span><h2>Plan changes</h2>
            <p>Choose a plan to submit a change request. StayQR confirms the billing change before the next collection.</p>
            <div className="owner-plan-list">
              {plans.map((item, index) => {
                const current = item.id === subscription?.plan_id
                const direction = currentPlanRank < 0 || index > currentPlanRank ? 'upgrade' : 'downgrade'
                return (
                  <div key={item.id} className={current ? 'current' : ''}>
                    <div>
                      <strong>{item.plan_name}</strong>
                      <small>{moneyMajor(item.price_monthly, item.currency_code)} monthly · {moneyMajor(item.price_annual, item.currency_code)} yearly</small>
                    </div>
                    <button type="button" disabled={Boolean(busy) || current} onClick={() => action(direction, { planId: item.id })}>
                      {current ? 'Current plan' : direction === 'upgrade' ? 'Request upgrade' : 'Request downgrade'}
                    </button>
                  </div>
                )
              })}
            </div>
          </article>

          <article className="owner-billing-card">
            <span>CANCELLATION &amp; REACTIVATION</span><h2>Subscription control</h2>
            <p>Cancellation is scheduled for the end of the current paid period. You can withdraw the request before it takes effect.</p>
            <label>Reason<textarea value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Reason for cancellation" maxLength={500} /></label>
            <div className="owner-billing-actions">
              <button className="danger" type="button" disabled={Boolean(busy) || subscription?.cancel_at_period_end} onClick={() => action('cancel')}>Schedule cancellation</button>
              {subscription?.cancel_at_period_end && <button type="button" disabled={Boolean(busy)} onClick={() => action('reactivate', { reason: 'Owner withdrew scheduled cancellation' })}>Keep subscription</button>}
            </div>
          </article>

          <article className="owner-billing-card owner-billing-history">
            <span>PAYMENT &amp; REQUEST HISTORY</span><h2>Recent activity</h2>
            <div className="owner-history-list">
              {[...manualPayments.map((payment) => ({ ...payment, action: 'manual_payment', created_at: payment.paid_at })), ...(billing.payment_history || []), ...requests]
                .sort((a, b) => new Date(b.created_at || b.occurred_at || 0) - new Date(a.created_at || a.occurred_at || 0))
                .slice(0, 12)
                .map((item) => (
                  <div key={`${item.id}-${item.action || item.status}`}>
                    <div>
                      <strong>{label(item.action || item.event_type || 'payment')}{item.amount_minor ? ` · ${money(item.amount_minor, item.currency_code)}` : ''}</strong>
                      <small>{dateTime(item.created_at || item.occurred_at)}{item.payment_reference ? ` · ${item.payment_reference}` : ''}</small>
                    </div>
                    <Pill tone={['paid', 'completed', 'active', 'confirmed'].includes(item.status) ? 'good' : item.status === 'failed' ? 'bad' : 'warn'}>{label(item.status)}</Pill>
                  </div>
                ))}
              {(billing.payment_history || []).length === 0 && requests.length === 0 && manualPayments.length === 0 && <p>No billing activity yet.</p>}
            </div>
          </article>

          <article className="owner-billing-card owner-billing-support">
            <div>
              <span>STAYQR SUPPORT</span><h2>Support &amp; escalation</h2>
              <p>Submit support requests anytime. Critical incidents can be escalated to the StayQR team based on operational impact.</p>
            </div>
            <div className="owner-billing-actions">
              <button type="button" onClick={() => onNavigate?.('operationscenter', { initialTab: 'support', initialAction: 'create-ticket' })}>Open support ticket</button>
            </div>
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
