import { useEffect, useState } from 'react'
import LocalQrCode from '../../components/qr/LocalQrCode'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  getGuestAccessLinks,
  revokeGuestAccessToken,
  rotateGuestAccessToken,
} from '../../lib/guestPortal'
import { downloadLocalQrSvg } from '../../lib/localQr'
import './QRGenerator.css'

export default function QRGenerator() {
  const [links, setLinks] = useState([])
  const [loading, setLoading] = useState(true)
  const [currentHotel, setCurrentHotel] = useState(null)
  const [busySessionId, setBusySessionId] = useState(null)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    initPage()
  }, [])

  async function initPage() {
    const hotel = await getCurrentHotel()

    if (!hotel) {
      setError('No authorized hotel is selected.')
      setLoading(false)
      return
    }

    setCurrentHotel(hotel)
    await loadLinks(hotel.id)
  }

  async function loadLinks(hotelId = currentHotel?.id) {
    if (!hotelId) return

    setLoading(true)
    setError('')

    try {
      const data = await getGuestAccessLinks(hotelId)
      setLinks(data)
    } catch (loadError) {
      console.error('Secure guest link load error:', loadError)
      setError(loadError.message || 'Unable to load secure guest links.')
    } finally {
      setLoading(false)
    }
  }

  function absoluteUrl(path) {
    if (!path) return ''

    try {
      return new URL(path, window.location.origin).toString()
    } catch {
      return ''
    }
  }

  async function copyLink(path, label) {
    const url = absoluteUrl(path)
    if (!url) return

    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(url)
      } else {
        const input = document.createElement('textarea')
        input.value = url
        input.setAttribute('readonly', '')
        input.style.position = 'fixed'
        input.style.opacity = '0'
        document.body.appendChild(input)
        input.select()
        document.execCommand('copy')
        input.remove()
      }

      setError('')
      setNotice(`${label} copied.`)
    } catch (copyError) {
      console.error('Clipboard error:', copyError)
      setError(`Unable to copy the ${label.toLowerCase()}.`)
    }
  }

  function downloadQr(link, path, purpose) {
    const url = absoluteUrl(path)
    if (!url) return

    try {
      const room = safeFilenamePart(link.room_number || 'room')
      const hotel = safeFilenamePart(currentHotel?.slug || currentHotel?.hotel_name || 'hotel')
      downloadLocalQrSvg({
        value: url,
        filename: `stayqr-${hotel}-room-${room}-${purpose}.svg`,
        label: `StayQR ${purpose} QR for Room ${link.room_number}`,
      })
      setError('')
      setNotice(`${purpose === 'guest-guide' ? 'Guest guide' : 'Food menu'} QR downloaded.`)
    } catch (downloadError) {
      console.error('QR download error:', downloadError)
      setError('Unable to download the QR code.')
    }
  }

  async function activateOrRotateLink(link, mode = 'rotate') {
    if (!currentHotel?.id || !link?.guest_session_id || busySessionId) return

    const isActivation = mode === 'activate'
    const confirmed = window.confirm(
      isActivation
        ? `Activate a new secure guest link for Room ${link.room_number}?`
        : `Rotate guest access for Room ${link.room_number}? The previous link will stop working immediately.`
    )

    if (!confirmed) return

    setBusySessionId(link.guest_session_id)
    setNotice('')
    setError('')

    try {
      await rotateGuestAccessToken({
        hotelId: currentHotel.id,
        guestSessionId: link.guest_session_id,
        reason: isActivation
          ? 'Activated from Secure Guest Access screen'
          : 'Rotated from Secure Guest Access screen',
      })
      setNotice(
        isActivation
          ? `New secure guest access activated for Room ${link.room_number}.`
          : `Guest access rotated for Room ${link.room_number}.`
      )
      await loadLinks(currentHotel.id)
    } catch (rotateError) {
      console.error('Guest access rotation error:', rotateError)
      setError(
        rotateError.message ||
          (isActivation
            ? 'Unable to activate guest access.'
            : 'Unable to rotate guest access.')
      )
    } finally {
      setBusySessionId(null)
    }
  }

  async function revokeLink(link) {
    if (!currentHotel?.id || !link?.guest_session_id || busySessionId) return

    const confirmed = window.confirm(
      `Revoke guest access for Room ${link.room_number}? The guest guide and food menu will become unavailable immediately.`
    )

    if (!confirmed) return

    setBusySessionId(link.guest_session_id)
    setNotice('')
    setError('')

    try {
      await revokeGuestAccessToken({
        hotelId: currentHotel.id,
        guestSessionId: link.guest_session_id,
        reason: 'Revoked from Secure Guest Access screen',
      })
      setNotice(`Guest access revoked for Room ${link.room_number}.`)
      await loadLinks(currentHotel.id)
    } catch (revokeError) {
      console.error('Guest access revocation error:', revokeError)
      setError(revokeError.message || 'Unable to revoke guest access.')
    } finally {
      setBusySessionId(null)
    }
  }

  if (loading) {
    return <div className="secure-qr-page secure-qr-loading">Loading secure guest access…</div>
  }

  return (
    <div className="secure-qr-page">
      <div className="secure-qr-header">
        <div>
          <p className="secure-qr-eyebrow">SIGNED · ROTATING · REVOCABLE</p>
          <h1>Secure Guest Access</h1>
          <p className="secure-qr-hotel">{currentHotel?.hotel_name || 'Selected hotel'}</p>
        </div>

        <button type="button" className="secure-qr-button secondary" onClick={() => loadLinks()}>
          Refresh
        </button>
      </div>

      <p className="secure-qr-description">
        Every QR is generated locally in this browser and stays on StayQR. Guest links are bound to an active stay; a hotel slug or room number alone cannot reveal guest data. Checkout, expiry, rotation and revocation invalidate access.
      </p>

      {notice && <div className="secure-qr-alert success" role="status">{notice}</div>}
      {error && <div className="secure-qr-alert error" role="alert">{error}</div>}

      <div className="secure-qr-grid">
        {links.map((link) => (
          <SecureRoomAccessCard
            key={link.room_id}
            link={link}
            busy={busySessionId === link.guest_session_id}
            absoluteUrl={absoluteUrl}
            onCopy={copyLink}
            onDownload={downloadQr}
            onActivate={(selectedLink) => activateOrRotateLink(selectedLink, 'activate')}
            onRotate={(selectedLink) => activateOrRotateLink(selectedLink, 'rotate')}
            onRevoke={revokeLink}
          />
        ))}
      </div>

      {links.length === 0 && (
        <div className="secure-qr-empty">No rooms are available for the selected hotel.</div>
      )}
    </div>
  )
}

function SecureRoomAccessCard({
  link,
  busy,
  absoluteUrl,
  onCopy,
  onDownload,
  onActivate,
  onRotate,
  onRevoke,
}) {
  const stayActive = Boolean(link.stay_active ?? link.active)
  const accessActive = Boolean(
    link.access_active && link.guest_path && link.food_path
  )
  const guestUrl = absoluteUrl(link.guest_path)
  const foodUrl = absoluteUrl(link.food_path)
  const status = getAccessStatus({ ...link, stay_active: stayActive, access_active: accessActive })

  return (
    <article className="secure-qr-card">
      <div className="secure-qr-card-top">
        <div>
          <h2>Room {link.room_number}</h2>
          <p>{link.room_type || 'Room'}</p>
        </div>
        <span className={`secure-qr-pill ${status.tone}`}>{status.label}</span>
      </div>

      {!stayActive ? (
        <p className="secure-qr-inactive-copy">
          A signed guest link is created only after a guest has an active checked-in stay.
        </p>
      ) : (
        <>
          <div className="secure-qr-guest-box">
            <strong>{link.guest_name || 'Current guest'}</strong>
            <span>Stay valid until {formatDateTime(link.expires_at)}</span>
            {link.token_issued_at && <span>Link issued {formatDateTime(link.token_issued_at)}</span>}
          </div>

          {accessActive ? (
            <>
              <div className="secure-qr-pair-grid">
                <QrAccessPanel
                  title="Guest guide"
                  url={guestUrl}
                  roomNumber={link.room_number}
                  onCopy={() => onCopy(link.guest_path, 'Guest guide link')}
                  onDownload={() => onDownload(link, link.guest_path, 'guest-guide')}
                />
                <QrAccessPanel
                  title="Food menu"
                  url={foodUrl}
                  roomNumber={link.room_number}
                  onCopy={() => onCopy(link.food_path, 'Food menu link')}
                  onDownload={() => onDownload(link, link.food_path, 'food-menu')}
                />
              </div>

              <div className="secure-qr-token-meta">
                <span>Token valid until {formatDateTime(link.token_expires_at)}</span>
                <span>Used {Number(link.token_use_count || 0)} time(s)</span>
                {link.token_last_used_at && <span>Last used {formatDateTime(link.token_last_used_at)}</span>}
              </div>

              <div className="secure-qr-actions">
                <button type="button" className="secure-qr-button secondary" disabled={busy} onClick={() => onRotate(link)}>
                  {busy ? 'Working…' : 'Rotate both links'}
                </button>
                <button type="button" className="secure-qr-button danger" disabled={busy} onClick={() => onRevoke(link)}>
                  Revoke access
                </button>
              </div>
            </>
          ) : (
            <div className="secure-qr-disabled-box">
              <h3>{status.label}</h3>
              <p>{getInactiveAccessMessage(link)}</p>
              {link.revocation_reason && <p className="secure-qr-reason">Reason: {link.revocation_reason}</p>}
              <button type="button" className="secure-qr-button primary" disabled={busy} onClick={() => onActivate(link)}>
                {busy ? 'Activating…' : 'Activate new secure link'}
              </button>
            </div>
          )}
        </>
      )}
    </article>
  )
}

function QrAccessPanel({ title, url, roomNumber, onCopy, onDownload }) {
  return (
    <section className="secure-qr-panel">
      <div className="secure-qr-panel-heading">
        <h3>{title}</h3>
        <span>Room {roomNumber}</span>
      </div>
      <LocalQrCode value={url} label={`StayQR ${title} QR for Room ${roomNumber}`} />
      <div className="secure-qr-url" title={url}>{url}</div>
      <div className="secure-qr-panel-actions">
        <button type="button" className="secure-qr-button primary" onClick={onCopy}>Copy link</button>
        <button type="button" className="secure-qr-button secondary" onClick={onDownload}>Download SVG</button>
      </div>
    </section>
  )
}

function getAccessStatus(link) {
  if (!link.stay_active) return { label: 'No active stay', tone: 'neutral' }
  if (link.access_active) return { label: 'Access active', tone: 'active' }

  const labels = {
    revoked: 'Access revoked',
    expired: 'Access expired',
    not_issued: 'Access not issued',
  }

  return {
    label: labels[link.access_status] || 'Access unavailable',
    tone: link.access_status === 'revoked' ? 'revoked' : 'warning',
  }
}

function getInactiveAccessMessage(link) {
  if (link.access_status === 'revoked') {
    return 'The previous guest and food links no longer work. Access remains revoked until staff explicitly activates a new signed link.'
  }

  if (link.access_status === 'expired') {
    return 'The previous signed link has expired. Confirm the stay details before activating a replacement.'
  }

  return 'No signed guest link is currently active for this stay.'
}

function safeFilenamePart(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'stayqr'
}

function formatDateTime(value) {
  if (!value) return 'stay checkout'

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return 'stay checkout'

  return date.toLocaleString('en-IN')
}
