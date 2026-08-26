import { useEffect, useMemo, useState } from 'react'
import { getRoomQrPublicContext, resolvePermanentRoomQr } from '../../lib/guestPortal'
import './RoomAccess.css'

export default function RoomAccess() {
  const publicCode = useMemo(() => {
    const parts = window.location.pathname.split('/').filter(Boolean)
    return parts[0] === 'room' ? parts[1] || '' : ''
  }, [])
  const [context, setContext] = useState(null)
  const [pin, setPin] = useState('')
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    async function load() {
      try {
        if (!/^[0-9a-f-]{36}$/i.test(publicCode)) throw new Error('This room QR is invalid.')
        const data = await getRoomQrPublicContext(publicCode)
        if (!active) return
        setContext(data)
        if (!data?.valid) setError('This room QR is unavailable. Please contact reception.')
      } catch (loadError) {
        if (active) setError(loadError?.message || 'This room QR is unavailable.')
      } finally {
        if (active) setLoading(false)
      }
    }
    void load()
    return () => { active = false }
  }, [publicCode])

  async function submit(event) {
    event.preventDefault()
    if (!/^\d{6}$/.test(pin)) {
      setError('Enter the 6-digit stay PIN provided by reception.')
      return
    }

    setSubmitting(true)
    setError('')
    try {
      const data = await resolvePermanentRoomQr({ publicCode, pin })
      if (!data?.ok || !data?.guest_path) {
        setError(data?.error || 'Room access could not be verified.')
        return
      }
      window.location.replace(data.guest_path)
    } catch (submitError) {
      setError(submitError?.message || 'Room access could not be verified.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <main className="room-entry-shell">
      <section className="room-entry-card">
        <div className="room-entry-brand">StayQR</div>
        <p className="room-entry-kicker">PERMANENT ROOM QR</p>
        <h1>{loading ? 'Checking room…' : context?.valid ? `Room ${context.room_number}` : 'Room access'}</h1>
        {context?.valid && <p className="room-entry-hotel">{context.hotel_name}</p>}
        <p className="room-entry-copy">
          This QR stays in the room. Your private access changes for every stay.
          Enter the PIN issued by reception to open the current guest guide.
        </p>

        {error && <div className="room-entry-error" role="alert">{error}</div>}

        {context?.valid && (
          <form onSubmit={submit} className="room-entry-form">
            <label>
              <span>6-digit stay PIN</span>
              <input
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                pattern="[0-9]{6}"
                value={pin}
                onChange={(event) => setPin(event.target.value.replace(/\D/g, '').slice(0, 6))}
                placeholder="••••••"
                aria-label="6-digit stay PIN"
              />
            </label>
            <button type="submit" disabled={submitting || pin.length !== 6}>
              {submitting ? 'Verifying…' : 'Open guest guide'}
            </button>
          </form>
        )}

        <small>Old stay access stops working after checkout, expiry, rotation or revocation.</small>
      </section>
    </main>
  )
}
