import { useEffect, useState } from 'react'
import LocalQrCode from '../../components/qr/LocalQrCode'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  getPermanentRoomQrLinks,
  regeneratePermanentRoomQr,
  revokeGuestAccessToken,
  rotateGuestAccessToken,
} from '../../lib/guestPortal'
import { downloadLocalQrSvg } from '../../lib/localQr'
import './QRGenerator.css'

export default function QRGenerator() {
  const [rooms, setRooms] = useState([])
  const [loading, setLoading] = useState(true)
  const [currentHotel, setCurrentHotel] = useState(null)
  const [busyId, setBusyId] = useState(null)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')

  useEffect(() => { void initPage() }, [])

  async function initPage() {
    const hotel = await getCurrentHotel()
    if (!hotel) {
      setError('No authorized hotel is selected.')
      setLoading(false)
      return
    }
    setCurrentHotel(hotel)
    await loadRooms(hotel.id)
  }

  async function loadRooms(hotelId = currentHotel?.id) {
    if (!hotelId) return
    setLoading(true)
    setError('')
    try {
      setRooms(await getPermanentRoomQrLinks(hotelId))
    } catch (loadError) {
      console.error('Room QR load error:', loadError)
      setError(loadError.message || 'Unable to load room QR guides.')
    } finally {
      setLoading(false)
    }
  }

  function absoluteUrl(path) {
    if (!path) return ''
    try { return new URL(path, window.location.origin).toString() } catch { return '' }
  }

  async function copyPermanentLink(room) {
    const url = absoluteUrl(room.permanent_path)
    if (!url) return
    try {
      await navigator.clipboard.writeText(url)
      setNotice(`Room ${room.room_number} permanent link copied.`)
      setError('')
    } catch (copyError) {
      console.error('Clipboard error:', copyError)
      setError('Unable to copy the permanent room link.')
    }
  }

  function downloadPermanentQr(room) {
    const url = absoluteUrl(room.permanent_path)
    if (!url) return
    try {
      const hotel = safeFilenamePart(currentHotel?.slug || currentHotel?.hotel_name || 'hotel')
      const roomNumber = safeFilenamePart(room.room_number || 'room')
      downloadLocalQrSvg({
        value: url,
        filename: `stayqr-${hotel}-room-${roomNumber}-permanent.svg`,
        label: `StayQR permanent room QR for Room ${room.room_number}`,
      })
      setNotice(`Room ${room.room_number} permanent QR downloaded.`)
      setError('')
    } catch (downloadError) {
      console.error('QR download error:', downloadError)
      setError('Unable to download the permanent room QR.')
    }
  }

  async function rotateStayAccess(room) {
    if (!currentHotel?.id || !room?.guest_session_id || busyId) return
    const mode = room.access_active ? 'rotate' : 'restore'
    const confirmed = window.confirm(
      mode === 'restore'
        ? `Restore guest-guide access for the current stay in Room ${room.room_number}?`
        : `Rotate the current stay access for Room ${room.room_number}? Any previously copied direct guest link will stop working, while the permanent room QR will continue to work.`
    )
    if (!confirmed) return

    setBusyId(room.guest_session_id)
    setNotice('')
    setError('')
    try {
      await rotateGuestAccessToken({
        hotelId: currentHotel.id,
        guestSessionId: room.guest_session_id,
        reason: mode === 'restore' ? 'Guest access restored from Room QR Guides' : 'Guest access rotated from Room QR Guides',
      })
      setNotice(`${mode === 'restore' ? 'Guest access restored' : 'Guest access rotated'} for Room ${room.room_number}.`)
      await loadRooms(currentHotel.id)
    } catch (actionError) {
      console.error('Guest access rotation error:', actionError)
      setError(actionError.message || 'Unable to update guest access.')
    } finally {
      setBusyId(null)
    }
  }

  async function emergencyRevoke(room) {
    if (!currentHotel?.id || !room?.guest_session_id || busyId) return
    if (!window.confirm(`Emergency-revoke guest-guide access for Room ${room.room_number}? The permanent QR will remain installed but will not open the guide until access is restored by authorized staff.`)) return

    setBusyId(room.guest_session_id)
    setNotice('')
    setError('')
    try {
      await revokeGuestAccessToken({
        hotelId: currentHotel.id,
        guestSessionId: room.guest_session_id,
        reason: 'Emergency revoke from Room QR Guides',
      })
      setNotice(`Guest access revoked for Room ${room.room_number}.`)
      await loadRooms(currentHotel.id)
    } catch (actionError) {
      console.error('Guest access revoke error:', actionError)
      setError(actionError.message || 'Unable to revoke guest access.')
    } finally {
      setBusyId(null)
    }
  }

  async function regenerateQr(room) {
    if (!currentHotel?.id || !room?.room_id || busyId) return
    if (!window.confirm(`Regenerate the permanent QR for Room ${room.room_number}? Only use this if the physical QR is lost, copied or compromised. The old QR will stop working immediately and the hotel must replace the printed card/standee.`)) return

    setBusyId(room.room_id)
    setNotice('')
    setError('')
    try {
      await regeneratePermanentRoomQr({ hotelId: currentHotel.id, roomId: room.room_id })
      setNotice(`Permanent QR regenerated for Room ${room.room_number}. Replace the old printed QR.`)
      await loadRooms(currentHotel.id)
    } catch (actionError) {
      console.error('Permanent QR regeneration error:', actionError)
      setError(actionError.message || 'Unable to regenerate the permanent room QR.')
    } finally {
      setBusyId(null)
    }
  }

  if (loading) return <div className="secure-qr-page secure-qr-loading">Loading room QR guides…</div>

  return (
    <div className="secure-qr-page">
      <div className="secure-qr-header">
        <div>
          <p className="secure-qr-eyebrow">PRINT ONCE · AUTO-ACTIVATE EVERY STAY</p>
          <h1>Room QR Guides</h1>
          <p className="secure-qr-hotel">{currentHotel?.hotel_name || 'Selected hotel'}</p>
        </div>
        <button type="button" className="secure-qr-button secondary" onClick={() => loadRooms()}>Refresh</button>
      </div>

      <p className="secure-qr-description">
        Each room has one permanent StayQR code for the key-card sleeve and in-room standee. Check-in automatically activates the personalized guide; checkout, expiry or room move automatically ends access. Guests never need a PIN or login.
      </p>

      <div className="secure-qr-launch-note">
        <strong>Zero front-desk QR work</strong>
        <span>Print each room QR once. StayQR securely maps it to the current checked-in stay and keeps the signed guest-access lifecycle underneath.</span>
      </div>

      {notice && <div className="secure-qr-alert success" role="status">{notice}</div>}
      {error && <div className="secure-qr-alert error" role="alert">{error}</div>}

      <div className="secure-qr-grid">
        {rooms.map((room) => (
          <RoomQrCard
            key={room.room_id}
            room={room}
            busy={busyId === room.room_id || busyId === room.guest_session_id}
            url={absoluteUrl(room.permanent_path)}
            onCopy={() => copyPermanentLink(room)}
            onDownload={() => downloadPermanentQr(room)}
            onRotate={() => rotateStayAccess(room)}
            onRevoke={() => emergencyRevoke(room)}
            onRegenerate={() => regenerateQr(room)}
          />
        ))}
      </div>

      {rooms.length === 0 && <div className="secure-qr-empty">No active rooms are available for the selected hotel.</div>}
    </div>
  )
}

function RoomQrCard({ room, busy, url, onCopy, onDownload, onRotate, onRevoke, onRegenerate }) {
  const status = room.stay_active
    ? room.access_active
      ? { label: 'Guide active', tone: 'active' }
      : { label: 'Access paused', tone: 'warning' }
    : { label: 'Vacant · QR ready', tone: 'neutral' }

  return (
    <article className="secure-qr-card secure-qr-card--launch">
      <div className="secure-qr-card-top">
        <div><h2>Room {room.room_number}</h2><p>{room.room_type || 'Room'}</p></div>
        <span className={`secure-qr-pill ${status.tone}`}>{status.label}</span>
      </div>

      <section className="secure-qr-permanent secure-qr-permanent--launch">
        <div className="secure-qr-permanent-grid">
          <LocalQrCode value={url} label={`Permanent StayQR room QR for Room ${room.room_number}`} />
          <div className="secure-qr-permanent-actions">
            <span>PERMANENT ROOM QR</span>
            <strong>Use this same QR for every stay</strong>
            <p>Place it on the room standee and key-card sleeve. It never contains the guest name or stay token.</p>
            <div className="secure-qr-inline-actions">
              <button type="button" className="secure-qr-button secondary" onClick={onCopy}>Copy link</button>
              <button type="button" className="secure-qr-button primary" onClick={onDownload}>Download QR</button>
            </div>
          </div>
        </div>
      </section>

      <div className="secure-qr-stay-summary">
        {room.stay_active ? (
          <>
            <div><span>CURRENT STAY</span><strong>{room.guest_name || 'Checked-in guest'}{Number(room.occupant_count || 1) > 1 ? ` + ${Number(room.occupant_count) - 1}` : ''}</strong></div>
            <div><span>ACCESS</span><strong>{room.access_active ? 'Automatically active' : 'Paused by security control'}</strong></div>
            <div><span>VALID UNTIL</span><strong>{formatDateTime(room.stay_expires_at)}</strong></div>
          </>
        ) : (
          <div className="secure-qr-vacant"><span>ROOM STATUS</span><strong>Ready for the next check-in</strong><small>The guide activates automatically when reception checks a guest into this room.</small></div>
        )}
      </div>

      <details className="secure-qr-advanced">
        <summary>Advanced security controls</summary>
        <p>These actions are exceptional. Normal check-in, extension, room move and checkout require no QR management.</p>
        <div className="secure-qr-actions">
          {room.stay_active && (
            <button type="button" className="secure-qr-button secondary" disabled={busy} onClick={onRotate}>
              {busy ? 'Working…' : room.access_active ? 'Rotate active stay access' : 'Restore guest access'}
            </button>
          )}
          {room.stay_active && room.access_active && (
            <button type="button" className="secure-qr-button danger" disabled={busy} onClick={onRevoke}>Emergency revoke</button>
          )}
          <button type="button" className="secure-qr-button danger ghost" disabled={busy} onClick={onRegenerate}>Regenerate permanent QR</button>
        </div>
      </details>
    </article>
  )
}

function safeFilenamePart(value) {
  return String(value || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'stayqr'
}

function formatDateTime(value) {
  if (!value) return 'Checkout time'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Checkout time' : date.toLocaleString('en-IN')
}
