import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import { getReservationConfiguration } from '../../lib/reservations'
import {
  CALENDAR_INVALIDATION_EVENT,
  changeCalendarRoomBlockStatus,
  createCalendarRoomBlock,
  getBookingCalendar,
  getCalendarRoomBlockDetails,
  moveReservationOnCalendar,
  navigateToSection,
  updateCalendarRoomBlock,
} from '../../lib/bookingCalendar'
import './BookingCalendar.css'

const VIEW_OPTIONS = [
  { value: 'day', label: 'Day' },
  { value: 'week', label: 'Week' },
  { value: 'month', label: 'Month' },
]

const RESERVATION_STATUS_OPTIONS = [
  ['draft', 'Draft'],
  ['tentative', 'Tentative'],
  ['confirmed', 'Confirmed'],
  ['checked_in', 'Checked In'],
  ['checked_out', 'Checked Out'],
  ['cancelled', 'Cancelled'],
  ['no_show', 'No Show'],
]

const BLOCK_TYPES = [
  ['operational', 'Operational'],
  ['maintenance', 'Maintenance'],
  ['out_of_order', 'Out of Order'],
  ['owner_use', 'Owner Use'],
  ['deep_cleaning', 'Deep Cleaning'],
  ['other', 'Other'],
]

const LEGEND = [
  ['draft', 'Draft'],
  ['tentative', 'Tentative'],
  ['confirmed', 'Confirmed'],
  ['checked_in', 'Checked In'],
  ['checked_out', 'Checked Out'],
  ['cancelled', 'Cancelled'],
  ['no_show', 'No Show'],
  ['block-maintenance', 'Maintenance Block'],
  ['block-operational', 'Operational Block'],
  ['block-out_of_order', 'Out of Order'],
  ['direct_stay', 'Direct Stay'],
]

const PAGE_LIMIT = 18

function dateInput(value) {
  const date = value instanceof Date ? new Date(value) : new Date(`${value}T12:00:00`)
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset())
  return date.toISOString().slice(0, 10)
}

function addDays(value, days) {
  const date = value instanceof Date ? new Date(value) : new Date(`${value}T12:00:00`)
  date.setDate(date.getDate() + days)
  return dateInput(date)
}

function startOfMonth(value) {
  const date = value instanceof Date ? new Date(value) : new Date(`${value}T12:00:00`)
  date.setDate(1)
  return dateInput(date)
}

function addMonths(value, months) {
  const date = value instanceof Date ? new Date(value) : new Date(`${value}T12:00:00`)
  date.setDate(1)
  date.setMonth(date.getMonth() + months)
  return dateInput(date)
}

function differenceInDays(start, end) {
  return Math.max(
    0,
    Math.round(
      (new Date(`${end}T12:00:00`) - new Date(`${start}T12:00:00`)) /
        86400000
    )
  )
}

function formatDate(value, options = {}) {
  if (!value) return '—'
  return new Date(`${value}T12:00:00`).toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: options.year ? 'numeric' : undefined,
    weekday: options.weekday ? 'short' : undefined,
  })
}

function formatDateTime(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function money(value, currency = 'INR') {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: currency || 'INR',
    maximumFractionDigits: 2,
  }).format(Number(value || 0))
}

function normalizeStatus(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/\s+/g, '_')
}

function labelize(value) {
  return String(value || '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}

function calculateRange(view, anchorDate) {
  if (view === 'month') {
    const rangeStart = startOfMonth(anchorDate)
    return {
      rangeStart,
      rangeEnd: addMonths(rangeStart, 1),
    }
  }

  const length = view === 'week' ? 7 : 1
  return {
    rangeStart: anchorDate,
    rangeEnd: addDays(anchorDate, length),
  }
}

function createDays(rangeStart, rangeEnd) {
  const count = differenceInDays(rangeStart, rangeEnd)
  return Array.from({ length: count }, (_, index) => addDays(rangeStart, index))
}

function getEventPlacement(event, rangeStart, rangeEnd) {
  const visibleStart = event.start_date < rangeStart ? rangeStart : event.start_date
  const visibleEnd = event.end_date > rangeEnd ? rangeEnd : event.end_date
  const startIndex = differenceInDays(rangeStart, visibleStart)
  const span = Math.max(1, differenceInDays(visibleStart, visibleEnd))
  return { startIndex, span }
}

function allocateHistoricalEventLanes(events) {
  const laneEnds = []
  const laneByEventKey = new Map()

  events
    .filter((event) => !event.occupies_inventory)
    .slice()
    .sort((left, right) => {
      const startComparison = String(left.start_date || '').localeCompare(String(right.start_date || ''))
      if (startComparison !== 0) return startComparison
      return String(left.end_date || '').localeCompare(String(right.end_date || ''))
    })
    .forEach((event) => {
      const eventStart = event.start_date || ''
      const eventEnd = event.end_date || eventStart
      let laneIndex = laneEnds.findIndex((laneEnd) => laneEnd <= eventStart)

      if (laneIndex === -1) {
        laneIndex = laneEnds.length
        laneEnds.push(eventEnd)
      } else {
        laneEnds[laneIndex] = eventEnd
      }

      laneByEventKey.set(`${event.event_type}-${event.id}`, laneIndex)
    })

  return {
    laneByEventKey,
    laneCount: laneEnds.length,
  }
}

function eventClass(event) {
  if (event.event_type === 'room_block') {
    return `block-${normalizeStatus(event.block_type)}`
  }
  if (event.event_type === 'direct_stay') return 'direct_stay'
  return normalizeStatus(event.status)
}

function bookingStatusLabel(event) {
  const bookingStatus = normalizeStatus(event.booking_status || event.status)
  const roomStatus = normalizeStatus(event.status)

  if (bookingStatus === 'checked_in' && roomStatus === 'confirmed') {
    return 'Partially Checked In'
  }

  return labelize(bookingStatus)
}

function canMoveReservationEvent(event) {
  const roomStatus = normalizeStatus(event.status)
  const bookingStatus = normalizeStatus(event.booking_status || event.status)

  return (
    ['tentative', 'confirmed'].includes(roomStatus) &&
    ['tentative', 'confirmed'].includes(bookingStatus)
  )
}

function eventTitle(event) {
  if (event.event_type === 'room_block') return event.reason || labelize(event.block_type)
  if (event.event_type === 'direct_stay') return event.guest_name || 'Direct stay'
  return `${event.reservation_number} · ${event.guest_name || 'Guest'}`
}

function createBlockForm({ roomId = '', startDate = '', endDate = '', block = null } = {}) {
  return {
    room_id: block?.room_id || roomId,
    block_type: block?.block_type || 'operational',
    start_date: block?.start_date || startDate,
    end_date: block?.end_date || endDate,
    reason: block?.reason || '',
    notes: block?.notes || '',
  }
}

function setCompactDragImage(event, label) {
  const preview = document.createElement('div')
  preview.className = 'calendar-drag-preview'
  preview.textContent = label
  document.body.appendChild(preview)
  event.dataTransfer.setDragImage(preview, 22, 18)
  window.setTimeout(() => preview.remove(), 100)
}

export default function BookingCalendar() {
  const [hotel, setHotel] = useState(null)
  const [roomTypes, setRoomTypes] = useState([])
  const [calendar, setCalendar] = useState(null)
  const [view, setView] = useState('week')
  const [anchorDate, setAnchorDate] = useState(dateInput(new Date()))
  const [roomTypeId, setRoomTypeId] = useState('')
  const [reservationStatuses, setReservationStatuses] = useState([])
  const [showHistoricalBlocks, setShowHistoricalBlocks] = useState(false)
  const [pageOffset, setPageOffset] = useState(0)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [pageError, setPageError] = useState('')
  const [notice, setNotice] = useState(null)
  const [selectedEvent, setSelectedEvent] = useState(null)
  const [blockModal, setBlockModal] = useState(null)
  const [allocationModal, setAllocationModal] = useState(null)
  const [busyAction, setBusyAction] = useState(false)
  const [draggingReservation, setDraggingReservation] = useState(null)
  const [dragTarget, setDragTarget] = useState(null)
  const operationLockRef = useRef(false)
  const noticeTimerRef = useRef(null)
  const draggingReservationRef = useRef(null)

  const hotelId = hotel?.id || ''

  const { rangeStart, rangeEnd } = useMemo(
    () => calculateRange(view, anchorDate),
    [view, anchorDate]
  )

  const days = useMemo(
    () => createDays(rangeStart, rangeEnd),
    [rangeStart, rangeEnd]
  )

  const showNotice = useCallback((type, message) => {
    if (noticeTimerRef.current) {
      window.clearTimeout(noticeTimerRef.current)
    }
    setNotice({ type, message })
    noticeTimerRef.current = window.setTimeout(() => {
      setNotice(null)
      noticeTimerRef.current = null
    }, 6500)
  }, [])

  const resetDragUi = useCallback(() => {
    draggingReservationRef.current = null
    setDraggingReservation(null)
    setDragTarget(null)
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur()
    }
  }, [])

  useEffect(
    () => () => {
      if (noticeTimerRef.current) {
        window.clearTimeout(noticeTimerRef.current)
      }
    },
    []
  )

  const loadCalendar = useCallback(
    async ({ silent = false } = {}) => {
      if (!hotelId) return
      if (silent) setRefreshing(true)
      else setLoading(true)

      try {
        const data = await getBookingCalendar({
          hotelId,
          rangeStart,
          rangeEnd,
          roomTypeId,
          reservationStatuses,
          blockStatuses: showHistoricalBlocks
            ? ['active', 'released', 'cancelled']
            : ['active'],
          limit: PAGE_LIMIT,
          offset: pageOffset,
        })
        setCalendar(data)
        setPageError('')
      } catch (error) {
        console.error('Booking calendar load error:', error)
        setPageError(error.message || 'Unable to load the booking calendar.')
      } finally {
        setLoading(false)
        setRefreshing(false)
      }
    }, [
      hotelId,
      pageOffset,
      rangeEnd,
      rangeStart,
      reservationStatuses,
      roomTypeId,
      showHistoricalBlocks,
    ]
  )

  useEffect(() => {
    let cancelled = false

    async function initialize() {
      setLoading(true)
      try {
        const currentHotel = await getCurrentHotel()
        if (!currentHotel) throw new Error('No active hotel is assigned to this account.')
        const configuration = await getReservationConfiguration(currentHotel.id)
        if (cancelled) return
        setHotel(currentHotel)
        setRoomTypes(configuration.roomTypes || [])
      } catch (error) {
        console.error('Booking calendar initialization error:', error)
        if (!cancelled) setPageError(error.message || 'Unable to initialize Booking Calendar.')
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    initialize()
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (hotelId) loadCalendar()
  }, [hotelId, loadCalendar])

  useEffect(() => {
    const handleInvalidation = () => loadCalendar({ silent: true })
    window.addEventListener(CALENDAR_INVALIDATION_EVENT, handleInvalidation)
    return () => window.removeEventListener(CALENDAR_INVALIDATION_EVENT, handleInvalidation)
  }, [loadCalendar])

  useEffect(() => {
    setPageOffset(0)
  }, [view, anchorDate, roomTypeId, reservationStatuses, showHistoricalBlocks])

  function movePeriod(direction) {
    if (view === 'month') {
      setAnchorDate((current) => addMonths(current, direction))
    } else {
      setAnchorDate((current) => addDays(current, direction * (view === 'week' ? 7 : 1)))
    }
  }

  function toggleReservationStatus(status) {
    setReservationStatuses((current) =>
      current.includes(status)
        ? current.filter((item) => item !== status)
        : [...current, status]
    )
  }

  async function handleDrop(event, roomId, arrivalDate) {
    event.preventDefault()
    event.stopPropagation()
    event.currentTarget?.blur?.()
    if (operationLockRef.current) {
      resetDragUi()
      return
    }

    let payload
    try {
      const serializedPayload =
        event.dataTransfer.getData('application/json') ||
        event.dataTransfer.getData('text/plain')
      payload = JSON.parse(serializedPayload)
    } catch {
      resetDragUi()
      showNotice('error', 'The dragged reservation could not be read. Please try again.')
      return
    }

    if (payload.type !== 'reservation') {
      resetDragUi()
      return
    }

    const room = calendar?.rooms?.find((item) => item.id === roomId)
    if (!room) {
      resetDragUi()
      showNotice('error', 'The target room is no longer available. Refresh and try again.')
      return
    }

    resetDragUi()

    if (payload.roomId === roomId && payload.startDate === arrivalDate) {
      showNotice('error', 'Choose a different room or arrival date.')
      return
    }

    const confirmed = window.confirm(
      `Move ${payload.reservationNumber} to Room ${room.room_number} from ${formatDate(arrivalDate, { year: true })}?`
    )
    if (!confirmed) {
      resetDragUi()
      return
    }

    operationLockRef.current = true
    setBusyAction(true)
    try {
      await moveReservationOnCalendar({
        hotelId: hotel.id,
        reservationId: payload.reservationId,
        reservationRoomId: payload.reservationRoomId,
        roomId,
        arrivalDate,
        expectedUpdatedAt: payload.updatedAt,
      })
      showNotice('success', `${payload.reservationNumber} moved successfully.`)
      await loadCalendar({ silent: true })
    } catch (error) {
      console.error('Calendar move rejected:', error)
      showNotice(
        'error',
        error?.message ||
          error?.details ||
          'The reservation could not be moved because the selected room or dates are unavailable.'
      )
      await loadCalendar({ silent: true })
    } finally {
      operationLockRef.current = false
      setBusyAction(false)
      resetDragUi()
    }
  }

  function getTrackElement(event) {
    const currentTarget = event.currentTarget
    if (!(currentTarget instanceof HTMLElement)) return null
    if (currentTarget.classList.contains('calendar-room-track')) return currentTarget
    return currentTarget.closest('.calendar-room-track')
  }

  function getTrackDropDate(event) {
    const track = getTrackElement(event)
    if (!track || days.length === 0) return null

    const bounds = track.getBoundingClientRect()
    if (!bounds.width) return null

    const pointerOffset = Math.min(
      Math.max(event.clientX - bounds.left, 0),
      Math.max(bounds.width - 1, 0)
    )
    const dayIndex = Math.min(
      days.length - 1,
      Math.floor((pointerOffset / bounds.width) * days.length)
    )
    return days[dayIndex]
  }

  function updateDragTarget(room, arrivalDate) {
    setDragTarget((current) => {
      if (current?.roomId === room.id && current?.arrivalDate === arrivalDate) {
        return current
      }
      return {
        roomId: room.id,
        roomNumber: room.room_number,
        arrivalDate,
      }
    })
  }

  function handleTrackDragOver(event, room) {
    if (!draggingReservationRef.current) return
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = 'move'

    const arrivalDate = getTrackDropDate(event)
    if (!arrivalDate) return
    updateDragTarget(room, arrivalDate)
  }

  function handleCellDragOver(event, room, day) {
    if (!draggingReservationRef.current) return
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = 'move'
    updateDragTarget(room, day)
  }

  function handleCellDrop(event, room, day) {
    event.preventDefault()
    event.stopPropagation()
    handleDrop(event, room.id, day)
  }

  function handleTrackDragLeave(event, roomId) {
    const nextTarget = event.relatedTarget
    if (nextTarget && event.currentTarget.contains(nextTarget)) return

    setDragTarget((current) => (current?.roomId === roomId ? null : current))
  }

  function handleTrackDrop(event, room) {
    event.preventDefault()
    event.stopPropagation()
    const arrivalDate = getTrackDropDate(event)

    if (!arrivalDate) {
      resetDragUi()
      showNotice('error', 'The target date could not be determined. Please try again.')
      return
    }

    handleDrop(event, room.id, arrivalDate)
  }

  function handleDragStart(event, calendarEvent) {
    if (
      calendarEvent.event_type !== 'reservation' ||
      !canMoveReservationEvent(calendarEvent)
    ) {
      event.preventDefault()
      return
    }

    event.dataTransfer.effectAllowed = 'move'
    const dragState = {
      reservationNumber: calendarEvent.reservation_number,
      roomId: calendarEvent.room_id,
      startDate: calendarEvent.start_date,
      endDate: calendarEvent.end_date,
      nights: differenceInDays(calendarEvent.start_date, calendarEvent.end_date),
    }
    draggingReservationRef.current = dragState
    setDraggingReservation(dragState)
    setCompactDragImage(
      event,
      `${calendarEvent.reservation_number} · ${differenceInDays(calendarEvent.start_date, calendarEvent.end_date)} night(s)`
    )
    const dragPayload = JSON.stringify({
      type: 'reservation',
      reservationId: calendarEvent.reservation_id,
      reservationRoomId: calendarEvent.reservation_room_id,
      reservationNumber: calendarEvent.reservation_number,
      updatedAt: calendarEvent.updated_at,
      roomId: calendarEvent.room_id,
      startDate: calendarEvent.start_date,
    })
    event.dataTransfer.setData('application/json', dragPayload)
    event.dataTransfer.setData('text/plain', dragPayload)
  }

  function handleDragEnd() {
    resetDragUi()
  }

  function handleUnallocatedDragStart(event, reservation) {
    event.dataTransfer.effectAllowed = 'move'
    const dragState = {
      reservationNumber: reservation.reservation_number,
      roomId: null,
      startDate: reservation.start_date,
      endDate: reservation.end_date,
      nights: differenceInDays(reservation.start_date, reservation.end_date),
    }
    draggingReservationRef.current = dragState
    setDraggingReservation(dragState)
    setCompactDragImage(
      event,
      `${reservation.reservation_number} · ${differenceInDays(reservation.start_date, reservation.end_date)} night(s)`
    )
    const dragPayload = JSON.stringify({
      type: 'reservation',
      reservationId: reservation.reservation_id,
      reservationRoomId: reservation.reservation_room_id,
      reservationNumber: reservation.reservation_number,
      updatedAt: reservation.updated_at,
      roomId: null,
      startDate: reservation.start_date,
    })
    event.dataTransfer.setData('application/json', dragPayload)
    event.dataTransfer.setData('text/plain', dragPayload)
  }

  async function openBlockDetails(event) {
    setBusyAction(true)
    try {
      const block = await getCalendarRoomBlockDetails(hotel.id, event.room_block_id)
      setSelectedEvent({ ...event, ...block, event_type: 'room_block' })
    } catch (error) {
      showNotice('error', error.message || 'Unable to load room-block details.')
    } finally {
      setBusyAction(false)
    }
  }

  async function handleBlockSubmit(form, editingBlock) {
    if (operationLockRef.current) return
    operationLockRef.current = true
    setBusyAction(true)

    try {
      let result
      if (editingBlock) {
        result = await updateCalendarRoomBlock({
          hotelId,
          roomBlockId: editingBlock.id,
          payload: form,
          expectedUpdatedAt: editingBlock.updated_at,
        })
        showNotice('success', 'Room block updated successfully.')
      } else {
        result = await createCalendarRoomBlock(hotel.id, form)
        showNotice('success', 'Room block created successfully.')
      }
      setBlockModal(null)
      setSelectedEvent({ ...result, event_type: 'room_block' })
      await loadCalendar({ silent: true })
    } catch (error) {
      console.error('Room-block save error:', error)
      throw error
    } finally {
      operationLockRef.current = false
      setBusyAction(false)
    }
  }

  async function handleBlockStatus(block, status) {
    if (operationLockRef.current) return
    const actionLabel = status === 'released' ? 'release' : 'cancel'
    const reason = window.prompt(
      `Enter the reason to ${actionLabel} this room block:`
    )

    // Cancel closes the browser prompt without changing the room block.
    if (reason === null) return

    const normalizedReason = reason.trim()
    if (!normalizedReason) {
      showNotice('error', `A reason is required to ${actionLabel} this room block.`)
      return
    }

    operationLockRef.current = true
    setBusyAction(true)
    try {
      const result = await changeCalendarRoomBlockStatus({
        hotelId: hotel.id,
        roomBlockId: block.id || block.room_block_id,
        status,
        reason: normalizedReason,
      })
      setSelectedEvent({ ...result, event_type: 'room_block' })
      showNotice('success', `Room block ${status}.`)
      await loadCalendar({ silent: true })
    } catch (error) {
      showNotice('error', error.message || 'Unable to change room-block status.')
    } finally {
      operationLockRef.current = false
      setBusyAction(false)
    }
  }

  async function handleAllocationSubmit({ reservation, roomId, arrivalDate }) {
    if (operationLockRef.current) return
    operationLockRef.current = true
    setBusyAction(true)
    try {
      await moveReservationOnCalendar({
        hotelId: hotel.id,
        reservationId: reservation.reservation_id,
        reservationRoomId: reservation.reservation_room_id,
        roomId,
        arrivalDate,
        expectedUpdatedAt: reservation.updated_at,
      })
      setAllocationModal(null)
      setSelectedEvent(null)
      showNotice('success', `${reservation.reservation_number} assigned successfully.`)
      await loadCalendar({ silent: true })
    } catch (error) {
      console.error('Room assignment error:', error)
      throw error
    } finally {
      operationLockRef.current = false
      setBusyAction(false)
    }
  }

  if (loading && !calendar) {
    return <CalendarState title="Booking Calendar" message="Loading room timeline…" />
  }

  if (pageError && !calendar) {
    return <CalendarState title="Booking Calendar" message={pageError} error />
  }

  const rooms = calendar?.rooms || []
  const events = calendar?.events || []
  const unallocated = calendar?.unallocated_reservations || []
  const pagination = calendar?.pagination || {}
  const eventsByRoom = new Map()
  events.forEach((item) => {
    const current = eventsByRoom.get(item.room_id) || []
    current.push(item)
    eventsByRoom.set(item.room_id, current)
  })

  const historicalLayoutsByRoom = new Map()
  eventsByRoom.forEach((roomEvents, roomId) => {
    historicalLayoutsByRoom.set(roomId, allocateHistoricalEventLanes(roomEvents))
  })

  const timelineMinWidth = Math.max(days.length * (view === 'month' ? 88 : 120), 700)

  return (
    <div className="booking-calendar-page">
      {notice && (
        <div
          className={`calendar-toast ${notice.type}`}
          role={notice.type === 'error' ? 'alert' : 'status'}
          aria-live={notice.type === 'error' ? 'assertive' : 'polite'}
        >
          {notice.message}
        </div>
      )}

      <header className="calendar-page-header">
        <div>
          <p className="calendar-eyebrow">Inventory Control Desk</p>
          <h1>Booking Calendar</h1>
          <p>
            {hotel?.hotel_name} · Room-wise reservations, direct stays and operational blocks.
          </p>
        </div>
        <div className="calendar-header-actions">
          <button
            type="button"
            className="calendar-btn secondary"
            onClick={() => loadCalendar({ silent: true })}
            disabled={refreshing || busyAction}
          >
            {refreshing ? 'Refreshing…' : '↻ Refresh'}
          </button>
          <button
            type="button"
            className="calendar-btn primary"
            onClick={() =>
              setBlockModal({
                block: null,
                initial: createBlockForm({
                  startDate: rangeStart,
                  endDate: addDays(rangeStart, 1),
                }),
              })
            }
          >
            ＋ Block Room
          </button>
        </div>
      </header>

      <section className="calendar-toolbar">
        <div className="calendar-period-controls">
          <button type="button" onClick={() => movePeriod(-1)} aria-label="Previous period">‹</button>
          <button type="button" className="today" onClick={() => setAnchorDate(dateInput(new Date()))}>Today</button>
          <button type="button" onClick={() => movePeriod(1)} aria-label="Next period">›</button>
          <input
            type="date"
            value={anchorDate}
            onChange={(event) => setAnchorDate(event.target.value)}
          />
          <strong>
            {formatDate(rangeStart, { year: true })}
            {view !== 'day' && ` – ${formatDate(addDays(rangeEnd, -1), { year: true })}`}
          </strong>
        </div>

        <div className="calendar-view-switch" role="group" aria-label="Calendar view">
          {VIEW_OPTIONS.map((option) => (
            <button
              type="button"
              key={option.value}
              className={view === option.value ? 'active' : ''}
              onClick={() => setView(option.value)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </section>

      <section className="calendar-filters">
        <label>
          <span>Hotel</span>
          <input value={hotel?.hotel_name || ''} disabled />
        </label>
        <label>
          <span>Room type</span>
          <select value={roomTypeId} onChange={(event) => setRoomTypeId(event.target.value)}>
            <option value="">All room types</option>
            {roomTypes.map((roomType) => (
              <option key={roomType.id} value={roomType.id}>{roomType.name}</option>
            ))}
          </select>
        </label>
        <div className="calendar-status-filter">
          <span>Reservation status</span>
          <div>
            {RESERVATION_STATUS_OPTIONS.map(([value, label]) => (
              <label key={value} className={reservationStatuses.includes(value) ? 'selected' : ''}>
                <input
                  type="checkbox"
                  checked={reservationStatuses.includes(value)}
                  onChange={() => toggleReservationStatus(value)}
                />
                {label}
              </label>
            ))}
          </div>
        </div>
        <label className="historical-block-filter">
          <span>Blocks</span>
          <button
            type="button"
            className={showHistoricalBlocks ? 'active' : ''}
            onClick={() => setShowHistoricalBlocks((current) => !current)}
          >
            {showHistoricalBlocks ? 'All block statuses' : 'Active blocks only'}
          </button>
        </label>
        <button
          type="button"
          className="calendar-clear-filters"
          onClick={() => {
            setRoomTypeId('')
            setReservationStatuses([])
            setShowHistoricalBlocks(false)
          }}
        >
          Clear filters
        </button>
      </section>

      <section className="calendar-legend" aria-label="Calendar status legend">
        {LEGEND.map(([value, label]) => (
          <span key={value}><i className={`legend-dot ${value}`} />{label}</span>
        ))}
      </section>

      {pageError && <div className="calendar-inline-error">{pageError}</div>}

      <section className="calendar-workspace">
        <div className="calendar-timeline-scroll">
          <div className="calendar-timeline" style={{ minWidth: timelineMinWidth + 220 }}>
            <div className="calendar-grid-header">
              <div className="calendar-room-header">Room / Type</div>
              <div
                className="calendar-date-header-grid"
                style={{ gridTemplateColumns: `repeat(${days.length}, minmax(${view === 'month' ? 88 : 120}px, 1fr))` }}
              >
                {days.map((day) => (
                  <div key={day} className={day === dateInput(new Date()) ? 'today' : ''}>
                    <span>{formatDate(day, { weekday: true })}</span>
                    <strong>{new Date(`${day}T12:00:00`).getDate()}</strong>
                  </div>
                ))}
              </div>
            </div>

            {rooms.length === 0 ? (
              <div className="calendar-empty-row">No rooms match the selected filters.</div>
            ) : (
              rooms.map((room) => {
                const roomEvents = eventsByRoom.get(room.id) || []
                const historicalLayout = historicalLayoutsByRoom.get(room.id) || {
                  laneByEventKey: new Map(),
                  laneCount: 0,
                }
                const historicalLaneCount = historicalLayout.laneCount
                const trackRows = historicalLaneCount > 0
                  ? `82px repeat(${historicalLaneCount}, 38px)`
                  : '82px'

                return (
                <div className="calendar-room-row" key={room.id}>
                  <div className="calendar-room-meta">
                    <strong>Room {room.room_number}</strong>
                    <span>{room.room_type_name}</span>
                    <small className={`room-operational-status ${normalizeStatus(room.status)}`}>
                      {labelize(room.status)}
                    </small>
                  </div>
                  <div
                    className={`calendar-room-track ${draggingReservation ? 'dragging-active' : ''} ${historicalLaneCount > 0 ? 'has-historical-lanes' : ''}`}
                    style={{
                      gridTemplateColumns: `repeat(${days.length}, minmax(${view === 'month' ? 88 : 120}px, 1fr))`,
                      gridTemplateRows: trackRows,
                    }}
                    onDragOver={(event) => handleTrackDragOver(event, room)}
                    onDragLeave={(event) => handleTrackDragLeave(event, room.id)}
                    onDrop={(event) => handleTrackDrop(event, room)}
                  >
                    {days.map((day) => {
                      const isDragTarget =
                        dragTarget?.roomId === room.id && dragTarget?.arrivalDate === day
                      const isCurrentPosition =
                        draggingReservation?.roomId === room.id &&
                        draggingReservation?.startDate === day

                      return (
                        <button
                          type="button"
                          className={`calendar-drop-cell ${day === dateInput(new Date()) ? 'today' : ''} ${isDragTarget ? 'drag-target' : ''} ${isDragTarget && isCurrentPosition ? 'current-target' : ''}`}
                          key={`${room.id}-${day}`}
                          onDragEnter={(event) => handleCellDragOver(event, room, day)}
                          onDragOver={(event) => handleCellDragOver(event, room, day)}
                          onDrop={(event) => handleCellDrop(event, room, day)}
                          onDoubleClick={() =>
                            setBlockModal({
                              block: null,
                              initial: createBlockForm({
                                roomId: room.id,
                                startDate: day,
                                endDate: addDays(day, 1),
                              }),
                            })
                          }
                          title={`Drop a reservation or double-click to block Room ${room.room_number} on ${formatDate(day, { year: true })}`}
                        >
                          {isDragTarget && (
                            <span className="calendar-drop-target-label">
                              <strong>{isCurrentPosition ? 'Current position' : 'Move here'}</strong>
                              <small>
                                Room {room.room_number} · {formatDate(day)}
                              </small>
                              {!isCurrentPosition && draggingReservation?.nights > 0 && (
                                <small>
                                  Checkout {formatDate(addDays(day, draggingReservation.nights))}
                                </small>
                              )}
                            </span>
                          )}
                        </button>
                      )
                    })}

                    {roomEvents.map((calendarEvent) => {
                      const placement = getEventPlacement(calendarEvent, rangeStart, rangeEnd)
                      const draggable =
                        calendarEvent.event_type === 'reservation' &&
                        canMoveReservationEvent(calendarEvent)
                      return (
                        <div
                          key={`${calendarEvent.event_type}-${calendarEvent.id}`}
                          className={`calendar-event ${eventClass(calendarEvent)} ${calendarEvent.occupies_inventory ? '' : 'non-inventory'}`}
                          style={{
                            gridColumn: `${placement.startIndex + 1} / span ${placement.span}`,
                            gridRow: calendarEvent.occupies_inventory
                              ? '1'
                              : String(
                                  (historicalLayout.laneByEventKey.get(
                                    `${calendarEvent.event_type}-${calendarEvent.id}`
                                  ) || 0) + 2
                                ),
                          }}
                          title={eventTitle(calendarEvent)}
                          onDragOver={(event) => handleTrackDragOver(event, room)}
                          onDrop={(event) => handleTrackDrop(event, room)}
                        >
                          <button
                            type="button"
                            className="calendar-event-content"
                            onClick={() =>
                              calendarEvent.event_type === 'room_block'
                                ? openBlockDetails(calendarEvent)
                                : setSelectedEvent(calendarEvent)
                            }
                          >
                            <strong>{eventTitle(calendarEvent)}</strong>
                            <span>
                              {calendarEvent.event_type === 'reservation'
                                ? labelize(calendarEvent.status)
                                : calendarEvent.event_type === 'room_block'
                                  ? labelize(calendarEvent.block_type)
                                  : labelize(calendarEvent.status || 'checked_in')}
                            </span>
                          </button>
                          {draggable && (
                            <span
                              className="calendar-drag-handle"
                              draggable
                              role="button"
                              aria-label={`Drag ${calendarEvent.reservation_number}`}
                              title="Drag to move this reservation"
                              onMouseDown={(event) => event.stopPropagation()}
                              onDragStart={(event) => handleDragStart(event, calendarEvent)}
                              onDragEnd={handleDragEnd}
                            >
                              ⋮⋮
                            </span>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </div>
                )
              })
            )}
          </div>
        </div>

        <aside className="unallocated-panel">
          <div className="unallocated-header">
            <div>
              <p>Assignment queue</p>
              <h2>Unallocated bookings</h2>
            </div>
            <span>{unallocated.length}</span>
          </div>
          <p className="unallocated-help">Drag a booking onto a compatible room/date, or use Assign.</p>
          <div className="unallocated-list">
            {unallocated.length === 0 ? (
              <div className="unallocated-empty">No unallocated reservations in this date range.</div>
            ) : (
              unallocated.map((reservation) => (
                <article
                  key={reservation.reservation_room_id}
                  className="unallocated-card"
                  draggable
                  onDragStart={(event) => handleUnallocatedDragStart(event, reservation)}
                  onDragEnd={handleDragEnd}
                >
                  <div>
                    <strong>{reservation.reservation_number}</strong>
                    <span className={`calendar-status-chip ${normalizeStatus(reservation.status)}`}>
                      {labelize(reservation.status)}
                    </span>
                  </div>
                  <h3>{reservation.guest_name || 'Guest'}</h3>
                  <p>{reservation.room_type_name}</p>
                  <small>{formatDate(reservation.start_date)} – {formatDate(reservation.end_date)}</small>
                  <small>{reservation.adults || 0} adult(s), {reservation.children || 0} child(ren)</small>
                  <button
                    type="button"
                    onClick={() => setAllocationModal({ reservation })}
                  >
                    Assign room
                  </button>
                </article>
              ))
            )}
          </div>
        </aside>
      </section>

      <footer className="calendar-pagination">
        <div>
          Rooms {Number(pagination.offset || 0) + (rooms.length ? 1 : 0)}–{Number(pagination.offset || 0) + rooms.length} of {pagination.total_rooms || 0}
        </div>
        <div>
          <button
            type="button"
            disabled={!pagination.has_previous || refreshing}
            onClick={() => setPageOffset(Math.max(0, pageOffset - PAGE_LIMIT))}
          >
            Previous rooms
          </button>
          <button
            type="button"
            disabled={!pagination.has_next || refreshing}
            onClick={() => setPageOffset(pageOffset + PAGE_LIMIT)}
          >
            Next rooms
          </button>
        </div>
      </footer>

      {selectedEvent && (
        <EventDetailsDrawer
          event={selectedEvent}
          roomTypes={roomTypes}
          onClose={() => setSelectedEvent(null)}
          onOpenReservation={(reservationId) =>
            navigateToSection('reservations', { reservationId })
          }
          onOpenStay={(guestSessionId) =>
            navigateToSection('guests', { guestSessionId })
          }
          onReassign={(event) =>
            setAllocationModal({ reservation: {
              reservation_id: event.reservation_id,
              reservation_room_id: event.reservation_room_id,
              reservation_number: event.reservation_number,
              room_type_id: event.room_type_id,
              room_type_name: event.room_type_name,
              room_id: event.room_id,
              room_number: event.room_number,
              start_date: event.start_date,
              end_date: event.end_date,
              updated_at: event.updated_at,
            } })
          }
          onEditBlock={(block) =>
            setBlockModal({ block, initial: createBlockForm({ block }) })
          }
          onBlockStatus={handleBlockStatus}
        />
      )}

      {blockModal && (
        <RoomBlockModal
          rooms={rooms}
          initial={blockModal.initial}
          editingBlock={blockModal.block}
          busy={busyAction}
          onClose={() => setBlockModal(null)}
          onSubmit={handleBlockSubmit}
        />
      )}

      {allocationModal && (
        <AllocationModal
          reservation={allocationModal.reservation}
          rooms={rooms.filter(
            (room) => room.room_type_id === allocationModal.reservation.room_type_id
          )}
          busy={busyAction}
          onClose={() => setAllocationModal(null)}
          onSubmit={handleAllocationSubmit}
        />
      )}
    </div>
  )
}

function EventDetailsDrawer({
  event,
  onClose,
  onOpenReservation,
  onOpenStay,
  onReassign,
  onEditBlock,
  onBlockStatus,
}) {
  const isReservation = event.event_type === 'reservation'
  const isBlock = event.event_type === 'room_block'
  const canMove = isReservation && canMoveReservationEvent(event)

  return (
    <div className="calendar-drawer-backdrop" role="presentation">
      <aside className="calendar-details-drawer" role="dialog" aria-modal="true">
        <header>
          <div>
            <p className="calendar-eyebrow">Quick details</p>
            <h2>
              {isReservation
                ? event.reservation_number
                : isBlock
                  ? `Room ${event.room_number} block`
                  : `Room ${event.room_number} stay`}
            </h2>
          </div>
          <button type="button" onClick={onClose}>×</button>
        </header>

        <div className="calendar-details-body">
          <span className={`calendar-large-status ${eventClass(event)}`}>
            {isReservation
              ? labelize(event.status)
              : isBlock
                ? `${labelize(event.block_type)} · ${labelize(event.status)}`
                : 'Direct Stay'}
          </span>

          <section className="calendar-detail-card">
            {!isBlock && <Detail label="Guest" value={event.guest_name || '—'} />}
            {!isBlock && <Detail label="Phone" value={event.guest_phone || '—'} />}
            <Detail label="Stay" value={`${formatDate(event.start_date, { year: true })} – ${formatDate(event.end_date, { year: true })}`} />
            <Detail label="Room" value={`Room ${event.room_number} · ${event.room_type_name}`} />
            {isReservation && <Detail label="Room status" value={labelize(event.status)} />}
            {isReservation && (
              <Detail
                label="Booking status"
                value={bookingStatusLabel(event)}
              />
            )}
            {!isReservation && !isBlock && (
              <Detail label="Status" value={labelize(event.status || 'checked_in')} wide />
            )}
            {isReservation && <Detail label="Source" value={labelize(event.booking_source)} />}
            {isReservation && <Detail label="Reference" value={event.source_reference || '—'} />}
            {isReservation && <Detail label="Total" value={money(event.total_amount, event.currency_code)} />}
            {isReservation && <Detail label="Deposit" value={money(event.deposit_collected, event.currency_code)} />}
            {isBlock && <Detail label="Reason" value={event.reason} wide />}
            {isBlock && <Detail label="Notes" value={event.notes || '—'} wide />}
            {isBlock && event.release_reason && (
              <Detail
                label={event.status === 'cancelled' ? 'Cancellation reason' : 'Release reason'}
                value={event.release_reason}
                wide
              />
            )}
            {isBlock && <Detail label="Created by" value={event.created_by_name || 'Unknown user'} />}
            {isBlock && <Detail label="Created at" value={formatDateTime(event.created_at)} />}
            {isBlock && <Detail label="Last updated" value={formatDateTime(event.updated_at)} wide />}
            {event.special_requests && <Detail label="Special requests" value={event.special_requests} wide />}
            {event.internal_notes && <Detail label="Internal notes" value={event.internal_notes} wide />}
          </section>
        </div>

        <footer>
          {isReservation && (
            <button type="button" className="secondary" onClick={() => onOpenReservation(event.reservation_id)}>
              Open Reservation
            </button>
          )}
          {canMove && (
            <button type="button" className="primary" onClick={() => onReassign(event)}>
              Reassign / Move
            </button>
          )}
          {!isReservation && !isBlock && (
            <button
              type="button"
              className="primary"
              onClick={() => onOpenStay(event.guest_session_id)}
            >
              Open Guest Stay
            </button>
          )}
          {isBlock && event.status === 'active' && (
            <>
              <button type="button" className="secondary" onClick={() => onEditBlock(event)}>Edit block</button>
              <button type="button" className="primary" onClick={() => onBlockStatus(event, 'released')}>Release</button>
              <button type="button" className="danger" onClick={() => onBlockStatus(event, 'cancelled')}>Cancel</button>
            </>
          )}
        </footer>
      </aside>
    </div>
  )
}

function Detail({ label, value, wide = false }) {
  return (
    <div className={wide ? 'wide' : ''}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

function RoomBlockModal({ rooms, initial, editingBlock, busy, onClose, onSubmit }) {
  const [form, setForm] = useState(initial)
  const [error, setError] = useState('')

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    try {
      if (!form.room_id || !form.start_date || !form.end_date || !form.reason.trim()) {
        throw new Error('Room, dates and reason are required.')
      }
      await onSubmit(form, editingBlock)
    } catch (submitError) {
      setError(submitError.message || 'Unable to save room block.')
    }
  }

  return (
    <div className="calendar-modal-backdrop" role="presentation">
      <form className="calendar-modal" onSubmit={handleSubmit}>
        <header>
          <div>
            <p className="calendar-eyebrow">Inventory restriction</p>
            <h2>{editingBlock ? 'Edit Room Block' : 'Block a Room'}</h2>
          </div>
          <button type="button" onClick={onClose} disabled={busy}>×</button>
        </header>
        <div className="calendar-modal-grid">
          <label>
            <span>Room *</span>
            <select value={form.room_id} onChange={(event) => setForm({ ...form, room_id: event.target.value })}>
              <option value="">Select room</option>
              {rooms.map((room) => <option key={room.id} value={room.id}>Room {room.room_number} · {room.room_type_name}</option>)}
            </select>
          </label>
          <label>
            <span>Block type *</span>
            <select value={form.block_type} onChange={(event) => setForm({ ...form, block_type: event.target.value })}>
              {BLOCK_TYPES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </label>
          <label>
            <span>Start date *</span>
            <input type="date" value={form.start_date} onChange={(event) => setForm({ ...form, start_date: event.target.value })} />
          </label>
          <label>
            <span>End date *</span>
            <input type="date" value={form.end_date} min={addDays(form.start_date || dateInput(new Date()), 1)} onChange={(event) => setForm({ ...form, end_date: event.target.value })} />
          </label>
          <label className="wide">
            <span>Reason *</span>
            <input value={form.reason} onChange={(event) => setForm({ ...form, reason: event.target.value })} placeholder="Maintenance, owner use, deep cleaning…" />
          </label>
          <label className="wide">
            <span>Notes</span>
            <textarea value={form.notes} onChange={(event) => setForm({ ...form, notes: event.target.value })} placeholder="Operational notes for hotel staff" />
          </label>
        </div>
        {error && <div className="calendar-form-error">{error}</div>}
        <footer>
          <button type="button" className="secondary" onClick={onClose} disabled={busy}>Close</button>
          <button type="submit" className="primary" disabled={busy}>{busy ? 'Saving…' : editingBlock ? 'Save Changes' : 'Create Block'}</button>
        </footer>
      </form>
    </div>
  )
}

function AllocationModal({ reservation, rooms, busy, onClose, onSubmit }) {
  const [roomId, setRoomId] = useState(reservation.room_id || '')
  const [arrivalDate, setArrivalDate] = useState(reservation.start_date)
  const [error, setError] = useState('')
  const stayLength = differenceInDays(reservation.start_date, reservation.end_date)
  const calculatedDeparture = arrivalDate
    ? addDays(arrivalDate, stayLength)
    : reservation.end_date
  const isMove = Boolean(reservation.room_id)

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    try {
      if (!roomId || !arrivalDate) throw new Error('Select a target room and arrival date.')
      await onSubmit({ reservation, roomId, arrivalDate })
    } catch (submitError) {
      setError(submitError.message || 'Unable to assign room.')
    }
  }

  return (
    <div className="calendar-modal-backdrop" role="presentation">
      <form className="calendar-modal compact" onSubmit={handleSubmit}>
        <header>
          <div>
            <p className="calendar-eyebrow">Server-validated allocation</p>
            <h2>{reservation.reservation_number}</h2>
          </div>
          <button type="button" onClick={onClose} disabled={busy}>×</button>
        </header>
        <p className="allocation-description">
          {reservation.room_type_name}
          {isMove && reservation.room_number ? ` · Current Room ${reservation.room_number}` : ''}
          {' · '}
          {formatDate(reservation.start_date)} – {formatDate(reservation.end_date)}
        </p>
        <div className="calendar-modal-grid">
          <label className="wide">
            <span>Compatible room *</span>
            <select value={roomId} onChange={(event) => setRoomId(event.target.value)}>
              <option value="">Select room</option>
              {rooms.map((room) => <option key={room.id} value={room.id}>Room {room.room_number} · {room.room_type_name}</option>)}
            </select>
          </label>
          <label className="wide">
            <span>Arrival date *</span>
            <input type="date" value={arrivalDate} onChange={(event) => setArrivalDate(event.target.value)} />
          </label>
          <div className="allocation-summary wide">
            <span>Proposed stay</span>
            <strong>
              {formatDate(arrivalDate, { year: true })} – {formatDate(calculatedDeparture, { year: true })}
            </strong>
            <small>{stayLength} night(s), checkout-exclusive inventory</small>
          </div>
        </div>
        <p className="allocation-warning">Stay length is preserved. If the target dates change the rate, StayQR will reject the move and require Reservation Edit.</p>
        {error && <div className="calendar-form-error">{error}</div>}
        <footer>
          <button type="button" className="secondary" onClick={onClose} disabled={busy}>Close</button>
          <button type="submit" className="primary" disabled={busy}>
            {busy ? 'Validating…' : isMove ? 'Move Reservation' : 'Assign Room'}
          </button>
        </footer>
      </form>
    </div>
  )
}

function CalendarState({ title, message, error = false }) {
  return (
    <div className="calendar-state">
      <div>{error ? '⚠️' : '📅'}</div>
      <h2>{title}</h2>
      <p>{message}</p>
    </div>
  )
}
