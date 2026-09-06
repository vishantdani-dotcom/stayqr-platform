import { useCallback, useEffect, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import { supabase } from '../../lib/supabase'
import {
  getGuestGuideMediaUrl,
  removeGuestGuideMediaFile,
  saveGuestGuideMedia,
  uploadGuestGuideMediaFile,
} from '../../lib/guestGuideBuilder'
import {
  archiveFloor,
  archiveRoom,
  archiveRoomType,
  getRoomInventoryWorkspace,
  importRooms,
  saveFloor,
  saveRoom,
  saveRoomType,
  transitionRoomStatus,
} from '../../lib/day13Operations'
import '../day13/Day13Operations.css'
import './Rooms.css'

const EMPTY_FLOOR = {
  id: null,
  code: '',
  name: '',
  floor_number: '',
  description: '',
  sort_order: 0,
}

const EMPTY_TYPE = {
  id: null,
  code: '',
  name: '',
  description: '',
  base_occupancy: 1,
  max_adults: 2,
  max_children: 1,
  max_occupancy: 3,
  base_rate: 0,
  extra_adult_rate: 0,
  extra_child_rate: 0,
  sort_order: 0,
}

const EMPTY_ROOM = {
  id: null,
  room_number: '',
  floor_id: '',
  room_type_id: '',
  status: 'available',
}

async function loadRoomVisualMedia(hotelId) {
  const empty = { byRoom: {}, hotelFallback: '', qrRoomIds: new Set() }
  try {
    const [mediaResult, qrResult] = await Promise.all([
      supabase
        .from('guest_guide_media')
        .select('id, room_id, scope_type, category, object_path, mime_type, updated_at, is_active')
        .eq('hotel_id', hotelId)
        .eq('is_active', true)
        .in('category', ['room', 'hero', 'property'])
        .order('updated_at', { ascending: false }),
      supabase
        .from('room_qr_codes')
        .select('room_id, is_active')
        .eq('hotel_id', hotelId)
        .eq('is_active', true),
    ])

    const byRoom = {}
    let hotelFallback = ''
    if (!mediaResult.error) {
      for (const item of mediaResult.data || []) {
        const isImage = String(item.mime_type || '').startsWith('image/')
        if (!isImage || !item.object_path) continue
        const url = getGuestGuideMediaUrl(item.object_path)
        if (!url) continue
        if (item.scope_type === 'room' && item.room_id && !byRoom[item.room_id]) {
          byRoom[item.room_id] = { ...item, url }
        } else if (!hotelFallback && item.scope_type === 'hotel') {
          hotelFallback = url
        }
      }
    }

    const qrRoomIds = new Set(
      qrResult.error ? [] : (qrResult.data || []).map((item) => item.room_id).filter(Boolean)
    )
    return { byRoom, hotelFallback, qrRoomIds }
  } catch {
    return empty
  }
}

export default function Rooms({ hotel: hotelProp }) {
  const [hotel, setHotel] = useState(hotelProp || null)
  const [workspace, setWorkspace] = useState({
    rooms: [],
    floors: [],
    room_types: [],
    imports: [],
    status_events: [],
  })
  const [activeTab, setActiveTab] = useState('rooms')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [search, setSearch] = useState('')
  const [floorForm, setFloorForm] = useState(EMPTY_FLOOR)
  const [typeForm, setTypeForm] = useState(EMPTY_TYPE)
  const [roomForm, setRoomForm] = useState(EMPTY_ROOM)
  const [roomMedia, setRoomMedia] = useState({})
  const [hotelFallbackMedia, setHotelFallbackMedia] = useState('')
  const [qrRoomIds, setQrRoomIds] = useState(() => new Set())
  const [mediaBusyRoomId, setMediaBusyRoomId] = useState('')
  const [openRoomMenuId, setOpenRoomMenuId] = useState('')
  const [importText, setImportText] = useState(
    'room_number,floor_code,room_type_code,status\n'
  )

  const loadWorkspace = useCallback(async (showSpinner = true) => {
    if (showSpinner) setLoading(true)
    setError('')

    try {
      const activeHotel = hotel || (await getCurrentHotel())
      if (!activeHotel?.id) throw new Error('No active hotel is selected.')

      if (!hotel) setHotel(activeHotel)

      const [data, visuals] = await Promise.all([
        getRoomInventoryWorkspace(activeHotel.id),
        loadRoomVisualMedia(activeHotel.id),
      ])
      setWorkspace({
        rooms: data?.rooms || [],
        floors: data?.floors || [],
        room_types: data?.room_types || [],
        imports: data?.imports || [],
        status_events: data?.status_events || [],
      })
      setRoomMedia(visuals.byRoom || {})
      setHotelFallbackMedia(visuals.hotelFallback || '')
      setQrRoomIds(visuals.qrRoomIds || new Set())
    } catch (loadError) {
      setError(loadError.message)
    } finally {
      if (showSpinner) setLoading(false)
    }
  }, [hotel])

  useEffect(() => {
    loadWorkspace()
  }, [loadWorkspace])

  const rooms = workspace.rooms || []
  const activeRooms = rooms.filter((room) => room.is_active)
  const stats = {
    total: activeRooms.length,
    available: activeRooms.filter((room) => room.status === 'available').length,
    occupied: activeRooms.filter((room) => room.status === 'occupied').length,
    cleaning: activeRooms.filter((room) => room.status === 'cleaning').length,
    offline: activeRooms.filter((room) =>
      ['maintenance', 'out_of_order'].includes(room.status)
    ).length,
    archived: rooms.filter((room) => !room.is_active).length,
  }

  const query = search.trim().toLowerCase()
  const filteredRooms = query
    ? rooms.filter((room) =>
        [
          room.room_number,
          room.room_type_name,
          room.floor_name,
          room.status,
        ]
          .filter(Boolean)
          .some((value) => String(value).toLowerCase().includes(query))
      )
    : rooms

  const runAction = async (message, action) => {
    setSaving(true)
    setError('')
    setSuccess('')

    try {
      await action()
      setSuccess(message)
      await loadWorkspace(false)
    } catch (actionError) {
      setError(actionError.message)
    } finally {
      setSaving(false)
    }
  }

  const submitFloor = (event) => {
    event.preventDefault()
    runAction(floorForm.id ? 'Floor updated.' : 'Floor created.', async () => {
      await saveFloor(hotel.id, floorForm)
      setFloorForm(EMPTY_FLOOR)
    })
  }

  const submitType = (event) => {
    event.preventDefault()
    runAction(typeForm.id ? 'Room type updated.' : 'Room type created.', async () => {
      await saveRoomType(hotel.id, typeForm)
      setTypeForm(EMPTY_TYPE)
    })
  }

  const submitRoom = (event) => {
    event.preventDefault()
    runAction(roomForm.id ? 'Room updated.' : 'Room created.', async () => {
      await saveRoom(hotel.id, roomForm)
      setRoomForm(EMPTY_ROOM)
    })
  }

  const parseImportRows = () => {
    const lines = importText
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)

    if (lines.length < 2) {
      throw new Error('Paste at least one CSV room row.')
    }

    const [headerLine, ...dataLines] = lines
    const headers = headerLine.split(',').map((value) => value.trim().toLowerCase())
    const required = ['room_number', 'floor_code', 'room_type_code']
    const missing = required.filter((header) => !headers.includes(header))

    if (missing.length) {
      throw new Error(`Missing CSV column(s): ${missing.join(', ')}`)
    }

    return dataLines.map((line, index) => {
      const values = line.split(',').map((value) => value.trim())
      const row = Object.fromEntries(headers.map((header, column) => [header, values[column] || '']))

      if (!row.room_number) {
        throw new Error(`CSV row ${index + 2} has no room number.`)
      }

      return {
        room_number: row.room_number,
        floor_code: row.floor_code,
        room_type_code: row.room_type_code,
        status: row.status || 'available',
      }
    })
  }

  const submitImport = (event) => {
    event.preventDefault()
    runAction('Room import completed atomically.', async () => {
      const rowsToImport = parseImportRows()
      await importRooms(hotel.id, rowsToImport)
      setImportText('room_number,floor_code,room_type_code,status\n')
    })
  }

  const requestArchive = (label, archiveAction) => {
    const reason = window.prompt(`Reason for archiving ${label}:`)
    if (!reason?.trim()) return
    runAction(`${label} archived.`, () => archiveAction(reason))
  }

  const requestStatus = (room, status) => {
    if (status === room.status) return
    const reason = window.prompt(
      `Reason for changing Room ${room.room_number} from ${room.status} to ${status}:`
    )
    if (!reason?.trim()) return

    runAction(`Room ${room.room_number} status updated.`, () =>
      transitionRoomStatus(hotel.id, room.id, status, reason)
    )
  }

  const openRoomEditor = (room) => {
    setRoomForm({
      id: room.id,
      room_number: room.room_number,
      floor_id: room.floor_id,
      room_type_id: room.room_type_id,
      status: room.status,
      metadata: room.metadata || {},
    })
    setOpenRoomMenuId('')
    setActiveTab('room-form')
  }

  const uploadRoomPhoto = async (room, file) => {
    if (!hotel?.id || !room?.id || !file) return
    if (!String(file.type || '').startsWith('image/')) {
      setError('Room photos must be JPG, PNG or WebP images.')
      return
    }

    setMediaBusyRoomId(room.id)
    setError('')
    setSuccess('')
    const previous = roomMedia[room.id]
    try {
      const upload = await uploadGuestGuideMediaFile({
        hotelId: hotel.id,
        file,
        scopeType: 'room',
        roomId: room.id,
        category: 'room',
      })
      await saveGuestGuideMedia(hotel.id, {
        scope_type: 'room',
        room_type_id: null,
        room_id: room.id,
        section_id: null,
        item_id: null,
        media_key: `room_cover_${room.id}`,
        category: 'room',
        object_path: upload.objectPath,
        mime_type: upload.mimeType,
        title: `Room ${room.room_number}`,
        caption: `${room.room_type_name || 'Hotel room'} photo`,
        alt_text: `Room ${room.room_number} at ${hotel.hotel_name || 'the hotel'}`,
        locale: null,
        sort_order: 0,
        is_active: true,
        metadata: {
          media_kind: 'image',
          managed_from: 'rooms_inventory',
        },
      })
      if (previous?.object_path && previous.object_path !== upload.objectPath) {
        await removeGuestGuideMediaFile(previous.object_path).catch(() => undefined)
      }
      setSuccess(`Room ${room.room_number} photo updated.`)
      setOpenRoomMenuId('')
      await loadWorkspace(false)
    } catch (uploadError) {
      setError(uploadError?.message || 'Unable to upload the room photo.')
    } finally {
      setMediaBusyRoomId('')
    }
  }


  if (loading) {
    return <div className="day13-page">Loading authoritative room inventory…</div>
  }

  return (
    <div className="day13-page rooms22-page">
      <div className="rooms22-pagehead">
        <div>
          <div className="day13-kicker rooms22-kicker">Inventory</div>
          <h1>Rooms</h1>
          <p>Visual room cards keep status, guest access and room actions readable on every screen size.</p>
        </div>
        <div className="day13-actions rooms22-head-actions">
          <button className="day13-button" type="button" onClick={() => loadWorkspace()}>
            Refresh
          </button>
          <button
            className="day13-button day13-button-primary"
            type="button"
            onClick={() => {
              setRoomForm(EMPTY_ROOM)
              setActiveTab('room-form')
            }}
          >
            Add room
          </button>
        </div>
      </div>

      {error && <div className="day13-alert">{error}</div>}
      {success && <div className="day13-success">{success}</div>}

      <div className="rooms22-controlbar">
        <div className="rooms22-search-wrap">
          <span aria-hidden="true">⌕</span>
          <input
            className="day13-search rooms22-search"
            placeholder="Search room, floor, type or status"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
        </div>
        <div className="rooms22-summary" aria-label="Room inventory summary">
          <span><b>{stats.total}</b> active</span>
          <span><b>{stats.available}</b> available</span>
          <span><b>{stats.cleaning}</b> cleaning</span>
          {stats.archived > 0 && <span><b>{stats.archived}</b> archived</span>}
        </div>
      </div>

      <div className="day13-tabs rooms22-tabs" aria-label="Room management sections">
        {[
          ['rooms', 'Rooms'],
          ['room-form', roomForm.id ? 'Edit room' : 'Add room'],
          ['floors', 'Floors'],
          ['types', 'Room types'],
          ['import', 'Bulk import'],
          ['events', 'Status history'],
        ].map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={`day13-tab ${activeTab === id ? 'day13-tab-active' : ''}`}
            onClick={() => setActiveTab(id)}
          >
            {label}
          </button>
        ))}
      </div>

      {activeTab === 'rooms' && (
        <section className="rooms22-section" aria-label="Room inventory cards">
          {filteredRooms.length === 0 ? (
            <div className="day13-panel day13-empty">No rooms match this search.</div>
          ) : (
            <div className="rooms22-grid">
              {filteredRooms.map((room) => {
                const roomType = workspace.room_types.find((item) => item.id === room.room_type_id)
                const commitments = room.commitments || {}
                const commitmentCount =
                  Number(commitments.active_stays || 0) +
                  Number(commitments.active_reservations || 0) +
                  Number(commitments.active_blocks || 0) +
                  Number(commitments.pending_housekeeping || 0)
                const media = roomMedia[room.id]
                const photoUrl = media?.url || hotelFallbackMedia
                const qrReady = qrRoomIds.has(room.id)
                const statusLabel = String(room.status || 'available').replaceAll('_', ' ')
                const rate = Number(roomType?.base_rate || 0)
                const guestName =
                  room.current_guest_name ||
                  room.active_guest_name ||
                  room.guest_name ||
                  room.guest_full_name ||
                  ''
                const stayCopy = guestName
                  ? guestName
                  : room.status === 'occupied'
                    ? 'Occupied · active stay'
                    : room.status === 'cleaning'
                      ? 'Housekeeping in progress'
                      : ['maintenance', 'out_of_order'].includes(room.status)
                        ? 'Temporarily unavailable'
                        : 'Ready for check-in'
                return (
                  <article className={`rooms22-card ${!room.is_active ? 'is-archived' : ''}`} key={room.id}>
                    <div
                      className={`rooms22-photo ${photoUrl ? 'has-photo' : 'is-empty'}`}
                      style={photoUrl ? { backgroundImage: `linear-gradient(180deg, rgba(0,0,0,.04), rgba(0,0,0,.68)), url("${photoUrl}")` } : undefined}
                    >
                      {!photoUrl && (
                        <label className="rooms22-empty-photo-action">
                          <span className="rooms22-camera" aria-hidden="true">▣</span>
                          <span>{mediaBusyRoomId === room.id ? 'Uploading…' : 'Add room photo'}</span>
                          <input
                            type="file"
                            accept="image/jpeg,image/png,image/webp"
                            disabled={!room.is_active || Boolean(mediaBusyRoomId)}
                            onChange={(event) => {
                              const file = event.target.files?.[0]
                              event.target.value = ''
                              if (file) void uploadRoomPhoto(room, file)
                            }}
                          />
                        </label>
                      )}
                      <span className={`rooms22-status rooms22-status-${room.status}`}>{statusLabel}</span>
                    </div>

                    <div className="rooms22-body">
                      <div className="rooms22-rhead">
                        <div>
                          <h3>Room {room.room_number}</h3>
                          <p>{room.room_type_name || 'Room'}{room.floor_name ? ` · ${room.floor_name}` : ''}</p>
                        </div>
                        <div className="rooms22-menu-wrap">
                          <button
                            type="button"
                            className="rooms22-more"
                            aria-label={`Manage Room ${room.room_number}`}
                            aria-expanded={openRoomMenuId === room.id}
                            onClick={() => setOpenRoomMenuId((current) => current === room.id ? '' : room.id)}
                          >
                            •••
                          </button>
                          {openRoomMenuId === room.id && (
                            <div className="rooms22-menu" role="menu">
                              <button type="button" role="menuitem" disabled={!room.is_active || saving} onClick={() => openRoomEditor(room)}>
                                Edit room
                              </button>
                              <label className={mediaBusyRoomId === room.id ? 'is-disabled' : ''}>
                                {mediaBusyRoomId === room.id ? 'Uploading…' : photoUrl ? 'Replace room photo' : 'Upload room photo'}
                                <input
                                  type="file"
                                  accept="image/jpeg,image/png,image/webp"
                                  disabled={!room.is_active || Boolean(mediaBusyRoomId)}
                                  onChange={(event) => {
                                    const file = event.target.files?.[0]
                                    event.target.value = ''
                                    if (file) void uploadRoomPhoto(room, file)
                                  }}
                                />
                              </label>
                              <div className="rooms22-menu-status">
                                <span>Room status</span>
                                <select
                                  value={room.status}
                                  disabled={!room.is_active || saving}
                                  onChange={(event) => {
                                    setOpenRoomMenuId('')
                                    requestStatus(room, event.target.value)
                                  }}
                                >
                                  <option value="available">Available</option>
                                  <option value="cleaning">Cleaning</option>
                                  <option value="maintenance">Maintenance</option>
                                  <option value="out_of_order">Out of order</option>
                                  {room.status === 'occupied' && <option value="occupied">Occupied</option>}
                                </select>
                              </div>
                              <button
                                type="button"
                                role="menuitem"
                                className="danger"
                                disabled={!room.is_active || saving}
                                onClick={() => {
                                  setOpenRoomMenuId('')
                                  requestArchive(`Room ${room.room_number}`, (reason) =>
                                    archiveRoom(hotel.id, room.id, reason)
                                  )
                                }}
                              >
                                Archive room
                              </button>
                            </div>
                          )}
                        </div>
                      </div>

                      <div className="rooms22-stay-copy">
                        <strong>{stayCopy}</strong>
                        <span>{room.is_active ? 'Live room inventory' : 'Archived room'}</span>
                        {commitmentCount > 0 && (
                          <span className="rooms22-commitments">
                            Stay {commitments.active_stays || 0} · Reservations {commitments.active_reservations || 0} · HK {commitments.pending_housekeeping || 0}
                          </span>
                        )}
                      </div>

                      <div className="rooms22-foot">
                        <b>{rate > 0 ? `₹${rate.toLocaleString('en-IN')}/night` : 'Rate not set'}</b>
                        <span className={`rooms22-qr-pill ${qrReady ? 'is-ready' : ''}`}>
                          {qrReady ? (room.status === 'occupied' ? 'QR active' : 'QR ready') : 'QR pending'}
                        </span>
                      </div>
                    </div>
                  </article>
                )
              })}
            </div>
          )}
        </section>
      )}

      {activeTab === 'room-form' && (
        <div className="day13-panel rooms22-form-panel">
          <div className="day13-panel-header">
            <div>
              <h2>{roomForm.id ? `Edit Room ${roomForm.room_number}` : 'Create room'}</h2>
              <div className="day13-muted day13-small">Room identity, type, status and guest-facing room photo.</div>
            </div>
          </div>
          {roomForm.id && (
            <div className="rooms22-form-photo">
              <div
                className={`rooms22-form-photo-preview ${roomMedia[roomForm.id]?.url || hotelFallbackMedia ? 'has-photo' : ''}`}
                style={(roomMedia[roomForm.id]?.url || hotelFallbackMedia) ? { backgroundImage: `linear-gradient(180deg, rgba(0,0,0,.05), rgba(0,0,0,.55)), url("${roomMedia[roomForm.id]?.url || hotelFallbackMedia}")` } : undefined}
              />
              <div>
                <strong>Room photo</strong>
                <p>Used on the room card and remains scoped to this hotel room.</p>
                <label className="day13-button rooms22-upload-button">
                  {mediaBusyRoomId === roomForm.id ? 'Uploading…' : roomMedia[roomForm.id]?.url ? 'Replace photo' : 'Upload photo'}
                  <input
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    disabled={Boolean(mediaBusyRoomId)}
                    onChange={(event) => {
                      const file = event.target.files?.[0]
                      event.target.value = ''
                      const room = rooms.find((item) => item.id === roomForm.id)
                      if (file && room) void uploadRoomPhoto(room, file)
                    }}
                  />
                </label>
              </div>
            </div>
          )}
          <form className="day13-panel-body day13-form" onSubmit={submitRoom}>
            <Field label="Room number">
              <input
                required
                value={roomForm.room_number}
                onChange={(event) =>
                  setRoomForm((current) => ({ ...current, room_number: event.target.value }))
                }
              />
            </Field>
            <Field label="Floor">
              <select
                required
                value={roomForm.floor_id}
                onChange={(event) =>
                  setRoomForm((current) => ({ ...current, floor_id: event.target.value }))
                }
              >
                <option value="">Select floor</option>
                {workspace.floors.filter((floor) => floor.is_active).map((floor) => (
                  <option key={floor.id} value={floor.id}>{floor.name} ({floor.code})</option>
                ))}
              </select>
            </Field>
            <Field label="Room type">
              <select
                required
                value={roomForm.room_type_id}
                onChange={(event) =>
                  setRoomForm((current) => ({ ...current, room_type_id: event.target.value }))
                }
              >
                <option value="">Select type</option>
                {workspace.room_types.filter((roomType) => roomType.is_active).map((roomType) => (
                  <option key={roomType.id} value={roomType.id}>{roomType.name} ({roomType.code})</option>
                ))}
              </select>
            </Field>
            <Field label="Initial status">
              <select
                value={roomForm.status}
                disabled={roomForm.status === 'occupied'}
                onChange={(event) =>
                  setRoomForm((current) => ({ ...current, status: event.target.value }))
                }
              >
                <option value="available">Available</option>
                <option value="cleaning">Cleaning</option>
                <option value="maintenance">Maintenance</option>
                <option value="out_of_order">Out of order</option>
                {roomForm.status === 'occupied' && <option value="occupied">Occupied (managed by stay)</option>}
              </select>
            </Field>
            <div className="day13-field day13-field-full day13-inline-actions">
              <button className="day13-button day13-button-primary" disabled={saving}>
                {saving ? 'Saving…' : roomForm.id ? 'Save room' : 'Create room'}
              </button>
              <button
                type="button"
                className="day13-button"
                onClick={() => {
                  setRoomForm(EMPTY_ROOM)
                  setActiveTab('rooms')
                }}
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      )}

      {activeTab === 'floors' && (
        <div className="day13-grid">
          <div className="day13-panel">
            <div className="day13-panel-header">
              <h2>{floorForm.id ? 'Edit floor' : 'Create floor'}</h2>
            </div>
            <form className="day13-panel-body day13-form" onSubmit={submitFloor}>
              <Field label="Code">
                <input
                  required
                  value={floorForm.code}
                  onChange={(event) =>
                    setFloorForm((current) => ({ ...current, code: event.target.value }))
                  }
                />
              </Field>
              <Field label="Name">
                <input
                  required
                  value={floorForm.name}
                  onChange={(event) =>
                    setFloorForm((current) => ({ ...current, name: event.target.value }))
                  }
                />
              </Field>
              <Field label="Floor number">
                <input
                  type="number"
                  value={floorForm.floor_number ?? ''}
                  onChange={(event) =>
                    setFloorForm((current) => ({
                      ...current,
                      floor_number: event.target.value,
                    }))
                  }
                />
              </Field>
              <Field label="Sort order">
                <input
                  type="number"
                  value={floorForm.sort_order}
                  onChange={(event) =>
                    setFloorForm((current) => ({
                      ...current,
                      sort_order: event.target.value,
                    }))
                  }
                />
              </Field>
              <Field label="Description" wide>
                <textarea
                  value={floorForm.description || ''}
                  onChange={(event) =>
                    setFloorForm((current) => ({
                      ...current,
                      description: event.target.value,
                    }))
                  }
                />
              </Field>
              <div className="day13-field day13-field-full day13-inline-actions">
                <button className="day13-button day13-button-primary" disabled={saving}>
                  Save floor
                </button>
                <button
                  type="button"
                  className="day13-button"
                  onClick={() => setFloorForm(EMPTY_FLOOR)}
                >
                  Clear
                </button>
              </div>
            </form>
          </div>
          <div className="day13-panel">
            <div className="day13-panel-header">
              <h2>Configured floors</h2>
            </div>
            <div className="day13-panel-body day13-grid">
              {workspace.floors.map((floor) => (
                <div className="day13-card" key={floor.id}>
                  <h3>{floor.name}</h3>
                  <div className="day13-muted">
                    {floor.code} · Floor {floor.floor_number ?? '—'}
                  </div>
                  <div className="day13-inline-actions" style={{ marginTop: 12 }}>
                    <button
                      className="day13-button"
                      type="button"
                      disabled={!floor.is_active}
                      onClick={() => setFloorForm({ ...EMPTY_FLOOR, ...floor })}
                    >
                      Edit
                    </button>
                    <button
                      className="day13-button day13-button-danger"
                      type="button"
                      disabled={!floor.is_active}
                      onClick={() =>
                        requestArchive(floor.name, (reason) =>
                          archiveFloor(hotel.id, floor.id, reason)
                        )
                      }
                    >
                      Archive
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {activeTab === 'types' && (
        <div className="day13-grid">
          <div className="day13-panel">
            <div className="day13-panel-header">
              <h2>{typeForm.id ? 'Edit room type' : 'Create room type'}</h2>
            </div>
            <form className="day13-panel-body day13-form" onSubmit={submitType}>
              {[
                ['code', 'Code', 'text'],
                ['name', 'Name', 'text'],
                ['base_occupancy', 'Base occupancy', 'number'],
                ['max_adults', 'Max adults', 'number'],
                ['max_children', 'Max children', 'number'],
                ['max_occupancy', 'Max occupancy', 'number'],
                ['base_rate', 'Base rate', 'number'],
                ['extra_adult_rate', 'Extra adult', 'number'],
                ['extra_child_rate', 'Extra child', 'number'],
                ['sort_order', 'Sort order', 'number'],
              ].map(([key, label, type]) => (
                <Field key={key} label={label}>
                  <input
                    required={['code', 'name'].includes(key)}
                    type={type}
                    value={typeForm[key]}
                    onChange={(event) =>
                      setTypeForm((current) => ({ ...current, [key]: event.target.value }))
                    }
                  />
                </Field>
              ))}
              <Field label="Description" wide>
                <textarea
                  value={typeForm.description || ''}
                  onChange={(event) =>
                    setTypeForm((current) => ({
                      ...current,
                      description: event.target.value,
                    }))
                  }
                />
              </Field>
              <div className="day13-field day13-field-full day13-inline-actions">
                <button className="day13-button day13-button-primary" disabled={saving}>
                  Save room type
                </button>
                <button
                  type="button"
                  className="day13-button"
                  onClick={() => setTypeForm(EMPTY_TYPE)}
                >
                  Clear
                </button>
              </div>
            </form>
          </div>
          <div className="day13-panel">
            <div className="day13-panel-header">
              <h2>Configured room types</h2>
            </div>
            <div className="day13-panel-body day13-grid">
              {workspace.room_types.map((roomType) => (
                <div className="day13-card" key={roomType.id}>
                  <h3>{roomType.name}</h3>
                  <div className="day13-muted">
                    {roomType.code} · ₹{Number(roomType.base_rate || 0).toLocaleString('en-IN')}
                  </div>
                  <div className="day13-small" style={{ marginTop: 8 }}>
                    {roomType.max_adults} adults · {roomType.max_children} children ·{' '}
                    {roomType.max_occupancy} total
                  </div>
                  <div className="day13-inline-actions" style={{ marginTop: 12 }}>
                    <button
                      className="day13-button"
                      type="button"
                      disabled={!roomType.is_active}
                      onClick={() => setTypeForm({ ...EMPTY_TYPE, ...roomType })}
                    >
                      Edit
                    </button>
                    <button
                      className="day13-button day13-button-danger"
                      type="button"
                      disabled={!roomType.is_active}
                      onClick={() =>
                        requestArchive(roomType.name, (reason) =>
                          archiveRoomType(hotel.id, roomType.id, reason)
                        )
                      }
                    >
                      Archive
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {activeTab === 'import' && (
        <div className="day13-panel">
          <div className="day13-panel-header">
            <div>
              <h2>Atomic room import</h2>
              <div className="day13-muted day13-small">
                Maximum 100 rooms. Any invalid row rolls back the complete batch.
              </div>
            </div>
          </div>
          <form className="day13-panel-body day13-form" onSubmit={submitImport}>
            <Field label="CSV rows" full>
              <textarea
                style={{ minHeight: 240, fontFamily: 'monospace' }}
                value={importText}
                onChange={(event) => setImportText(event.target.value)}
              />
            </Field>
            <div className="day13-field day13-field-full">
              <button className="day13-button day13-button-primary" disabled={saving}>
                Import rooms atomically
              </button>
            </div>
          </form>
          <div className="day13-table-wrap">
            <table className="day13-table">
              <thead>
                <tr>
                  <th>Batch</th>
                  <th>Source</th>
                  <th>Requested</th>
                  <th>Inserted</th>
                  <th>Status</th>
                  <th>Created</th>
                </tr>
              </thead>
              <tbody>
                {workspace.imports.map((batch) => (
                  <tr key={batch.id}>
                    <td>{batch.id.slice(0, 8)}</td>
                    <td>{batch.source_name || '—'}</td>
                    <td>{batch.requested_rows}</td>
                    <td>{batch.inserted_rows}</td>
                    <td>{batch.status}</td>
                    <td>{formatDate(batch.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'events' && (
        <div className="day13-panel">
          <div className="day13-panel-header">
            <h2>Immutable room-status history</h2>
          </div>
          <div className="day13-table-wrap">
            <table className="day13-table">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Room</th>
                  <th>Transition</th>
                  <th>Source</th>
                  <th>Reason</th>
                </tr>
              </thead>
              <tbody>
                {workspace.status_events.map((event) => {
                  const room = rooms.find((item) => item.id === event.room_id)
                  return (
                    <tr key={event.id}>
                      <td>{formatDate(event.occurred_at)}</td>
                      <td>{room?.room_number || event.room_id.slice(0, 8)}</td>
                      <td>
                        {event.previous_status || '—'} → {event.new_status}
                      </td>
                      <td>{event.source || '—'}</td>
                      <td>{event.reason || '—'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}

function Field({ label, children, wide = false, full = false }) {
  return (
    <div
      className={`day13-field ${wide ? 'day13-field-wide' : ''} ${
        full ? 'day13-field-full' : ''
      }`}
    >
      <label>{label}</label>
      {children}
    </div>
  )
}


function formatDate(value) {
  return value ? new Date(value).toLocaleString('en-IN') : '—'
}
