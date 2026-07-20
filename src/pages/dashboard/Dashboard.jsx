import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import HotelOverviewCard from '../../components/cards/HotelOverviewCard'
import RoomsTable from '../../components/table/RoomsTable'
import QuickActions from '../../components/buttons/QuickActions'
import PlaceholderCards from '../../components/cards/PlaceholderCards'
import AddRoomModal from '../../components/modals/AddRoomModal'
import './Dashboard.css'

export default function Dashboard() {
  const [rooms, setRooms] = useState([])
  const [currentHotel, setCurrentHotel] = useState(null)

  const [analytics, setAnalytics] = useState({
    totalRooms: 0,
    availableRooms: 0,
    occupiedRooms: 0,
    cleaningRooms: 0,
    totalGuests: 0,
    activeGuests: 0,
    pendingRequests: 0,
    todayOrders: 0,
    todayRevenue: 0,
  })

  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [lastFetch, setLastFetch] = useState(null)
  const [showAddRoomModal, setShowAddRoomModal] = useState(false)

  const fetchDashboardData = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const hotel = await getCurrentHotel()

      if (!hotel) {
        throw new Error('No hotel assigned to current user')
      }

      setCurrentHotel(hotel)

      const { data: roomsData, error: roomsError } = await supabase
        .from('rooms')
        .select('*')
        .eq('hotel_id', hotel.id)
        .order('room_number', { ascending: true })

      if (roomsError) throw roomsError

      const { count: guestsCount, error: guestsError } = await supabase
        .from('guests')
        .select('*', { count: 'exact', head: true })
        .eq('hotel_id', hotel.id)

      if (guestsError) throw guestsError

      const { count: activeGuestsCount, error: activeGuestsError } =
        await supabase
          .from('guest_sessions')
          .select('*', { count: 'exact', head: true })
          .eq('hotel_id', hotel.id)
          .eq('status', 'active')

      if (activeGuestsError) throw activeGuestsError

      const { count: pendingRequestsCount, error: requestsError } =
        await supabase
          .from('service_requests')
          .select('*', { count: 'exact', head: true })
          .eq('hotel_id', hotel.id)
          .eq('status', 'pending')

      if (requestsError) throw requestsError

      const { data: foodOrdersData, error: foodOrdersError } = await supabase
        .from('food_orders')
        .select('total_amount, created_at, order_status')
        .eq('hotel_id', hotel.id)

      if (foodOrdersError) throw foodOrdersError

      const today = new Date().toISOString().split('T')[0]

      const todayOrders =
        foodOrdersData?.filter(order =>
          order.created_at?.split('T')[0] === today
        ) || []

      const todayRevenue = todayOrders.reduce((sum, order) => {
        return sum + Number(order.total_amount || 0)
      }, 0)

      const totalRooms = roomsData?.length || 0
      const availableRooms =
        roomsData?.filter(room => room.status === 'available').length || 0
      const occupiedRooms =
        roomsData?.filter(room => room.status === 'occupied').length || 0
      const cleaningRooms =
        roomsData?.filter(room => room.status === 'cleaning').length || 0

      setRooms(roomsData || [])

      setAnalytics({
        totalRooms,
        availableRooms,
        occupiedRooms,
        cleaningRooms,
        totalGuests: guestsCount || 0,
        activeGuests: activeGuestsCount || 0,
        pendingRequests: pendingRequestsCount || 0,
        todayOrders: todayOrders.length,
        todayRevenue,
      })

      setLastFetch(new Date())
    } catch (err) {
      console.error('[Dashboard] Fetch error:', err)
      setError(err?.message || 'Failed to fetch dashboard data')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchDashboardData()
  }, [fetchDashboardData])

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
            Good {getTimeOfDay()}, <span className="gold-text">Admin</span> 👋
          </h1>

          <p className="dash-page-sub">
            Here's what's happening at {currentHotel?.hotel_name || 'your hotel'} today
            {lastFetch && (
              <span className="last-fetch">
                · Last updated {formatTime(lastFetch)}
              </span>
            )}
          </p>
        </div>

        <div className="dash-header-actions">
          <button
            className="dash-refresh-btn"
            onClick={fetchDashboardData}
            disabled={loading}
          >
            <RefreshIcon spinning={loading} />
            {loading ? 'Syncing...' : 'Refresh'}
          </button>
        </div>
      </div>

      <section className="dash-section">
        <HotelOverviewCard />
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
            value={`₹${analytics.todayRevenue}`}
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

function getTimeOfDay() {
  const h = new Date().getHours()
  if (h < 12) return 'morning'
  if (h < 17) return 'afternoon'
  return 'evening'
}

function formatTime(date) {
  return date.toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
  })
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