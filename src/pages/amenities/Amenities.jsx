import { useCallback, useEffect, useMemo, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import { addAmenity, updateAmenity } from '../../lib/onboarding'
import {
  getGuestGuideMediaUrl,
  isGuestGuideVideo,
  makeGuestGuideKey,
  removeGuestGuideMediaFile,
  saveGuestGuideMedia,
  uploadGuestGuideMediaFile,
} from '../../lib/guestGuideBuilder'
import { supabase } from '../../lib/supabase'
import './Amenities.css'

const EMPTY_FORM = {
  name: '',
  code: '',
  category: 'general',
  description: '',
  icon: '',
}

export default function Amenities() {
  const [hotel, setHotel] = useState(null)
  const [amenities, setAmenities] = useState([])
  const [media, setMedia] = useState([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [busyAmenityId, setBusyAmenityId] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [form, setForm] = useState(EMPTY_FORM)

  const loadAmenities = useCallback(async (hotelId) => {
    const [amenityResult, mediaResult] = await Promise.all([
      supabase
        .from('amenities')
        .select('*')
        .eq('hotel_id', hotelId)
        .order('sort_order', { ascending: true })
        .order('name', { ascending: true }),
      supabase
        .from('guest_guide_media')
        .select('*')
        .eq('hotel_id', hotelId)
        .eq('category', 'facility')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: true }),
    ])

    if (amenityResult.error) throw amenityResult.error
    if (mediaResult.error) throw mediaResult.error
    setAmenities(amenityResult.data || [])
    setMedia(mediaResult.data || [])
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
    void initialize()
  }, [initialize])

  const mediaByAmenity = useMemo(() => {
    const grouped = new Map()
    media.forEach((item) => {
      const amenityId = String(item?.metadata?.amenity_id || '')
      if (!amenityId) return
      if (!grouped.has(amenityId)) grouped.set(amenityId, [])
      grouped.get(amenityId).push(item)
    })
    return grouped
  }, [media])

  async function handleAdd(event) {
    event.preventDefault()
    if (!form.name.trim()) {
      setError('Amenity name is required.')
      return
    }

    setSaving(true)
    setError('')
    setNotice('')
    try {
      await addAmenity(hotel.id, form)
      setForm(EMPTY_FORM)
      await loadAmenities(hotel.id)
      setNotice('Amenity added.')
    } catch (saveError) {
      setError(saveError?.message || 'Amenity could not be added.')
    } finally {
      setSaving(false)
    }
  }

  async function toggleAmenity(amenity, field) {
    setBusyAmenityId(amenity.id)
    setError('')
    try {
      await updateAmenity(hotel.id, amenity.id, { [field]: !amenity[field] })
      await loadAmenities(hotel.id)
    } catch (updateError) {
      setError(updateError?.message || 'Amenity could not be updated.')
    } finally {
      setBusyAmenityId('')
    }
  }

  async function editAmenity(amenity) {
    const name = window.prompt('Amenity name', amenity.name || '')
    if (name === null || !name.trim()) return
    const description = window.prompt('Description', amenity.description || '')
    if (description === null) return
    const instructions = window.prompt('Guest instructions', amenity.instructions || '')
    if (instructions === null) return

    setBusyAmenityId(amenity.id)
    setError('')
    try {
      await updateAmenity(hotel.id, amenity.id, {
        name: name.trim(),
        description: description.trim() || null,
        instructions: instructions.trim() || null,
      })
      await loadAmenities(hotel.id)
      setNotice('Amenity details updated.')
    } catch (updateError) {
      setError(updateError?.message || 'Amenity could not be updated.')
    } finally {
      setBusyAmenityId('')
    }
  }

  async function uploadAmenityMedia(amenity, file) {
    if (!file) return
    setBusyAmenityId(amenity.id)
    setError('')
    setNotice('')
    try {
      const upload = await uploadGuestGuideMediaFile({
        hotelId: hotel.id,
        file,
        scopeType: 'hotel',
        category: 'facility',
      })
      const existing = mediaByAmenity.get(amenity.id) || []
      await saveGuestGuideMedia(hotel.id, {
        section_id: null,
        item_id: null,
        scope_type: 'hotel',
        room_type_id: null,
        room_id: null,
        media_key: makeGuestGuideKey(
          `amenity_${amenity.code}_${String(upload.objectPath || file.name).split('/').pop()}`,
          'amenity_media',
        ),
        category: 'facility',
        object_path: upload.objectPath,
        mime_type: upload.mimeType,
        title: amenity.name,
        caption: '',
        alt_text: `${amenity.name} ${upload.mediaKind === 'video' ? 'video' : 'image'}`,
        locale: null,
        sort_order: existing.length * 10,
        is_active: true,
        metadata: {
          amenity_id: amenity.id,
          purpose: 'amenity_gallery',
          media_kind: upload.mediaKind,
          duration_seconds: upload.durationSeconds,
        },
      })
      await loadAmenities(hotel.id)
      setNotice(`${upload.mediaKind === 'video' ? 'Short video' : 'Image'} added to ${amenity.name}.`)
    } catch (uploadError) {
      setError(uploadError?.message || 'Amenity media could not be uploaded.')
    } finally {
      setBusyAmenityId('')
    }
  }

  async function editMediaDetails(item) {
    const title = window.prompt('Media title', item.title || '')
    if (title === null) return
    const caption = window.prompt('Caption', item.caption || '')
    if (caption === null) return

    setBusyAmenityId(String(item?.metadata?.amenity_id || 'media'))
    try {
      await saveGuestGuideMedia(hotel.id, {
        section_id: item.section_id,
        item_id: item.item_id,
        scope_type: item.scope_type,
        room_type_id: item.room_type_id,
        room_id: item.room_id,
        media_key: item.media_key,
        category: item.category,
        object_path: item.object_path,
        mime_type: item.mime_type,
        title: title.trim(),
        caption: caption.trim(),
        alt_text: item.alt_text || title.trim() || 'Amenity media',
        locale: item.locale,
        sort_order: item.sort_order,
        is_active: true,
        metadata: item.metadata || {},
      })
      await loadAmenities(hotel.id)
      setNotice('Amenity media details updated.')
    } catch (mediaError) {
      setError(mediaError?.message || 'Media details could not be updated.')
    } finally {
      setBusyAmenityId('')
    }
  }

  async function removeMedia(item) {
    if (!window.confirm(`Remove ${item.title || 'this media item'}?`)) return
    setBusyAmenityId(String(item?.metadata?.amenity_id || 'media'))
    try {
      await saveGuestGuideMedia(hotel.id, {
        section_id: item.section_id,
        item_id: item.item_id,
        scope_type: item.scope_type,
        room_type_id: item.room_type_id,
        room_id: item.room_id,
        media_key: item.media_key,
        category: item.category,
        object_path: item.object_path,
        mime_type: item.mime_type,
        title: item.title,
        caption: item.caption,
        alt_text: item.alt_text,
        locale: item.locale,
        sort_order: item.sort_order,
        is_active: false,
        metadata: item.metadata || {},
      })
      await removeGuestGuideMediaFile(item.object_path)
      await loadAmenities(hotel.id)
      setNotice('Amenity media removed.')
    } catch (mediaError) {
      setError(mediaError?.message || 'Amenity media could not be removed.')
    } finally {
      setBusyAmenityId('')
    }
  }

  if (loading) return <div className="amenities-page">Loading amenities…</div>

  const activeCount = amenities.filter((item) => item.is_active).length
  const guestVisibleCount = amenities.filter((item) => item.is_active && item.guest_visible).length

  return (
    <div className="amenities-page">
      <header className="amenities-header">
        <div>
          <span>HOTEL CONFIGURATION</span>
          <h1>Amenities & Gallery</h1>
          <p>{hotel?.hotel_name} · Manage amenity details, guest visibility and tenant-scoped media.</p>
        </div>
        <button type="button" onClick={() => void loadAmenities(hotel?.id)}>Refresh</button>
      </header>

      {error && <div className="amenities-alert error">{error}</div>}
      {notice && <div className="amenities-alert success">{notice}</div>}

      <div className="amenities-stats">
        <Stat label="Total" value={amenities.length} />
        <Stat label="Active" value={activeCount} />
        <Stat label="Guest visible" value={guestVisibleCount} />
        <Stat label="Media assets" value={media.length} />
      </div>

      <form className="amenities-form" onSubmit={handleAdd}>
        <h2>Add amenity</h2>
        <div className="amenities-form-grid">
          <input placeholder="Amenity name" value={form.name} onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))} />
          <input placeholder="Code (optional)" value={form.code} onChange={(event) => setForm((current) => ({ ...current, code: event.target.value }))} />
          <input placeholder="Category" value={form.category} onChange={(event) => setForm((current) => ({ ...current, category: event.target.value }))} />
          <input placeholder="Icon name" value={form.icon} onChange={(event) => setForm((current) => ({ ...current, icon: event.target.value }))} />
        </div>
        <textarea placeholder="Description" value={form.description} onChange={(event) => setForm((current) => ({ ...current, description: event.target.value }))} />
        <button className="primary" disabled={saving}>{saving ? 'Saving…' : 'Add amenity'}</button>
      </form>

      <div className="amenities-grid">
        {amenities.map((item) => {
          const gallery = mediaByAmenity.get(item.id) || []
          const busy = busyAmenityId === item.id
          return (
            <article key={item.id} className="amenity-card">
              <div className="amenity-card-head">
                <div className="amenity-icon">{displayIcon(item.icon)}</div>
                <span className={item.is_active ? 'active' : 'disabled'}>{item.is_active ? 'Active' : 'Disabled'}</span>
              </div>
              <h3>{item.name}</h3>
              <small>{item.category}</small>
              <p>{item.description || 'No description added.'}</p>
              {item.instructions && <p className="amenity-instructions">Guest instructions: {item.instructions}</p>}

              <div className="amenity-gallery">
                {gallery.map((asset) => (
                  <figure key={asset.id}>
                    {isGuestGuideVideo(asset.mime_type) ? (
                      <video src={getGuestGuideMediaUrl(asset.object_path)} controls playsInline preload="metadata" />
                    ) : (
                      <img src={getGuestGuideMediaUrl(asset.object_path)} alt={asset.alt_text || asset.title || item.name} loading="lazy" />
                    )}
                    <figcaption>
                      <strong>{asset.title || item.name}</strong>
                      <span>{asset.caption || (isGuestGuideVideo(asset.mime_type) ? 'Short video' : 'Gallery image')}</span>
                      <div>
                        <button type="button" onClick={() => void editMediaDetails(asset)} disabled={busy}>Edit</button>
                        <button type="button" className="danger" onClick={() => void removeMedia(asset)} disabled={busy}>Remove</button>
                      </div>
                    </figcaption>
                  </figure>
                ))}
                {gallery.length === 0 && <div className="amenity-gallery-empty">No gallery media yet.</div>}
              </div>

              <label className="amenity-upload">
                {busy ? 'Working…' : '+ Add image / short video'}
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp,video/mp4,video/webm"
                  hidden
                  disabled={busy}
                  onChange={(event) => {
                    const file = event.target.files?.[0]
                    if (file) void uploadAmenityMedia(item, file)
                    event.target.value = ''
                  }}
                />
              </label>

              <div className="amenity-actions">
                <button type="button" disabled={busy} onClick={() => void editAmenity(item)}>Edit details</button>
                <button type="button" disabled={busy} onClick={() => void toggleAmenity(item, 'is_active')}>{item.is_active ? 'Disable' : 'Enable'}</button>
                <button type="button" disabled={busy} onClick={() => void toggleAmenity(item, 'guest_visible')}>{item.guest_visible ? 'Hide from guests' : 'Show to guests'}</button>
              </div>
            </article>
          )
        })}
      </div>
    </div>
  )
}

function Stat({ label, value }) {
  return <div className="amenities-stat"><span>{label}</span><strong>{value}</strong></div>
}

function displayIcon(iconName) {
  const icons = { wifi: '📶', 'air-conditioning': '❄️', droplets: '🚿', tv: '📺', sparkles: '✨' }
  return icons[iconName] || '★'
}
