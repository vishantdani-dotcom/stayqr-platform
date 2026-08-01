import { useEffect, useMemo, useRef, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  checkInReservationRoom,
  getReservationOperations,
} from '../../lib/day5Reservations'
import {
  navigateToSection,
  notifyCalendarInvalidated,
} from '../../lib/bookingCalendar'
import './ReservationOperations.css'

const TABS = [
  ['today_arrivals', 'Today arrivals'],
  ['upcoming_arrivals', 'Upcoming arrivals'],
  ['today_departures', 'Today departures'],
  ['in_house', 'In house'],
  ['unallocated_arrivals', 'Unallocated'],
  ['overdue_arrivals', 'Overdue'],
]

function toDateInput(value = new Date()) {
  const date = new Date(value)
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset())
  return date.toISOString().slice(0, 10)
}

export default function ReservationOperations() {
  const [hotel, setHotel] = useState(null)
  const [businessDate, setBusinessDate] = useState(() => toDateInput())
  const [upcomingDays, setUpcomingDays] = useState(7)
  const [operations, setOperations] = useState(null)
  const [activeTab, setActiveTab] = useState('today_arrivals')
  const [loading, setLoading] = useState(true)
  const [actionId, setActionId] = useState(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState(null)
  const requestRef = useRef(0)

  useEffect(() => {
    let cancelled = false

    async function initialize() {
      setLoading(true)
      setError('')

      try {
        const selectedHotel = await getCurrentHotel()
        if (!selectedHotel?.id) {
          throw new Error('No active hotel is assigned to this account.')
        }
        if (cancelled) return
        setHotel(selectedHotel)
        await loadOperations(selectedHotel.id, businessDate, upcomingDays, cancelled)
      } catch (initializationError) {
        if (!cancelled) {
          setError(
            initializationError?.message ||
              'StayQR could not load reservation operations.'
          )
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    initialize()
    return () => {
      cancelled = true
      requestRef.current += 1
    }
    // This initialization runs once per tenant-remounted page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function loadOperations(
    hotelId = hotel?.id,
    dateValue = businessDate,
    daysValue = upcomingDays,
    cancelled = false
  ) {
    if (!hotelId) return

    const requestId = requestRef.current + 1
    requestRef.current = requestId
    setLoading(true)
    setError('')

    try {
      const result = await getReservationOperations({
        hotelId,
        businessDate: dateValue,
        upcomingDays: daysValue,
      })

      if (cancelled || requestId !== requestRef.current) return

      setOperations({
        ...result,
        overdue_arrivals:
          result?.overdue_exceptions || result?.overdue_arrivals || [],
      })
    } catch (loadError) {
      if (!cancelled && requestId === requestRef.current) {
        setError(loadError?.message || 'Unable to load arrivals and departures.')
      }
    } finally {
      if (!cancelled && requestId === requestRef.current) setLoading(false)
    }
  }

  function showNotice(type, message) {
    setNotice({ type, message })
    window.setTimeout(() => {
      setNotice((current) =>
        current?.message === message ? null : current
      )
    }, 5500)
  }

  async function handleRefresh() {
    await loadOperations()
  }

  async function handleDateChange(event) {
    const nextDate = event.target.value
    setBusinessDate(nextDate)
    await loadOperations(hotel?.id, nextDate, upcomingDays)
  }

  async function handleUpcomingDaysChange(event) {
    const nextDays = Number(event.target.value) || 7
    setUpcomingDays(nextDays)
    await loadOperations(hotel?.id, businessDate, nextDays)
  }

  async function handleCheckIn(item) {
    if (!hotel?.id || !item?.reservation_id || !item?.reservation_room_id) return

    const confirmed = window.confirm(
      `Check in ${item.guest_name || item.reservation_number} to Room ${item.room_number}?`
    )
    if (!confirmed) return

    const lockId = item.reservation_room_id
    setActionId(lockId)

    try {
      const result = await checkInReservationRoom({
        hotelId: hotel.id,
        reservationId: item.reservation_id,
        reservationRoomId: item.reservation_room_id,
        expectedUpdatedAt: item.updated_at,
      })

      notifyCalendarInvalidated({
        reason: 'reservation_checked_in',
        reservationId: item.reservation_id,
      })

      showNotice(
        'success',
        `Checked in to Room ${result.room_number}. Deposit transferred: ${formatMoney(
          result.deposit_transferred,
          hotel.currency_code || 'INR'
        )}.`
      )
      await loadOperations()
    } catch (checkInError) {
      showNotice(
        'error',
        checkInError?.message || 'StayQR could not complete the check-in.'
      )
      await loadOperations()
    } finally {
      setActionId(null)
    }
  }

  const counts = useMemo(
    () =>
      Object.fromEntries(
        TABS.map(([key]) => [key, operations?.[key]?.length || 0])
      ),
    [operations]
  )

  const activeItems = operations?.[activeTab] || []

  if (loading && !operations) {
    return <OperationsState title="Arrivals & Departures" message="Loading authoritative reservation operations…" />
  }

  if (error && !operations) {
    return <OperationsState title="Arrivals & Departures" message={error} error />
  }

  return (
    <div className="reservation-operations-page">
      {notice && (
        <div className={`operations-toast ${notice.type}`} role="status">
          {notice.message}
        </div>
      )}

      <header className="operations-header">
        <div>
          <p className="operations-eyebrow">Front desk control desk</p>
          <h1>Arrivals & Departures</h1>
          <p>
            {hotel?.hotel_name || 'Selected hotel'} · confirmed arrivals,
            departures, active stays and exceptions from one authoritative view.
          </p>
        </div>
        <button
          className="operations-btn secondary"
          type="button"
          onClick={handleRefresh}
          disabled={loading}
        >
          {loading ? 'Refreshing…' : '↻ Refresh'}
        </button>
      </header>

      <section className="operations-control-panel">
        <label>
          <span>Business date</span>
          <input type="date" value={businessDate} onChange={handleDateChange} />
        </label>
        <label>
          <span>Upcoming window</span>
          <select value={upcomingDays} onChange={handleUpcomingDaysChange}>
            <option value="3">3 days</option>
            <option value="7">7 days</option>
            <option value="14">14 days</option>
            <option value="30">30 days</option>
          </select>
        </label>
        <div className="operations-control-note">
          <span>Hotel scope</span>
          <strong>{hotel?.hotel_name || '—'}</strong>
          <small>Switching property reloads this entire page.</small>
        </div>
      </section>

      <section className="operations-summary-grid">
        {TABS.map(([key, label]) => (
          <button
            type="button"
            key={key}
            className={`operations-summary-card ${activeTab === key ? 'active' : ''}`}
            onClick={() => setActiveTab(key)}
          >
            <span>{label}</span>
            <strong>{counts[key]}</strong>
          </button>
        ))}
      </section>

      {error && <div className="operations-inline-error">{error}</div>}

      <section className="operations-list-panel">
        <div className="operations-list-heading">
          <div>
            <p className="operations-eyebrow">Operational queue</p>
            <h2>{TABS.find(([key]) => key === activeTab)?.[1]}</h2>
          </div>
          <span>{activeItems.length} record(s)</span>
        </div>

        {activeItems.length ? (
          <div className="operations-table-wrap">
            <table className="operations-table">
              <thead>
                <tr>
                  <th>Booking / guest</th>
                  <th>Stay</th>
                  <th>Room</th>
                  <th>Status</th>
                  <th>Guests</th>
                  <th>Amount / deposit</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {activeItems.map((item) => (
                  <OperationRow
                    key={`${item.operation_source || 'operation'}-${
                      item.reservation_room_id ||
                      item.guest_session_id ||
                      item.reservation_id ||
                      item.reservation_number
                    }-${activeTab}`}
                    item={item}
                    activeTab={activeTab}
                    actionId={actionId}
                    onCheckIn={handleCheckIn}
                    currencyCode={hotel?.currency_code || 'INR'}
                  />
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="operations-empty">
            <span>✓</span>
            <h3>No records in this queue</h3>
            <p>The selected hotel and business date have no matching items.</p>
          </div>
        )}
      </section>
    </div>
  )
}

function OperationRow({ item, activeTab, actionId, onCheckIn, currencyCode }) {
  const isDirectStay =
    item.is_walk_in === true ||
    item.operation_source === 'walk_in' ||
    (!item.reservation_id && Boolean(item.guest_session_id))

  const isArrivalException = ['missed_arrival', 'late_arrival'].includes(
    item.exception_type
  )

  const canCheckIn =
    !isDirectStay &&
    (activeTab === 'today_arrivals' || isArrivalException) &&
    item.reservation_status === 'confirmed' &&
    item.room_status === 'confirmed' &&
    Boolean(item.room_id)

  function openPrimaryRecord() {
    if (isDirectStay && item.guest_session_id) {
      navigateToSection('guests', {
        guestSessionId: item.guest_session_id,
      })
      return
    }

    if (item.reservation_id) {
      navigateToSection('reservations', {
        reservationId: item.reservation_id,
      })
    }
  }

  const exceptionLabel = item.exception_type
    ? formatStatus(item.exception_type)
    : null
  const overdueDuration = formatOverdueDuration(item.minutes_overdue)

  return (
    <tr className={item.is_overdue ? 'operations-row-overdue' : undefined}>
      <td>
        <button
          type="button"
          className="operations-booking-link"
          onClick={openPrimaryRecord}
          disabled={!item.reservation_id && !item.guest_session_id}
          title={isDirectStay ? 'Open active guest stay' : 'Open reservation'}
        >
          {item.reservation_number}
        </button>
        <strong>{item.guest_name || 'Guest not linked'}</strong>
        <small>{item.guest_phone || 'No phone saved'}</small>
      </td>
      <td>
        <strong>{formatDate(item.arrival_date)} → {formatDate(item.departure_date)}</strong>
        <small>
          {item.expected_checkin_time || 'Check-in time not set'} /{' '}
          {item.expected_checkout_time || '11:00'}
        </small>
      </td>
      <td>
        <strong>{item.room_number ? `Room ${item.room_number}` : 'Unallocated'}</strong>
        <small>{item.room_type || 'Room type not found'}</small>
      </td>
      <td>
        {exceptionLabel && item.is_overdue ? (
          <>
            <span
              className={`operations-exception operations-exception-${item.exception_type}`}
            >
              {exceptionLabel}
            </span>
            {overdueDuration && (
              <small className="operations-exception-duration">
                Overdue by {overdueDuration}
              </small>
            )}
          </>
        ) : (
          <span className={`operations-status ${item.room_status || item.reservation_status}`}>
            {formatStatus(item.room_status || item.reservation_status)}
          </span>
        )}
        {item.guest_session_status && (
          <small>Stay: {formatStatus(item.guest_session_status)}</small>
        )}
      </td>
      <td>
        <strong>{item.adults || 0} adult(s)</strong>
        <small>{item.children || 0} child(ren)</small>
      </td>
      <td>
        <strong>{formatMoney(item.total_amount, currencyCode)}</strong>
        <small>{formatMoney(item.deposit_collected, currencyCode)} deposit</small>
      </td>
      <td>
        <div className="operations-row-actions">
          <button
            type="button"
            className="operations-btn ghost"
            onClick={openPrimaryRecord}
            disabled={!item.reservation_id && !item.guest_session_id}
          >
            {isDirectStay ? 'Open stay' : 'Open booking'}
          </button>
          {canCheckIn && (
            <button
              type="button"
              className="operations-btn primary"
              onClick={() => onCheckIn(item)}
              disabled={actionId === item.reservation_room_id}
            >
              {actionId === item.reservation_room_id ? 'Checking in…' : 'Check in'}
            </button>
          )}
          {activeTab === 'unallocated_arrivals' && (
            <button
              type="button"
              className="operations-btn secondary"
              onClick={() => navigateToSection('calendar')}
            >
              Assign room
            </button>
          )}
          {activeTab === 'in_house' && item.guest_session_id && !isDirectStay && (
            <button
              type="button"
              className="operations-btn secondary"
              onClick={() =>
                navigateToSection('guests', {
                  guestSessionId: item.guest_session_id,
                })
              }
            >
              Open stay
            </button>
          )}
        </div>
      </td>
    </tr>
  )
}

function OperationsState({ title, message, error = false }) {
  return (
    <div className={`operations-state ${error ? 'error' : ''}`}>
      <span>{error ? '!' : '…'}</span>
      <h1>{title}</h1>
      <p>{message}</p>
    </div>
  )
}

function formatStatus(value) {
  return String(value || 'unknown')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}

function formatDate(value) {
  if (!value) return '—'
  const parsed = new Date(`${value}T12:00:00`)
  if (Number.isNaN(parsed.getTime())) return value
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(parsed)
}

function formatOverdueDuration(value) {
  const totalMinutes = Math.max(0, Math.floor(Number(value || 0)))
  if (!totalMinutes) return ''

  const days = Math.floor(totalMinutes / 1440)
  const hours = Math.floor((totalMinutes % 1440) / 60)
  const minutes = totalMinutes % 60
  const parts = []

  if (days) parts.push(`${days}d`)
  if (hours) parts.push(`${hours}h`)
  if (!days && minutes) parts.push(`${minutes}m`)

  return parts.join(' ')
}

function formatMoney(value, currency = 'INR') {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency,
    maximumFractionDigits: 2,
  }).format(Number(value || 0))
}
