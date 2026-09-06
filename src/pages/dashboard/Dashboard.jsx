import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import { getHotelDateKey, summarizeDashboardFoodOrders } from '../../lib/dashboardAnalytics'
import HotelOverviewCard from '../../components/cards/HotelOverviewCard'
import RoomsTable from '../../components/table/RoomsTable'
import QuickActions from '../../components/buttons/QuickActions'
import AddRoomModal from '../../components/modals/AddRoomModal'
import ActivationScore from '../../components/cards/ActivationScore'
import './Dashboard.css'

const EMPTY_ANALYTICS = {
  totalRooms: 0,
  availableRooms: 0,
  occupiedRooms: 0,
  cleaningRooms: 0,
  totalGuests: 0,
  activeGuests: 0,
  pendingRequests: 0,
  todayOrders: 0,
  todayRevenue: 0,
  checkInsToday: 0,
  checkOutsDue: 0,
}

export default function Dashboard({ hotel = null, staff = null, onNavigate }) {
  const [rooms, setRooms] = useState([])
  const [currentHotel, setCurrentHotel] = useState(hotel)
  const [analytics, setAnalytics] = useState(EMPTY_ANALYTICS)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [lastFetch, setLastFetch] = useState(null)
  const [showAddRoomModal, setShowAddRoomModal] = useState(false)
  const requestSequence = useRef(0)

  const fetchDashboardData = useCallback(async () => {
    const requestId = requestSequence.current + 1
    requestSequence.current = requestId

    setLoading(true)
    setError(null)

    try {
      const resolvedHotel = hotel || (await getCurrentHotel())

      if (!resolvedHotel?.id) {
        throw new Error('No hotel assigned to current user')
      }

      const hotelId = resolvedHotel.id

      const [
        roomsResult,
        guestsResult,
        guestSessionsResult,
        requestsResult,
        foodOrdersResult,
      ] = await Promise.all([
        supabase
          .from('rooms')
          .select('*')
          .eq('hotel_id', hotelId)
          .order('room_number', { ascending: true }),
        supabase
          .from('guests')
          .select('*', { count: 'exact', head: true })
          .eq('hotel_id', hotelId),
        supabase
          .from('guest_sessions')
          .select('id, status, checkin_time, checkout_time, extended_until')
          .eq('hotel_id', hotelId),
        supabase
          .from('service_requests')
          .select('*', { count: 'exact', head: true })
          .eq('hotel_id', hotelId)
          .eq('status', 'pending'),
        supabase
          .from('food_orders')
          .select('hotel_id, total_amount, created_at, order_status')
          .eq('hotel_id', hotelId),
      ])

      const firstError = [
        roomsResult.error,
        guestsResult.error,
        guestSessionsResult.error,
        requestsResult.error,
        foodOrdersResult.error,
      ].find(Boolean)

      if (firstError) throw firstError
      if (requestSequence.current !== requestId) return

      const roomsData = roomsResult.data || []
      const guestSessions = guestSessionsResult.data || []
      const foodOrders = foodOrdersResult.data || []
      const timeZone = resolvedHotel.timezone || 'Asia/Kolkata'
      const todayKey = getHotelDateKey(new Date(), timeZone)
      const { todayOrders, todayRevenue } = summarizeDashboardFoodOrders(foodOrders, { hotelId, timeZone })

      const activeSessions = guestSessions.filter(
        (session) => session.status === 'active'
      )

      const checkInsToday = guestSessions.filter(
        (session) => getHotelDateKey(session.checkin_time, timeZone) === todayKey
      ).length

      const checkOutsDue = activeSessions.filter((session) => {
        const effectiveCheckout = session.extended_until || session.checkout_time
        return getHotelDateKey(effectiveCheckout, timeZone) === todayKey
      }).length

      const nextAnalytics = {
        totalRooms: roomsData.length,
        availableRooms: roomsData.filter((room) => room.status === 'available').length,
        occupiedRooms: roomsData.filter((room) => room.status === 'occupied').length,
        cleaningRooms: roomsData.filter((room) => room.status === 'cleaning').length,
        totalGuests: guestsResult.count || 0,
        activeGuests: activeSessions.length,
        pendingRequests: requestsResult.count || 0,
        todayOrders,
        todayRevenue,
        checkInsToday,
        checkOutsDue,
      }

      setCurrentHotel(resolvedHotel)
      setRooms(roomsData)
      setAnalytics(nextAnalytics)
      setLastFetch(new Date())
    } catch (fetchError) {
      if (requestSequence.current !== requestId) return
      console.error('[Dashboard] Fetch error:', fetchError)
      setRooms([])
      setAnalytics(EMPTY_ANALYTICS)
      setError(fetchError?.message || 'Failed to fetch dashboard data')
    } finally {
      if (requestSequence.current === requestId) {
        setLoading(false)
      }
    }
  }, [hotel])

  useEffect(() => {
    setCurrentHotel(hotel)
    setRooms([])
    setAnalytics(EMPTY_ANALYTICS)
    setLastFetch(null)
    fetchDashboardData()
  }, [hotel, fetchDashboardData])

  const handleAction = (actionId) => {
    if (actionId === 'addroom') {
      setShowAddRoomModal(true)
      return
    }

    if (actionId === 'checkin') {
      onNavigate?.('checkin')
      return
    }

    if (actionId === 'generateqr') {
      onNavigate?.('qr')
      return
    }

    if (actionId === 'guests') {
      onNavigate?.('guests')
      return
    }

    if (actionId === 'support') {
      onNavigate?.('operationscenter', { initialTab: 'support' })
      return
    }

    if (actionId === 'reportissue') {
      onNavigate?.('operationscenter', {
        initialTab: 'support',
        initialAction: 'create-ticket',
      })
      return
    }

    alert(`Action: ${actionId}`)
  }

  return (
    <div className="dashboard-page">
      {showAddRoomModal && (
        <AddRoomModal
          hotelId={currentHotel?.id}
          onClose={() => setShowAddRoomModal(false)}
          onSuccess={fetchDashboardData}
        />
      )}

      <div className="dash-page-header">
        <div>
          <h1 className="dash-page-title">
            Good {getTimeOfDay()}, <span className="gold-text">{getGreetingName(staff)}</span> 👋
          </h1>

          <p className="dash-page-sub">
            <span className="dash-page-sub-copy">
              Here&apos;s what&apos;s happening at {currentHotel?.hotel_name || 'your hotel'} today
            </span>
            {lastFetch && (
              <span className="last-fetch">
                Last updated {formatTime(lastFetch)}
              </span>
            )}
          </p>
        </div>

        <div className="dash-header-actions">
          <button
            className="dash-refresh-btn"
            onClick={fetchDashboardData}
            disabled={loading}
            type="button"
          >
            <RefreshIcon spinning={loading} />
            {loading ? 'Syncing...' : 'Refresh'}
          </button>
        </div>
      </div>

      <section className="dash-section">
        <HotelOverviewCard
          hotel={currentHotel}
          analytics={analytics}
          loading={loading}
        />
      </section>

      <section className="dash-section">
        <ActivationScore
          hotelId={currentHotel?.id}
          onNavigate={onNavigate}
          refreshKey={lastFetch?.getTime?.() || 0}
        />
      </section>

      <section className="dash-section">
        <div style={analyticsGrid}>
          <AnalyticsCard title="Total Rooms" value={analytics.totalRooms} type="rooms" />
          <AnalyticsCard title="Available Rooms" value={analytics.availableRooms} type="available" />
          <AnalyticsCard title="Occupied Rooms" value={analytics.occupiedRooms} type="occupied" />
          <AnalyticsCard title="Cleaning Rooms" value={analytics.cleaningRooms} type="cleaning" />
          <AnalyticsCard title="Total Guests" value={analytics.totalGuests} type="guests" />
          <AnalyticsCard title="Active Guests" value={analytics.activeGuests} type="active" />
          <AnalyticsCard title="Pending Requests" value={analytics.pendingRequests} type="requests" />
          <AnalyticsCard title="Food Orders Today" value={analytics.todayOrders} type="food" />
          <AnalyticsCard
            title="Food Revenue Today"
            detail="Delivered orders placed today; not cash collected."
            value={formatCurrency(analytics.todayRevenue, currentHotel?.currency_code)}
            type="revenue"
          />
        </div>
      </section>

      <section className="dash-section dash-main-grid">
        <div className="dash-actions-col">
          <QuickActions onAction={handleAction} />
        </div>
      </section>

      <section className="dash-section dash-support-panel glass-card gold-border" aria-label="StayQR support">
        <div>
          <p className="dash-support-kicker">STAYQR SUPPORT</p>
          <h2>Need assistance?</h2>
          <p>Submit support requests anytime. Critical incidents can be escalated to the StayQR team based on operational impact.</p>
        </div>
        <div className="dash-support-actions">
          <button
            type="button"
            onClick={() => onNavigate?.('operationscenter')}
          >
            Operations Centre
          </button>
          <button
            type="button"
            onClick={() => onNavigate?.('operationscenter', {
              initialTab: 'support',
              initialAction: 'create-ticket',
            })}
          >
            Report an issue
          </button>
        </div>
      </section>

      <section className="dash-section">
        <RoomsTable
          rooms={rooms}
          loading={loading}
          error={error}
          onRefresh={fetchDashboardData}
        />
      </section>

    </div>
  )
}

function AnalyticsCard({ title, value, type, detail }) {
  return (
    <article style={analyticsCard} className="dash-metric-card">
      <div style={analyticsIcon} className={`dash-metric-icon dash-metric-icon-${type || 'default'}`}>
        <MetricIcon type={type} />
      </div>
      <div className="dash-metric-copy">
        <p style={analyticsTitle}>{title}</p>
        <h3 style={analyticsValue}>{value}</h3>
        {detail && <small className="dash-metric-detail">{detail}</small>}
      </div>
    </article>
  )
}

function MetricIcon({ type }) {
  const common = { width: 19, height: 19, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.9, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true }
  if (type === 'rooms') return <svg {...common}><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h.01M16 7h.01M8 11h.01M16 11h.01M8 15h8M9 21v-3h6v3"/></svg>
  if (type === 'available') return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/></svg>
  if (type === 'occupied') return <svg {...common}><path d="M3 18v-6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v6"/><path d="M5 10V7a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3M12 10V7a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3M3 18h18"/></svg>
  if (type === 'cleaning') return <svg {...common}><path d="m4 20 5-5"/><path d="m14.5 3.5 6 6-9 9-6-6 9-9Z"/><path d="m5.5 12.5-2 2 6 6 2-2"/></svg>
  if (type === 'guests') return <svg {...common}><circle cx="9" cy="8" r="3"/><path d="M3 20v-1a6 6 0 0 1 12 0v1"/><path d="M16 5a3 3 0 0 1 0 6M18 14a5 5 0 0 1 3 5v1"/></svg>
  if (type === 'active') return <svg {...common}><path d="M3 18v-7h18v7"/><path d="M5 11V7h5a2 2 0 0 1 2 2v2M12 11V8h5a2 2 0 0 1 2 2v1M3 18h18"/></svg>
  if (type === 'requests') return <svg {...common}><path d="M4 13a8 8 0 0 1 16 0"/><path d="M4 13v4a2 2 0 0 0 2 2h2v-7H6a2 2 0 0 0-2 1ZM20 13v4a2 2 0 0 1-2 2h-2v-7h2a2 2 0 0 1 2 1Z"/></svg>
  if (type === 'food') return <svg {...common}><path d="M7 3v8M10 3v8M7 7h3M8.5 11v10M16 3v18M16 3c3 2 4 5 4 8h-4"/></svg>
  if (type === 'revenue') return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M8 8h8M8 11h7M10 8c3 0 4 1 4 3s-1 3-4 3H9l5 5"/></svg>
  return <svg {...common}><circle cx="12" cy="12" r="9"/></svg>
}


function getGreetingName(staff) {
  const fullName = String(staff?.full_name || '').trim()
  if (!fullName) return 'there'
  return fullName.split(/\s+/)[0]
}

function getTimeOfDay() {
  const hour = new Date().getHours()
  if (hour < 12) return 'morning'
  if (hour < 17) return 'afternoon'
  return 'evening'
}

function formatTime(date) {
  return date.toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
  })
}

function formatCurrency(value, currencyCode = 'INR') {
  try {
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: currencyCode || 'INR',
      maximumFractionDigits: 0,
    }).format(Number(value || 0))
  } catch {
    return `₹${Number(value || 0).toLocaleString('en-IN')}`
  }
}

function RefreshIcon({ spinning }) {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      style={spinning ? { animation: 'spin 0.8s linear infinite' } : {}}
      aria-hidden="true"
    >
      <polyline points="23 4 23 10 17 10" />
      <polyline points="1 20 1 14 7 14" />
      <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
    </svg>
  )
}

const analyticsGrid = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
  gap: '18px',
}

const analyticsCard = {
  background: '#0f0f0f',
  border: '1px solid #222',
  borderRadius: '18px',
  padding: '22px',
  display: 'flex',
  alignItems: 'center',
  gap: '16px',
}

const analyticsIcon = {
  width: '46px',
  height: '46px',
  borderRadius: '14px',
  background: 'rgba(212,175,55,0.12)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontSize: '22px',
}

const analyticsTitle = {
  margin: 0,
  color: '#d4af37',
  fontSize: '13px',
  fontWeight: 700,
}

const analyticsValue = {
  margin: '6px 0 0',
  color: '#fff',
  fontSize: '28px',
}
