import { useCallback, useEffect, useState } from 'react'
import {
  loadV11cMultiPropertyOverview,
  loadV11cPlatformWorkspace,
  saveV11cWhatsAppSettings,
} from '../../lib/v11Platform'
import './PlatformHub.css'

const TABS = [
  ['group', 'Group View'],
  ['whatsapp', 'WhatsApp Resilience'],
  ['support', 'Support Guard'],
]

export default function PlatformHub({ hotel, tenantContext, onHotelChange, onNavigate }) {
  const [tab, setTab] = useState('group')
  const [workspace, setWorkspace] = useState(null)
  const [group, setGroup] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState('')
  const hotelId = hotel?.id || null

  const refresh = useCallback(async () => {
    if (!hotelId) return
    setLoading(true)
    try {
      const [nextWorkspace, nextGroup] = await Promise.all([
        loadV11cPlatformWorkspace(hotelId),
        loadV11cMultiPropertyOverview(),
      ])
      setWorkspace(nextWorkspace || {})
      setGroup(nextGroup || {})
    } catch (error) {
      setNotice(error?.message || 'Unable to load Platform Hub.')
    } finally {
      setLoading(false)
    }
  }, [hotelId])

  useEffect(() => {
    refresh()
  }, [refresh])

  if (!hotelId) return <div className="v11c-page">Select a hotel to continue.</div>

  const settings = workspace?.whatsapp?.settings || {}
  const health = workspace?.whatsapp?.health || {}
  const provider = workspace?.whatsapp?.provider || null
  const templateCounts = workspace?.whatsapp?.templates || {}
  const deliveryCounts = workspace?.whatsapp?.deliveries || {}
  const summary = group?.summary || {}
  const properties = group?.properties || []

  async function saveSettings(next) {
    setBusy(true)
    setNotice('')
    try {
      await saveV11cWhatsAppSettings(hotelId, next)
      setNotice('WhatsApp safety settings saved.')
      await refresh()
    } catch (error) {
      setNotice(error?.message || 'Unable to save WhatsApp safety settings.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="v11c-page">
      <header className="v11c-hero">
        <div>
          <span>V1.1-C · PLATFORM, COMMUNICATION & MULTI-PROPERTY</span>
          <h1>Platform Hub</h1>
          <p>Authorized group visibility, consent-led WhatsApp resilience and audited support-access controls.</p>
        </div>
        <button type="button" onClick={refresh} disabled={loading}>Refresh</button>
      </header>

      {notice && <div className="v11c-notice">{notice}</div>}

      <section className="v11c-metrics">
        <Metric label="Authorized properties" value={summary.property_count ?? tenantContext?.hotels?.length ?? properties.length} />
        <Metric label="Total rooms" value={summary.total_rooms ?? 0} />
        <Metric label="Occupied rooms" value={summary.occupied_rooms ?? 0} />
        <Metric label="Open balance" value={money(summary.open_balance)} />
      </section>

      <nav className="v11c-tabs">
        {TABS.map(([id, label]) => (
          <button key={id} type="button" className={tab === id ? 'active' : ''} onClick={() => setTab(id)}>{label}</button>
        ))}
      </nav>

      {loading ? <section className="v11c-card">Loading V1.1-C workspace…</section> : null}

      {!loading && tab === 'group' && (
        <section className="v11c-grid">
          {properties.map((property) => (
            <article className={`v11c-card ${property.hotel_id === hotelId ? 'selected' : ''}`} key={property.hotel_id}>
              <div className="v11c-card-head"><div><span>PROPERTY</span><h2>{property.hotel_name}</h2><p>{property.location || 'Location not set'}</p></div><strong>{property.hotel_id === hotelId ? 'CURRENT' : 'AUTHORIZED'}</strong></div>
              <div className="v11c-property-stats">
                <Small label="Rooms" value={property.total_rooms} />
                <Small label="Available" value={property.available_rooms} />
                <Small label="Occupied" value={property.occupied_rooms} />
                <Small label="Active guests" value={property.active_guests} />
                <Small label="Open folios" value={property.open_folios} />
                <Small label="Outstanding" value={money(property.open_balance)} />
              </div>
              <button type="button" disabled={property.hotel_id === hotelId} onClick={() => onHotelChange?.(property.hotel_id)}>{property.hotel_id === hotelId ? 'Current property' : 'Switch to property'}</button>
            </article>
          ))}
          {properties.length === 0 && <article className="v11c-card">No authorized properties were returned.</article>}
        </section>
      )}

      {!loading && tab === 'whatsapp' && (
        <WhatsAppPanel
          settings={settings}
          health={health}
          provider={provider}
          templateCounts={templateCounts}
          deliveryCounts={deliveryCounts}
          busy={busy}
          onSave={saveSettings}
          onNavigate={onNavigate}
        />
      )}

      {!loading && tab === 'support' && (
        <section className="v11c-grid two">
          <article className="v11c-card">
            <span>SUPPORT ACCESS POLICY</span>
            <h2>Audited View as Hotel</h2>
            <p>Platform support remains explicit, reason-bound and time-limited. V1.1-C permits one active support session per Platform Admin, with a maximum duration of 120 minutes.</p>
            <div className="v11c-property-stats">
              <Small label="Max duration" value="120 min" />
              <Small label="Concurrent sessions" value="1 / admin" />
              <Small label="Silent impersonation" value="Blocked" />
              <Small label="Expiry extends on use" value="No" />
            </div>
          </article>
          <article className="v11c-card">
            <span>FAIL-CLOSED TENANT CONTROL</span>
            <h2>Cross-property writes stay local</h2>
            <p>Group View is read-only aggregation. Operational changes still require switching into an individually authorized hotel context; Platform Admin hotel entry still requires an active audited support session.</p>
            <div className="v11c-guard-list"><b>✓ Authorization before aggregation</b><b>✓ Existing tenant selector preserved</b><b>✓ No cross-property bulk writes</b><b>✓ Support expiry/revocation enforced server-side</b></div>
          </article>
        </section>
      )}
    </main>
  )
}

function WhatsAppPanel({ settings, health, provider, templateCounts, deliveryCounts, busy, onSave, onNavigate }) {
  const [form, setForm] = useState(() => ({
    channel_enabled: Boolean(settings.channel_enabled),
    transactional_enabled: settings.transactional_enabled !== false,
    marketing_enabled: Boolean(settings.marketing_enabled),
    failure_threshold: Number(settings.failure_threshold || 3),
    cooldown_minutes: Number(settings.cooldown_minutes || 15),
  }))

  useEffect(() => {
    setForm({
      channel_enabled: Boolean(settings.channel_enabled),
      transactional_enabled: settings.transactional_enabled !== false,
      marketing_enabled: Boolean(settings.marketing_enabled),
      failure_threshold: Number(settings.failure_threshold || 3),
      cooldown_minutes: Number(settings.cooldown_minutes || 15),
    })
  }, [settings.channel_enabled, settings.transactional_enabled, settings.marketing_enabled, settings.failure_threshold, settings.cooldown_minutes])

  const providerReady = provider?.status === 'active' && Number(templateCounts.provider_approved || 0) > 0
  const circuitOpen = health?.circuit_state === 'open'
  const automationReady = providerReady && form.channel_enabled && !circuitOpen

  return <section className="v11c-grid two">
    <form className="v11c-card" onSubmit={(event) => { event.preventDefault(); onSave(form) }}>
      <div className="v11c-card-head"><div><span>HOTEL CHANNEL POLICY</span><h2>WhatsApp delivery guard</h2></div><strong>{automationReady ? 'READY' : 'LOCKED'}</strong></div>
      <label className="v11c-check"><input type="checkbox" checked={form.channel_enabled} onChange={(e) => setForm({ ...form, channel_enabled: e.target.checked })} />Enable automated provider channel</label>
      <label className="v11c-check"><input type="checkbox" checked={form.transactional_enabled} onChange={(e) => setForm({ ...form, transactional_enabled: e.target.checked })} />Allow transactional messaging</label>
      <label className="v11c-check"><input type="checkbox" checked={form.marketing_enabled} onChange={(e) => setForm({ ...form, marketing_enabled: e.target.checked })} />Allow marketing messaging after explicit consent</label>
      <div className="v11c-form-grid"><label>Failure threshold<input type="number" min="2" max="10" value={form.failure_threshold} onChange={(e) => setForm({ ...form, failure_threshold: Number(e.target.value) })} /></label><label>Cooldown (minutes)<input type="number" min="5" max="60" value={form.cooldown_minutes} onChange={(e) => setForm({ ...form, cooldown_minutes: Number(e.target.value) })} /></label></div>
      <button disabled={busy}>Save safety settings</button>
      <p className="v11c-muted">Enabling is rejected server-side unless the hotel has an active Meta sender and at least one published provider-approved template. Edge environment credentials and WHATSAPP_AUTOMATION_ENABLED remain separately required.</p>
    </form>

    <article className="v11c-card">
      <span>PROVIDER & CIRCUIT HEALTH</span>
      <h2>{providerReady ? 'Meta sender configured' : 'Provider activation incomplete'}</h2>
      <div className="v11c-property-stats">
        <Small label="Provider" value={provider?.provider || 'meta_cloud'} />
        <Small label="Sender" value={provider?.status || 'not configured'} />
        <Small label="Approved templates" value={templateCounts.provider_approved || 0} />
        <Small label="Circuit" value={health?.circuit_state || 'closed'} />
        <Small label="Failure streak" value={health?.failure_streak || 0} />
        <Small label="Failed deliveries" value={deliveryCounts.failed || 0} />
      </div>
      <div className="v11c-guard-list"><b>✓ Consent is rechecked before send</b><b>✓ Opt-out suppression is rechecked before send</b><b>✓ Meta template approval is rechecked</b><b>✓ Provider failures trip a per-hotel circuit breaker</b></div>
      <button type="button" onClick={() => onNavigate?.('guests')}>Open Guest Communications</button>
    </article>
  </section>
}

function Metric({ label, value }) { return <article className="v11c-metric"><span>{label}</span><strong>{value}</strong></article> }
function Small({ label, value }) { return <div><span>{label}</span><strong>{value ?? 0}</strong></div> }
function money(value) { return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 }).format(Number(value || 0)) }
