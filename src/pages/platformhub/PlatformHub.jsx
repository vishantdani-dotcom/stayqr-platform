import { useCallback, useEffect, useState } from 'react'
import { loadV11cMultiPropertyOverview } from '../../lib/v11Platform'
import './PlatformHub.css'

const TABS = [
  ['group', 'Group View'],
  ['support', 'Support Guard'],
]

export default function PlatformHub({ hotel, tenantContext, onHotelChange }) {
  const [tab, setTab] = useState('group')
  const [group, setGroup] = useState(null)
  const [loading, setLoading] = useState(true)
  const [notice, setNotice] = useState('')
  const hotelId = hotel?.id || null

  const refresh = useCallback(async () => {
    if (!hotelId) return
    setLoading(true)
    setNotice('')
    try {
      setGroup(await loadV11cMultiPropertyOverview())
    } catch (error) {
      setNotice(error?.message || 'Unable to load property network.')
    } finally {
      setLoading(false)
    }
  }, [hotelId])

  useEffect(() => { void refresh() }, [refresh])

  if (!hotelId) return <div className="v11c-page">Select a hotel to continue.</div>

  const summary = group?.summary || {}
  const properties = group?.properties || []

  return (
    <main className="v11c-page">
      <header className="v11c-hero">
        <div>
          <span>PROPERTY NETWORK &amp; SUPPORT</span>
          <h1>Properties &amp; Support</h1>
          <p>Authorized multi-property visibility and explicit, audited StayQR support access.</p>
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

      {loading ? <section className="v11c-card">Loading property network…</section> : null}

      {!loading && tab === 'group' && (
        <section className="v11c-grid">
          {properties.map((property) => (
            <article className={`v11c-card ${property.hotel_id === hotelId ? 'selected' : ''}`} key={property.hotel_id}>
              <div className="v11c-card-head">
                <div><span>PROPERTY</span><h2>{property.hotel_name}</h2><p>{property.location || 'Location not set'}</p></div>
                <strong>{property.hotel_id === hotelId ? 'CURRENT' : 'AUTHORIZED'}</strong>
              </div>
              <div className="v11c-property-stats">
                <Small label="Rooms" value={property.total_rooms} />
                <Small label="Available" value={property.available_rooms} />
                <Small label="Occupied" value={property.occupied_rooms} />
                <Small label="Active guests" value={property.active_guests} />
                <Small label="Open folios" value={property.open_folios} />
                <Small label="Outstanding" value={money(property.open_balance)} />
              </div>
              <button type="button" disabled={property.hotel_id === hotelId} onClick={() => onHotelChange?.(property.hotel_id)}>
                {property.hotel_id === hotelId ? 'Current property' : 'Switch to property'}
              </button>
            </article>
          ))}
          {properties.length === 0 && <article className="v11c-card">No additional authorized properties were returned.</article>}
        </section>
      )}

      {!loading && tab === 'support' && (
        <section className="v11c-grid two">
          <article className="v11c-card">
            <span>SUPPORT ACCESS POLICY</span>
            <h2>Audited View as Hotel</h2>
            <p>StayQR support access is explicit, reason-bound and time-limited. Platform support never silently impersonates a hotel user.</p>
            <div className="v11c-property-stats">
              <Small label="Max session" value="120 min" />
              <Small label="Concurrent sessions" value="1 / admin" />
              <Small label="Silent impersonation" value="Blocked" />
              <Small label="Automatic extension" value="No" />
            </div>
          </article>
          <article className="v11c-card">
            <span>TENANT CONTROL</span>
            <h2>Cross-property writes stay isolated</h2>
            <p>Group View is read-only aggregation. Operational changes still require switching into an individually authorized hotel context.</p>
            <div className="v11c-guard-list"><b>✓ Authorization before aggregation</b><b>✓ Existing tenant selector preserved</b><b>✓ No cross-property bulk writes</b><b>✓ Support expiry/revocation enforced server-side</b></div>
          </article>
          <article className="v11c-card">
            <span>UPCOMING INTEGRATIONS</span>
            <h2>Provider automations are intentionally on hold</h2>
            <p>Automated WhatsApp campaigns and online AutoPay are not required for the launch product. Their hardened backend foundations remain disabled until StayQR explicitly enables them later.</p>
          </article>
        </section>
      )}
    </main>
  )
}

function Metric({ label, value }) { return <article className="v11c-metric"><span>{label}</span><strong>{value}</strong></article> }
function Small({ label, value }) { return <div><span>{label}</span><strong>{value ?? '—'}</strong></div> }
function money(value) { return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(Number(value || 0)) }
