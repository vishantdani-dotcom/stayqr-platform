import { useEffect, useState } from 'react'
import {
  disableBackgroundPush,
  enableBackgroundPush,
  getBackgroundPushEnvironment,
  getBackgroundPushStatus,
  sendBackgroundPushTest,
  syncExistingBackgroundPush,
} from '../../lib/backgroundPush'
import './BackgroundPushCard.css'

function statusLabel(status) {
  if (!status?.supported) return 'Not supported'
  if (status.permission === 'denied') return 'Blocked by browser'
  if (status.enabled) return 'Enabled on this device'
  return 'Off on this device'
}

export default function BackgroundPushCard({ hotelId }) {
  const [status, setStatus] = useState(() => ({
    ...getBackgroundPushEnvironment(),
    enabled: false,
    activeDevices: 0,
    localSubscription: false,
  }))
  const [busy, setBusy] = useState('')
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false

    async function initialize() {
      if (!hotelId) return
      try {
        await syncExistingBackgroundPush(hotelId)
        const next = await getBackgroundPushStatus(hotelId)
        if (!cancelled) setStatus(next)
      } catch (loadError) {
        if (!cancelled) {
          setError(
            loadError?.message ||
              'Background notification status could not be loaded.'
          )
        }
      }
    }

    initialize()
    return () => {
      cancelled = true
    }
  }, [hotelId])

  async function refreshStatus() {
    const next = await getBackgroundPushStatus(hotelId)
    setStatus(next)
    return next
  }

  async function handleEnable() {
    setBusy('enable')
    setError('')
    setNotice('')
    try {
      const next = await enableBackgroundPush(hotelId)
      setStatus(next)
      setNotice(
        'Background notifications are enabled on this device.'
      )
    } catch (actionError) {
      setError(
        actionError?.message ||
          'Background notifications could not be enabled.'
      )
      await refreshStatus().catch(() => null)
    } finally {
      setBusy('')
    }
  }

  async function handleDisable() {
    setBusy('disable')
    setError('')
    setNotice('')
    try {
      const next = await disableBackgroundPush(hotelId)
      setStatus(next)
      setNotice(
        'Background notifications are disabled on this device.'
      )
    } catch (actionError) {
      setError(
        actionError?.message ||
          'Background notifications could not be disabled.'
      )
    } finally {
      setBusy('')
    }
  }

  async function handleTest() {
    setBusy('test')
    setError('')
    setNotice('')
    try {
      await sendBackgroundPushTest(hotelId)
      setNotice(
        'Test push sent. Minimize StayQR to confirm the system notification appears.'
      )
    } catch (actionError) {
      setError(
        actionError?.message ||
          'The test background notification could not be sent.'
      )
    } finally {
      setBusy('')
    }
  }

  const iosNeedsInstall =
    status?.supported && status?.isIos && !status?.isStandalone

  return (
    <section className="stayqr-push-card" aria-labelledby="stayqr-push-title">
      <div className="stayqr-push-card__heading">
        <div>
          <p className="staff-kicker">Device notifications</p>
          <h2 id="stayqr-push-title">Background notifications</h2>
          <p>
            Receive StayQR alerts on this device when the app is minimized
            or not currently visible. Foreground notification ringtones are
            unchanged.
          </p>
        </div>
        <span className={`stayqr-push-state${status.enabled ? ' enabled' : ''}`}>
          {statusLabel(status)}
        </span>
      </div>

      {iosNeedsInstall && (
        <div className="stayqr-push-info">
          On iPhone or iPad, add StayQR to the Home Screen, open it from the
          Home Screen icon, then enable notifications here.
        </div>
      )}

      {!status.supported && (
        <div className="stayqr-push-info">
          This browser does not support standards-based background push
          notifications.
        </div>
      )}

      {error && <div className="staff-alert error">{error}</div>}
      {notice && <div className="staff-alert success">{notice}</div>}

      <div className="stayqr-push-card__meta">
        <span>Permission: <b>{String(status.permission || 'unknown')}</b></span>
        <span>Active devices for this hotel: <b>{status.activeDevices || 0}</b></span>
      </div>

      <div className="stayqr-push-card__actions">
        {status.enabled ? (
          <>
            <button
              className="staff-secondary-btn"
              type="button"
              onClick={handleTest}
              disabled={Boolean(busy)}
            >
              {busy === 'test' ? 'Sending…' : 'Send test notification'}
            </button>
            <button
              className="staff-secondary-btn"
              type="button"
              onClick={handleDisable}
              disabled={Boolean(busy)}
            >
              {busy === 'disable' ? 'Disabling…' : 'Disable on this device'}
            </button>
          </>
        ) : (
          <button
            className="staff-primary-btn"
            type="button"
            onClick={handleEnable}
            disabled={Boolean(busy) || !status.supported || iosNeedsInstall || status.permission === 'denied'}
          >
            {busy === 'enable' ? 'Enabling…' : 'Enable on this device'}
          </button>
        )}
      </div>
    </section>
  )
}
