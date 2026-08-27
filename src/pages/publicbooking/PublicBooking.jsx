import { useEffect, useMemo, useRef, useState } from 'react'
import {
  createPublicBooking,
  createV11RequestId,
  loadPublicBookingHotel,
  loadPublicBookingOptions,
} from '../../lib/v11Revenue'
import './PublicBooking.css'

function todayInput() {
  const date = new Date()
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset())
  return date.toISOString().slice(0, 10)
}

function addDays(value, days) {
  const date = new Date(`${value}T12:00:00`)
  date.setDate(date.getDate() + days)
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset())
  return date.toISOString().slice(0, 10)
}

function formatMoney(value, currency = 'INR') {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency,
    maximumFractionDigits: 2,
  }).format(Number(value || 0))
}

function hotelSlugFromPath() {
  const parts = window.location.pathname.split('/').filter(Boolean)
  return parts[0] === 'book' ? decodeURIComponent(parts[1] || '') : ''
}

export default function PublicBooking() {
  const hotelSlug = hotelSlugFromPath()
  const query = useMemo(() => new URLSearchParams(window.location.search), [])
  const [hotel, setHotel] = useState(null)
  const [loading, setLoading] = useState(true)
  const [pageError, setPageError] = useState('')
  const [searching, setSearching] = useState(false)
  const [booking, setBooking] = useState(false)
  const [options, setOptions] = useState([])
  const [searchResult, setSearchResult] = useState(null)
  const [selectedOption, setSelectedOption] = useState(null)
  const [confirmation, setConfirmation] = useState(null)
  const [search, setSearch] = useState(() => {
    const arrival = query.get('arrival') || todayInput()
    return {
      arrival_date: arrival,
      departure_date: query.get('departure') || addDays(arrival, 1),
      adults: Number(query.get('adults') || 1),
      children: Number(query.get('children') || 0),
      corporate_code: query.get('corporate') || '',
    }
  })
  const [guest, setGuest] = useState({
    full_name: '',
    phone: '',
    email: '',
    preferred_language: 'english',
    special_requests: '',
    website: '',
  })
  const requestIdRef = useRef(createV11RequestId('public-booking'))

  useEffect(() => {
    let active = true
    async function load() {
      if (!hotelSlug) {
        setPageError('Booking page was not found.')
        setLoading(false)
        return
      }
      try {
        const data = await loadPublicBookingHotel(hotelSlug)
        if (!active) return
        setHotel(data)
        if (!data?.enabled) {
          setPageError('Online booking is not currently enabled for this hotel.')
        }
      } catch (error) {
        if (!active) return
        setPageError(error?.message || 'Unable to load this booking page.')
      } finally {
        if (active) setLoading(false)
      }
    }
    load()
    return () => {
      active = false
    }
  }, [hotelSlug])

  async function handleSearch(event) {
    event?.preventDefault()
    if (!hotel?.enabled) return
    setSearching(true)
    setPageError('')
    setSelectedOption(null)
    setConfirmation(null)
    try {
      const result = await loadPublicBookingOptions({
        hotelSlug,
        arrivalDate: search.arrival_date,
        departureDate: search.departure_date,
        adults: search.adults,
        children: search.children,
        corporateCode: search.corporate_code,
      })
      setSearchResult(result)
      setOptions(result?.items || [])
      if ((result?.items || []).length === 0) {
        setPageError('No rooms are available for these dates and guest counts.')
      }
    } catch (error) {
      setOptions([])
      setSearchResult(null)
      setPageError(error?.message || 'Unable to check availability.')
    } finally {
      setSearching(false)
    }
  }

  async function handleBook(event) {
    event.preventDefault()
    if (!selectedOption || booking) return
    setBooking(true)
    setPageError('')
    try {
      const result = await createPublicBooking({
        hotelSlug,
        requestId: requestIdRef.current,
        payload: {
          arrival_date: search.arrival_date,
          departure_date: search.departure_date,
          adults: Number(search.adults),
          children: Number(search.children),
          room_type_id: selectedOption.room_type_id,
          rate_plan_id: selectedOption.rate_plan_id,
          corporate_code: search.corporate_code.trim() || null,
          special_requests: guest.special_requests.trim() || null,
          guest: {
            full_name: guest.full_name.trim(),
            phone: guest.phone.trim() || null,
            email: guest.email.trim() || null,
            preferred_language: guest.preferred_language,
          },
          website: guest.website,
        },
      })
      setConfirmation(result)
      setOptions([])
      setSelectedOption(null)
      window.scrollTo({ top: 0, behavior: 'smooth' })
    } catch (error) {
      setPageError(error?.message || 'Unable to complete the booking.')
    } finally {
      setBooking(false)
    }
  }

  if (loading) {
    return <div className="public-booking-state">Loading secure booking…</div>
  }

  return (
    <div className="public-booking-page">
      <header className="public-booking-topbar">
        <a href="https://stayqr.in" className="public-booking-brand">StayQR</a>
        <span>Secure direct booking</span>
      </header>

      <main className="public-booking-shell">
        <section className="public-booking-hero">
          <div className="public-booking-hotel-mark">
            {hotel?.logo_url ? <img src={hotel.logo_url} alt={`${hotel.hotel_name} logo`} /> : <span>{hotel?.hotel_name?.charAt(0) || 'S'}</span>}
          </div>
          <div>
            <p>Book direct</p>
            <h1>{hotel?.hotel_name || 'StayQR Hotel'}</h1>
            <span>{[hotel?.city, hotel?.state].filter(Boolean).join(', ')}</span>
          </div>
        </section>

        {hotel?.booking_message && <div className="public-booking-message">{hotel.booking_message}</div>}
        {pageError && <div className="public-booking-alert">{pageError}</div>}

        {confirmation ? (
          <section className="public-booking-confirmation">
            <div className="public-booking-check">✓</div>
            <p>{confirmation.status === 'confirmed' ? 'Booking confirmed' : 'Booking request received'}</p>
            <h2>{confirmation.reservation_number}</h2>
            <div className="public-booking-confirmation-grid">
              <Info label="Hotel" value={confirmation.hotel_name} />
              <Info label="Stay" value={`${confirmation.arrival_date} → ${confirmation.departure_date}`} />
              <Info label="Total" value={formatMoney(confirmation.total_amount, confirmation.currency_code)} />
              <Info label="Deposit required" value={formatMoney(confirmation.deposit_required, confirmation.currency_code)} />
            </div>
            <p className="public-booking-small">Keep your reservation number for hotel communication. Payment, KYC and final check-in remain governed by the hotel&apos;s policies.</p>
          </section>
        ) : (
          <>
            <form className="public-booking-search" onSubmit={handleSearch}>
              <label><span>Check-in</span><input type="date" min={todayInput()} value={search.arrival_date} onChange={(event) => setSearch((current) => ({ ...current, arrival_date: event.target.value, departure_date: event.target.value >= current.departure_date ? addDays(event.target.value, 1) : current.departure_date }))} required /></label>
              <label><span>Check-out</span><input type="date" min={addDays(search.arrival_date, 1)} value={search.departure_date} onChange={(event) => setSearch((current) => ({ ...current, departure_date: event.target.value }))} required /></label>
              <label><span>Adults</span><input type="number" min="1" max="20" value={search.adults} onChange={(event) => setSearch((current) => ({ ...current, adults: event.target.value }))} required /></label>
              <label><span>Children</span><input type="number" min="0" max="10" value={search.children} onChange={(event) => setSearch((current) => ({ ...current, children: event.target.value }))} /></label>
              <label className="corporate-code"><span>Corporate code</span><input value={search.corporate_code} onChange={(event) => setSearch((current) => ({ ...current, corporate_code: event.target.value.toUpperCase() }))} placeholder="Optional" /></label>
              <button type="submit" disabled={searching || !hotel?.enabled}>{searching ? 'Checking…' : 'Check availability'}</button>
            </form>

            {searchResult?.corporate_rate_applied && <div className="public-booking-corporate">Corporate negotiated pricing applied.</div>}

            {options.length > 0 && (
              <section className="public-booking-room-list">
                <div className="public-booking-section-title"><p>Available rooms</p><span>{search.arrival_date} → {search.departure_date}</span></div>
                {options.map((option) => <article key={option.room_type_id} className={`public-booking-room ${selectedOption?.room_type_id === option.room_type_id ? 'selected' : ''}`}><div><p>{option.room_type_name}</p><span>{option.description || `${option.max_occupancy} guest capacity`}</span><small>{option.available_rooms} room(s) available · {option.rate_plan_name}</small>{option.cancellation_policy && <small>{option.cancellation_policy}</small>}</div><div className="public-booking-price"><strong>{formatMoney(option.quote?.total_amount, option.quote?.currency_code)}</strong><span>{option.quote?.nights} night(s)</span>{Number(option.deposit_required || 0) > 0 && <small>{formatMoney(option.deposit_required, option.quote?.currency_code)} deposit</small>}<button type="button" onClick={() => setSelectedOption(option)}>{selectedOption?.room_type_id === option.room_type_id ? 'Selected' : 'Select room'}</button></div></article>)}
              </section>
            )}

            {selectedOption && (
              <form className="public-booking-guest" onSubmit={handleBook}>
                <div className="public-booking-section-title"><p>Guest details</p><span>{selectedOption.room_type_name}</span></div>
                <div className="public-booking-guest-grid">
                  <label><span>Full name</span><input value={guest.full_name} onChange={(event) => setGuest((current) => ({ ...current, full_name: event.target.value }))} autoComplete="name" required /></label>
                  <label><span>Phone</span><input value={guest.phone} onChange={(event) => setGuest((current) => ({ ...current, phone: event.target.value }))} autoComplete="tel" /></label>
                  <label><span>Email</span><input type="email" value={guest.email} onChange={(event) => setGuest((current) => ({ ...current, email: event.target.value }))} autoComplete="email" /></label>
                  <label><span>Language</span><select value={guest.preferred_language} onChange={(event) => setGuest((current) => ({ ...current, preferred_language: event.target.value }))}><option value="english">English</option><option value="hindi">Hindi</option><option value="marathi">Marathi</option><option value="tamil">Tamil</option></select></label>
                  <label className="wide"><span>Special requests</span><textarea rows="3" value={guest.special_requests} onChange={(event) => setGuest((current) => ({ ...current, special_requests: event.target.value }))} placeholder="Optional" /></label>
                  <label className="public-booking-honeypot" aria-hidden="true"><span>Website</span><input tabIndex="-1" autoComplete="off" value={guest.website} onChange={(event) => setGuest((current) => ({ ...current, website: event.target.value }))} /></label>
                </div>
                <div className="public-booking-total"><div><span>Total stay</span><strong>{formatMoney(selectedOption.quote?.total_amount, selectedOption.quote?.currency_code)}</strong></div><button type="submit" disabled={booking || (!guest.phone.trim() && !guest.email.trim())}>{booking ? 'Booking…' : hotel?.confirmation_mode === 'request' ? 'Send booking request' : 'Confirm booking'}</button></div>
                {!guest.phone.trim() && !guest.email.trim() && <small className="public-booking-contact-note">Enter a phone number or email so the hotel can contact you.</small>}
              </form>
            )}
          </>
        )}
      </main>

      <footer className="public-booking-footer">Powered by StayQR · Secure direct hotel booking</footer>
    </div>
  )
}

function Info({ label, value }) {
  return <div><span>{label}</span><strong>{value}</strong></div>
}
