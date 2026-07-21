import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  changeReservationStatus,
  createReservation,
  getAvailableRooms,
  getRateQuote,
  getReservationActivity,
  getReservationConfiguration,
  getReservationDetails,
  listReservations,
  searchGuests,
  updateReservation,
} from '../../lib/reservations'
import {
  notifyCalendarInvalidated,
} from '../../lib/bookingCalendar'
import './Reservations.css'

const ACTIVE_STATUSES = ['draft', 'tentative', 'confirmed']
const STATUS_FILTERS = [
  { value: '', label: 'All statuses' },
  { value: 'draft', label: 'Draft' },
  { value: 'tentative', label: 'Tentative' },
  { value: 'confirmed', label: 'Confirmed' },
  { value: 'checked_in', label: 'Checked In' },
  { value: 'checked_out', label: 'Checked Out' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'no_show', label: 'No Show' },
]

const BOOKING_SOURCES = [
  ['walk_in', 'Walk-in'],
  ['phone', 'Phone'],
  ['website', 'Website'],
  ['ota_manual', 'OTA / Manual'],
  ['travel_agent', 'Travel Agent'],
  ['corporate', 'Corporate'],
  ['repeat_guest', 'Repeat Guest'],
  ['other', 'Other'],
]

const PAYMENT_METHODS = [
  ['cash', 'Cash'],
  ['upi', 'UPI'],
  ['card', 'Card'],
  ['bank_transfer', 'Bank Transfer'],
  ['payment_link', 'Payment Link'],
  ['other', 'Other'],
]

const EMPTY_FILTERS = {
  search: '',
  status: '',
  arrivalFrom: '',
  arrivalTo: '',
}

function toDateInput(date) {
  const copy = new Date(date)
  copy.setMinutes(copy.getMinutes() - copy.getTimezoneOffset())
  return copy.toISOString().slice(0, 10)
}

function addDays(dateValue, days) {
  const date = new Date(`${dateValue}T12:00:00`)
  date.setDate(date.getDate() + days)
  return toDateInput(date)
}

function createInitialForm(mode = 'advance') {
  const today = toDateInput(new Date())
  const arrival = mode === 'walk_in' ? today : addDays(today, 1)

  return {
    mode,
    status: 'confirmed',
    booking_source: mode === 'walk_in' ? 'walk_in' : 'phone',
    source_reference: '',
    arrival_date: arrival,
    departure_date: addDays(arrival, 1),
    expected_checkin_time: mode === 'walk_in' ? '14:00' : '',
    expected_checkout_time: '11:00',
    adults: 1,
    children: 0,
    room_type_id: '',
    rate_plan_id: '',
    room_id: '',
    guest_mode: 'new',
    guest_search: '',
    guest_id: '',
    guest_full_name: '',
    guest_phone: '',
    guest_email: '',
    guest_id_type: '',
    guest_id_number: '',
    preferred_language: 'english',
    deposit_required: '',
    deposit_amount: '',
    additional_deposit_amount: '',
    payment_method: 'cash',
    payment_reference: '',
    payment_notes: '',
    special_requests: '',
    internal_notes: '',
    room_notes: '',
  }
}

export default function Reservations() {
  const [hotel, setHotel] = useState(null)
  const [roomTypes, setRoomTypes] = useState([])
  const [ratePlans, setRatePlans] = useState([])
  const [reservations, setReservations] = useState([])
  const [totalCount, setTotalCount] = useState(0)
  const [loading, setLoading] = useState(true)
  const [listLoading, setListLoading] = useState(false)
  const [pageError, setPageError] = useState('')
  const [notice, setNotice] = useState(null)
  const [filters, setFilters] = useState(EMPTY_FILTERS)
  const [formOpen, setFormOpen] = useState(false)
  const [createKind, setCreateKind] = useState('advance')
  const [formMode, setFormMode] = useState('create')
  const [editingReservation, setEditingReservation] = useState(null)
  const [detailReservation, setDetailReservation] = useState(null)
  const [detailActivity, setDetailActivity] = useState([])
  const [detailLoading, setDetailLoading] = useState(false)
  const statusActionLockRef = useRef(false)

  const showNotice = useCallback((type, message) => {
    setNotice({ type, message })
    window.setTimeout(() => setNotice(null), 5000)
  }, [])

  const loadReservations = useCallback(
    async (hotelId, activeFilters = EMPTY_FILTERS) => {
      if (!hotelId) return
      setListLoading(true)

      try {
        const result = await listReservations({
          hotelId,
          status: activeFilters.status,
          search: activeFilters.search.trim(),
          arrivalFrom: activeFilters.arrivalFrom,
          arrivalTo: activeFilters.arrivalTo,
        })

        setReservations(result.items || [])
        setTotalCount(Number(result.total_count || 0))
      } catch (error) {
        console.error('Reservation list error:', error)
        showNotice('error', error.message || 'Unable to load reservations.')
      } finally {
        setListLoading(false)
      }
    },
    [showNotice]
  )

  useEffect(() => {
    let cancelled = false

    async function initialize() {
      setLoading(true)
      setPageError('')

      try {
        const currentHotel = await getCurrentHotel()
        if (!currentHotel) {
          throw new Error('No active hotel is assigned to this account.')
        }

        const configuration = await getReservationConfiguration(
          currentHotel.id
        )

        if (cancelled) return

        setHotel(currentHotel)
        setRoomTypes(configuration.roomTypes)
        setRatePlans(configuration.ratePlans)
        await loadReservations(currentHotel.id)
      } catch (error) {
        console.error('Reservations initialization error:', error)
        if (!cancelled) {
          setPageError(error.message || 'Unable to initialize Reservations.')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    initialize()

    return () => {
      cancelled = true
    }
  }, [loadReservations])

  const summary = useMemo(() => {
    const today = toDateInput(new Date())
    return {
      confirmed: reservations.filter((item) => item.status === 'confirmed')
        .length,
      arrivals: reservations.filter(
        (item) => item.arrival_date === today && item.status === 'confirmed'
      ).length,
      tentative: reservations.filter((item) => item.status === 'tentative')
        .length,
      depositDue: reservations.reduce(
        (total, item) => total + Number(item.deposit_balance || 0),
        0
      ),
    }
  }, [reservations])

  async function handleFilterSubmit(event) {
    event.preventDefault()
    await loadReservations(hotel?.id, filters)
  }

  function openCreate(mode) {
    setCreateKind(mode)
    setEditingReservation(null)
    setFormMode('create')
    setFormOpen(true)
    setDetailReservation(null)
    setNotice(null)
  }

  async function openDetails(reservationId) {
    setDetailLoading(true)
    setDetailReservation(null)
    setDetailActivity([])

    try {
      const [details, activity] = await Promise.all([
        getReservationDetails(hotel.id, reservationId),
        getReservationActivity(hotel.id, reservationId),
      ])
      setDetailReservation(details)
      setDetailActivity(activity)
    } catch (error) {
      console.error('Reservation details error:', error)
      showNotice('error', error.message || 'Unable to load reservation.')
    } finally {
      setDetailLoading(false)
    }
  }

  async function openEdit(reservation) {
    try {
      const fullDetails =
        reservation.rooms && reservation.status_history
          ? reservation
          : await getReservationDetails(hotel.id, reservation.id)
      setEditingReservation(fullDetails)
      setFormMode('edit')
      setFormOpen(true)
      setDetailReservation(null)
    } catch (error) {
      showNotice('error', error.message || 'Unable to open reservation.')
    }
  }

  async function handleStatusChange(reservation, status) {
    if (statusActionLockRef.current) return

    let reason

    if (status === 'cancelled') {
      reason = window.prompt(
        `Enter the cancellation reason for ${reservation.reservation_number}:`
      )
      if (!reason?.trim()) return
    } else {
      const confirmed = window.confirm(
        `Mark ${reservation.reservation_number} as no-show? This will release its room allocation.`
      )
      if (!confirmed) return
      reason = 'Marked no-show by hotel staff'
    }

    statusActionLockRef.current = true

    try {
      const updated = await changeReservationStatus({
        hotelId: hotel.id,
        reservationId: reservation.id,
        status,
        reason,
      })
      notifyCalendarInvalidated({
        reason: `reservation_${status}`,
        reservationId: reservation.id,
      })
      showNotice(
        'success',
        status === 'cancelled'
          ? 'Reservation cancelled and room released.'
          : 'Reservation marked no-show and room released.'
      )
      await loadReservations(hotel.id, filters)
      if (detailReservation?.id === updated.id) {
        await openDetails(updated.id)
      }
    } catch (error) {
      console.error('Reservation status action error:', error)
      showNotice('error', error.message || 'Unable to update status.')
    } finally {
      statusActionLockRef.current = false
    }
  }

  async function handleFormSuccess(reservation, message) {
    notifyCalendarInvalidated({
      reason: editingReservation ? 'reservation_updated' : 'reservation_created',
      reservationId: reservation.id,
    })
    setFormOpen(false)
    setEditingReservation(null)
    showNotice('success', message)
    await loadReservations(hotel.id, filters)
    await openDetails(reservation.id)
  }

  if (loading) {
    return <PageState title="Reservations" message="Loading hotel inventory…" />
  }

  if (pageError) {
    return <PageState title="Reservations" message={pageError} error />
  }

  return (
    <div className="reservations-page">
      {notice && (
        <div className={`reservation-toast ${notice.type}`}>
          {notice.message}
        </div>
      )}

      <header className="reservations-header">
        <div>
          <p className="reservations-eyebrow">Reservations & Rate Desk</p>
          <h1>Reservations</h1>
          <p>
            {hotel.hotel_name} · Create advance or walk-in bookings, quote live
            rates and control room inventory.
          </p>
        </div>

        <div className="reservations-header-actions">
          <button
            type="button"
            className="reservation-btn secondary"
            onClick={() => openCreate('walk_in')}
          >
            <span>⚡</span> Walk-In
          </button>
          <button
            type="button"
            className="reservation-btn primary"
            onClick={() => openCreate('advance')}
          >
            <span>＋</span> New Reservation
          </button>
        </div>
      </header>

      <section className="reservation-stat-grid">
        <StatCard label="Visible records" value={totalCount} icon="▤" />
        <StatCard label="Confirmed" value={summary.confirmed} icon="✓" />
        <StatCard label="Today's arrivals" value={summary.arrivals} icon="↘" />
        <StatCard label="Deposit pending" value={formatMoney(summary.depositDue, hotel.currency_code)} icon="₹" />
      </section>

      <section className="reservation-panel reservation-filter-panel">
        <form className="reservation-filters" onSubmit={handleFilterSubmit}>
          <label className="reservation-search-field">
            <span>Search</span>
            <input
              value={filters.search}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  search: event.target.value,
                }))
              }
              placeholder="Booking no., guest, phone or email"
            />
          </label>

          <label>
            <span>Status</span>
            <select
              value={filters.status}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  status: event.target.value,
                }))
              }
            >
              {STATUS_FILTERS.map((filter) => (
                <option key={filter.value} value={filter.value}>
                  {filter.label}
                </option>
              ))}
            </select>
          </label>

          <label>
            <span>From</span>
            <input
              type="date"
              value={filters.arrivalFrom}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  arrivalFrom: event.target.value,
                }))
              }
            />
          </label>

          <label>
            <span>To</span>
            <input
              type="date"
              value={filters.arrivalTo}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  arrivalTo: event.target.value,
                }))
              }
            />
          </label>

          <button className="reservation-btn primary compact" type="submit">
            {listLoading ? 'Searching…' : 'Apply'}
          </button>

          <button
            type="button"
            className="reservation-btn ghost compact"
            onClick={() => {
              const cleared = EMPTY_FILTERS
              setFilters(cleared)
              loadReservations(hotel.id, cleared)
            }}
          >
            Clear
          </button>
        </form>
      </section>

      <section className="reservation-panel reservation-list-panel">
        <div className="reservation-panel-heading">
          <div>
            <h2>Booking register</h2>
            <p>Live inventory-backed reservations for the selected hotel.</p>
          </div>
          <button
            type="button"
            className="reservation-icon-button"
            onClick={() => loadReservations(hotel.id, filters)}
            title="Refresh reservations"
          >
            ↻
          </button>
        </div>

        <ReservationTable
          reservations={reservations}
          loading={listLoading}
          currencyCode={hotel.currency_code}
          onDetails={openDetails}
          onEdit={openEdit}
          onStatusChange={handleStatusChange}
        />
      </section>

      {formOpen && (
        <ReservationFormModal
          hotel={hotel}
          mode={formMode}
          initialReservation={editingReservation}
          createMode={createKind}
          roomTypes={roomTypes}
          ratePlans={ratePlans}
          onClose={() => {
            setFormOpen(false)
            setEditingReservation(null)
          }}
          onSuccess={handleFormSuccess}
        />
      )}

      {(detailLoading || detailReservation) && (
        <ReservationDetailDrawer
          reservation={detailReservation}
          activity={detailActivity}
          loading={detailLoading}
          currencyCode={hotel.currency_code}
          onClose={() => setDetailReservation(null)}
          onEdit={openEdit}
          onStatusChange={handleStatusChange}
        />
      )}
    </div>
  )
}

function ReservationFormModal({
  hotel,
  mode,
  initialReservation,
  createMode,
  roomTypes,
  ratePlans,
  onClose,
  onSuccess,
}) {
  const [form, setForm] = useState(() =>
    initialReservation
      ? formFromReservation(initialReservation)
      : createInitialForm(createMode)
  )
  const [guestResults, setGuestResults] = useState([])
  const [guestSearching, setGuestSearching] = useState(false)
  const [availableRooms, setAvailableRooms] = useState([])
  const [availabilityLoading, setAvailabilityLoading] = useState(false)
  const [quote, setQuote] = useState(null)
  const [quoteLoading, setQuoteLoading] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const submissionLockRef = useRef(false)
  const [formError, setFormError] = useState('')
  const [duplicateNotice, setDuplicateNotice] = useState('')

  const isEdit = mode === 'edit'
  const filteredRatePlans = useMemo(
    () =>
      ratePlans.filter(
        (plan) => plan.room_type_id === form.room_type_id
      ),
    [ratePlans, form.room_type_id]
  )

  useEffect(() => {
    if (!form.room_type_id) return

    const compatible = ratePlans.filter(
      (plan) => plan.room_type_id === form.room_type_id
    )
    if (
      compatible.length > 0 &&
      !compatible.some((plan) => plan.id === form.rate_plan_id)
    ) {
      setForm((current) => ({
        ...current,
        rate_plan_id: compatible[0].id,
      }))
    }
  }, [form.room_type_id, form.rate_plan_id, ratePlans])

  useEffect(() => {
    let cancelled = false

    async function loadAvailability() {
      if (
        !form.arrival_date ||
        !form.departure_date ||
        !form.room_type_id ||
        form.departure_date <= form.arrival_date
      ) {
        setAvailableRooms([])
        return
      }

      setAvailabilityLoading(true)
      try {
        const rooms = await getAvailableRooms({
          hotelId: hotel.id,
          arrivalDate: form.arrival_date,
          departureDate: form.departure_date,
          roomTypeId: form.room_type_id,
          excludeReservationId: initialReservation?.id || null,
        })
        if (!cancelled) {
          setAvailableRooms(rooms)
          if (
            form.room_id &&
            !rooms.some((room) => room.room_id === form.room_id)
          ) {
            setForm((current) => ({ ...current, room_id: '' }))
          }
        }
      } catch (error) {
        if (!cancelled) setFormError(error.message)
      } finally {
        if (!cancelled) setAvailabilityLoading(false)
      }
    }

    loadAvailability()
    return () => {
      cancelled = true
    }
  }, [
    form.arrival_date,
    form.departure_date,
    form.room_type_id,
    form.room_id,
    hotel.id,
    initialReservation?.id,
  ])

  useEffect(() => {
    let cancelled = false

    async function loadQuote() {
      if (
        !form.arrival_date ||
        !form.departure_date ||
        !form.rate_plan_id ||
        form.departure_date <= form.arrival_date
      ) {
        setQuote(null)
        return
      }

      setQuoteLoading(true)
      try {
        const result = await getRateQuote({
          hotelId: hotel.id,
          ratePlanId: form.rate_plan_id,
          arrivalDate: form.arrival_date,
          departureDate: form.departure_date,
          adults: Number(form.adults || 1),
          children: Number(form.children || 0),
        })
        if (!cancelled) setQuote(result)
      } catch (error) {
        if (!cancelled) {
          setQuote(null)
          setFormError(error.message)
        }
      } finally {
        if (!cancelled) setQuoteLoading(false)
      }
    }

    loadQuote()
    return () => {
      cancelled = true
    }
  }, [
    form.arrival_date,
    form.departure_date,
    form.rate_plan_id,
    form.adults,
    form.children,
    hotel.id,
  ])

  useEffect(() => {
    if (form.guest_mode !== 'existing' || form.guest_search.trim().length < 2) {
      setGuestResults([])
      return
    }

    let cancelled = false
    const timer = window.setTimeout(async () => {
      setGuestSearching(true)
      try {
        const results = await searchGuests(
          hotel.id,
          form.guest_search.trim(),
          20
        )
        if (!cancelled) setGuestResults(results)
      } catch (error) {
        if (!cancelled) setFormError(error.message)
      } finally {
        if (!cancelled) setGuestSearching(false)
      }
    }, 350)

    return () => {
      cancelled = true
      window.clearTimeout(timer)
    }
  }, [form.guest_mode, form.guest_search, hotel.id])

  function updateField(field, value) {
    setFormError('')
    setDuplicateNotice('')
    setForm((current) => ({ ...current, [field]: value }))
  }

  function switchMode(nextMode) {
    if (isEdit) return
    setForm(createInitialForm(nextMode))
    setQuote(null)
    setAvailableRooms([])
  }

  function selectGuest(guest) {
    setForm((current) => ({
      ...current,
      guest_id: guest.guest_id,
      guest_search: guest.full_name,
      guest_full_name: guest.full_name,
      guest_phone: guest.phone || '',
      guest_email: guest.email || '',
    }))
    setGuestResults([])
  }

  async function resolveGuestPayload() {
    if (form.guest_mode === 'existing') {
      if (!form.guest_id) {
        throw new Error('Select a guest from the search results.')
      }
      return { id: form.guest_id }
    }

    if (!form.guest_full_name.trim()) {
      throw new Error('Guest full name is required.')
    }

    const duplicateKey = form.guest_phone.trim() || form.guest_email.trim()
    if (duplicateKey) {
      const matches = await searchGuests(hotel.id, duplicateKey, 10)
      const exact = matches.find(
        (guest) =>
          (form.guest_phone.trim() &&
            String(guest.phone || '').trim() === form.guest_phone.trim()) ||
          (form.guest_email.trim() &&
            String(guest.email || '').toLowerCase() ===
              form.guest_email.trim().toLowerCase())
      )

      if (exact) {
        setDuplicateNotice(
          `Existing guest found: ${exact.full_name}. StayQR will use this profile to avoid a duplicate guest.`
        )
        return { id: exact.guest_id }
      }
    }

    return {
      full_name: form.guest_full_name.trim(),
      phone: form.guest_phone.trim() || null,
      email: form.guest_email.trim() || null,
      id_type: form.guest_id_type.trim() || null,
      id_number: form.guest_id_number.trim() || null,
      preferred_language: form.preferred_language || 'english',
    }
  }

  async function handleSubmit(event) {
    event.preventDefault()
    if (submissionLockRef.current) return

    submissionLockRef.current = true
    setSubmitting(true)
    setFormError('')

    try {
      if (!form.room_type_id || !form.rate_plan_id) {
        throw new Error('Select a room type and rate plan.')
      }
      if (!form.room_id && form.status !== 'draft') {
        throw new Error('Select an available room.')
      }
      if (!quote) {
        throw new Error('A valid rate quote is required.')
      }

      const guest = await resolveGuestPayload()
      const payload = {
        status: form.status,
        booking_source: form.booking_source,
        source_reference: form.source_reference,
        arrival_date: form.arrival_date,
        departure_date: form.departure_date,
        expected_checkin_time: form.expected_checkin_time,
        expected_checkout_time: form.expected_checkout_time,
        adults: Number(form.adults),
        children: Number(form.children),
        room_type_id: form.room_type_id,
        rate_plan_id: form.rate_plan_id,
        room_id: form.room_id || null,
        guest,
        deposit_required: form.deposit_required || 0,
        payment_method: form.payment_method,
        payment_reference: form.payment_reference,
        payment_notes: form.payment_notes,
        special_requests: form.special_requests,
        internal_notes: form.internal_notes,
        room_notes: form.room_notes,
      }

      let result
      if (isEdit) {
        result = await updateReservation({
          hotelId: hotel.id,
          reservationId: initialReservation.id,
          payload: {
            ...payload,
            additional_deposit_amount:
              form.additional_deposit_amount || 0,
          },
          expectedUpdatedAt: initialReservation.updated_at,
        })
      } else {
        result = await createReservation(hotel.id, {
          ...payload,
          deposit_amount: form.deposit_amount || 0,
        })
      }

      onSuccess(
        result,
        isEdit
          ? `${result.reservation_number} updated successfully.`
          : `${result.reservation_number} created successfully.`
      )
    } catch (error) {
      console.error('Reservation submit error:', error)
      setFormError(error.message || 'Unable to save reservation.')
    } finally {
      submissionLockRef.current = false
      setSubmitting(false)
    }
  }

  return (
    <div className="reservation-modal-backdrop" role="presentation">
      <section className="reservation-modal" role="dialog" aria-modal="true">
        <header className="reservation-modal-header">
          <div>
            <p className="reservations-eyebrow">
              {isEdit ? 'Modify booking' : 'Create booking'}
            </p>
            <h2>
              {isEdit
                ? initialReservation.reservation_number
                : form.mode === 'walk_in'
                  ? 'Walk-In Reservation'
                  : 'Advance Reservation'}
            </h2>
          </div>
          <button
            className="reservation-modal-close"
            type="button"
            onClick={onClose}
            aria-label="Close"
            disabled={submitting}
          >
            ×
          </button>
        </header>

        {!isEdit && (
          <div className="reservation-mode-switch">
            <button
              type="button"
              className={form.mode === 'advance' ? 'active' : ''}
              onClick={() => switchMode('advance')}
            >
              📅 Advance
            </button>
            <button
              type="button"
              className={form.mode === 'walk_in' ? 'active' : ''}
              onClick={() => switchMode('walk_in')}
            >
              ⚡ Walk-In
            </button>
          </div>
        )}

        <form className="reservation-form" onSubmit={handleSubmit}>
          {formError && <div className="reservation-form-error">{formError}</div>}
          {duplicateNotice && (
            <div className="reservation-form-notice">{duplicateNotice}</div>
          )}

          <FormSection title="Stay & booking" subtitle="Dates, source and reservation state">
            <div className="reservation-form-grid four">
              <Field label="Arrival" required>
                <input
                  type="date"
                  value={form.arrival_date}
                  onChange={(event) =>
                    updateField('arrival_date', event.target.value)
                  }
                  required
                />
              </Field>
              <Field label="Departure" required>
                <input
                  type="date"
                  min={addDays(form.arrival_date, 1)}
                  value={form.departure_date}
                  onChange={(event) =>
                    updateField('departure_date', event.target.value)
                  }
                  required
                />
              </Field>
              <Field label="Adults" required>
                <input
                  type="number"
                  min="1"
                  value={form.adults}
                  onChange={(event) => updateField('adults', event.target.value)}
                  required
                />
              </Field>
              <Field label="Children">
                <input
                  type="number"
                  min="0"
                  value={form.children}
                  onChange={(event) =>
                    updateField('children', event.target.value)
                  }
                />
              </Field>
              <Field label="Booking source" required>
                <select
                  value={form.booking_source}
                  onChange={(event) =>
                    updateField('booking_source', event.target.value)
                  }
                >
                  {BOOKING_SOURCES.map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Source reference">
                <input
                  value={form.source_reference}
                  onChange={(event) =>
                    updateField('source_reference', event.target.value)
                  }
                  placeholder="OTA ID, agent ref., campaign"
                />
              </Field>
              {!isEdit && (
                <Field label="Reservation status" required>
                  <select
                    value={form.status}
                    onChange={(event) => updateField('status', event.target.value)}
                  >
                    <option value="confirmed">Confirmed</option>
                    <option value="tentative">Tentative</option>
                    <option value="draft">Draft</option>
                  </select>
                </Field>
              )}
              <Field label="Expected check-in">
                <input
                  type="time"
                  value={form.expected_checkin_time}
                  onChange={(event) =>
                    updateField('expected_checkin_time', event.target.value)
                  }
                />
              </Field>
              <Field label="Expected checkout">
                <input
                  type="time"
                  value={form.expected_checkout_time}
                  onChange={(event) =>
                    updateField('expected_checkout_time', event.target.value)
                  }
                />
              </Field>
            </div>
          </FormSection>

          <FormSection title="Guest" subtitle="Find an existing guest or create a new profile">
            <div className="reservation-subtabs">
              <button
                type="button"
                className={form.guest_mode === 'existing' ? 'active' : ''}
                onClick={() => updateField('guest_mode', 'existing')}
              >
                Existing guest
              </button>
              <button
                type="button"
                className={form.guest_mode === 'new' ? 'active' : ''}
                onClick={() => updateField('guest_mode', 'new')}
              >
                New guest
              </button>
            </div>

            {form.guest_mode === 'existing' ? (
              <div className="reservation-guest-search-wrap">
                <Field label="Search guest" required>
                  <input
                    value={form.guest_search}
                    onChange={(event) => {
                      updateField('guest_search', event.target.value)
                      updateField('guest_id', '')
                    }}
                    placeholder="Name, mobile, email or ID number"
                  />
                </Field>
                {guestSearching && <p className="reservation-inline-help">Searching…</p>}
                {guestResults.length > 0 && (
                  <div className="reservation-guest-results">
                    {guestResults.map((guest) => (
                      <button
                        type="button"
                        key={guest.guest_id}
                        onClick={() => selectGuest(guest)}
                      >
                        <strong>{guest.full_name}</strong>
                        <span>{guest.phone || guest.email || 'No contact saved'}</span>
                        <small>{guest.reservation_count} previous reservation(s)</small>
                      </button>
                    ))}
                  </div>
                )}
                {form.guest_id && (
                  <div className="reservation-selected-guest">
                    ✓ Selected: {form.guest_full_name}
                  </div>
                )}
              </div>
            ) : (
              <div className="reservation-form-grid three">
                <Field label="Full name" required>
                  <input
                    value={form.guest_full_name}
                    onChange={(event) =>
                      updateField('guest_full_name', event.target.value)
                    }
                    placeholder="Guest full name"
                    required
                  />
                </Field>
                <Field label="Mobile number">
                  <input
                    type="tel"
                    value={form.guest_phone}
                    onChange={(event) =>
                      updateField('guest_phone', event.target.value)
                    }
                    placeholder="Mobile number"
                  />
                </Field>
                <Field label="Email">
                  <input
                    type="email"
                    value={form.guest_email}
                    onChange={(event) =>
                      updateField('guest_email', event.target.value)
                    }
                    placeholder="guest@example.com"
                  />
                </Field>
                <Field label="ID type">
                  <select
                    value={form.guest_id_type}
                    onChange={(event) =>
                      updateField('guest_id_type', event.target.value)
                    }
                  >
                    <option value="">Not captured</option>
                    <option value="aadhaar">Aadhaar</option>
                    <option value="passport">Passport</option>
                    <option value="driving_license">Driving Licence</option>
                    <option value="voter_id">Voter ID</option>
                    <option value="other">Other</option>
                  </select>
                </Field>
                <Field label="ID number">
                  <input
                    value={form.guest_id_number}
                    onChange={(event) =>
                      updateField('guest_id_number', event.target.value)
                    }
                    placeholder="Identity document number"
                  />
                </Field>
                <Field label="Language">
                  <select
                    value={form.preferred_language}
                    onChange={(event) =>
                      updateField('preferred_language', event.target.value)
                    }
                  >
                    <option value="english">English</option>
                    <option value="hindi">Hindi</option>
                    <option value="marathi">Marathi</option>
                  </select>
                </Field>
              </div>
            )}
          </FormSection>

          <FormSection title="Room & rate" subtitle="Live availability and seasonal quotation">
            <div className="reservation-form-grid three">
              <Field label="Room type" required>
                <select
                  value={form.room_type_id}
                  onChange={(event) => {
                    updateField('room_type_id', event.target.value)
                    updateField('room_id', '')
                  }}
                  required
                >
                  <option value="">Select room type</option>
                  {roomTypes.map((roomType) => (
                    <option key={roomType.id} value={roomType.id}>
                      {roomType.name} · up to {roomType.max_occupancy}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Rate plan" required>
                <select
                  value={form.rate_plan_id}
                  onChange={(event) =>
                    updateField('rate_plan_id', event.target.value)
                  }
                  required
                  disabled={!form.room_type_id}
                >
                  <option value="">Select rate plan</option>
                  {filteredRatePlans.map((plan) => (
                    <option key={plan.id} value={plan.id}>
                      {plan.name} · {formatMoney(plan.base_rate, plan.currency_code)}
                    </option>
                  ))}
                </select>
              </Field>
              <Field
                label={`Available room${availableRooms.length === 1 ? '' : 's'}`}
                required={form.status !== 'draft'}
                hint={
                  availabilityLoading
                    ? 'Checking inventory…'
                    : `${availableRooms.length} room(s) available`
                }
              >
                <select
                  value={form.room_id}
                  onChange={(event) => updateField('room_id', event.target.value)}
                  disabled={availabilityLoading || !form.room_type_id}
                >
                  <option value="">
                    {form.status === 'draft'
                      ? 'Leave unassigned'
                      : 'Select available room'}
                  </option>
                  {availableRooms.map((room) => (
                    <option key={room.room_id} value={room.room_id}>
                      Room {room.room_number}
                    </option>
                  ))}
                </select>
              </Field>
            </div>

            <RateQuoteCard quote={quote} loading={quoteLoading} />
          </FormSection>

          <FormSection title="Deposit" subtitle="Requirement and collection at reservation stage">
            <div className="reservation-form-grid three">
              <Field label="Deposit required">
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={form.deposit_required}
                  onChange={(event) =>
                    updateField('deposit_required', event.target.value)
                  }
                  placeholder="0.00"
                />
              </Field>
              <Field label={isEdit ? 'Collect additional' : 'Collect now'}>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={
                    isEdit
                      ? form.additional_deposit_amount
                      : form.deposit_amount
                  }
                  onChange={(event) =>
                    updateField(
                      isEdit
                        ? 'additional_deposit_amount'
                        : 'deposit_amount',
                      event.target.value
                    )
                  }
                  placeholder="0.00"
                />
              </Field>
              <Field label="Payment method">
                <select
                  value={form.payment_method}
                  onChange={(event) =>
                    updateField('payment_method', event.target.value)
                  }
                >
                  {PAYMENT_METHODS.map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Transaction reference">
                <input
                  value={form.payment_reference}
                  onChange={(event) =>
                    updateField('payment_reference', event.target.value)
                  }
                  placeholder="UPI ref., card trace, link ID"
                />
              </Field>
              <Field label="Payment note" className="span-two">
                <input
                  value={form.payment_notes}
                  onChange={(event) =>
                    updateField('payment_notes', event.target.value)
                  }
                  placeholder="Optional collection note"
                />
              </Field>
            </div>
          </FormSection>

          <FormSection title="Notes" subtitle="Guest-facing requests and internal hotel notes">
            <div className="reservation-form-grid two">
              <Field label="Special requests">
                <textarea
                  value={form.special_requests}
                  onChange={(event) =>
                    updateField('special_requests', event.target.value)
                  }
                  placeholder="Airport pickup, accessibility, celebration setup…"
                />
              </Field>
              <Field label="Internal notes">
                <textarea
                  value={form.internal_notes}
                  onChange={(event) =>
                    updateField('internal_notes', event.target.value)
                  }
                  placeholder="Visible only to hotel staff"
                />
              </Field>
              <Field label="Room allocation note" className="span-two">
                <input
                  value={form.room_notes}
                  onChange={(event) =>
                    updateField('room_notes', event.target.value)
                  }
                  placeholder="Preference or operational note"
                />
              </Field>
            </div>
          </FormSection>

          <footer className="reservation-modal-footer">
            <div className="reservation-submit-summary">
              <span>{quote?.nights || 0} night(s)</span>
              <strong>
                {formatMoney(
                  quote?.total_amount || 0,
                  quote?.currency_code || hotel.currency_code
                )}
              </strong>
            </div>
            <button
              type="button"
              className="reservation-btn ghost"
              onClick={onClose}
              disabled={submitting}
            >
              Close
            </button>
            <button
              type="submit"
              className="reservation-btn primary"
              disabled={submitting || quoteLoading || availabilityLoading}
            >
              {submitting
                ? 'Saving…'
                : isEdit
                  ? 'Save Changes'
                  : 'Create Reservation'}
            </button>
          </footer>
        </form>
      </section>
    </div>
  )
}

function ReservationTable({
  reservations,
  loading,
  currencyCode,
  onDetails,
  onEdit,
  onStatusChange,
}) {
  if (loading && reservations.length === 0) {
    return <div className="reservation-empty">Loading reservations…</div>
  }

  if (reservations.length === 0) {
    return (
      <div className="reservation-empty">
        <span>📅</span>
        <h3>No reservations found</h3>
        <p>Create a booking or adjust the filters.</p>
      </div>
    )
  }

  return (
    <div className="reservation-table-wrap">
      <table className="reservation-table">
        <thead>
          <tr>
            <th>Reservation</th>
            <th>Guest</th>
            <th>Stay</th>
            <th>Room</th>
            <th>Status</th>
            <th>Amount</th>
            <th>Deposit</th>
            <th aria-label="Actions" />
          </tr>
        </thead>
        <tbody>
          {reservations.map((reservation) => {
            const room = reservation.rooms?.[0]
            const editable = ACTIVE_STATUSES.includes(reservation.status)
            const canNoShow = ['tentative', 'confirmed'].includes(
              reservation.status
            )

            return (
              <tr key={reservation.id}>
                <td>
                  <button
                    type="button"
                    className="reservation-number-link"
                    onClick={() => onDetails(reservation.id)}
                  >
                    {reservation.reservation_number}
                  </button>
                  <small>{formatSource(reservation.booking_source)}</small>
                </td>
                <td>
                  <strong>{reservation.guest?.full_name || 'Guest not set'}</strong>
                  <small>
                    {reservation.guest?.phone ||
                      reservation.guest?.email ||
                      'No contact'}
                  </small>
                </td>
                <td>
                  <strong>{formatDate(reservation.arrival_date)}</strong>
                  <small>to {formatDate(reservation.departure_date)}</small>
                </td>
                <td>
                  <strong>{room?.room_number ? `Room ${room.room_number}` : 'Unassigned'}</strong>
                  <small>{room?.room_type_name || 'Room type unavailable'}</small>
                </td>
                <td>
                  <StatusBadge status={reservation.status} />
                </td>
                <td>
                  <strong>{formatMoney(reservation.total_amount, currencyCode)}</strong>
                  <small>{reservation.adults} adult(s), {reservation.children} child</small>
                </td>
                <td>
                  <strong>{formatMoney(reservation.deposit_collected, currencyCode)}</strong>
                  <small>
                    {Number(reservation.deposit_balance || 0) > 0
                      ? `${formatMoney(reservation.deposit_balance, currencyCode)} due`
                      : 'No balance'}
                  </small>
                </td>
                <td>
                  <div className="reservation-row-actions">
                    <button type="button" onClick={() => onDetails(reservation.id)} title="View details">👁</button>
                    {editable && (
                      <button type="button" onClick={() => onEdit(reservation)} title="Edit reservation">✎</button>
                    )}
                    {editable && (
                      <button type="button" onClick={() => onStatusChange(reservation, 'cancelled')} title="Cancel reservation">×</button>
                    )}
                    {canNoShow && (
                      <button type="button" onClick={() => onStatusChange(reservation, 'no_show')} title="Mark no-show">!</button>
                    )}
                  </div>
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

function ReservationDetailDrawer({
  reservation,
  activity,
  loading,
  currencyCode,
  onClose,
  onEdit,
  onStatusChange,
}) {
  const visibleActivity = useMemo(
    () => activity.filter((log) => !isNoOpReservationUpdate(log)),
    [activity]
  )

  return (
    <div className="reservation-drawer-backdrop" role="presentation">
      <aside className="reservation-drawer">
        <header className="reservation-drawer-header">
          <div>
            <p className="reservations-eyebrow">Reservation details</p>
            <h2>{reservation?.reservation_number || 'Loading…'}</h2>
          </div>
          <button type="button" onClick={onClose} aria-label="Close">×</button>
        </header>

        {loading || !reservation ? (
          <div className="reservation-drawer-loading">Loading complete booking record…</div>
        ) : (
          <div className="reservation-drawer-content">
            <div className="reservation-detail-hero">
              <div>
                <StatusBadge status={reservation.status} />
                <h3>{reservation.guest?.full_name}</h3>
                <p>{reservation.guest?.phone || reservation.guest?.email || 'No contact saved'}</p>
              </div>
              <div className="reservation-detail-total">
                <span>Total</span>
                <strong>{formatMoney(reservation.total_amount, currencyCode)}</strong>
                <small>{formatMoney(reservation.deposit_collected, currencyCode)} collected</small>
              </div>
            </div>

            <DetailGrid reservation={reservation} currencyCode={currencyCode} />

            {reservation.status === 'cancelled' && (
              <section className="reservation-detail-section">
                <h3>Cancellation</h3>
                <div className="reservation-status-reason danger">
                  <span>Reason</span>
                  <strong>
                    {reservation.cancellation_reason ||
                      'No cancellation reason was recorded.'}
                  </strong>
                  {reservation.cancelled_at && (
                    <small>{formatDateTime(reservation.cancelled_at)}</small>
                  )}
                </div>
              </section>
            )}

            {reservation.status === 'no_show' && (
              <section className="reservation-detail-section">
                <h3>No-show record</h3>
                <div className="reservation-status-reason warning">
                  <span>Room allocation</span>
                  <strong>Released after the reservation was marked no-show.</strong>
                  {reservation.no_show_at && (
                    <small>{formatDateTime(reservation.no_show_at)}</small>
                  )}
                </div>
              </section>
            )}

            <section className="reservation-detail-section">
              <h3>Notes</h3>
              <div className="reservation-note-grid">
                <div>
                  <span>Special requests</span>
                  <p>{reservation.special_requests || 'None'}</p>
                </div>
                <div>
                  <span>Internal notes</span>
                  <p>{reservation.internal_notes || 'None'}</p>
                </div>
              </div>
            </section>

            <section className="reservation-detail-section">
              <h3>Deposit history</h3>
              {reservation.payments?.length ? (
                <div className="reservation-payment-list">
                  {reservation.payments.map((payment) => (
                    <div key={payment.id}>
                      <span>{formatSource(payment.payment_method)}</span>
                      <strong>{formatMoney(payment.amount, currencyCode)}</strong>
                      <small>{formatDateTime(payment.collected_at)}</small>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="reservation-muted">No reservation-stage payment collected.</p>
              )}
            </section>

            <section className="reservation-detail-section">
              <h3>Activity</h3>
              <div className="reservation-timeline">
                {visibleActivity.length > 0
                  ? visibleActivity.map((log) => (
                      <div className="reservation-timeline-item" key={log.id}>
                        <span className="reservation-timeline-dot" />
                        <div>
                          <strong>{formatActivity(log.action)}</strong>
                          <p>{log.description || 'Reservation activity recorded.'}</p>
                          <small>{formatDateTime(log.created_at)} · {formatSource(log.actor_role)}</small>
                        </div>
                      </div>
                    ))
                  : reservation.status_history?.map((history) => (
                      <div className="reservation-timeline-item" key={history.id}>
                        <span className="reservation-timeline-dot" />
                        <div>
                          <strong>{formatSource(history.new_status)}</strong>
                          <p>{history.reason || 'Reservation status updated.'}</p>
                          <small>{formatDateTime(history.created_at)}</small>
                        </div>
                      </div>
                    ))}
              </div>
            </section>
          </div>
        )}

        {reservation && (
          <footer className="reservation-drawer-footer">
            {ACTIVE_STATUSES.includes(reservation.status) && (
              <button className="reservation-btn secondary" type="button" onClick={() => onEdit(reservation)}>
                Edit
              </button>
            )}
            {ACTIVE_STATUSES.includes(reservation.status) && (
              <button className="reservation-btn danger" type="button" onClick={() => onStatusChange(reservation, 'cancelled')}>
                Cancel
              </button>
            )}
            {['tentative', 'confirmed'].includes(reservation.status) && (
              <button className="reservation-btn ghost" type="button" onClick={() => onStatusChange(reservation, 'no_show')}>
                Mark No-Show
              </button>
            )}
          </footer>
        )}
      </aside>
    </div>
  )
}

function DetailGrid({ reservation, currencyCode }) {
  const room = reservation.rooms?.[0]
  return (
    <section className="reservation-detail-grid">
      <DetailItem label="Stay" value={`${formatDate(reservation.arrival_date)} → ${formatDate(reservation.departure_date)}`} />
      <DetailItem label="Room" value={room?.room_number ? `Room ${room.room_number} · ${room.room_type_name}` : 'Unassigned'} />
      <DetailItem label="Rate plan" value={room?.rate_plan_name || 'Not selected'} />
      <DetailItem label="Guests" value={`${reservation.adults} adult(s), ${reservation.children} child`} />
      <DetailItem label="Source" value={formatSource(reservation.booking_source)} />
      <DetailItem label="Source reference" value={reservation.source_reference || '—'} />
      <DetailItem label="Room subtotal" value={formatMoney(reservation.room_subtotal, currencyCode)} />
      <DetailItem label="Deposit balance" value={formatMoney(reservation.deposit_balance, currencyCode)} />
    </section>
  )
}

function RateQuoteCard({ quote, loading }) {
  if (loading) {
    return <div className="reservation-rate-card loading">Calculating seasonal rate…</div>
  }
  if (!quote) {
    return <div className="reservation-rate-card empty">Select valid dates and a rate plan to calculate the stay amount.</div>
  }

  return (
    <div className="reservation-rate-card">
      <div>
        <span>Quoted stay</span>
        <strong>{quote.nights} night(s)</strong>
      </div>
      <div>
        <span>Average nightly</span>
        <strong>{formatMoney(quote.average_nightly_rate, quote.currency_code)}</strong>
      </div>
      <div>
        <span>Room subtotal</span>
        <strong>{formatMoney(quote.room_subtotal, quote.currency_code)}</strong>
      </div>
      <div className="total">
        <span>Total</span>
        <strong>{formatMoney(quote.total_amount, quote.currency_code)}</strong>
      </div>
      {quote.nightly_breakdown?.some((night) => night.rate_source === 'seasonal') && (
        <p>Seasonal pricing applied to one or more nights.</p>
      )}
    </div>
  )
}

function FormSection({ title, subtitle, children }) {
  return (
    <section className="reservation-form-section">
      <header>
        <h3>{title}</h3>
        <p>{subtitle}</p>
      </header>
      {children}
    </section>
  )
}

function Field({ label, hint, required, className = '', children }) {
  return (
    <label className={`reservation-field ${className}`}>
      <span>
        {label} {required && <em>*</em>}
      </span>
      {children}
      {hint && <small>{hint}</small>}
    </label>
  )
}

function StatCard({ label, value, icon }) {
  return (
    <article className="reservation-stat-card">
      <span className="reservation-stat-icon">{icon}</span>
      <div>
        <p>{label}</p>
        <strong>{value}</strong>
      </div>
    </article>
  )
}

function StatusBadge({ status }) {
  return (
    <span className={`reservation-status ${status}`}>
      {formatSource(status)}
    </span>
  )
}

function DetailItem({ label, value }) {
  return (
    <div>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

function PageState({ title, message, error = false }) {
  return (
    <div className="reservations-page">
      <section className={`reservation-page-state ${error ? 'error' : ''}`}>
        <span>{error ? '⚠' : '◌'}</span>
        <h1>{title}</h1>
        <p>{message}</p>
      </section>
    </div>
  )
}

function formFromReservation(reservation) {
  const base = createInitialForm('advance')
  const room = reservation.rooms?.[0] || {}
  return {
    ...base,
    mode: reservation.booking_source === 'walk_in' ? 'walk_in' : 'advance',
    status: reservation.status,
    booking_source: reservation.booking_source,
    source_reference: reservation.source_reference || '',
    arrival_date: reservation.arrival_date,
    departure_date: reservation.departure_date,
    expected_checkin_time: reservation.expected_checkin_time || '',
    expected_checkout_time: reservation.expected_checkout_time || '',
    adults: reservation.adults,
    children: reservation.children,
    room_type_id: room.room_type_id || '',
    rate_plan_id: room.rate_plan_id || '',
    room_id: room.room_id || '',
    guest_mode: 'existing',
    guest_search: reservation.guest?.full_name || '',
    guest_id: reservation.guest?.id || '',
    guest_full_name: reservation.guest?.full_name || '',
    guest_phone: reservation.guest?.phone || '',
    guest_email: reservation.guest?.email || '',
    guest_id_type: reservation.guest?.id_type || '',
    guest_id_number: reservation.guest?.id_number || '',
    preferred_language: reservation.guest?.preferred_language || 'english',
    deposit_required: reservation.deposit_required || '',
    deposit_amount: '',
    additional_deposit_amount: '',
    payment_method: 'cash',
    payment_reference: '',
    payment_notes: '',
    special_requests: reservation.special_requests || '',
    internal_notes: reservation.internal_notes || '',
    room_notes: room.notes || '',
  }
}

function normalizeActivitySnapshot(value) {
  if (Array.isArray(value)) {
    return value.map(normalizeActivitySnapshot)
  }

  if (!value || typeof value !== 'object') return value

  return Object.keys(value)
    .sort()
    .reduce((result, key) => {
      if (['updated_at', 'updated_by', 'status_history'].includes(key)) {
        return result
      }

      result[key] = normalizeActivitySnapshot(value[key])
      return result
    }, {})
}

function isNoOpReservationUpdate(log) {
  if (log?.action !== 'reservation.updated') return false
  if (!log.before_data || !log.after_data) return false

  return (
    JSON.stringify(normalizeActivitySnapshot(log.before_data)) ===
    JSON.stringify(normalizeActivitySnapshot(log.after_data))
  )
}

function formatMoney(value, currencyCode = 'INR') {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: currencyCode || 'INR',
    maximumFractionDigits: 2,
  }).format(Number(value || 0))
}

function formatDate(value) {
  if (!value) return '—'
  return new Date(`${value}T12:00:00`).toLocaleDateString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
}

function formatDateTime(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function formatSource(value) {
  return String(value || '—')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}

function formatActivity(action) {
  return formatSource(String(action || '').replace('reservation.', ''))
}
