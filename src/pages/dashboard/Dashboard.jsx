import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import HotelOverviewCard from '../../components/cards/HotelOverviewCard'
import RoomsTable from '../../components/table/RoomsTable'
import QuickActions from '../../components/buttons/QuickActions'
import PlaceholderCards from '../../components/cards/PlaceholderCards'
import AddRoomModal from '../../components/modals/AddRoomModal'
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

export default function Dashboard({ hotel = null, staff = null }) {
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
          .select('total_amount, created_at, order_status')
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
      const todayKey = toLocalDateKey(new Date())

      const todayOrders = foodOrders.filter(
        (order) => toLocalDateKey(order.created_at) === todayKey
      )

      const todayRevenue = todayOrders.reduce(
        (sum, order) => sum + Number(order.total_amount || 0),
        0
      )

      const activeSessions = guestSessions.filter(
        (session) => session.status === 'active'
      )

      const checkInsToday = guestSessions.filter(
        (session) => toLocalDateKey(session.checkin_time) === todayKey
      ).length

      const checkOutsDue = activeSessions.filter((session) => {
        const effectiveCheckout = session.extended_until || session.checkout_time
        return toLocalDateKey(effectiveCheckout) === todayKey
      }).length

      const nextAnalytics = {
        totalRooms: roomsData.length,
        availableRooms: roomsData.filter((room) => room.status === 'available').length,
        occupiedRooms: roomsData.filter((room) => room.status === 'occupied').length,
        cleaningRooms: roomsData.filter((room) => room.status === 'cleaning').length,
        totalGuests: guestsResult.count || 0,
        activeGuests: activeSessions.length,
        pendingRequests: requestsResult.count || 0,
        todayOrders: todayOrders.length,
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
      alert('Go to Check-In / Out from sidebar')
      return
    }

    if (actionId === 'generateqr') {
      alert('Open QR Guides from sidebar')
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
            Here&apos;s what&apos;s happening at {currentHotel?.hotel_name || 'your hotel'} today
            {lastFetch && (
              <span className="last-fetch">
                {' '}· Last updated {formatTime(lastFetch)}
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
        <div style={analyticsGrid}>
          <AnalyticsCard title="Total Rooms" value={analytics.totalRooms} icon="🏨" />
          <AnalyticsCard title="Available Rooms" value={analytics.availableRooms} icon="🟢" />
          <AnalyticsCard title="Occupied Rooms" value={analytics.occupiedRooms} icon="🔴" />
          <AnalyticsCard title="Cleaning Rooms" value={analytics.cleaningRooms} icon="🧹" />
          <AnalyticsCard title="Total Guests" value={analytics.totalGuests} icon="👥" />
          <AnalyticsCard title="Active Guests" value={analytics.activeGuests} icon="🛏️" />
          <AnalyticsCard title="Pending Requests" value={analytics.pendingRequests} icon="🛎️" />
          <AnalyticsCard title="Food Orders Today" value={analytics.todayOrders} icon="🍽️" />
          <AnalyticsCard
            title="Revenue Today"
            value={formatCurrency(analytics.todayRevenue, currentHotel?.currency_code)}
            icon="💰"
          />
        </div>
      </section>

      <section className="dash-section dash-main-grid">
        <div className="dash-actions-col">
          <QuickActions onAction={handleAction} />
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

      <section className="dash-section">
        <PlaceholderCards />
      </section>
    </div>
  )
}

function AnalyticsCard({ title, value, icon }) {
  return (
    <div style={analyticsCard}>
      <div style={analyticsIcon}>{icon}</div>
      <div>
        <p style={analyticsTitle}>{title}</p>
        <h3 style={analyticsValue}>{value}</h3>
      </div>
    </div>
  )
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

function toLocalDateKey(value) {
  if (!value) return ''
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return ''

  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
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
