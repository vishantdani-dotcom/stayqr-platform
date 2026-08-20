import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  addSupportMessage,
  cancelSubscription,
  changeSubscriptionPlan,
  createActionKey,
  createCashfreePaymentLink,
  createSupportTicket,
  endSafeSupportAccess,
  extendTrial,
  getActiveSupportSessions,
  getCommercialData,
  getPostlaunchBatch2PlatformMetrics,
  getHotelUsage,
  getPlatformAnnouncements,
  reactivateSubscription,
  reconcileExpiredSubscriptions,
  renewSubscription,
  savePlatformAnnouncement,
  saveSubscriptionPlan,
  startSafeSupportAccess,
  suspendSubscription,
  updateSupportTicketStatus,
} from '../../lib/commercialControl'
import './SuperAdmin.css'

const TABS = [
  { id: 'overview', label: 'Overview' },
  { id: 'hotels', label: 'Hotels & subscriptions' },
  { id: 'plans', label: 'Plans' },
  { id: 'payments', label: 'Payment links' },
  { id: 'support', label: 'Support' },
  { id: 'events', label: 'Events & webhooks' },
  { id: 'announcements', label: 'Announcements' },
]

const EMPTY_DATA = {
  generated_at: null,
  summary: {},
  hotels: [],
  plans: [],
  usage: [],
  payment_links: [],
  support_tickets: [],
  subscription_events: [],
  webhook_events: [],
}

export default function SuperAdmin({ onNavigate }) {
  const [data, setData] = useState(EMPTY_DATA)
  const [platformMetrics, setPlatformMetrics] = useState({})
  const [announcements, setAnnouncements] = useState([])
  const [supportSessions, setSupportSessions] = useState([])
  const [activeTab, setActiveTab] = useState('overview')
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState(null)
  const [query, setQuery] = useState('')
  const [dialog, setDialog] = useState(null)

  const loadData = useCallback(async ({ quiet = false } = {}) => {
    if (quiet) setRefreshing(true)
    else setLoading(true)
    setError('')

    try {
      const [commercial, announcementRows, sessionRows, metricRows] = await Promise.all([
        getCommercialData(150),
        getPlatformAnnouncements(),
        getActiveSupportSessions(),
        getPostlaunchBatch2PlatformMetrics(),
      ])
      setData(commercial)
      setAnnouncements(announcementRows)
      setSupportSessions(sessionRows)
      setPlatformMetrics(metricRows || {})
    } catch (loadError) {
      setError(
        loadError?.message ||
          'StayQR could not load the Super Admin commercial control centre.'
      )
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [])

  useEffect(() => {
    loadData()
  }, [loadData])

  const summary = data.summary || {}
  const normalizedQuery = query.trim().toLowerCase()

  const filteredHotels = useMemo(() => {
    if (!normalizedQuery) return data.hotels
    return data.hotels.filter((hotel) =>
      [
        hotel.hotel_name,
        hotel.slug,
        hotel.city,
        hotel.state,
        hotel.plan_name,
        hotel.lifecycle_status,
        hotel.provider,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(normalizedQuery))
    )
  }, [data.hotels, normalizedQuery])

  const filteredLinks = useMemo(() => {
    if (!normalizedQuery) return data.payment_links
    return data.payment_links.filter((link) =>
      [
        link.hotel_name,
        link.plan_name,
        link.provider,
        link.status,
        link.reference_id,
        link.provider_payment_id,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(normalizedQuery))
    )
  }, [data.payment_links, normalizedQuery])

  const filteredTickets = useMemo(() => {
    if (!normalizedQuery) return data.support_tickets
    return data.support_tickets.filter((ticket) =>
      [
        ticket.hotel_name,
        ticket.subject,
        ticket.description,
        ticket.category,
        ticket.priority,
        ticket.status,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(normalizedQuery))
    )
  }, [data.support_tickets, normalizedQuery])

  function openDialog(type, payload = {}) {
    setNotice(null)
    setDialog({ type, ...payload })
  }

  function closeDialog() {
    setDialog(null)
  }

  async function completeAction(message, result = null) {
    setNotice({ tone: 'success', message, result })
    closeDialog()
    await loadData({ quiet: true })
  }

  function actionFailed(actionError) {
    setNotice({
      tone: 'error',
      message:
        actionError?.message || 'StayQR could not complete the requested action.',
    })
  }

  async function runReconciliation() {
    const confirmed = window.confirm(
      'Run authoritative subscription expiry reconciliation now? This may expire trials, complete scheduled cancellations and suspend affected hotel access.'
    )
    if (!confirmed) return

    setRefreshing(true)
    setNotice(null)
    try {
      const result = await reconcileExpiredSubscriptions()
      await completeAction('Subscription reconciliation completed.', result)
    } catch (actionError) {
      actionFailed(actionError)
      setRefreshing(false)
    }
  }

  if (loading) {
    return (
      <div className="commercial-shell commercial-loading-shell">
        <div className="commercial-loader" />
        <strong>Loading commercial control centre…</strong>
        <span>Authoritative subscriptions, payments and support data</span>
      </div>
    )
  }

  return (
    <div className="commercial-shell">
      <header className="commercial-hero">
        <div>
          <span className="commercial-kicker">Platform control centre</span>
          <h1>Super Admin</h1>
          <p>
            Global commercial operations for plans, hotel subscriptions, Cashfree
            payment links, usage, support and immutable lifecycle evidence.
          </p>
        </div>

        <div className="commercial-hero-actions">
          <button
            type="button"
            className="commercial-btn secondary"
            onClick={() => loadData({ quiet: true })}
            disabled={refreshing}
          >
            {refreshing ? 'Refreshing…' : 'Refresh'}
          </button>
          <button
            type="button"
            className="commercial-btn warning"
            onClick={runReconciliation}
            disabled={refreshing}
          >
            Reconcile expiries
          </button>
          <button
            type="button"
            className="commercial-btn primary"
            onClick={() => onNavigate?.('onboarding')}
          >
            Onboard hotel
          </button>
        </div>
      </header>

      <div className="commercial-runtime-strip">
        <div>
          <span className="runtime-dot" />
          <strong>Cashfree</strong>
          <span>Test environment connected</span>
        </div>
        <div>
          <span>Last server snapshot</span>
          <strong>{formatDateTime(data.generated_at)}</strong>
        </div>
        <div>
          <span>Provider secrets</span>
          <strong>Edge Functions only</strong>
        </div>
      </div>

      {error && <Alert tone="error" message={error} />}
      {notice && (
        <Alert tone={notice.tone} message={notice.message} result={notice.result} />
      )}

      <nav className="commercial-tabs" aria-label="Super Admin sections">
        {TABS.map((tab) => (
          <button
            type="button"
            key={tab.id}
            className={activeTab === tab.id ? 'active' : ''}
            onClick={() => {
              setActiveTab(tab.id)
              setQuery('')
            }}
          >
            {tab.label}
            <TabCount tab={tab.id} data={data} announcements={announcements} />
          </button>
        ))}
      </nav>

      {['hotels', 'payments', 'support'].includes(activeTab) && (
        <div className="commercial-toolbar">
          <label className="commercial-search">
            <span>Search</span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={`Search ${activeTab}…`}
            />
          </label>
          <span className="commercial-result-count">
            {activeTab === 'hotels' && `${filteredHotels.length} hotels`}
            {activeTab === 'payments' && `${filteredLinks.length} links`}
            {activeTab === 'support' && `${filteredTickets.length} tickets`}
          </span>
        </div>
      )}

      {activeTab === 'overview' && (
        <OverviewTab
          data={data}
          summary={summary}
          platformMetrics={platformMetrics}
          onOpenTab={setActiveTab}
          onCreateLink={(hotel) => openDialog('payment-link', { hotel })}
          onManageHotel={(hotel) => openDialog('hotel-actions', { hotel })}
          onViewHotel={(hotel) => openDialog('safe-support', { hotel })}
        />
      )}

      {activeTab === 'hotels' && (
        <HotelsTab
          hotels={filteredHotels}
          plans={data.plans}
          onAction={(hotel) => openDialog('hotel-actions', { hotel })}
          onPayment={(hotel) => openDialog('payment-link', { hotel })}
          onUsage={(hotel) => openDialog('usage', { hotel })}
          onSupport={(hotel) => openDialog('safe-support', { hotel })}
        />
      )}

      {activeTab === 'plans' && (
        <PlansTab
          plans={data.plans}
          onCreate={() => openDialog('plan', { plan: null })}
          onEdit={(plan) => openDialog('plan', { plan })}
        />
      )}

      {activeTab === 'payments' && <PaymentLinksTab links={filteredLinks} />}

      {activeTab === 'support' && (
        <SupportTab
          tickets={filteredTickets}
          supportSessions={supportSessions}
          hotels={data.hotels}
          onCreate={() => openDialog('support-create')}
          onTicket={(ticket) => openDialog('support-ticket', { ticket })}
          onEndSession={(session) =>
            openDialog('safe-support-end', { session })
          }
        />
      )}

      {activeTab === 'events' && (
        <EventsTab
          subscriptionEvents={data.subscription_events}
          webhookEvents={data.webhook_events}
        />
      )}

      {activeTab === 'announcements' && (
        <AnnouncementsTab
          announcements={announcements}
          hotels={data.hotels}
          onCreate={() => openDialog('announcement', { announcement: null })}
          onEdit={(announcement) =>
            openDialog('announcement', { announcement })
          }
        />
      )}

      {dialog && (
        <CommercialDialog title={dialogTitle(dialog)} onClose={closeDialog}>
          {dialog.type === 'plan' && (
            <PlanForm
              plan={dialog.plan}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={(result) =>
                completeAction(
                  dialog.plan ? 'Plan updated.' : 'Plan created.',
                  result
                )
              }
            />
          )}

          {dialog.type === 'hotel-actions' && (
            <HotelActionForm
              hotel={dialog.hotel}
              plans={data.plans}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={completeAction}
            />
          )}

          {dialog.type === 'payment-link' && (
            <PaymentLinkForm
              hotel={dialog.hotel}
              plans={data.plans}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={(result) =>
                completeAction('Cashfree payment link created.', result)
              }
            />
          )}

          {dialog.type === 'usage' && (
            <UsagePanel hotel={dialog.hotel} onClose={closeDialog} />
          )}

          {dialog.type === 'support-create' && (
            <SupportCreateForm
              hotels={data.hotels}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={(result) =>
                completeAction('Support ticket created.', result)
              }
            />
          )}

          {dialog.type === 'support-ticket' && (
            <SupportTicketForm
              ticket={dialog.ticket}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={completeAction}
            />
          )}

          {dialog.type === 'safe-support' && (
            <SafeSupportForm
              hotel={dialog.hotel}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={(result) =>
                completeAction('Audited View as Hotel access started.', result)
              }
            />
          )}

          {dialog.type === 'safe-support-end' && (
            <SafeSupportEndForm
              session={dialog.session}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={(result) =>
                completeAction('Safe support session ended.', result)
              }
            />
          )}

          {dialog.type === 'announcement' && (
            <AnnouncementForm
              announcement={dialog.announcement}
              hotels={data.hotels}
              onCancel={closeDialog}
              onError={actionFailed}
              onSuccess={(result) =>
                completeAction('Announcement saved.', result)
              }
            />
          )}
        </CommercialDialog>
      )}
    </div>
  )
}

function OverviewTab({
  data,
  summary,
  platformMetrics,
  onOpenTab,
  onCreateLink,
  onManageHotel,
  onViewHotel,
}) {
  const hotels = summary.hotels || {}
  const subscriptions = summary.subscriptions || {}
  const revenue = summary.revenue || {}
  const support = summary.support || {}
  const webhooks = summary.webhooks || {}
  const usage = summary.usage || {}
  const attentionHotels = data.hotels.filter((hotel) =>
    ['past_due', 'suspended', 'expired', 'cancelled'].includes(
      hotel.lifecycle_status || hotel.subscription_status
    )
  )
  const recentLinks = data.payment_links.slice(0, 5)

  return (
    <section className="commercial-tab-panel">
      <div className="commercial-metrics-grid">
        <MetricCard
          label="Monthly recurring revenue"
          value={formatMoney(revenue.mrr_minor, revenue.currency_code, true)}
          meta={`${subscriptions.active_paid || 0} paid subscriptions`}
          tone="gold"
        />
        <MetricCard
          label="Active hotels"
          value={hotels.active || 0}
          meta={`${hotels.total || data.hotels.length} total hotels`}
          tone="green"
        />
        <MetricCard
          label="Trials"
          value={subscriptions.trialing || 0}
          meta={`${subscriptions.trials_expiring_7_days || 0} expiring in 7 days`}
          tone="blue"
        />
        <MetricCard
          label="Open support"
          value={support.open || 0}
          meta={`${support.urgent_open || 0} urgent`}
          tone={support.urgent_open ? 'red' : 'neutral'}
        />
        <MetricCard
          label="Webhook failures"
          value={webhooks.failed || 0}
          meta={`${webhooks.pending || 0} pending`}
          tone={webhooks.failed ? 'red' : 'green'}
        />
        <MetricCard
          label="Capacity exceptions"
          value={
            Number(usage.hotels_over_room_limit || 0) +
            Number(usage.hotels_over_staff_limit || 0)
          }
          meta={`${usage.hotels_over_room_limit || 0} room · ${usage.hotels_over_staff_limit || 0} staff`}
          tone="warning"
        />
        <MetricCard
          label="Total guests"
          value={platformMetrics.total_guests || 0}
          meta={`${platformMetrics.active_stays || 0} active stays`}
          tone="blue"
        />
        <MetricCard
          label="Guest document scans"
          value={platformMetrics.document_scans || 0}
          meta="Private hotel-scoped records"
          tone="neutral"
        />
        <MetricCard
          label="Reservations"
          value={platformMetrics.reservations || 0}
          meta={`${platformMetrics.rooms || 0} rooms across platform`}
          tone="green"
        />
        <MetricCard
          label="Hotel staff"
          value={platformMetrics.staff || 0}
          meta="Active and inactive records"
          tone="neutral"
        />
        <MetricCard
          label="Guest guide QR scans"
          value={platformMetrics.guest_guide_qr_scans_total || 0}
          meta={`${platformMetrics.guest_guide_qr_scans_unique || 0} unique guest access links`}
          tone="gold"
        />
      </div>

      <div className="commercial-overview-grid">
        <div className="commercial-card">
          <SectionHeader
            eyebrow="Attention queue"
            title="Hotels requiring commercial action"
            action={
              <button type="button" className="text-action" onClick={() => onOpenTab('hotels')}>
                View all
              </button>
            }
          />
          {attentionHotels.length === 0 ? (
            <EmptyState
              title="No commercial exceptions"
              text="No current hotel is past due, suspended, expired or cancelled."
            />
          ) : (
            <div className="commercial-list">
              {attentionHotels.slice(0, 6).map((hotel) => (
                <div className="commercial-list-row" key={hotel.id}>
                  <div>
                    <strong>{hotel.hotel_name}</strong>
                    <span>
                      {hotel.plan_name || 'No plan'} ·{' '}
                      {humanize(hotel.lifecycle_status || hotel.subscription_status)}
                    </span>
                  </div>
                  <button
                    type="button"
                    className="small-action"
                    onClick={() => onManageHotel(hotel)}
                  >
                    Manage
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="commercial-card">
          <SectionHeader
            eyebrow="Cashfree ledger"
            title="Recent payment links"
            action={
              <button type="button" className="text-action" onClick={() => onOpenTab('payments')}>
                View ledger
              </button>
            }
          />
          {recentLinks.length === 0 ? (
            <EmptyState
              title="No payment links"
              text="Create a controlled Cashfree link from a hotel subscription."
            />
          ) : (
            <div className="commercial-list">
              {recentLinks.map((link) => (
                <div className="commercial-list-row" key={link.id}>
                  <div>
                    <strong>{link.hotel_name}</strong>
                    <span>
                      {formatMoney(link.amount_minor, link.currency_code, true)} ·{' '}
                      {humanize(link.status)}
                    </span>
                  </div>
                  <StatusBadge status={link.status} />
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="commercial-card">
        <SectionHeader
          eyebrow="Quick commercial actions"
          title="Start from a hotel"
        />
        <div className="quick-hotel-grid">
          {data.hotels.slice(0, 6).map((hotel) => (
            <article key={hotel.id} className="quick-hotel-card">
              <div>
                <strong>{hotel.hotel_name}</strong>
                <span>{hotel.plan_name || 'No current plan'}</span>
              </div>
              <div className="quick-hotel-actions">
                <button type="button" onClick={() => onManageHotel(hotel)}>
                  Lifecycle
                </button>
                <button type="button" onClick={() => onCreateLink(hotel)}>
                  Payment link
                </button>
                <button type="button" onClick={() => onViewHotel(hotel)}>
                  View as Hotel
                </button>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}

function HotelsTab({ hotels, onAction, onPayment, onUsage, onSupport }) {
  return (
    <section className="commercial-tab-panel">
      <div className="commercial-card table-card">
        <SectionHeader
          eyebrow="Tenant commercial state"
          title="Hotels and subscriptions"
        />
        {hotels.length === 0 ? (
          <EmptyState title="No hotels match" text="Try a different search." />
        ) : (
          <div className="commercial-table-wrap">
            <table className="commercial-table hotels-table">
              <thead>
                <tr>
                  <th>Hotel</th>
                  <th>Plan</th>
                  <th>Lifecycle</th>
                  <th>Commercial</th>
                  <th>Period</th>
                  <th>Provider</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {hotels.map((hotel) => (
                  <tr key={hotel.id}>
                    <td>
                      <strong>{hotel.hotel_name}</strong>
                      <span>{hotel.slug || hotel.city || 'No slug'}</span>
                    </td>
                    <td>
                      <strong>{hotel.plan_name || 'No plan'}</strong>
                      <span>{hotel.plan_code || '—'}</span>
                    </td>
                    <td>
                      <StatusBadge
                        status={hotel.lifecycle_status || hotel.subscription_status}
                      />
                      <span className="table-subtext">Hotel: {humanize(hotel.status)}</span>
                    </td>
                    <td>
                      <strong>{humanize(hotel.billing_mode || 'missing')}</strong>
                      <span>
                        {formatMoney(
                          hotel.amount_minor,
                          hotel.subscription_currency || hotel.currency_code,
                          true
                        )}{' '}
                        {hotel.billing_cycle && hotel.billing_cycle !== 'none'
                          ? `/ ${humanize(hotel.billing_cycle)}`
                          : ''}
                      </span>
                    </td>
                    <td>
                      <strong>{formatDate(hotel.current_period_end || hotel.trial_ends_at)}</strong>
                      <span>{hotel.trial_ends_at ? 'Trial / period end' : 'Current period end'}</span>
                    </td>
                    <td>
                      <strong>{humanize(hotel.provider || 'manual')}</strong>
                      <span>{humanize(hotel.provider_status || '—')}</span>
                    </td>
                    <td>
                      <div className="row-actions">
                        <button type="button" onClick={() => onAction(hotel)}>
                          Manage
                        </button>
                        <button type="button" onClick={() => onPayment(hotel)}>
                          Link
                        </button>
                        <button type="button" onClick={() => onUsage(hotel)}>
                          Usage
                        </button>
                        <button type="button" onClick={() => onSupport(hotel)}>
                          View as Hotel
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  )
}

function PlansTab({ plans, onCreate, onEdit }) {
  return (
    <section className="commercial-tab-panel">
      <div className="panel-heading-row">
        <div>
          <span className="commercial-kicker">Product catalogue</span>
          <h2>Subscription plans and limits</h2>
        </div>
        <button type="button" className="commercial-btn primary" onClick={onCreate}>
          Create plan
        </button>
      </div>

      {plans.length === 0 ? (
        <div className="commercial-card">
          <EmptyState title="No plans found" text="Create the first subscription plan." />
        </div>
      ) : (
        <div className="plans-grid">
          {plans.map((plan) => (
            <article className="plan-card" key={plan.id}>
              <div className="plan-card-topline">
                <StatusBadge status={plan.status} />
                <span>{plan.current_hotels || 0} current hotels</span>
              </div>
              <h3>{plan.plan_name}</h3>
              <p className="plan-code">{plan.plan_code}</p>
              <div className="plan-price">
                {formatMoneyFromMajor(plan.price_monthly, plan.currency_code)}
                <span>/month</span>
              </div>
              <div className="plan-annual">
                {plan.price_annual != null
                  ? `${formatMoneyFromMajor(plan.price_annual, plan.currency_code)} annual`
                  : 'Annual price not configured'}
              </div>
              <div className="plan-limits">
                <Limit label="Rooms" value={plan.max_rooms} />
                <Limit label="Staff" value={plan.max_staff} />
                <Limit label="Properties" value={plan.max_properties} />
                <Limit label="Trial" value={`${plan.trial_days || 0} days`} />
              </div>
              <Features features={plan.features} />
              <button type="button" className="commercial-btn secondary full" onClick={() => onEdit(plan)}>
                Edit plan
              </button>
            </article>
          ))}
        </div>
      )}
    </section>
  )
}

function PaymentLinksTab({ links }) {
  const paid = links.filter((link) => link.status === 'paid')
  const open = links.filter((link) => ['created', 'issued', 'partially_paid'].includes(link.status))
  const failed = links.filter((link) => ['failed', 'expired', 'cancelled'].includes(link.status))

  return (
    <section className="commercial-tab-panel">
      <div className="commercial-metrics-grid compact">
        <MetricCard label="Ledger rows" value={links.length} meta="Visible records" tone="neutral" />
        <MetricCard label="Paid" value={paid.length} meta={formatMoney(paid.reduce((sum, link) => sum + Number(link.amount_minor || 0), 0), 'INR', true)} tone="green" />
        <MetricCard label="Open" value={open.length} meta="Awaiting final state" tone="blue" />
        <MetricCard label="Failed / closed" value={failed.length} meta="Review exceptions" tone={failed.length ? 'warning' : 'neutral'} />
      </div>

      <div className="commercial-card table-card">
        <SectionHeader eyebrow="Provider ledger" title="Cashfree payment links" />
        {links.length === 0 ? (
          <EmptyState title="No payment links match" text="Create a link from Hotels & subscriptions." />
        ) : (
          <div className="commercial-table-wrap">
            <table className="commercial-table payment-table">
              <thead>
                <tr>
                  <th>Hotel / plan</th>
                  <th>Amount</th>
                  <th>Status</th>
                  <th>Reference</th>
                  <th>Payment</th>
                  <th>Created / expiry</th>
                  <th>Link</th>
                </tr>
              </thead>
              <tbody>
                {links.map((link) => (
                  <tr key={link.id}>
                    <td>
                      <strong>{link.hotel_name}</strong>
                      <span>{link.plan_name}</span>
                    </td>
                    <td>
                      <strong>{formatMoney(link.amount_minor, link.currency_code, true)}</strong>
                      <span>{humanize(link.billing_cycle)}</span>
                    </td>
                    <td><StatusBadge status={link.status} /></td>
                    <td>
                      <code className="compact-code">{truncate(link.reference_id, 22)}</code>
                      <span>{humanize(link.provider)}</span>
                    </td>
                    <td>
                      <strong>{link.provider_payment_id ? truncate(link.provider_payment_id, 20) : '—'}</strong>
                      <span>{link.paid_at ? formatDateTime(link.paid_at) : link.failure_reason || 'Not paid'}</span>
                    </td>
                    <td>
                      <strong>{formatDateTime(link.created_at)}</strong>
                      <span>Expires {formatDateTime(link.expires_at)}</span>
                    </td>
                    <td>
                      {link.provider_url ? (
                        <a className="small-action link-action" href={link.provider_url} target="_blank" rel="noreferrer">
                          Open
                        </a>
                      ) : (
                        <span>—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  )
}

function SupportTab({ tickets, supportSessions, hotels, onCreate, onTicket, onEndSession }) {
  return (
    <section className="commercial-tab-panel">
      <div className="panel-heading-row">
        <div>
          <span className="commercial-kicker">Audited support operations</span>
          <h2>Support tickets and time-bound access</h2>
        </div>
        <button type="button" className="commercial-btn primary" onClick={onCreate}>
          Create ticket
        </button>
      </div>

      {supportSessions.length > 0 && (
        <div className="commercial-card active-session-card">
          <SectionHeader eyebrow="Security" title="Active safe-support sessions" />
          <div className="commercial-list">
            {supportSessions.map((session) => {
              const hotel = hotels.find((row) => row.id === session.hotel_id)
              return (
                <div className="commercial-list-row" key={session.id}>
                  <div>
                    <strong>{hotel?.hotel_name || session.hotel_id}</strong>
                    <span>
                      {session.permissions?.map(humanize).join(', ') || 'Read only'} · expires {formatDateTime(session.expires_at)}
                    </span>
                  </div>
                  <button type="button" className="small-action danger" onClick={() => onEndSession(session)}>
                    End access
                  </button>
                </div>
              )
            })}
          </div>
        </div>
      )}

      <div className="commercial-card table-card">
        <SectionHeader eyebrow="Ticket queue" title="Hotel support" />
        {tickets.length === 0 ? (
          <EmptyState title="No support tickets match" text="No ticket requires attention for this search." />
        ) : (
          <div className="commercial-table-wrap">
            <table className="commercial-table support-table">
              <thead>
                <tr>
                  <th>Hotel</th>
                  <th>Ticket</th>
                  <th>Category</th>
                  <th>Priority</th>
                  <th>Status</th>
                  <th>Updated</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {tickets.map((ticket) => (
                  <tr key={ticket.id}>
                    <td><strong>{ticket.hotel_name}</strong></td>
                    <td>
                      <strong>{ticket.subject}</strong>
                      <span>{truncate(ticket.description, 80)}</span>
                    </td>
                    <td>{humanize(ticket.category)}</td>
                    <td><StatusBadge status={ticket.priority} /></td>
                    <td><StatusBadge status={ticket.status} /></td>
                    <td>{formatDateTime(ticket.updated_at)}</td>
                    <td>
                      <button type="button" className="small-action" onClick={() => onTicket(ticket)}>
                        Triage
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  )
}

function EventsTab({ subscriptionEvents, webhookEvents }) {
  return (
    <section className="commercial-tab-panel events-grid">
      <div className="commercial-card table-card">
        <SectionHeader eyebrow="Immutable ledger" title="Subscription events" />
        <div className="event-stream">
          {subscriptionEvents.length === 0 ? (
            <EmptyState title="No events" text="No subscription lifecycle events are visible." />
          ) : (
            subscriptionEvents.map((event) => (
              <article className="event-row" key={event.id}>
                <span className="event-icon subscription">S</span>
                <div>
                  <strong>{humanize(event.event_type)}</strong>
                  <p>
                    {event.hotel_name} · {humanize(event.event_source)}
                  </p>
                  <small>
                    {event.old_status ? `${humanize(event.old_status)} → ` : ''}
                    {humanize(event.new_status || event.old_status || 'recorded')} · {formatDateTime(event.occurred_at)}
                  </small>
                </div>
              </article>
            ))
          )}
        </div>
      </div>

      <div className="commercial-card table-card">
        <SectionHeader eyebrow="Signed provider receipts" title="Webhook health" />
        <div className="event-stream">
          {webhookEvents.length === 0 ? (
            <EmptyState title="No webhook events" text="No provider receipts are visible." />
          ) : (
            webhookEvents.map((event) => (
              <article className="event-row" key={event.id}>
                <span className={`event-icon webhook ${event.processing_status}`}>W</span>
                <div>
                  <div className="event-title-line">
                    <strong>{humanize(event.event_type)}</strong>
                    <StatusBadge status={event.processing_status} />
                  </div>
                  <p>
                    {humanize(event.provider)} · signature {event.signature_valid ? 'valid' : 'invalid'} · attempts {event.attempts || 0}
                  </p>
                  <small>
                    {event.hotel_name || 'Unmatched test/provider event'} · {formatDateTime(event.received_at)}
                  </small>
                  {event.last_error && <em>{event.last_error}</em>}
                </div>
              </article>
            ))
          )}
        </div>
      </div>
    </section>
  )
}

function AnnouncementsTab({ announcements, onCreate, onEdit }) {
  return (
    <section className="commercial-tab-panel">
      <div className="panel-heading-row">
        <div>
          <span className="commercial-kicker">Platform communications</span>
          <h2>Announcements</h2>
        </div>
        <button type="button" className="commercial-btn primary" onClick={onCreate}>
          New announcement
        </button>
      </div>

      <div className="announcement-grid">
        {announcements.length === 0 ? (
          <div className="commercial-card">
            <EmptyState title="No announcements" text="Create a global or hotel-targeted announcement." />
          </div>
        ) : (
          announcements.map((announcement) => (
            <article className={`announcement-card ${announcement.severity || 'info'}`} key={announcement.id}>
              <div className="announcement-meta">
                <StatusBadge status={announcement.status} />
                <span>{humanize(announcement.scope)}</span>
                <span>{humanize(announcement.severity)}</span>
              </div>
              <h3>{announcement.title}</h3>
              <p>{announcement.body}</p>
              <div className="announcement-dates">
                <span>Starts {formatDateTime(announcement.starts_at)}</span>
                <span>Ends {formatDateTime(announcement.ends_at)}</span>
              </div>
              <button type="button" className="commercial-btn secondary full" onClick={() => onEdit(announcement)}>
                Edit announcement
              </button>
            </article>
          ))
        )}
      </div>
    </section>
  )
}

function PlanForm({ plan, onCancel, onError, onSuccess }) {
  const [form, setForm] = useState(() => ({
    id: plan?.id || '',
    plan_name: plan?.plan_name || '',
    plan_code: plan?.plan_code || '',
    price_monthly: plan?.price_monthly ?? '',
    price_annual: plan?.price_annual ?? '',
    currency_code: plan?.currency_code || 'INR',
    max_rooms: plan?.max_rooms ?? '',
    max_staff: plan?.max_staff ?? '',
    max_properties: plan?.max_properties ?? 1,
    max_storage_mb: plan?.max_storage_mb ?? '',
    trial_days: plan?.trial_days ?? 14,
    status: plan?.status || 'active',
    is_public: plan?.is_public ?? true,
    features: featuresToText(plan?.features),
  }))
  const [busy, setBusy] = useState(false)

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      const payload = {
        ...(form.id ? { id: form.id } : {}),
        plan_name: form.plan_name.trim(),
        plan_code: form.plan_code.trim(),
        price_monthly: numberOrZero(form.price_monthly),
        price_annual: nullableNumber(form.price_annual),
        currency_code: form.currency_code.trim().toUpperCase(),
        max_rooms: nullableInteger(form.max_rooms),
        max_staff: nullableInteger(form.max_staff),
        max_properties: Number(form.max_properties || 1),
        max_storage_mb: nullableInteger(form.max_storage_mb),
        trial_days: Number(form.trial_days || 0),
        status: form.status,
        is_public: Boolean(form.is_public),
        features: textToFeatures(form.features),
      }
      const result = await saveSubscriptionPlan(payload)
      await onSuccess(result)
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  return (
    <form className="commercial-form" onSubmit={submit}>
      <div className="form-grid two">
        <Field label="Plan name" required>
          <input required value={form.plan_name} onChange={(event) => setForm({ ...form, plan_name: event.target.value })} />
        </Field>
        <Field label="Plan code" required>
          <input required value={form.plan_code} onChange={(event) => setForm({ ...form, plan_code: event.target.value.toUpperCase() })} placeholder="GROWTH" />
        </Field>
        <Field label="Monthly price" required>
          <input type="number" min="0" step="0.01" required value={form.price_monthly} onChange={(event) => setForm({ ...form, price_monthly: event.target.value })} />
        </Field>
        <Field label="Annual price">
          <input type="number" min="0" step="0.01" value={form.price_annual} onChange={(event) => setForm({ ...form, price_annual: event.target.value })} />
        </Field>
        <Field label="Currency">
          <input maxLength="3" value={form.currency_code} onChange={(event) => setForm({ ...form, currency_code: event.target.value.toUpperCase() })} />
        </Field>
        <Field label="Trial days">
          <input type="number" min="0" max="90" value={form.trial_days} onChange={(event) => setForm({ ...form, trial_days: event.target.value })} />
        </Field>
        <Field label="Room limit">
          <input type="number" min="1" value={form.max_rooms} onChange={(event) => setForm({ ...form, max_rooms: event.target.value })} placeholder="Unlimited when blank" />
        </Field>
        <Field label="Staff limit">
          <input type="number" min="1" value={form.max_staff} onChange={(event) => setForm({ ...form, max_staff: event.target.value })} placeholder="Unlimited when blank" />
        </Field>
        <Field label="Property limit">
          <input type="number" min="1" value={form.max_properties} onChange={(event) => setForm({ ...form, max_properties: event.target.value })} />
        </Field>
        <Field label="Storage MB">
          <input type="number" min="1" value={form.max_storage_mb} onChange={(event) => setForm({ ...form, max_storage_mb: event.target.value })} />
        </Field>
        <Field label="Status">
          <select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value })}>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
            <option value="archived">Archived</option>
          </select>
        </Field>
        <Field label="Public plan">
          <label className="check-control">
            <input type="checkbox" checked={form.is_public} onChange={(event) => setForm({ ...form, is_public: event.target.checked })} />
            Visible for onboarding and sales
          </label>
        </Field>
      </div>
      <Field label="Features" hint="One feature per line">
        <textarea rows="6" value={form.features} onChange={(event) => setForm({ ...form, features: event.target.value })} />
      </Field>
      <FormActions onCancel={onCancel} busy={busy} submitLabel={plan ? 'Save plan' : 'Create plan'} />
    </form>
  )
}

function HotelActionForm({ hotel, plans, onCancel, onError, onSuccess }) {
  const lifecycle = String(
    hotel.lifecycle_status || hotel.subscription_status || ''
  ).toLowerCase()
  const requiresPaymentRecovery = ['expired', 'cancelled'].includes(lifecycle)
  const canRenew = ['active', 'past_due', 'suspended'].includes(lifecycle)
  const defaultAction = ['trial', 'trialing'].includes(lifecycle)
    ? 'extend'
    : lifecycle === 'suspended'
      ? 'reactivate'
      : requiresPaymentRecovery
        ? ''
        : 'change-plan'
  const [action, setAction] = useState(defaultAction)
  const [reason, setReason] = useState('')
  const [days, setDays] = useState('7')
  const [planId, setPlanId] = useState(hotel.plan_id || plans[0]?.id || '')
  const selectedPlan = plans.find((plan) => plan.id === planId)
  const [amount, setAmount] = useState(String(
    selectedPlan?.price_monthly ??
      (hotel.amount_minor != null ? hotel.amount_minor / 100 : '')
  ))
  const [billingCycle, setBillingCycle] = useState(
    hotel.billing_cycle === 'annual' ? 'annual' : 'monthly'
  )
  const [periodStart, setPeriodStart] = useState(toLocalDateTime(new Date()))
  const [periodEnd, setPeriodEnd] = useState(
    toLocalDateTime(addDays(new Date(), billingCycle === 'annual' ? 365 : 30))
  )
  const [immediate, setImmediate] = useState(false)
  const [actionKey] = useState(() => createActionKey('day9:admin-action'))
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    const plan = plans.find((row) => row.id === planId)
    if (!plan) return
    if (billingCycle === 'annual' && plan.price_annual == null) {
      setBillingCycle('monthly')
      return
    }
    const nextAmount =
      billingCycle === 'annual' ? plan.price_annual : plan.price_monthly
    if (nextAmount != null) setAmount(String(nextAmount))
  }, [billingCycle, planId, plans])

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      let result
      let message

      if (action === 'extend') {
        result = await extendTrial(hotel.id, days, reason, actionKey)
        message = `Trial extended by ${days} days.`
      } else if (action === 'suspend') {
        result = await suspendSubscription(hotel.id, reason, actionKey)
        message = 'Hotel subscription suspended.'
      } else if (action === 'reactivate') {
        result = await reactivateSubscription(hotel.id, reason, actionKey)
        message = 'Hotel subscription reactivated.'
      } else if (action === 'change-plan') {
        result = await changeSubscriptionPlan(hotel.id, {
          plan_id: planId,
          amount_minor: Math.round(Number(amount || 0) * 100),
          currency_code:
            selectedPlan?.currency_code ||
            hotel.subscription_currency ||
            'INR',
          reason,
          idempotency_key: actionKey,
        })
        message = 'Hotel subscription plan changed.'
      } else if (action === 'renew' && canRenew) {
        result = await renewSubscription(hotel.id, {
          billing_cycle: billingCycle,
          amount_minor: Math.round(Number(amount || 0) * 100),
          currency_code:
            selectedPlan?.currency_code ||
            hotel.subscription_currency ||
            'INR',
          provider: hotel.provider || 'manual',
          provider_status: 'active',
          current_period_start: new Date(periodStart).toISOString(),
          current_period_end: new Date(periodEnd).toISOString(),
          last_payment_at: new Date().toISOString(),
          idempotency_key: actionKey,
          metadata: { reason },
        })
        message = 'Subscription period renewed.'
      } else if (action === 'cancel') {
        result = await cancelSubscription(
          hotel.id,
          reason,
          immediate,
          actionKey
        )
        message = immediate
          ? 'Subscription cancelled immediately.'
          : 'Cancellation scheduled for period end.'
      } else {
        throw new Error(
          'This lifecycle action is not allowed for the current subscription state.'
        )
      }

      await onSuccess(message, result)
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  const reasonRequired = [
    'extend',
    'suspend',
    'reactivate',
    'change-plan',
    'renew',
    'cancel',
  ].includes(action)

  if (requiresPaymentRecovery) {
    return (
      <div className="commercial-form">
        <div className="dialog-context-card">
          <div><span>Hotel</span><strong>{hotel.hotel_name}</strong></div>
          <div><span>Current plan</span><strong>{hotel.plan_name || 'No plan'}</strong></div>
          <div><span>Lifecycle</span><StatusBadge status={lifecycle} /></div>
        </div>
        <div className="security-callout recovery-callout">
          <strong>Payment recovery required</strong>
          <span>
            Expired and cancelled subscriptions are not renewable through the
            manual renewal RPC. Close this window and use the Link action to
            create a controlled Cashfree payment link. A successful signed
            webhook is the authoritative recovery path.
          </span>
        </div>
        <div className="form-actions">
          <button
            type="button"
            className="commercial-btn secondary"
            onClick={onCancel}
          >
            Close
          </button>
        </div>
      </div>
    )
  }

  return (
    <form className="commercial-form" onSubmit={submit}>
      <div className="dialog-context-card">
        <div><span>Hotel</span><strong>{hotel.hotel_name}</strong></div>
        <div><span>Current plan</span><strong>{hotel.plan_name || 'No plan'}</strong></div>
        <div><span>Lifecycle</span><StatusBadge status={lifecycle} /></div>
      </div>

      <Field label="Action">
        <select value={action} onChange={(event) => setAction(event.target.value)}>
          {['trial', 'trialing'].includes(lifecycle) && (
            <option value="extend">Extend trial</option>
          )}
          {lifecycle !== 'suspended' && (
            <option value="suspend">Suspend access</option>
          )}
          {lifecycle === 'suspended' && (
            <option value="reactivate">Reactivate</option>
          )}
          <option value="change-plan">Change plan</option>
          {canRenew && <option value="renew">Renew period</option>}
          <option value="cancel">Cancel subscription</option>
        </select>
      </Field>

      {action === 'extend' && (
        <Field label="Extension days" hint="1–60 days">
          <input
            type="number"
            min="1"
            max="60"
            required
            value={days}
            onChange={(event) => setDays(event.target.value)}
          />
        </Field>
      )}

      {['change-plan', 'renew'].includes(action) && (
        <div className="form-grid two">
          {action === 'change-plan' && (
            <Field label="Target plan">
              <select
                required
                value={planId}
                onChange={(event) => setPlanId(event.target.value)}
              >
                {plans
                  .filter((plan) => plan.status === 'active')
                  .map((plan) => (
                    <option key={plan.id} value={plan.id}>
                      {plan.plan_name}
                    </option>
                  ))}
              </select>
            </Field>
          )}
          <Field label="Billing cycle">
            <select
              value={billingCycle}
              onChange={(event) => setBillingCycle(event.target.value)}
            >
              <option value="monthly">Monthly</option>
              <option
                value="annual"
                disabled={selectedPlan?.price_annual == null}
              >
                {selectedPlan?.price_annual == null
                  ? 'Annual — not configured'
                  : 'Annual'}
              </option>
            </select>
          </Field>
          <Field label="Amount">
            <input
              type="number"
              min="0"
              step="0.01"
              required
              value={amount}
              onChange={(event) => setAmount(event.target.value)}
            />
          </Field>
        </div>
      )}

      {action === 'renew' && (
        <div className="form-grid two">
          <Field label="Period start">
            <input
              type="datetime-local"
              required
              value={periodStart}
              onChange={(event) => setPeriodStart(event.target.value)}
            />
          </Field>
          <Field label="Period end">
            <input
              type="datetime-local"
              required
              value={periodEnd}
              onChange={(event) => setPeriodEnd(event.target.value)}
            />
          </Field>
        </div>
      )}

      {action === 'cancel' && (
        <label className="danger-choice">
          <input
            type="checkbox"
            checked={immediate}
            onChange={(event) => setImmediate(event.target.checked)}
          />
          <span>
            <strong>Cancel immediately</strong>
            <small>
              Immediately suspends hotel access. Leave unchecked to schedule
              cancellation at period end.
            </small>
          </span>
        </label>
      )}

      <Field label="Reason / audit note" required={reasonRequired}>
        <textarea
          rows="4"
          required={reasonRequired}
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Explain why this commercial action is required."
        />
      </Field>

      <div className="idempotency-note">
        <span>Idempotency key</span>
        <code>{actionKey}</code>
      </div>
      <FormActions
        onCancel={onCancel}
        busy={busy}
        submitLabel="Confirm action"
        danger={['suspend', 'cancel'].includes(action)}
      />
    </form>
  )
}

function PaymentLinkForm({ hotel, plans, onCancel, onError, onSuccess }) {
  const [planId, setPlanId] = useState(hotel.plan_id || plans[0]?.id || '')
  const [billingCycle, setBillingCycle] = useState('monthly')
  const [customerName, setCustomerName] = useState(`${hotel.hotel_name} Billing`)
  const [customerEmail, setCustomerEmail] = useState('')
  const [customerPhone, setCustomerPhone] = useState('')
  const [expiresInDays, setExpiresInDays] = useState('7')
  const [sendEmail, setSendEmail] = useState(false)
  const [sendSms, setSendSms] = useState(false)
  const [sendWhatsapp, setSendWhatsapp] = useState(false)
  const [requestId] = useState(() => globalThis.crypto?.randomUUID?.() || createActionKey('cashfree').split(':').pop())
  const [busy, setBusy] = useState(false)
  const selectedPlan = plans.find((plan) => plan.id === planId)
  const price = billingCycle === 'annual' ? selectedPlan?.price_annual : selectedPlan?.price_monthly

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      if (price == null) throw new Error(`The ${billingCycle} price is not configured for this plan.`)
      const result = await createCashfreePaymentLink({
        hotel_id: hotel.id,
        plan_id: planId,
        billing_cycle: billingCycle,
        customer_name: customerName.trim(),
        customer_email: customerEmail.trim() || undefined,
        customer_phone: customerPhone.trim(),
        expires_in_days: Number(expiresInDays),
        send_email: sendEmail,
        send_sms: sendSms,
        send_whatsapp: sendWhatsapp,
        request_id: requestId,
      })
      await onSuccess(result)
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  return (
    <form className="commercial-form" onSubmit={submit}>
      <div className="cashfree-test-banner">
        <strong>Cashfree test environment</strong>
        <span>No production activation is performed from this screen.</span>
      </div>
      <div className="dialog-context-card">
        <div><span>Hotel</span><strong>{hotel.hotel_name}</strong></div>
        <div><span>Current lifecycle</span><StatusBadge status={hotel.lifecycle_status || hotel.subscription_status} /></div>
      </div>
      <div className="form-grid two">
        <Field label="Plan">
          <select value={planId} onChange={(event) => setPlanId(event.target.value)} required>
            {plans.filter((plan) => plan.status === 'active').map((plan) => (
              <option value={plan.id} key={plan.id}>{plan.plan_name}</option>
            ))}
          </select>
        </Field>
        <Field label="Billing cycle">
          <select value={billingCycle} onChange={(event) => setBillingCycle(event.target.value)}>
            <option value="monthly">Monthly</option>
            <option value="annual" disabled={selectedPlan?.price_annual == null}>
              {selectedPlan?.price_annual == null
                ? 'Annual — not configured'
                : 'Annual'}
            </option>
          </select>
        </Field>
        <Field label="Amount">
          <input readOnly value={price == null ? 'Not configured' : formatMoneyFromMajor(price, selectedPlan?.currency_code)} />
        </Field>
        <Field label="Expires in days">
          <input type="number" min="1" max="30" required value={expiresInDays} onChange={(event) => setExpiresInDays(event.target.value)} />
        </Field>
        <Field label="Customer name">
          <input required value={customerName} onChange={(event) => setCustomerName(event.target.value)} />
        </Field>
        <Field label="Customer phone">
          <input required inputMode="tel" value={customerPhone} onChange={(event) => setCustomerPhone(event.target.value)} placeholder="10-digit mobile number" />
        </Field>
        <Field label="Customer email">
          <input type="email" value={customerEmail} onChange={(event) => setCustomerEmail(event.target.value)} />
        </Field>
      </div>
      <div className="delivery-options">
        <label><input type="checkbox" checked={sendEmail} onChange={(event) => setSendEmail(event.target.checked)} />Email</label>
        <label><input type="checkbox" checked={sendSms} onChange={(event) => setSendSms(event.target.checked)} />SMS</label>
        <label><input type="checkbox" checked={sendWhatsapp} onChange={(event) => setSendWhatsapp(event.target.checked)} />WhatsApp</label>
      </div>
      <div className="idempotency-note"><span>Request ID</span><code>{requestId}</code></div>
      <FormActions onCancel={onCancel} busy={busy} submitLabel="Create Cashfree link" />
    </form>
  )
}

function UsagePanel({ hotel, onClose }) {
  const [usage, setUsage] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    getHotelUsage(hotel.id)
      .then((result) => {
        if (active) setUsage(result)
      })
      .catch((loadError) => {
        if (active) setError(loadError?.message || 'Usage could not be loaded.')
      })
    return () => { active = false }
  }, [hotel.id])

  if (error) return <Alert tone="error" message={error} />
  if (!usage) return <div className="inline-loading"><div className="commercial-loader small" />Refreshing authoritative usage…</div>

  return (
    <div className="usage-panel">
      <div className="dialog-context-card">
        <div><span>Hotel</span><strong>{hotel.hotel_name}</strong></div>
        <div><span>Plan</span><strong>{hotel.plan_name}</strong></div>
        <div><span>Captured</span><strong>{formatDateTime(usage.captured_at)}</strong></div>
      </div>
      <div className="usage-grid">
        {(usage.counters || []).map((counter) => {
          const current = Number(counter.current_value || 0)
          const limit = counter.limit_value == null ? null : Number(counter.limit_value)
          const percent = limit ? Math.min(100, (current / limit) * 100) : 0
          return (
            <article className="usage-card" key={counter.metric_key}>
              <div><span>{humanize(counter.metric_key)}</span><strong>{current} / {limit ?? '∞'}</strong></div>
              <div className="usage-bar"><span style={{ width: `${percent}%` }} /></div>
              <small>{formatDateTime(counter.captured_at)}</small>
            </article>
          )
        })}
      </div>
      <div className="form-actions"><button type="button" className="commercial-btn primary" onClick={onClose}>Close</button></div>
    </div>
  )
}

function SupportCreateForm({ hotels, onCancel, onError, onSuccess }) {
  const [form, setForm] = useState({ hotelId: hotels[0]?.id || '', subject: '', description: '', category: 'general', priority: 'normal' })
  const [busy, setBusy] = useState(false)

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      const result = await createSupportTicket(form.hotelId, form.subject, form.description, form.category, form.priority)
      await onSuccess(result)
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  return (
    <form className="commercial-form" onSubmit={submit}>
      <Field label="Hotel"><select required value={form.hotelId} onChange={(event) => setForm({ ...form, hotelId: event.target.value })}>{hotels.map((hotel) => <option key={hotel.id} value={hotel.id}>{hotel.hotel_name}</option>)}</select></Field>
      <Field label="Subject"><input required maxLength="200" value={form.subject} onChange={(event) => setForm({ ...form, subject: event.target.value })} /></Field>
      <Field label="Description"><textarea required rows="5" value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} /></Field>
      <div className="form-grid two">
        <Field label="Category"><input value={form.category} onChange={(event) => setForm({ ...form, category: event.target.value })} /></Field>
        <Field label="Priority"><select value={form.priority} onChange={(event) => setForm({ ...form, priority: event.target.value })}><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option><option value="urgent">Urgent</option></select></Field>
      </div>
      <FormActions onCancel={onCancel} busy={busy} submitLabel="Create ticket" />
    </form>
  )
}

function SupportTicketForm({ ticket, onCancel, onError, onSuccess }) {
  const [status, setStatus] = useState(ticket.status)
  const [message, setMessage] = useState('')
  const [mode, setMode] = useState('status')
  const [busy, setBusy] = useState(false)

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      if (mode === 'message') {
        const result = await addSupportMessage(ticket.id, message)
        await onSuccess('Support message added.', result)
      } else {
        const result = await updateSupportTicketStatus(ticket.id, status, message)
        await onSuccess('Support ticket updated.', result)
      }
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  return (
    <form className="commercial-form" onSubmit={submit}>
      <div className="dialog-context-card"><div><span>Hotel</span><strong>{ticket.hotel_name}</strong></div><div><span>Priority</span><StatusBadge status={ticket.priority} /></div><div><span>Current status</span><StatusBadge status={ticket.status} /></div></div>
      <div className="ticket-summary"><h3>{ticket.subject}</h3><p>{ticket.description}</p></div>
      <div className="segmented-control"><button type="button" className={mode === 'status' ? 'active' : ''} onClick={() => setMode('status')}>Change status</button><button type="button" className={mode === 'message' ? 'active' : ''} onClick={() => setMode('message')}>Add message</button></div>
      {mode === 'status' && <Field label="New status"><select value={status} onChange={(event) => setStatus(event.target.value)}><option value="open">Open</option><option value="in_progress">In progress</option><option value="waiting_on_hotel">Waiting on hotel</option><option value="resolved">Resolved</option><option value="closed">Closed</option></select></Field>}
      <Field label={mode === 'message' ? 'Message' : 'Status note'} required={mode === 'message'}><textarea rows="4" required={mode === 'message'} value={message} onChange={(event) => setMessage(event.target.value)} /></Field>
      <FormActions onCancel={onCancel} busy={busy} submitLabel={mode === 'message' ? 'Add message' : 'Update ticket'} />
    </form>
  )
}

function SafeSupportForm({ hotel, onCancel, onError, onSuccess }) {
  const [reason, setReason] = useState('')
  const [duration, setDuration] = useState('30')
  const [permissions, setPermissions] = useState(['read_only'])
  const [busy, setBusy] = useState(false)
  const permissionOptions = ['read_only', 'hotel_configuration', 'subscription_support', 'ticket_support']

  function togglePermission(permission) {
    setPermissions((current) => current.includes(permission) ? current.filter((item) => item !== permission) : [...current, permission])
  }

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      if (permissions.length === 0) throw new Error('Select at least one approved permission.')
      const result = await startSafeSupportAccess(hotel.id, reason, duration, permissions)
      await onSuccess(result)
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  return (
    <form className="commercial-form" onSubmit={submit}>
      <div className="security-callout"><strong>No silent impersonation</strong><span>This creates an explicit, time-bound and immutable View as Hotel audit trail. After starting it, use the hotel switcher to enter that hotel context.</span></div>
      <div className="dialog-context-card"><div><span>Hotel</span><strong>{hotel.hotel_name}</strong></div><div><span>Lifecycle</span><StatusBadge status={hotel.lifecycle_status || hotel.subscription_status} /></div></div>
      <Field label="Reason"><textarea required rows="4" value={reason} onChange={(event) => setReason(event.target.value)} /></Field>
      <Field label="Duration"><select value={duration} onChange={(event) => setDuration(event.target.value)}><option value="15">15 minutes</option><option value="30">30 minutes</option><option value="60">60 minutes</option><option value="120">2 hours</option><option value="240">4 hours</option></select></Field>
      <Field label="Permissions"><div className="permission-grid">{permissionOptions.map((permission) => <label key={permission}><input type="checkbox" checked={permissions.includes(permission)} onChange={() => togglePermission(permission)} />{humanize(permission)}</label>)}</div></Field>
      <FormActions onCancel={onCancel} busy={busy} submitLabel="Start View as Hotel" />
    </form>
  )
}

function SafeSupportEndForm({ session, onCancel, onError, onSuccess }) {
  const [reason, setReason] = useState('Support work completed.')
  const [busy, setBusy] = useState(false)

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      const result = await endSafeSupportAccess(session.id, reason)
      await onSuccess(result)
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  return <form className="commercial-form" onSubmit={submit}><div className="security-callout"><strong>End audited access</strong><span>The session will be closed and an immutable end event will be appended.</span></div><Field label="End reason"><textarea rows="4" required value={reason} onChange={(event) => setReason(event.target.value)} /></Field><FormActions onCancel={onCancel} busy={busy} submitLabel="End session" danger /></form>
}

function AnnouncementForm({ announcement, hotels, onCancel, onError, onSuccess }) {
  const [form, setForm] = useState(() => ({ id: announcement?.id || '', scope: announcement?.scope || 'global', targetHotelId: announcement?.target_hotel_id || '', title: announcement?.title || '', body: announcement?.body || '', severity: announcement?.severity || 'info', status: announcement?.status || 'draft', startsAt: toLocalDateTime(announcement?.starts_at ? new Date(announcement.starts_at) : new Date()), endsAt: announcement?.ends_at ? toLocalDateTime(new Date(announcement.ends_at)) : '' }))
  const [busy, setBusy] = useState(false)

  async function submit(event) {
    event.preventDefault()
    setBusy(true)
    try {
      const result = await savePlatformAnnouncement({ ...(form.id ? { id: form.id } : {}), scope: form.scope, target_hotel_id: form.scope === 'hotel' ? form.targetHotelId : null, title: form.title.trim(), body: form.body.trim(), severity: form.severity, status: form.status, starts_at: form.startsAt ? new Date(form.startsAt).toISOString() : null, ends_at: form.endsAt ? new Date(form.endsAt).toISOString() : null, metadata: { source: 'day9_super_admin_frontend' } })
      await onSuccess(result)
    } catch (actionError) {
      onError(actionError)
      setBusy(false)
    }
  }

  return (
    <form className="commercial-form" onSubmit={submit}>
      <div className="form-grid two"><Field label="Scope"><select value={form.scope} onChange={(event) => setForm({ ...form, scope: event.target.value })}><option value="global">Global</option><option value="hotel">Hotel</option></select></Field>{form.scope === 'hotel' && <Field label="Target hotel"><select required value={form.targetHotelId} onChange={(event) => setForm({ ...form, targetHotelId: event.target.value })}><option value="">Select hotel</option>{hotels.map((hotel) => <option key={hotel.id} value={hotel.id}>{hotel.hotel_name}</option>)}</select></Field>}<Field label="Severity"><select value={form.severity} onChange={(event) => setForm({ ...form, severity: event.target.value })}><option value="info">Info</option><option value="success">Success</option><option value="warning">Warning</option><option value="critical">Critical</option></select></Field><Field label="Status"><select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value })}><option value="draft">Draft</option><option value="published">Published</option><option value="archived">Archived</option></select></Field></div>
      <Field label="Title"><input required value={form.title} onChange={(event) => setForm({ ...form, title: event.target.value })} /></Field>
      <Field label="Body"><textarea required rows="5" value={form.body} onChange={(event) => setForm({ ...form, body: event.target.value })} /></Field>
      <div className="form-grid two"><Field label="Starts at"><input type="datetime-local" value={form.startsAt} onChange={(event) => setForm({ ...form, startsAt: event.target.value })} /></Field><Field label="Ends at"><input type="datetime-local" value={form.endsAt} onChange={(event) => setForm({ ...form, endsAt: event.target.value })} /></Field></div>
      <FormActions onCancel={onCancel} busy={busy} submitLabel="Save announcement" />
    </form>
  )
}

function CommercialDialog({ title, onClose, children }) {
  useEffect(() => {
    function onKeyDown(event) {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [onClose])

  return (
    <div className="commercial-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}>
      <section className="commercial-dialog" role="dialog" aria-modal="true" aria-label={title}>
        <header><div><span className="commercial-kicker">Authoritative server action</span><h2>{title}</h2></div><button type="button" className="dialog-close" onClick={onClose} aria-label="Close dialog">×</button></header>
        <div className="commercial-dialog-body">{children}</div>
      </section>
    </div>
  )
}

function Alert({ tone, message, result }) {
  return <div className={`commercial-alert ${tone}`}><div><strong>{tone === 'success' ? 'Completed' : 'Action required'}</strong><span>{message}</span></div>{result && <details><summary>Server result</summary><pre>{JSON.stringify(result, null, 2)}</pre></details>}</div>
}

function MetricCard({ label, value, meta, tone }) {
  return <article className={`commercial-metric ${tone || 'neutral'}`}><span>{label}</span><strong>{value}</strong><small>{meta}</small></article>
}

function SectionHeader({ eyebrow, title, action }) {
  return <div className="commercial-section-header"><div><span>{eyebrow}</span><h2>{title}</h2></div>{action}</div>
}

function EmptyState({ title, text }) {
  return <div className="commercial-empty"><span>◇</span><strong>{title}</strong><p>{text}</p></div>
}

function StatusBadge({ status }) {
  const normalized = String(status || 'unknown').toLowerCase()
  return <span className={`status-badge status-${normalized.replace(/[^a-z0-9]+/g, '-')}`}>{humanize(status || 'unknown')}</span>
}

function Field({ label, hint, required, children }) {
  return <label className="commercial-field"><span>{label}{required ? ' *' : ''}</span>{children}{hint && <small>{hint}</small>}</label>
}

function FormActions({ onCancel, busy, submitLabel, danger = false }) {
  return <div className="form-actions"><button type="button" className="commercial-btn secondary" onClick={onCancel} disabled={busy}>Cancel</button><button type="submit" className={`commercial-btn ${danger ? 'danger' : 'primary'}`} disabled={busy}>{busy ? 'Processing…' : submitLabel}</button></div>
}

function Limit({ label, value }) {
  return <div><span>{label}</span><strong>{value ?? 'Unlimited'}</strong></div>
}

function Features({ features }) {
  const rows = Array.isArray(features) ? features : features && typeof features === 'object' ? Object.entries(features).filter(([, enabled]) => Boolean(enabled)).map(([key]) => key) : []
  if (rows.length === 0) return <p className="no-features">No feature list configured.</p>
  return <ul className="feature-list">{rows.slice(0, 6).map((feature) => <li key={String(feature)}>✓ {humanize(typeof feature === 'string' ? feature : JSON.stringify(feature))}</li>)}</ul>
}

function TabCount({ tab, data, announcements }) {
  const counts = { hotels: data.hotels.length, plans: data.plans.length, payments: data.payment_links.length, support: data.support_tickets.length, events: data.subscription_events.length + data.webhook_events.length, announcements: announcements.length }
  if (!(tab in counts)) return null
  return <span>{counts[tab]}</span>
}

function dialogTitle(dialog) {
  const titles = { plan: dialog.plan ? 'Edit subscription plan' : 'Create subscription plan', 'hotel-actions': `Manage ${dialog.hotel?.hotel_name || 'hotel'}`, 'payment-link': 'Create Cashfree payment link', usage: 'Authoritative hotel usage', 'support-create': 'Create support ticket', 'support-ticket': 'Triage support ticket', 'safe-support': 'Start audited View as Hotel', 'safe-support-end': 'End safe support access', announcement: dialog.announcement ? 'Edit announcement' : 'Create announcement' }
  return titles[dialog.type] || 'Commercial action'
}

function humanize(value) {
  if (value == null || value === '') return '—'
  return String(value).replace(/[_-]+/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function formatDateTime(value) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'
  return date.toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })
}

function formatDate(value) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'
  return date.toLocaleDateString('en-IN', { dateStyle: 'medium' })
}

function formatMoney(amountMinor, currency = 'INR', fromMinor = true) {
  const numeric = Number(amountMinor || 0)
  const major = fromMinor ? numeric / 100 : numeric
  return new Intl.NumberFormat('en-IN', { style: 'currency', currency: currency || 'INR', maximumFractionDigits: 2 }).format(major)
}

function formatMoneyFromMajor(amount, currency = 'INR') {
  return formatMoney(amount, currency, false)
}

function truncate(value, length = 24) {
  const text = String(value || '')
  return text.length > length ? `${text.slice(0, length - 1)}…` : text
}

function featuresToText(features) {
  if (Array.isArray(features)) return features.map((feature) => typeof feature === 'string' ? feature : JSON.stringify(feature)).join('\n')
  if (features && typeof features === 'object') return Object.entries(features).filter(([, enabled]) => Boolean(enabled)).map(([key]) => key).join('\n')
  return ''
}

function textToFeatures(text) {
  return text.split('\n').map((item) => item.trim()).filter(Boolean)
}

function nullableNumber(value) {
  return value === '' || value == null ? null : Number(value)
}

function nullableInteger(value) {
  return value === '' || value == null ? null : Math.trunc(Number(value))
}

function numberOrZero(value) {
  return Number(value || 0)
}

function addDays(date, days) {
  const next = new Date(date)
  next.setDate(next.getDate() + days)
  return next
}

function toLocalDateTime(date) {
  if (!date || Number.isNaN(date.getTime())) return ''
  const offset = date.getTimezoneOffset()
  return new Date(date.getTime() - offset * 60000).toISOString().slice(0, 16)
}
