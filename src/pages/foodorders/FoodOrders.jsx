import { useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import { createNotification } from '../../lib/notifications'

export default function FoodOrders() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [currentHotel, setCurrentHotel] = useState(null)
  const [newOrderAlert, setNewOrderAlert] = useState(null)
  const knownOrderIds = useRef(new Set())
  const firstLoadDone = useRef(false)

  useEffect(() => {
    initPage()
  }, [])

  useEffect(() => {
    if (!currentHotel?.id) return

    loadOrders(currentHotel.id)

    const channel = supabase
      .channel(`food_orders_${currentHotel.id}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'food_orders',
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        (payload) => {
          if (payload.eventType === 'INSERT') {
            handleNewOrder(payload.new)
          }
          loadOrders(currentHotel.id)
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [currentHotel?.id])

  async function initPage() {
    const hotel = await getCurrentHotel()

    if (!hotel) {
      alert('No hotel assigned')
      setLoading(false)
      return
    }

    setCurrentHotel(hotel)
    await loadOrders(hotel.id)
    setLoading(false)
  }

  function handleNewOrder(order) {
    if (!order?.id) return

    if (knownOrderIds.current.has(order.id)) return
    knownOrderIds.current.add(order.id)

    if (!firstLoadDone.current) return

    setNewOrderAlert(order)
    playKitchenSound()

    setTimeout(() => {
      setNewOrderAlert(null)
    }, 6000)
  }

  function playKitchenSound() {
    try {
      const audioContext = new (window.AudioContext || window.webkitAudioContext)()
      const oscillator = audioContext.createOscillator()
      const gainNode = audioContext.createGain()

      oscillator.connect(gainNode)
      gainNode.connect(audioContext.destination)

      oscillator.frequency.value = 880
      oscillator.type = 'sine'

      gainNode.gain.setValueAtTime(0.001, audioContext.currentTime)
      gainNode.gain.exponentialRampToValueAtTime(0.25, audioContext.currentTime + 0.02)
      gainNode.gain.exponentialRampToValueAtTime(0.001, audioContext.currentTime + 0.35)

      oscillator.start(audioContext.currentTime)
      oscillator.stop(audioContext.currentTime + 0.35)
    } catch {
      // Sound is optional. Ignore browser audio restrictions.
    }
  }

  async function loadOrders(hotelId = currentHotel?.id) {
    if (!hotelId) return

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
      .eq('hotel_id', hotelId)
      .order('created_at', { ascending: false })

    if (error) {
      alert(error.message)
      return
    }

    const nextOrders = data || []

    nextOrders.forEach((order) => {
      if (order?.id) knownOrderIds.current.add(order.id)
    })

    firstLoadDone.current = true
    setOrders(nextOrders)
  }

  async function updateStatus(order, status) {
    const { error } = await supabase
      .from('food_orders')
      .update({ order_status: status })
      .eq('id', order.id)
      .eq('hotel_id', currentHotel?.id)

    if (error) {
      alert(error.message)
      return
    }

    await createNotification({
      hotelId: currentHotel.id,
      roomId: order.room_id,
      guestId: order.guest_id,
      type: 'food_order',
      title: `Food Order · Room ${order.rooms?.room_number || '-'}`,
      message: `Order #${order.id.slice(0, 8)} marked ${status}`,
    })

    loadOrders(currentHotel?.id)
  }

  const today = new Date().toDateString()

  const todayOrders = orders.filter((order) => {
    return new Date(order.created_at).toDateString() === today
  })

  const todayRevenue = todayOrders.reduce((sum, order) => {
    return sum + Number(order.total_amount || 0)
  }, 0)

  const pendingOrders = orders.filter((order) => order.order_status === 'pending')
  const acceptedOrders = orders.filter((order) => order.order_status === 'accepted')
  const preparingOrders = orders.filter((order) => order.order_status === 'preparing')
  const deliveredOrders = orders.filter((order) => order.order_status === 'delivered')

  if (loading) return <div style={page}>Loading Food Orders...</div>

  return (
    <div style={page}>
      {newOrderAlert && (
        <div style={newOrderBanner}>
          <div style={bannerIcon}>🔔</div>
          <div>
            <strong>New Food Order</strong>
            <p>
              Room order received · ₹{newOrderAlert.total_amount || 0}
            </p>
          </div>
        </div>
      )}

      <div style={header}>
        <div>
          <p style={kicker}>Kitchen Operations</p>
          <h1 style={title}>Food Orders</h1>
          <p style={subtitle}>
            {currentHotel?.hotel_name || 'Hotel'} · Live kitchen order dashboard.
          </p>
        </div>

        <button style={refreshBtn} onClick={() => loadOrders(currentHotel?.id)}>
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Stat title="Today's Orders" value={todayOrders.length} />
        <Stat title="Today's Revenue" value={`₹${todayRevenue}`} />
        <Stat title="Pending" value={pendingOrders.length} />
        <Stat title="Accepted" value={acceptedOrders.length} />
        <Stat title="Preparing" value={preparingOrders.length} />
        <Stat title="Delivered" value={deliveredOrders.length} />
      </div>

      {orders.length === 0 ? (
        <div style={emptyCard}>
          <h3>No food orders yet</h3>
          <p>Guest food orders will appear here instantly.</p>
        </div>
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
              {orders.map((order) => {
                const isNew = isRecentPendingOrder(order)

                return (
                  <tr key={order.id} style={isNew ? newOrderRow : undefined}>
                    <td style={td}>
                      Room {order.rooms?.room_number || '-'}
                      {isNew && <span style={newBadge}>NEW</span>}
                    </td>

                    <td style={td}>{order.guests?.full_name || '-'}</td>

                    <td style={td}>
                      {order.food_order_items?.length > 0
                        ? order.food_order_items.map((item, index) => (
                            <div key={index}>
                              {item.menu_items?.item_name || 'Unknown Item'} x{' '}
                              {item.quantity}
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
                          onClick={() => updateStatus(order, 'accepted')}
                        >
                          Accept Order
                        </button>
                      )}

                      {order.order_status === 'accepted' && (
                        <button
                          style={btn}
                          onClick={() => updateStatus(order, 'preparing')}
                        >
                          Start Preparing
                        </button>
                      )}

                      {order.order_status === 'preparing' && (
                        <button
                          style={btn}
                          onClick={() => updateStatus(order, 'delivered')}
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
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function Stat({ title, value }) {
  return (
    <div style={statCard}>
      <span style={statLabel}>{title}</span>
      <strong style={statValue}>{value}</strong>
    </div>
  )
}

function isRecentPendingOrder(order) {
  if (order.order_status !== 'pending') return false
  if (!order.created_at) return false

  const created = new Date(order.created_at).getTime()
  const now = Date.now()
  return now - created < 10 * 60 * 1000
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
  marginBottom: '25px',
}

const kicker = {
  color: '#d4af37',
  fontSize: '12px',
  fontWeight: 900,
  letterSpacing: '2px',
  textTransform: 'uppercase',
  marginBottom: '8px',
}

const title = {
  fontSize: '42px',
  marginBottom: '8px',
}

const subtitle = {
  color: '#aaa',
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

const statsGrid = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))',
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

const emptyCard = {
  background: '#0f0f0f',
  border: '1px solid #222',
  borderRadius: '18px',
  padding: '28px',
  color: '#aaa',
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
  position: 'relative',
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

const newOrderBanner = {
  position: 'fixed',
  top: '90px',
  right: '28px',
  zIndex: 999,
  background: '#0f0f0f',
  border: '1px solid #d4af37',
  borderRadius: '16px',
  padding: '16px 18px',
  display: 'flex',
  gap: '14px',
  alignItems: 'center',
  boxShadow: '0 18px 50px rgba(0,0,0,.45)',
}

const bannerIcon = {
  width: '42px',
  height: '42px',
  borderRadius: '12px',
  background: 'rgba(212,175,55,.16)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontSize: '22px',
}

const newBadge = {
  display: 'inline-block',
  marginLeft: '8px',
  background: '#d4af37',
  color: '#000',
  padding: '3px 7px',
  borderRadius: '999px',
  fontSize: '10px',
  fontWeight: 900,
}

const newOrderRow = {
  background: 'rgba(212,175,55,.06)',
}

const badge = (status) => ({
  padding: '7px 12px',
  borderRadius: '999px',
  background:
    status === 'delivered'
      ? 'rgba(46,204,113,.18)'
      : status === 'preparing'
      ? 'rgba(52,152,219,.18)'
      : status === 'accepted'
      ? 'rgba(212,175,55,.18)'
      : 'rgba(255,170,0,.18)',
  color:
    status === 'delivered'
      ? '#2ecc71'
      : status === 'preparing'
      ? '#3498db'
      : status === 'accepted'
      ? '#d4af37'
      : '#ffaa00',
  fontWeight: 700,
  textTransform: 'capitalize',
})