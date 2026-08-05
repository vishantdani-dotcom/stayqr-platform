import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  getActiveAnnouncements,
  getActivityTimeline,
  getDeliveryFailures,
  getEmailAdapters,
  getEventCatalog,
  getHotelSystemSettings,
  getHotelTemplates,
  getNotificationInbox,
  getSupportWorkspace,
  getWhatsAppTemplates,
  markInboxAllRead,
  markInboxNotificationRead,
  publishNotificationTemplate,
  retryDelivery,
  saveEmailAdapter,
  saveNotificationPreferences,
  saveWhatsAppTemplate,
  subscribeToNotificationDeliveries,
  subscribeToNotificationInbox,
  updateHotelSystemSettings,
} from '../../lib/day17Operations'
import {
  getOperationalDiagnostics,
  setOperationalIncidentStatus,
} from '../../lib/day18Monitoring'
import './OperationsCenter.css'

const TABS = [
  ['notifications', 'Notifications'],
  ['activity', 'Activity'],
  ['preferences', 'Preferences'],
  ['templates', 'Templates'],
  ['support', 'Support'],
  ['announcements', 'Announcements'],
  ['delivery', 'Delivery'],
  ['diagnostics', 'Diagnostics'],
  ['settings', 'System settings'],
]

const emptyPreference = {
  in_app_enabled: true,
  email_enabled: false,
  manual_whatsapp_enabled: false,
  locale: 'en',
  quiet_hours_start: '',
  quiet_hours_end: '',
  event_overrides: {},
}

const emptyDiagnostics = {
  health_status: 'unknown',
  summary: {
    total_in_window: 0,
    open_count: 0,
    acknowledged_count: 0,
    resolved_count: 0,
    ignored_count: 0,
    critical_count: 0,
    error_count: 0,
    warning_count: 0,
  },
  items: [],
  query_health: {},
  delivery_health: {},
}

function isoStart(days = 7) {
  const d = new Date()
  d.setDate(d.getDate() - days)
  d.setHours(0, 0, 0, 0)
  return d.toISOString()
}

export default function OperationsCenter({ hotel, currentRole }) {
  const hotelId = hotel?.id
  const [tab, setTab] = useState('notifications')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState('')
  const [error, setError] = useState('')
  const [toast, setToast] = useState('')

  const [inbox, setInbox] = useState({ unread_count: 0, items: [] })
  const [activity, setActivity] = useState([])
  const [support, setSupport] = useState({ tickets: [] })
  const [announcements, setAnnouncements] = useState([])
  const [events, setEvents] = useState([])
  const [templates, setTemplates] = useState([])
  const [failures, setFailures] = useState([])
  const [adapters, setAdapters] = useState([])
  const [whatsappTemplates, setWhatsappTemplates] = useState([])

  const [preference, setPreference] = useState(emptyPreference)
  const [activityFilters, setActivityFilters] = useState({
    from: isoStart(7).slice(0, 16),
    to: new Date().toISOString().slice(0, 16),
    entity_type: '',
    action: '',
  })
  const [templateForm, setTemplateForm] = useState({
    event_key: 'reservation.created',
    channel: 'in_app',
    locale: 'en',
    title_template: '',
    body_template: '',
  })
  const [adapterForm, setAdapterForm] = useState({
    adapter_key: 'hotel_email',
    provider: 'edge_function',
    from_name: '',
    from_email: '',
    reply_to_email: '',
    endpoint_name: '',
    is_enabled: false,
    metadata: {},
  })
  const [whatsappForm, setWhatsappForm] = useState({
    event_key: 'reservation.created',
    locale: 'en',
    template_name: '',
    body_template: '',
    status: 'draft',
  })
  const [systemForm, setSystemForm] = useState({})
  const [diagnostics, setDiagnostics] = useState(emptyDiagnostics)
  const [diagnosticFilters, setDiagnosticFilters] = useState({
    severity: '',
    status: '',
    source: '',
    search: '',
  })
  const showToast = useCallback((message) => {
    setToast(message)
    window.setTimeout(() => setToast(''), 2600)
  }, [])

  const refresh = useCallback(async () => {
    if (!hotelId) return
    setLoading(true)
    setError('')
    try {
      const [
        inboxData,
        settingsData,
        supportData,
        announcementData,
        eventData,
        templateData,
        failureData,
        adapterData,
        whatsappData,
        activityData,
        diagnosticData,
      ] = await Promise.all([
        getNotificationInbox(hotelId, 100),
        getHotelSystemSettings(hotelId),
        getSupportWorkspace(hotelId),
        getActiveAnnouncements(hotelId),
        getEventCatalog(),
        getHotelTemplates(hotelId),
        getDeliveryFailures(hotelId),
        getEmailAdapters(hotelId),
        getWhatsAppTemplates(hotelId),
        getActivityTimeline(hotelId, isoStart(7), new Date().toISOString(), { limit: 200 }),
        getOperationalDiagnostics(hotelId, { limit: 50 }),
      ])

      setInbox(inboxData)
      setSupport(supportData || { tickets: [] })
      setAnnouncements(announcementData || [])
      setEvents(eventData || [])
      setTemplates(templateData || [])
      setFailures(failureData || [])
      setAdapters(adapterData || [])
      setWhatsappTemplates(whatsappData || [])
      setActivity(activityData?.items || [])
      setDiagnostics(diagnosticData || emptyDiagnostics)
      const savedPreference = settingsData?.notification_preferences
      setPreference(savedPreference ? {
        in_app_enabled: savedPreference.in_app_enabled,
        email_enabled: savedPreference.email_enabled,
        manual_whatsapp_enabled: savedPreference.manual_whatsapp_enabled,
        locale: savedPreference.locale || 'en',
        quiet_hours_start: savedPreference.quiet_hours_start || '',
        quiet_hours_end: savedPreference.quiet_hours_end || '',
        event_overrides: savedPreference.event_overrides || {},
      } : emptyPreference)

      const hs = settingsData?.hotel_settings || {}
      const bds = settingsData?.business_day_settings || {}
      setSystemForm({
        timezone: settingsData?.hotel?.timezone || 'Asia/Kolkata',
        currency_code: settingsData?.hotel?.currency_code || 'INR',
        legal_name: hs.legal_name || '',
        tax_registration_number: hs.tax_registration_number || '',
        default_tax_percent: hs.default_tax_percent ?? 0,
        prices_include_tax: Boolean(hs.prices_include_tax),
        checkin_time: hs.checkin_time || '14:00',
        checkout_time: hs.checkout_time || '11:00',
        checkout_grace_minutes: hs.checkout_grace_minutes ?? 0,
        locale: hs.locale || bds.locale || 'en-IN',
        date_format: hs.date_format || 'DD/MM/YYYY',
        business_day_cutoff: bds.business_day_cutoff || '00:00',
        week_starts_on: bds.week_starts_on ?? 1,
        night_audit_time: bds.night_audit_time || '02:00',
        cancellation_policy: hs.cancellation_policy || '',
        house_rules: hs.house_rules || '',
        terms_and_conditions: hs.terms_and_conditions || '',
      })
    } catch (err) {
      console.error(err)
      setError(err?.message || 'Day 17 workspace could not be loaded.')
    } finally {
      setLoading(false)
    }
  }, [hotelId])

  useEffect(() => {
    refresh()
  }, [refresh])

  useEffect(() => {
    if (!hotelId) return undefined
    const stopInbox = subscribeToNotificationInbox(hotelId, async () => {
      try {
        setInbox(await getNotificationInbox(hotelId, 100))
      } catch (err) {
        console.error(err)
      }
    })
    const stopDelivery = subscribeToNotificationDeliveries(hotelId, async () => {
      try {
        setFailures(await getDeliveryFailures(hotelId))
      } catch (err) {
        console.error(err)
      }
    })
    return () => {
      stopInbox()
      stopDelivery()
    }
  }, [hotelId])

  const criticalCount = useMemo(
    () => inbox.items.filter((item) => item.severity === 'critical' && item.status === 'unread').length,
    [inbox.items]
  )

  async function runAction(key, fn, message) {
    setSaving(key)
    setError('')
    try {
      await fn()
      showToast(message)
      await refresh()
    } catch (err) {
      console.error(err)
      setError(err?.message || 'The action could not be completed.')
    } finally {
      setSaving('')
    }
  }

  async function refreshActivity() {
    setSaving('activity')
    setError('')
    try {
      const result = await getActivityTimeline(
        hotelId,
        activityFilters.from ? new Date(activityFilters.from).toISOString() : null,
        activityFilters.to ? new Date(activityFilters.to).toISOString() : null,
        {
          limit: 500,
          entity_type: activityFilters.entity_type || undefined,
          action: activityFilters.action || undefined,
        }
      )
      setActivity(result?.items || [])
      showToast('Activity timeline refreshed.')
    } catch (err) {
      setError(err?.message || 'Activity timeline could not be refreshed.')
    } finally {
      setSaving('')
    }
  }

  async function refreshDiagnostics() {
    setSaving('diagnostics')
    setError('')

    try {
      const result = await getOperationalDiagnostics(hotelId, {
        ...diagnosticFilters,
        limit: 100,
      })
      setDiagnostics(result || emptyDiagnostics)
      showToast('Operational diagnostics refreshed.')
    } catch (err) {
      setError(
        err?.message || 'Operational diagnostics could not be refreshed.'
      )
    } finally {
      setSaving('')
    }
  }

  if (!hotelId) {
    return <div className="d17-empty">Select a hotel to open Day 17 operations.</div>
  }

  return (
    <section className="d17-page">
      <header className="d17-hero">
        <div>
          <p className="d17-eyebrow">DAY 17 · NOTIFICATIONS, ACTIVITY, SUPPORT & SETTINGS</p>
          <h1>Operations & Communications Centre</h1>
          <p>{hotel?.hotel_name || 'StayQR Hotel'} · Realtime, tenant-scoped operational control.</p>
        </div>
        <div className="d17-hero-actions">
          <span className="d17-role">{currentRole || 'manager'}</span>
          <button type="button" onClick={refresh} disabled={loading}>Refresh all</button>
        </div>
      </header>

      <div className="d17-kpis">
        <Metric label="Unread" value={inbox.unread_count || 0} />
        <Metric label="Critical" value={criticalCount} danger={criticalCount > 0} />
        <Metric label="Activity rows" value={activity.length} />
        <Metric label="Support tickets" value={support.tickets?.length || 0} />
        <Metric label="Announcements" value={announcements.length} />
        <Metric label="Failed deliveries" value={failures.length} danger={failures.length > 0} />
        <Metric
          label="Open incidents"
          value={diagnostics.summary?.open_count || 0}
          danger={(diagnostics.summary?.open_count || 0) > 0}
        />
        <Metric
          label="Critical incidents"
          value={diagnostics.summary?.critical_count || 0}
          danger={(diagnostics.summary?.critical_count || 0) > 0}
        />
      </div>

      <nav className="d17-tabs">
        {TABS.map(([id, label]) => (
          <button
            type="button"
            key={id}
            className={tab === id ? 'active' : ''}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </nav>

      {error && <div className="d17-error">{error}</div>}
      {loading ? <div className="d17-loading">Loading trusted Day 17 workspace…</div> : null}

      {!loading && tab === 'notifications' && (
        <Panel title="Notification Centre" subtitle="Realtime recipient-level inbox from the trusted notification outbox.">
          <div className="d17-toolbar">
            <span>{inbox.unread_count || 0} unread</span>
            <button
              type="button"
              disabled={!inbox.unread_count || saving === 'all-read'}
              onClick={() => runAction(
                'all-read',
                () => markInboxAllRead(hotelId),
                'All notifications marked as read.'
              )}
            >
              Mark all read
            </button>
          </div>
          <div className="d17-feed">
            {inbox.items.length === 0 ? <Empty text="No notifications yet." /> : inbox.items.map((item) => (
              <button
                type="button"
                className={`d17-notification ${item.status} severity-${item.severity}`}
                key={item.id}
                onClick={() => item.status === 'unread' && runAction(
                  item.id,
                  () => markInboxNotificationRead(item.id),
                  'Notification marked as read.'
                )}
              >
                <span className="d17-dot" />
                <span className="d17-notification-copy">
                  <strong>{item.title}</strong>
                  <span>{item.message}</span>
                  <small>{item.event_key} · {formatDate(item.created_at)}</small>
                </span>
                <span className="d17-pill">{item.severity}</span>
              </button>
            ))}
          </div>
        </Panel>
      )}

      {!loading && tab === 'activity' && (
        <Panel title="Activity Timeline" subtitle="Auditable hotel events from the trusted activity ledger.">
          <div className="d17-filter-grid">
            <Field label="From"><input type="datetime-local" value={activityFilters.from} onChange={(e) => setActivityFilters((p) => ({ ...p, from: e.target.value }))} /></Field>
            <Field label="To"><input type="datetime-local" value={activityFilters.to} onChange={(e) => setActivityFilters((p) => ({ ...p, to: e.target.value }))} /></Field>
            <Field label="Entity type"><input placeholder="reservation, payment…" value={activityFilters.entity_type} onChange={(e) => setActivityFilters((p) => ({ ...p, entity_type: e.target.value }))} /></Field>
            <Field label="Action"><input placeholder="notification_event_enqueued" value={activityFilters.action} onChange={(e) => setActivityFilters((p) => ({ ...p, action: e.target.value }))} /></Field>
            <button type="button" onClick={refreshActivity} disabled={saving === 'activity'}>Apply filters</button>
          </div>
          <div className="d17-table-wrap">
            <table>
              <thead><tr><th>Time</th><th>Action</th><th>Entity</th><th>Description</th><th>Actor</th></tr></thead>
              <tbody>
                {activity.map((row) => (
                  <tr key={row.id}>
                    <td>{formatDate(row.created_at)}</td>
                    <td><code>{row.action}</code></td>
                    <td>{row.entity_type || '—'}</td>
                    <td>{row.description || '—'}</td>
                    <td>{row.actor_role || 'system'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Panel>
      )}

      {!loading && tab === 'preferences' && (
        <Panel title="My Notification Preferences" subtitle="Personal channel, locale and quiet-hours controls for this hotel.">
          <div className="d17-form-grid">
            <Toggle label="In-app notifications" checked={preference.in_app_enabled} onChange={(value) => setPreference((p) => ({ ...p, in_app_enabled: value }))} />
            <Toggle label="Email notifications" checked={preference.email_enabled} onChange={(value) => setPreference((p) => ({ ...p, email_enabled: value }))} />
            <Toggle label="Manual WhatsApp" checked={preference.manual_whatsapp_enabled} onChange={(value) => setPreference((p) => ({ ...p, manual_whatsapp_enabled: value }))} />
            <Field label="Locale"><input value={preference.locale} onChange={(e) => setPreference((p) => ({ ...p, locale: e.target.value }))} /></Field>
            <Field label="Quiet hours start"><input type="time" value={preference.quiet_hours_start || ''} onChange={(e) => setPreference((p) => ({ ...p, quiet_hours_start: e.target.value }))} /></Field>
            <Field label="Quiet hours end"><input type="time" value={preference.quiet_hours_end || ''} onChange={(e) => setPreference((p) => ({ ...p, quiet_hours_end: e.target.value }))} /></Field>
          </div>
          <button className="d17-primary" type="button" onClick={() => runAction(
            'preferences',
            () => saveNotificationPreferences(hotelId, preference),
            'Notification preferences saved.'
          )}>Save preferences</button>
        </Panel>
      )}

      {!loading && tab === 'templates' && (
        <div className="d17-two-column">
          <Panel title="Publish Notification Template" subtitle="Publishing creates a new immutable template version.">
            <div className="d17-form-grid one">
              <Field label="Event">
                <select value={templateForm.event_key} onChange={(e) => setTemplateForm((p) => ({ ...p, event_key: e.target.value }))}>
                  {events.map((event) => <option key={event.event_key} value={event.event_key}>{event.event_key}</option>)}
                </select>
              </Field>
              <Field label="Channel">
                <select value={templateForm.channel} onChange={(e) => setTemplateForm((p) => ({ ...p, channel: e.target.value }))}>
                  <option value="in_app">In-app</option>
                  <option value="email">Email</option>
                  <option value="manual_whatsapp">Manual WhatsApp</option>
                </select>
              </Field>
              <Field label="Locale"><input value={templateForm.locale} onChange={(e) => setTemplateForm((p) => ({ ...p, locale: e.target.value }))} /></Field>
              <Field label="Title template"><input value={templateForm.title_template} onChange={(e) => setTemplateForm((p) => ({ ...p, title_template: e.target.value }))} /></Field>
              <Field label="Body template"><textarea rows="5" value={templateForm.body_template} onChange={(e) => setTemplateForm((p) => ({ ...p, body_template: e.target.value }))} /></Field>
            </div>
            <button className="d17-primary" type="button" onClick={() => runAction(
              'template',
              () => publishNotificationTemplate(hotelId, templateForm.event_key, templateForm.channel, {
                locale: templateForm.locale,
                title_template: templateForm.title_template,
                body_template: templateForm.body_template,
              }),
              'Notification template published.'
            )}>Publish new version</button>
          </Panel>
          <Panel title="Published Templates" subtitle={`${templates.length} global and hotel-specific templates visible.`}>
            <div className="d17-card-list">
              {templates.map((item) => (
                <article key={item.id} className="d17-mini-card">
                  <div><strong>{item.event_key}</strong><span>{item.channel} · {item.locale}</span></div>
                  <span className="d17-pill">v{item.current_version}</span>
                  <p>{item.title_template}</p>
                  <small>{item.hotel_id ? 'Hotel template' : 'Platform default'}</small>
                </article>
              ))}
            </div>
          </Panel>
        </div>
      )}

      {!loading && tab === 'support' && (
        <Panel title="Support Workspace" subtitle="Hotel-scoped tickets and complete ticket event history.">
          <div className="d17-card-list">
            {(support.tickets || []).length === 0 ? <Empty text="No support tickets for this hotel." /> : support.tickets.map((ticket) => (
              <article className="d17-ticket" key={ticket.id}>
                <header><div><small>{ticket.ticket_number}</small><h3>{ticket.subject}</h3></div><span className={`d17-pill status-${ticket.status}`}>{ticket.status}</span></header>
                <p>{ticket.description}</p>
                <div className="d17-ticket-meta"><span>{ticket.category}</span><span>{ticket.priority}</span><span>{formatDate(ticket.updated_at)}</span></div>
                <details>
                  <summary>{ticket.events?.length || 0} timeline event(s)</summary>
                  {(ticket.events || []).map((event) => <p key={event.id}><strong>{event.event_type || event.action || 'Event'}</strong> · {formatDate(event.created_at)}</p>)}
                </details>
              </article>
            ))}
          </div>
        </Panel>
      )}

      {!loading && tab === 'announcements' && (
        <Panel title="Active Announcements" subtitle="Platform and hotel announcements currently applicable to this property.">
          <div className="d17-card-list">
            {announcements.length === 0 ? <Empty text="No active announcements." /> : announcements.map((item) => (
              <article className={`d17-announcement severity-${item.severity}`} key={item.id}>
                <span className="d17-pill">{item.severity}</span>
                <h3>{item.title}</h3>
                <p>{item.body}</p>
                <small>{item.scope} · Published {formatDate(item.published_at)}</small>
              </article>
            ))}
          </div>
        </Panel>
      )}

      {!loading && tab === 'delivery' && (
        <div className="d17-stack">
          <Panel title="Delivery Failures & Retry" subtitle="Auditable failed/retrying delivery rows.">
            <div className="d17-table-wrap">
              <table>
                <thead><tr><th>Channel</th><th>Title</th><th>Status</th><th>Attempts</th><th>Error</th><th /></tr></thead>
                <tbody>
                  {failures.map((row) => (
                    <tr key={row.id}>
                      <td>{row.channel}</td><td>{row.rendered_title}</td><td>{row.status}</td>
                      <td>{row.attempt_count}/{row.max_attempts}</td>
                      <td>{row.last_error_code || row.last_error_message || '—'}</td>
                      <td><button type="button" onClick={() => runAction(row.id, () => retryDelivery(row.id), 'Delivery queued for retry.')}>Retry</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {failures.length === 0 ? <Empty text="No failed or retrying deliveries." /> : null}
            </div>
          </Panel>

          <div className="d17-two-column">
            <Panel title="Email Adapter" subtitle="Provider-neutral configuration. Secrets remain outside the frontend/database row.">
              <div className="d17-form-grid one">
                <Field label="Adapter key"><input value={adapterForm.adapter_key} onChange={(e) => setAdapterForm((p) => ({ ...p, adapter_key: e.target.value }))} /></Field>
                <Field label="Provider"><select value={adapterForm.provider} onChange={(e) => setAdapterForm((p) => ({ ...p, provider: e.target.value }))}><option value="edge_function">Edge function</option><option value="external_worker">External worker</option><option value="manual">Manual</option></select></Field>
                <Field label="From name"><input value={adapterForm.from_name} onChange={(e) => setAdapterForm((p) => ({ ...p, from_name: e.target.value }))} /></Field>
                <Field label="From email"><input type="email" value={adapterForm.from_email} onChange={(e) => setAdapterForm((p) => ({ ...p, from_email: e.target.value }))} /></Field>
                <Field label="Reply-to email"><input type="email" value={adapterForm.reply_to_email} onChange={(e) => setAdapterForm((p) => ({ ...p, reply_to_email: e.target.value }))} /></Field>
                <Field label="Endpoint name"><input value={adapterForm.endpoint_name} onChange={(e) => setAdapterForm((p) => ({ ...p, endpoint_name: e.target.value }))} /></Field>
                <Toggle label="Enabled" checked={adapterForm.is_enabled} onChange={(value) => setAdapterForm((p) => ({ ...p, is_enabled: value }))} />
              </div>
              <button className="d17-primary" type="button" onClick={() => runAction('adapter', () => saveEmailAdapter(hotelId, adapterForm), 'Email adapter saved.')}>Save email adapter</button>
              <p className="d17-footnote">{adapters.length} saved hotel adapter(s).</p>
            </Panel>

            <Panel title="Manual WhatsApp Template" subtitle="Creates a safe wa.me action; StayQR does not auto-send WhatsApp messages.">
              <div className="d17-form-grid one">
                <Field label="Event"><select value={whatsappForm.event_key} onChange={(e) => setWhatsappForm((p) => ({ ...p, event_key: e.target.value }))}>{events.map((event) => <option key={event.event_key} value={event.event_key}>{event.event_key}</option>)}</select></Field>
                <Field label="Locale"><input value={whatsappForm.locale} onChange={(e) => setWhatsappForm((p) => ({ ...p, locale: e.target.value }))} /></Field>
                <Field label="Template name"><input value={whatsappForm.template_name} onChange={(e) => setWhatsappForm((p) => ({ ...p, template_name: e.target.value }))} /></Field>
                <Field label="Body template"><textarea rows="5" value={whatsappForm.body_template} onChange={(e) => setWhatsappForm((p) => ({ ...p, body_template: e.target.value }))} /></Field>
                <Field label="Status"><select value={whatsappForm.status} onChange={(e) => setWhatsappForm((p) => ({ ...p, status: e.target.value }))}><option value="draft">Draft</option><option value="published">Published</option><option value="archived">Archived</option></select></Field>
              </div>
              <button className="d17-primary" type="button" onClick={() => runAction('whatsapp', () => saveWhatsAppTemplate(hotelId, whatsappForm), 'Manual WhatsApp template saved.')}>Save WhatsApp template</button>
              <p className="d17-footnote">{whatsappTemplates.length} saved hotel template(s).</p>
            </Panel>
          </div>
        </div>
      )}

      {!loading && tab === 'diagnostics' && (
        <div className="d17-stack">
          <Panel
            title="Operational Health & Error Diagnostics"
            subtitle="Sanitized, tenant-scoped incidents with query and delivery health."
          >
            <div
              className={`d18-health-banner status-${diagnostics.health_status || 'unknown'}`}
            >
              <div>
                <span>Current health</span>
                <strong>{diagnostics.health_status || 'unknown'}</strong>
              </div>
              <div>
                <span>Invalid indexes</span>
                <strong>
                  {diagnostics.query_health?.invalid_index_count ?? 'â€”'}
                </strong>
              </div>
              <div>
                <span>Day 18 indexes</span>
                <strong>
                  {diagnostics.query_health?.day18_index_count ?? 'â€”'}
                </strong>
              </div>
              <div>
                <span>Failed deliveries Â· 24h</span>
                <strong>
                  {diagnostics.delivery_health?.failed_24h ?? 0}
                </strong>
              </div>
            </div>

            <div className="d18-diagnostic-filters">
              <Field label="Severity">
                <select
                  value={diagnosticFilters.severity}
                  onChange={(event) =>
                    setDiagnosticFilters((previous) => ({
                      ...previous,
                      severity: event.target.value,
                    }))
                  }
                >
                  <option value="">All severities</option>
                  <option value="critical">Critical</option>
                  <option value="error">Error</option>
                  <option value="warning">Warning</option>
                  <option value="info">Info</option>
                </select>
              </Field>
              <Field label="Status">
                <select
                  value={diagnosticFilters.status}
                  onChange={(event) =>
                    setDiagnosticFilters((previous) => ({
                      ...previous,
                      status: event.target.value,
                    }))
                  }
                >
                  <option value="">All statuses</option>
                  <option value="open">Open</option>
                  <option value="acknowledged">Acknowledged</option>
                  <option value="resolved">Resolved</option>
                  <option value="ignored">Ignored</option>
                </select>
              </Field>
              <Field label="Source">
                <select
                  value={diagnosticFilters.source}
                  onChange={(event) =>
                    setDiagnosticFilters((previous) => ({
                      ...previous,
                      source: event.target.value,
                    }))
                  }
                >
                  <option value="">All sources</option>
                  <option value="client">Client</option>
                  <option value="edge_function">Edge function</option>
                  <option value="webhook">Webhook</option>
                  <option value="database">Database</option>
                  <option value="deployment">Deployment</option>
                  <option value="manual">Manual</option>
                </select>
              </Field>
              <Field label="Search incident, request or error">
                <input
                  value={diagnosticFilters.search}
                  onChange={(event) =>
                    setDiagnosticFilters((previous) => ({
                      ...previous,
                      search: event.target.value,
                    }))
                  }
                  placeholder="Incident ID, request ID, error codeâ€¦"
                />
              </Field>
              <button
                type="button"
                onClick={refreshDiagnostics}
                disabled={saving === 'diagnostics'}
              >
                Apply diagnostics
              </button>
            </div>
          </Panel>

          <Panel
            title="Structured Incident Ledger"
            subtitle={`${diagnostics.summary?.total_in_window || 0} incident(s) in the selected diagnostic window.`}
          >
            <div className="d17-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Last seen</th>
                    <th>Severity</th>
                    <th>Incident</th>
                    <th>Source</th>
                    <th>Message</th>
                    <th>Occurrences</th>
                    <th>Status</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {(diagnostics.items || []).map((row) => (
                    <tr key={row.id}>
                      <td>{formatDate(row.last_seen_at)}</td>
                      <td>
                        <span className={`d17-pill severity-${row.severity}`}>
                          {row.severity}
                        </span>
                      </td>
                      <td>
                        <code>{row.incident_id}</code>
                        <small className="d18-request-id">
                          {row.request_id || 'No request ID'}
                        </small>
                      </td>
                      <td>{row.source}</td>
                      <td>
                        <strong>{row.event_name}</strong>
                        <p className="d18-message">{row.message}</p>
                      </td>
                      <td>{row.occurrence_count}</td>
                      <td>
                        <span className={`d17-pill status-${row.status}`}>
                          {row.status}
                        </span>
                      </td>
                      <td>
                        <div className="d18-incident-actions">
                          {row.status === 'open' && (
                            <button
                              type="button"
                              onClick={() =>
                                runAction(
                                  `incident-${row.id}-ack`,
                                  () =>
                                    setOperationalIncidentStatus(
                                      hotelId,
                                      row.id,
                                      'acknowledged'
                                    ),
                                  'Incident acknowledged.'
                                )
                              }
                            >
                              Acknowledge
                            </button>
                          )}
                          {!['resolved', 'ignored'].includes(row.status) && (
                            <button
                              type="button"
                              onClick={() =>
                                runAction(
                                  `incident-${row.id}-resolve`,
                                  () =>
                                    setOperationalIncidentStatus(
                                      hotelId,
                                      row.id,
                                      'resolved'
                                    ),
                                  'Incident resolved.'
                                )
                              }
                            >
                              Resolve
                            </button>
                          )}
                          {['resolved', 'ignored'].includes(row.status) && (
                            <button
                              type="button"
                              onClick={() =>
                                runAction(
                                  `incident-${row.id}-reopen`,
                                  () =>
                                    setOperationalIncidentStatus(
                                      hotelId,
                                      row.id,
                                      'open'
                                    ),
                                  'Incident reopened.'
                                )
                              }
                            >
                              Reopen
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {(diagnostics.items || []).length === 0 ? (
                <Empty text="No operational incidents match the active filters." />
              ) : null}
            </div>
          </Panel>
        </div>
      )}

      {!loading && tab === 'settings' && (
        <Panel title="Hotel System Settings" subtitle="Timezone, currency, tax, check-in/out and business-day authority.">
          <div className="d17-form-grid">
            {[
              ['timezone', 'Timezone'], ['currency_code', 'Currency'], ['legal_name', 'Legal name'],
              ['tax_registration_number', 'Tax registration'], ['default_tax_percent', 'Default tax %'],
              ['checkin_time', 'Check-in time'], ['checkout_time', 'Checkout time'],
              ['checkout_grace_minutes', 'Checkout grace (min)'], ['locale', 'Locale'],
              ['date_format', 'Date format'], ['business_day_cutoff', 'Business-day cutoff'],
              ['week_starts_on', 'Week starts on'], ['night_audit_time', 'Night audit time'],
            ].map(([key, label]) => (
              <Field key={key} label={label}>
                <input value={systemForm[key] ?? ''} onChange={(e) => setSystemForm((p) => ({ ...p, [key]: e.target.value }))} />
              </Field>
            ))}
            <Toggle label="Prices include tax" checked={Boolean(systemForm.prices_include_tax)} onChange={(value) => setSystemForm((p) => ({ ...p, prices_include_tax: value }))} />
            <Field label="Cancellation policy"><textarea rows="3" value={systemForm.cancellation_policy || ''} onChange={(e) => setSystemForm((p) => ({ ...p, cancellation_policy: e.target.value }))} /></Field>
            <Field label="House rules"><textarea rows="3" value={systemForm.house_rules || ''} onChange={(e) => setSystemForm((p) => ({ ...p, house_rules: e.target.value }))} /></Field>
            <Field label="Terms & conditions"><textarea rows="3" value={systemForm.terms_and_conditions || ''} onChange={(e) => setSystemForm((p) => ({ ...p, terms_and_conditions: e.target.value }))} /></Field>
          </div>
          <button className="d17-primary" type="button" onClick={() => runAction(
            'settings',
            () => updateHotelSystemSettings(hotelId, {
              ...systemForm,
              default_tax_percent: Number(systemForm.default_tax_percent || 0),
              checkout_grace_minutes: Number(systemForm.checkout_grace_minutes || 0),
              week_starts_on: Number(systemForm.week_starts_on || 1),
            }),
            'Hotel system settings saved.'
          )}>Save system settings</button>
        </Panel>
      )}

      {toast && <div className="d17-toast">{toast}</div>}
    </section>
  )
}

function Metric({ label, value, danger }) {
  return <div className={`d17-metric ${danger ? 'danger' : ''}`}><span>{label}</span><strong>{value}</strong></div>
}

function Panel({ title, subtitle, children }) {
  return <section className="d17-panel"><header><h2>{title}</h2><p>{subtitle}</p></header>{children}</section>
}

function Field({ label, children }) {
  return <label className="d17-field"><span>{label}</span>{children}</label>
}

function Toggle({ label, checked, onChange }) {
  return <label className="d17-toggle"><input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} /><span>{label}</span></label>
}

function Empty({ text }) {
  return <div className="d17-empty">{text}</div>
}

function formatDate(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })
}
