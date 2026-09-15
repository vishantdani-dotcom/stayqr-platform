import { useCallback, useEffect, useMemo, useState } from 'react'
import { getRoomQrPublicContext, resolvePermanentRoomQr } from '../../lib/guestPortal'
import './RoomAccess.css'

export default function RoomAccess() {
  const publicCode = useMemo(() => {
    const parts = window.location.pathname.split('/').filter(Boolean)
    return parts[0] === 'room' ? parts[1] || '' : ''
  }, [])

  const [context, setContext] = useState(null)
  const [loading, setLoading] = useState(true)
  const [opening, setOpening] = useState(false)
  const [error, setError] = useState('')

  const openCurrentStay = useCallback(async () => {
    if (!/^[0-9a-f-]{36}$/i.test(publicCode)) {
      setError('This room QR is invalid. Please contact reception.')
      setLoading(false)
      return
    }

    setOpening(true)
    setError('')

    try {
      const data = await resolvePermanentRoomQr({ publicCode })
      if (!data?.ok || !data?.guest_path) {
        setError(data?.error || 'Guest access is currently inactive. Please contact reception.')
        return
      }

      window.location.replace(data.guest_path)
    } catch (resolveError) {
      console.error('StayQR room QR resolution failed:', resolveError)
      setError('Guest access is currently unavailable. Please contact reception.')
    } finally {
      setOpening(false)
      setLoading(false)
    }
  }, [publicCode])

  useEffect(() => {
    let active = true

    async function load() {
      try {
        if (!/^[0-9a-f-]{36}$/i.test(publicCode)) {
          throw new Error('This room QR is invalid. Please contact reception.')
        }

        const data = await getRoomQrPublicContext(publicCode)
        if (!active) return
        setContext(data)

        if (!data?.valid) {
          setError('This room QR is unavailable. Please contact reception.')
          setLoading(false)
          return
        }

        await openCurrentStay()
      } catch (loadError) {
        if (active) {
          console.error('StayQR room guide loading failed:', loadError)
      setError('This room QR is unavailable. Please contact reception.')
          setLoading(false)
        }
      }
    }

    void load()
    return () => { active = false }
  }, [openCurrentStay, publicCode])

  return (
    <main className="room-entry-shell">
      <section className="room-entry-card">
        <div className="room-entry-brand">StayQR</div>
        <p className="room-entry-kicker">SMART ROOM GUIDE</p>
        <h1>
          {loading
            ? 'Connecting your stay…'
            : context?.valid
              ? `Room ${context.room_number}`
              : 'Room guide'}
        </h1>
        {context?.valid && <p className="room-entry-hotel">{context.hotel_name}</p>}

        {!error && (
          <div className="room-entry-auto-status" role="status" aria-live="polite">
            <span className="room-entry-auto-dot" aria-hidden="true" />
            <div>
              <strong>{opening || loading ? 'Opening your personalized guest guide' : 'Guest guide ready'}</strong>
              <p>StayQR automatically connects this permanent room QR to the current checked-in stay.</p>
            </div>
          </div>
        )}

        {error && (
          <div className="room-entry-error" role="alert">
            <strong>Guest access is not active right now.</strong>
            <span>{error}</span>
          </div>
        )}

        {context?.valid && error && (
          <button type="button" className="room-entry-retry" disabled={opening} onClick={openCurrentStay}>
            {opening ? 'Checking…' : 'Try again'}
          </button>
        )}

        <small>
          No PIN or login is required. Access activates at check-in and stops automatically after checkout, expiry, room move or an emergency revoke.
        </small>
      </section>
    </main>
  )
}
