import { useCallback, useEffect, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import { addAmenity, updateAmenity } from '../../lib/onboarding'
import { supabase } from '../../lib/supabase'

export default function Amenities() {
  const [hotel, setHotel] = useState(null)
  const [amenities, setAmenities] = useState([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [form, setForm] = useState({
    name: '',
    code: '',
    category: 'general',
    description: '',
    icon: '',
  })

  const loadAmenities = useCallback(async (hotelId) => {
    const { data, error: loadError } = await supabase
      .from('amenities')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sort_order', { ascending: true })
      .order('name', { ascending: true })

    if (loadError) throw loadError
    setAmenities(data || [])
    setLoading(false)
  }, [])

  const initialize = useCallback(async () => {
    setLoading(true)
    setError('')

    try {
      const currentHotel = await getCurrentHotel()
      if (!currentHotel) throw new Error('No hotel is selected.')
      setHotel(currentHotel)
      await loadAmenities(currentHotel.id)
    } catch (loadError) {
      setError(loadError?.message || 'Amenities could not be loaded.')
      setLoading(false)
    }
  }, [loadAmenities])

  useEffect(() => {
    initialize()
  }, [initialize])

  async function handleAdd(event) {
    event.preventDefault()
    if (!form.name.trim()) {
      setError('Amenity name is required.')
      return
    }

    setSaving(true)
    setError('')

    try {
      await addAmenity(hotel.id, form)
      setForm({
        name: '',
        code: '',
        category: 'general',
        description: '',
        icon: '',
      })
      await loadAmenities(hotel.id)
    } catch (saveError) {
      setError(saveError?.message || 'Amenity could not be added.')
    } finally {
      setSaving(false)
    }
  }

  async function toggleAmenity(amenity, field) {
    setSaving(true)
    setError('')

    try {
      await updateAmenity(hotel.id, amenity.id, {
        [field]: !amenity[field],
      })
      await loadAmenities(hotel.id)
    } catch (updateError) {
      setError(updateError?.message || 'Amenity could not be updated.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <div className="amenities-page" style={page}>Loading amenities…</div>

  const activeCount = amenities.filter((item) => item.is_active).length
  const guestVisibleCount = amenities.filter(
    (item) => item.is_active && item.guest_visible
  ).length

  return (
    <div className="amenities-page" style={page}>
      <div style={header}>
        <div>
          <span style={kicker}>Hotel configuration</span>
          <h1 style={title}>Amenities</h1>
          <p style={subtitle}>
            {hotel?.hotel_name} · Control what guests see in the secure guide.
          </p>
        </div>
        <button style={refreshButton} onClick={() => loadAmenities(hotel?.id)}>
          Refresh
        </button>
      </div>

      {error && <div style={errorBox}>{error}</div>}

      <div style={statsGrid}>
        <Stat label="Total" value={amenities.length} />
        <Stat label="Active" value={activeCount} />
        <Stat label="Guest visible" value={guestVisibleCount} />
      </div>

      <form style={formCard} onSubmit={handleAdd}>
        <h2 style={sectionTitle}>Add amenity</h2>
        <div style={formGrid}>
          <input style={input} placeholder="Amenity name" value={form.name} onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))} />
          <input style={input} placeholder="Code (optional)" value={form.code} onChange={(event) => setForm((current) => ({ ...current, code: event.target.value }))} />
          <input style={input} placeholder="Category" value={form.category} onChange={(event) => setForm((current) => ({ ...current, category: event.target.value }))} />
          <input style={input} placeholder="Icon name" value={form.icon} onChange={(event) => setForm((current) => ({ ...current, icon: event.target.value }))} />
        </div>
        <textarea style={{ ...input, minHeight: 90 }} placeholder="Description" value={form.description} onChange={(event) => setForm((current) => ({ ...current, description: event.target.value }))} />
        <button style={primaryButton} disabled={saving}>
          {saving ? 'Saving…' : 'Add amenity'}
        </button>
      </form>

      <div style={grid}>
        {amenities.map((item) => (
          <div key={item.id} style={card}>
            <div style={cardTop}>
              <div style={icon}>{displayIcon(item.icon)}</div>
              <span style={statusBadge(item.is_active)}>
                {item.is_active ? 'Active' : 'Disabled'}
              </span>
            </div>
            <h3 style={name}>{item.name}</h3>
            <p style={meta}>{item.category}</p>
            <p style={description}>{item.description || 'No description added.'}</p>
            <div style={cardActions}>
              <button style={smallButton} disabled={saving} onClick={() => toggleAmenity(item, 'is_active')}>
                {item.is_active ? 'Disable' : 'Enable'}
              </button>
              <button style={smallButton} disabled={saving} onClick={() => toggleAmenity(item, 'guest_visible')}>
                {item.guest_visible ? 'Hide from guests' : 'Show to guests'}
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function Stat({ label, value }) {
  return <div style={statCard}><span style={statLabel}>{label}</span><strong style={statValue}>{value}</strong></div>
}

function displayIcon(iconName) {
  const icons = {
    wifi: '📶',
    'air-conditioning': '❄️',
    droplets: '🚿',
    tv: '📺',
    sparkles: '✨',
  }
  return icons[iconName] || '★'
}

const page = { padding: '30px', color: '#fff' }
const header = { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 20, marginBottom: 24 }
const kicker = { color: '#d4af37', fontSize: 12, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '.14em' }
const title = { fontSize: '40px', margin: '7px 0 6px' }
const subtitle = { color: '#999' }
const refreshButton = { background: '#191919', border: '1px solid #333', color: '#fff', padding: '11px 16px', borderRadius: 10, cursor: 'pointer', fontWeight: 700 }
const errorBox = { marginBottom: 18, padding: 13, borderRadius: 10, color: '#ffb4b4', background: 'rgba(255,72,72,.1)', border: '1px solid rgba(255,72,72,.25)' }
const statsGrid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(160px,1fr))', gap: 14, marginBottom: 22 }
const statCard = { display: 'flex', flexDirection: 'column', gap: 8, padding: 18, background: '#0f0f0f', border: '1px solid #222', borderRadius: 14 }
const statLabel = { color: '#888', fontSize: 12, textTransform: 'uppercase' }
const statValue = { fontSize: 26 }
const formCard = { padding: 22, marginBottom: 24, background: '#0f0f0f', border: '1px solid #222', borderRadius: 18 }
const sectionTitle = { color: '#d4af37', marginBottom: 16 }
const formGrid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))', gap: 12 }
const input = { width: '100%', padding: 12, marginBottom: 12, borderRadius: 10, border: '1px solid #333', background: '#111', color: '#fff' }
const primaryButton = { background: '#d4af37', color: '#000', border: 'none', borderRadius: 10, padding: '11px 17px', fontWeight: 800, cursor: 'pointer' }
const grid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(250px,1fr))', gap: 18 }
const card = { background: '#0f0f0f', border: '1px solid #222', borderRadius: 18, padding: 20 }
const cardTop = { display: 'flex', justifyContent: 'space-between', alignItems: 'center' }
const icon = { fontSize: 34 }
const name = { color: '#d4af37', margin: '14px 0 5px' }
const meta = { color: '#777', fontSize: 12, textTransform: 'uppercase' }
const description = { color: '#999', marginTop: 10, minHeight: 44 }
const cardActions = { display: 'flex', gap: 8, marginTop: 16, flexWrap: 'wrap' }
const smallButton = { padding: '8px 10px', borderRadius: 8, border: '1px solid #333', background: '#181818', color: '#fff', cursor: 'pointer' }
const statusBadge = (active) => ({ padding: '6px 9px', borderRadius: 999, fontSize: 11, fontWeight: 800, color: active ? '#72eab3' : '#ff9d9d', background: active ? 'rgba(61,220,151,.1)' : 'rgba(255,90,90,.1)' })
