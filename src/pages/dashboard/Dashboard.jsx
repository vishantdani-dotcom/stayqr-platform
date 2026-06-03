import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import HotelOverviewCard from '../../components/cards/HotelOverviewCard'
import StatCards from '../../components/cards/StatCards'
import RoomsTable from '../../components/table/RoomsTable'
import QuickActions from '../../components/buttons/QuickActions'
import PlaceholderCards from '../../components/cards/PlaceholderCards'
import AddRoomModal from '../../components/modals/AddRoomModal'
import './Dashboard.css'

export default function Dashboard() {
  const [rooms, setRooms] = useState([])
  const [stats, setStats] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [lastFetch, setLastFetch] = useState(null)
  const [showAddRoomModal, setShowAddRoomModal] = useState(false)

  const fetchRooms = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const { data, error: supaErr } = await supabase
        .from('rooms')
        .select('*')
        .order('room_number', { ascending: true })

      if (supaErr) throw supaErr

      setRooms(data || [])

      const total = data?.length ?? 0
      const available = data?.filter(r => r.status === 'available').length ?? 0
      const occupied = data?.filter(r => r.status === 'occupied').length ?? 0

      const { count: guestsCount, error: guestsErr } = await supabase
        .from('guests')
        .select('*', { count: 'exact', head: true })

      if (guestsErr) throw guestsErr

      setStats({
        total,
        available,
        occupied,
        guests: guestsCount || 0,
      })

      setLastFetch(new Date())
    } catch (err) {
      console.error('[Dashboard] Supabase fetch error:', err)
      setError(err?.message || 'Failed to fetch data. Check your Supabase connection.')
      setStats({ total: 12, available: 4, occupied: 7, guests: 0 })
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchRooms()
  }, [fetchRooms])

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
      alert('QR Generator coming soon')
      return
    }

    alert(`Action: ${actionId}`)
  }

  return (
    <div className="dashboard-page">
      {showAddRoomModal && (
        <AddRoomModal
          onClose={() => setShowAddRoomModal(false)}
          onSuccess={fetchRooms}
        />
      )}

      <div className="dash-page-header">
        <div>
          <h1 className="dash-page-title">
            Good {getTimeOfDay()}, <span className="gold-text">Admin</span> 👋
          </h1>

          <p className="dash-page-sub">
            Here's what's happening at VD Stay Inn today
            {lastFetch && (
              <span className="last-fetch">
                · Last updated {formatTime(lastFetch)}
              </span>
            )}
          </p>
        </div>

        <div className="dash-header-actions">
          <button className="dash-refresh-btn" onClick={fetchRooms} disabled={loading}>
            <RefreshIcon spinning={loading} />
            {loading ? 'Syncing...' : 'Refresh'}
          </button>
        </div>
      </div>

      <section className="dash-section">
        <HotelOverviewCard />
      </section>

      <section className="dash-section dash-main-grid">
        <div className="dash-stats-col">
          <StatCards stats={stats} loading={loading} />
        </div>

        <div className="dash-actions-col">
          <QuickActions onAction={handleAction} />
        </div>
      </section>

      <section className="dash-section">
        <RoomsTable
          rooms={rooms}
          loading={loading}
          error={error}
          onRefresh={fetchRooms}
        />
      </section>

      <section className="dash-section">
        <PlaceholderCards />
      </section>
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