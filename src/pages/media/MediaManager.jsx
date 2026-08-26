import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  getGuestGuideMediaUrl,
  isGuestGuideVideo,
  removeGuestGuideMediaFile,
  saveGuestGuideMedia,
  uploadGuestGuideMediaFile,
} from '../../lib/guestGuideBuilder'
import './MediaManager.css'

const CATEGORIES = [
  ['property', 'Property'],
  ['room', 'Rooms'],
  ['facility', 'Amenities'],
  ['dining', 'Dining / Menu'],
  ['custom', 'Guest Guide'],
  ['logo', 'Logo'],
  ['hero', 'Cover'],
  ['payment_qr', 'Payment QR'],
]

export default function MediaManager() {
  const [hotel, setHotel] = useState(null)
  const [media, setMedia] = useState([])
  const [roomTypes, setRoomTypes] = useState([])
  const [rooms, setRooms] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState('all')
  const [draft, setDraft] = useState({
    category: 'property',
    scope_type: 'hotel',
    room_type_id: '',
    room_id: '',
    title: '',
    caption: '',
  })

  const load = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      const currentHotel = await getCurrentHotel()
      if (!currentHotel?.id) throw new Error('No active hotel context.')
      setHotel(currentHotel)

      const [mediaResult, roomTypeResult, roomResult] = await Promise.all([
        supabase
          .from('guest_guide_media')
          .select('*')
          .eq('hotel_id', currentHotel.id)
          .eq('is_active', true)
          .order('updated_at', { ascending: false }),
        supabase
          .from('room_types')
          .select('id, name')
          .eq('hotel_id', currentHotel.id)
          .order('name'),
        supabase
          .from('rooms')
          .select('id, room_number, room_type')
          .eq('hotel_id', currentHotel.id)
          .eq('is_active', true)
          .order('room_number'),
      ])
      if (mediaResult.error) throw mediaResult.error
      if (roomTypeResult.error) throw roomTypeResult.error
      if (roomResult.error) throw roomResult.error
      setMedia(mediaResult.data || [])
      setRoomTypes(roomTypeResult.data || [])
      setRooms(roomResult.data || [])
    } catch (loadError) {
      setError(loadError?.message || 'Unable to load media manager.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const visibleMedia = useMemo(() => {
    const term = search.trim().toLowerCase()
    return media.filter((item) => {
      if (filter !== 'all' && item.category !== filter) return false
      if (!term) return true
      return [item.title, item.caption, item.category, item.mime_type]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(term))
    })
  }, [filter, media, search])

  async function upload(file) {
    if (!hotel?.id || !file) return
    setBusy(true)
    setError('')
    setNotice('')
    try {
      if (draft.scope_type === 'room_type' && !draft.room_type_id) throw new Error('Choose a room type.')
      if (draft.scope_type === 'room' && !draft.room_id) throw new Error('Choose a room.')

      const uploadResult = await uploadGuestGuideMediaFile({
        hotelId: hotel.id,
        file,
        scopeType: draft.scope_type,
        roomTypeId: draft.room_type_id,
        roomId: draft.room_id,
        category: draft.category,
      })
      const mediaKey = `media_${draft.category}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`
      await saveGuestGuideMedia(hotel.id, {
        scope_type: draft.scope_type,
        room_type_id: draft.scope_type === 'room_type' ? draft.room_type_id : null,
        room_id: draft.scope_type === 'room' ? draft.room_id : null,
        section_id: null,
        item_id: null,
        media_key: mediaKey,
        category: draft.category,
        object_path: uploadResult.objectPath,
        mime_type: uploadResult.mimeType,
        title: draft.title.trim() || CATEGORIES.find(([key]) => key === draft.category)?.[1] || 'Hotel media',
        caption: draft.caption.trim(),
        alt_text: draft.title.trim() || `${hotel.hotel_name} media`,
        locale: null,
        sort_order: 0,
        is_active: true,
        metadata: {
          media_kind: uploadResult.mediaKind,
          duration_seconds: uploadResult.durationSeconds,
          managed_from: 'media_manager',
        },
      })
      setDraft((current) => ({ ...current, title: '', caption: '' }))
      setNotice(`${uploadResult.mediaKind === 'video' ? 'Short video' : 'Image'} uploaded.`)
      await load()
    } catch (uploadError) {
      setError(uploadError?.message || 'Unable to upload media.')
    } finally {
      setBusy(false)
    }
  }

  async function edit(item) {
    const title = window.prompt('Media title', item.title || '')
    if (title === null) return
    const caption = window.prompt('Caption', item.caption || '')
    if (caption === null) return
    setBusy(true)
    setError('')
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
        alt_text: item.alt_text || title.trim() || 'Hotel media',
        locale: item.locale,
        sort_order: item.sort_order || 0,
        is_active: true,
        metadata: item.metadata || {},
      })
      setNotice('Media details updated.')
      await load()
    } catch (editError) {
      setError(editError?.message || 'Unable to edit media.')
    } finally {
      setBusy(false)
    }
  }

  async function remove(item) {
    if (!window.confirm('Remove this media asset from StayQR?')) return
    setBusy(true)
    setError('')
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
        sort_order: item.sort_order || 0,
        is_active: false,
        metadata: item.metadata || {},
      })
      await removeGuestGuideMediaFile(item.object_path).catch(() => undefined)
      setNotice('Media removed.')
      await load()
    } catch (removeError) {
      setError(removeError?.message || 'Unable to remove media.')
    } finally {
      setBusy(false)
    }
  }

  if (loading) return <div className="media-manager-page"><p>Loading unified media library…</p></div>

  return (
    <div className="media-manager-page">
      <header className="media-manager-header">
        <div>
          <p className="media-manager-kicker">Unified Media Library</p>
          <h1>Media Manager</h1>
          <p>{hotel?.hotel_name} · Manage tenant-scoped images and approved short videos from one place.</p>
        </div>
        <button type="button" onClick={() => void load()} disabled={busy}>Refresh</button>
      </header>

      {notice && <div className="media-manager-alert success">{notice}</div>}
      {error && <div className="media-manager-alert error">{error}</div>}

      <section className="media-manager-uploader">
        <div className="media-manager-form-grid">
          <label>Category
            <select value={draft.category} onChange={(event) => setDraft((current) => ({ ...current, category: event.target.value }))}>
              {CATEGORIES.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
            </select>
          </label>
          <label>Scope
            <select value={draft.scope_type} onChange={(event) => setDraft((current) => ({ ...current, scope_type: event.target.value, room_type_id: '', room_id: '' }))}>
              <option value="hotel">Entire hotel</option>
              <option value="room_type">Room type</option>
              <option value="room">Specific room</option>
            </select>
          </label>
          {draft.scope_type === 'room_type' && <label>Room type
            <select value={draft.room_type_id} onChange={(event) => setDraft((current) => ({ ...current, room_type_id: event.target.value }))}>
              <option value="">Choose room type</option>
              {roomTypes.map((roomType) => <option key={roomType.id} value={roomType.id}>{roomType.name}</option>)}
            </select>
          </label>}
          {draft.scope_type === 'room' && <label>Room
            <select value={draft.room_id} onChange={(event) => setDraft((current) => ({ ...current, room_id: event.target.value }))}>
              <option value="">Choose room</option>
              {rooms.map((room) => <option key={room.id} value={room.id}>Room {room.room_number} · {room.room_type || 'Room'}</option>)}
            </select>
          </label>}
          <label>Title<input value={draft.title} onChange={(event) => setDraft((current) => ({ ...current, title: event.target.value }))} /></label>
          <label>Caption<input value={draft.caption} onChange={(event) => setDraft((current) => ({ ...current, caption: event.target.value }))} /></label>
        </div>
        <div className="media-manager-upload-row">
          <label className="media-manager-upload-button">
            {busy ? 'Working…' : 'Upload image / short video'}
            <input type="file" hidden disabled={busy} accept="image/jpeg,image/png,image/webp,video/mp4,video/webm" onChange={(event) => { const file = event.target.files?.[0]; if (file) void upload(file); event.target.value = '' }} />
          </label>
          <small>Images: JPG/PNG/WebP. Short video: MP4/WebM, approved categories only, max 20 MB and 30 seconds.</small>
        </div>
      </section>

      <section className="media-manager-library">
        <div className="media-manager-toolbar">
          <input placeholder="Search media…" value={search} onChange={(event) => setSearch(event.target.value)} />
          <select value={filter} onChange={(event) => setFilter(event.target.value)}>
            <option value="all">All categories</option>
            {CATEGORIES.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
          </select>
          <span>{visibleMedia.length} asset(s)</span>
        </div>

        {visibleMedia.length === 0 ? <div className="media-manager-empty">No matching media assets.</div> : (
          <div className="media-manager-grid">
            {visibleMedia.map((item) => (
              <article key={item.id} className="media-manager-card">
                <div className="media-manager-preview">
                  {isGuestGuideVideo(item.mime_type)
                    ? <video src={getGuestGuideMediaUrl(item.object_path)} controls playsInline preload="metadata" />
                    : <img src={getGuestGuideMediaUrl(item.object_path)} alt={item.alt_text || item.title || 'Hotel media'} loading="lazy" />}
                </div>
                <div className="media-manager-copy">
                  <strong>{item.title || item.category}</strong>
                  <span>{item.category.replaceAll('_', ' ')} · {item.scope_type.replaceAll('_', ' ')} · {isGuestGuideVideo(item.mime_type) ? 'short video' : 'image'}</span>
                  {item.caption && <p>{item.caption}</p>}
                </div>
                <div className="media-manager-card-actions">
                  <button type="button" onClick={() => void edit(item)} disabled={busy}>Edit</button>
                  <button type="button" className="danger" onClick={() => void remove(item)} disabled={busy}>Remove</button>
                </div>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
