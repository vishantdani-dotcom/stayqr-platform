import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'

export default function FoodOrders() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadOrders()

    const interval = setInterval(() => {
      loadOrders()
    }, 3000)

    return () => clearInterval(interval)
  }, [])

  async function loadOrders() {
    setLoading(true)

    const { data, error } = await supabase
      .from('food_orders')
      .select(`
        *,
        rooms (
          room_number
        ),
        guests (
          full_name
        ),
        food_order_items (
          quantity,
          price,
          menu_items (
            item_name
          )
        )
      `)
      .order('created_at', { ascending: false })

    if (error) {
      alert(error.message)
    } else {
      setOrders(data || [])
    }

    setLoading(false)
  }

  async function updateStatus(orderId, status) {
    const { error } = await supabase
      .from('food_orders')
      .update({ order_status: status })
      .eq('id', orderId)

    if (error) {
      alert(error.message)
      return
    }

    loadOrders()
  }

  const today = new Date().toDateString()

  const todayOrders = orders.filter(order => {
    return new Date(order.created_at).toDateString() === today
  })

  const todayRevenue = todayOrders.reduce((sum, order) => {
    return sum + Number(order.total_amount || 0)
  }, 0)

  const pendingOrders = orders.filter(order => order.order_status === 'pending')
  const preparingOrders = orders.filter(order => order.order_status === 'preparing')
  const deliveredOrders = orders.filter(order => order.order_status === 'delivered')

  if (loading) return <div style={page}>Loading Food Orders...</div>

  return (
    <div style={page}>
      <h1 style={title}>Food Orders</h1>

      <div style={statsGrid}>
        <div style={statCard}>
          <span style={statLabel}>Today's Orders</span>
          <strong style={statValue}>{todayOrders.length}</strong>
        </div>

        <div style={statCard}>
          <span style={statLabel}>Today's Revenue</span>
          <strong style={statValue}>₹{todayRevenue}</strong>
        </div>

        <div style={statCard}>
          <span style={statLabel}>Pending Orders</span>
          <strong style={statValue}>{pendingOrders.length}</strong>
        </div>

        <div style={statCard}>
          <span style={statLabel}>Preparing Orders</span>
          <strong style={statValue}>{preparingOrders.length}</strong>
        </div>

        <div style={statCard}>
          <span style={statLabel}>Delivered Orders</span>
          <strong style={statValue}>{deliveredOrders.length}</strong>
        </div>
      </div>

      {orders.length === 0 ? (
        <p>No food orders found.</p>
      ) : (
        <div style={card}>
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Room</th>
                <th style={th}>Guest</th>
                <th style={th}>Items</th>
                <th style={th}>Amount</th>
                <th style={th}>Status</th>
                <th style={th}>Payment</th>
                <th style={th}>Time</th>
                <th style={th}>Action</th>
              </tr>
            </thead>

            <tbody>
              {orders.map(order => (
                <tr key={order.id}>
                  <td style={td}>Room {order.rooms?.room_number || '-'}</td>
                  <td style={td}>{order.guests?.full_name || '-'}</td>

                  <td style={td}>
                    {order.food_order_items?.length > 0
                      ? order.food_order_items.map((item, index) => (
                          <div key={index}>
                            {item.menu_items?.item_name || 'Unknown Item'} x {item.quantity}
                          </div>
                        ))
                      : 'No items'}
                  </td>

                  <td style={td}>₹{order.total_amount}</td>

                  <td style={td}>
                    <span style={badge(order.order_status)}>
                      {order.order_status}
                    </span>
                  </td>

                  <td style={td}>{order.payment_status}</td>

                  <td style={td}>
                    {new Date(order.created_at).toLocaleString('en-IN')}
                  </td>

                  <td style={td}>
                    {order.order_status === 'pending' && (
                      <button
                        style={btn}
                        onClick={() => updateStatus(order.id, 'preparing')}
                      >
                        Start Preparing
                      </button>
                    )}

                    {order.order_status === 'preparing' && (
                      <button
                        style={btn}
                        onClick={() => updateStatus(order.id, 'delivered')}
                      >
                        Mark Delivered
                      </button>
                    )}

                    {order.order_status === 'delivered' && (
                      <span style={{ color: '#2ecc71', fontWeight: 700 }}>
                        Delivered
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

const page = {
  padding: '32px',
  color: '#fff',
}

const title = {
  fontSize: '42px',
  marginBottom: '25px',
}

const statsGrid = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
  gap: '18px',
  marginBottom: '28px',
}

const statCard = {
  background: '#0f0f0f',
  border: '1px solid #222',
  borderRadius: '16px',
  padding: '20px',
}

const statLabel = {
  display: 'block',
  color: '#d4af37',
  fontSize: '13px',
  marginBottom: '10px',
}

const statValue = {
  fontSize: '28px',
}

const card = {
  background: '#0f0f0f',
  border: '1px solid #222',
  borderRadius: '18px',
  overflowX: 'auto',
}

const table = {
  width: '100%',
  borderCollapse: 'collapse',
  minWidth: '1100px',
}

const th = {
  padding: '18px',
  color: '#d4af37',
  textAlign: 'left',
  borderBottom: '1px solid #222',
}

const td = {
  padding: '18px',
  borderBottom: '1px solid #1f1f1f',
  verticalAlign: 'top',
}

const btn = {
  background: '#d4af37',
  color: '#000',
  border: 'none',
  padding: '9px 14px',
  borderRadius: '8px',
  marginRight: '8px',
  marginBottom: '6px',
  fontWeight: 700,
  cursor: 'pointer',
}

const badge = (status) => ({
  padding: '7px 12px',
  borderRadius: '999px',
  background:
    status === 'delivered'
      ? 'rgba(46,204,113,.18)'
      : status === 'preparing'
      ? 'rgba(52,152,219,.18)'
      : 'rgba(255,170,0,.18)',
  color:
    status === 'delivered'
      ? '#2ecc71'
      : status === 'preparing'
      ? '#3498db'
      : '#ffaa00',
  fontWeight: 700,
  textTransform: 'capitalize',
})