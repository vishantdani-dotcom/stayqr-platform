import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'

export default function Reports() {
  const [report, setReport] = useState(null)
  const [loading, setLoading] = useState(true)
  const [currentHotel, setCurrentHotel] = useState(null)

  useEffect(() => {
    initPage()
  }, [])

  async function initPage() {
    const hotel = await getCurrentHotel()

    if (!hotel) {
      alert('No hotel assigned')
      setLoading(false)
      return
    }

    setCurrentHotel(hotel)
    loadReport(hotel.id)
  }

  async function loadReport(hotelId = currentHotel?.id) {
    if (!hotelId) return

    setLoading(true)

    try {
      const { data: rooms } = await supabase
        .from('rooms')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: guests } = await supabase
        .from('guests')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: sessions } = await supabase
        .from('guest_sessions')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: requests } = await supabase
        .from('service_requests')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: orders } = await supabase
        .from('food_orders')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: payments } = await supabase
        .from('payments')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: manualCharges } = await supabase
        .from('manual_charges')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: invoices } = await supabase
        .from('invoices')
        .select('*')
        .eq('hotel_id', hotelId)

      const { data: housekeeping } = await supabase
        .from('housekeeping_tasks')
        .select('*')
        .eq('hotel_id', hotelId)

      const totalRooms = rooms?.length || 0
      const occupiedRooms = rooms?.filter(r => r.status === 'occupied').length || 0
      const availableRooms = rooms?.filter(r => r.status === 'available').length || 0
      const cleaningRooms = rooms?.filter(r => r.status === 'cleaning').length || 0
      const occupancyRate =
        totalRooms > 0 ? Math.round((occupiedRooms / totalRooms) * 100) : 0

      const activeGuests = sessions?.filter(s => s.status === 'active').length || 0
      const completedSessions =
        sessions?.filter(s => s.status === 'completed').length || 0

      const pendingRequests = requests?.filter(r => r.status === 'pending').length || 0
      const inProgressRequests =
        requests?.filter(r => r.status === 'in_progress').length || 0
      const completedRequests =
        requests?.filter(r => r.status === 'completed').length || 0

      const pendingOrders = orders?.filter(o => o.order_status === 'pending').length || 0
      const preparingOrders =
        orders?.filter(o => o.order_status === 'preparing').length || 0
      const deliveredOrders =
        orders?.filter(o => o.order_status === 'delivered').length || 0

      const foodRevenue =
        orders?.reduce((sum, order) => sum + Number(order.total_amount || 0), 0) || 0

      const paidPayments = payments?.filter(p => p.payment_status === 'paid') || []
      const pendingPayments = payments?.filter(p => p.payment_status !== 'paid') || []

      const roomRevenue = paidPayments
        .filter(p => p.payment_type === 'room_charge')
        .reduce((sum, p) => sum + Number(p.amount || 0), 0)

      const pendingRevenue = pendingPayments.reduce(
        (sum, p) => sum + Number(p.amount || 0),
        0
      )

      const manualRevenue =
        manualCharges?.reduce(
          (sum, charge) => sum + Number(charge.charge_amount || 0),
          0
        ) || 0

      const invoiceRevenue =
        invoices?.reduce((sum, invoice) => sum + Number(invoice.total_amount || 0), 0) ||
        0

      const totalRevenue = roomRevenue + foodRevenue + manualRevenue

      const pendingHousekeeping =
        housekeeping?.filter(t => t.status === 'pending').length || 0
      const completedHousekeeping =
        housekeeping?.filter(t => t.status === 'completed').length || 0

      setReport({
        totalRooms,
        occupiedRooms,
        availableRooms,
        cleaningRooms,
        occupancyRate,

        totalGuests: guests?.length || 0,
        activeGuests,
        completedSessions,

        totalOrders: orders?.length || 0,
        pendingOrders,
        preparingOrders,
        deliveredOrders,

        foodRevenue,
        roomRevenue,
        manualRevenue,
        pendingRevenue,
        invoiceRevenue,
        totalRevenue,

        totalInvoices: invoices?.length || 0,

        totalRequests: requests?.length || 0,
        pendingRequests,
        inProgressRequests,
        completedRequests,

        totalHousekeeping: housekeeping?.length || 0,
        pendingHousekeeping,
        completedHousekeeping,
      })
    } catch (err) {
      console.error(err)
      alert(err.message)
    }

    setLoading(false)
  }

  if (loading) {
    return <div style={page}>Loading Reports...</div>
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <h1 style={title}>Reports & Analytics</h1>
          <p style={sub}>
            Complete performance snapshot for {currentHotel?.hotel_name || 'your hotel'}.
          </p>
        </div>

        <button style={refreshBtn} onClick={() => loadReport(currentHotel?.id)}>
          Refresh
        </button>
      </div>

      <h2 style={sectionTitle}>Revenue Summary</h2>
      <div style={grid}>
        <Card title="Total Revenue" value={`₹${report.totalRevenue}`} />
        <Card title="Room Revenue" value={`₹${report.roomRevenue}`} />
        <Card title="Food Revenue" value={`₹${report.foodRevenue}`} />
        <Card title="Manual Charges" value={`₹${report.manualRevenue}`} />
        <Card title="Pending Revenue" value={`₹${report.pendingRevenue}`} />
        <Card title="Invoice Revenue" value={`₹${report.invoiceRevenue}`} />
      </div>

      <h2 style={sectionTitle}>Occupancy Report</h2>
      <div style={grid}>
        <Card title="Total Rooms" value={report.totalRooms} />
        <Card title="Occupied Rooms" value={report.occupiedRooms} />
        <Card title="Available Rooms" value={report.availableRooms} />
        <Card title="Cleaning Rooms" value={report.cleaningRooms} />
        <Card title="Occupancy Rate" value={`${report.occupancyRate}%`} />
      </div>

      <h2 style={sectionTitle}>Guest Report</h2>
      <div style={grid}>
        <Card title="Total Guests" value={report.totalGuests} />
        <Card title="Active Guests" value={report.activeGuests} />
        <Card title="Completed Stays" value={report.completedSessions} />
      </div>

      <h2 style={sectionTitle}>Food Orders Report</h2>
      <div style={grid}>
        <Card title="Total Food Orders" value={report.totalOrders} />
        <Card title="Pending Orders" value={report.pendingOrders} />
        <Card title="Preparing Orders" value={report.preparingOrders} />
        <Card title="Delivered Orders" value={report.deliveredOrders} />
      </div>

      <h2 style={sectionTitle}>Service Requests Report</h2>
      <div style={grid}>
        <Card title="Total Requests" value={report.totalRequests} />
        <Card title="Pending Requests" value={report.pendingRequests} />
        <Card title="In Progress Requests" value={report.inProgressRequests} />
        <Card title="Completed Requests" value={report.completedRequests} />
      </div>

      <h2 style={sectionTitle}>Housekeeping Report</h2>
      <div style={grid}>
        <Card title="Total Tasks" value={report.totalHousekeeping} />
        <Card title="Pending Cleaning" value={report.pendingHousekeeping} />
        <Card title="Completed Cleaning" value={report.completedHousekeeping} />
      </div>

      <h2 style={sectionTitle}>Invoice Report</h2>
      <div style={grid}>
        <Card title="Total Invoices" value={report.totalInvoices} />
        <Card title="Invoice Revenue" value={`₹${report.invoiceRevenue}`} />
      </div>
    </div>
  )
}

function Card({ title, value }) {
  return (
    <div style={card}>
      <div style={cardTitle}>{title}</div>
      <div style={cardValue}>{value}</div>
    </div>
  )
}

const page = {
  padding: '32px',
  color: '#fff',
}

const header = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: '20px',
  marginBottom: '28px',
}

const title = {
  fontSize: '42px',
  marginBottom: '8px',
}

const sub = {
  color: '#aaa',
}

const sectionTitle = {
  fontSize: '22px',
  color: '#d4af37',
  margin: '34px 0 18px',
}

const grid = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit,minmax(220px,1fr))',
  gap: '20px',
}

const card = {
  background: '#0f0f0f',
  border: '1px solid #222',
  borderRadius: '18px',
  padding: '24px',
}

const cardTitle = {
  color: '#d4af37',
  fontSize: '14px',
  marginBottom: '12px',
}

const cardValue = {
  fontSize: '34px',
  fontWeight: '700',
}

const refreshBtn = {
  background: '#d4af37',
  color: '#000',
  border: 'none',
  borderRadius: '10px',
  padding: '12px 18px',
  fontWeight: 800,
  cursor: 'pointer',
}