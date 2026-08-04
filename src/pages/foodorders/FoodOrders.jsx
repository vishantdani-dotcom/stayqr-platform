import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  getFoodOperationsAnalytics,
  getFoodOrderKot,
  loadDay15FoodOrders,
  postFoodOrderToFolio,
  updateFoodOrderStatus,
} from '../../lib/day15Operations'
import { supabase } from '../../lib/supabase'
import './FoodOrders.css'

const COLUMNS = [
  ['pending', 'New'],
  ['accepted', 'Accepted'],
  ['preparing', 'Preparing'],
  ['ready', 'Ready'],
  ['out_for_delivery', 'On the way'],
]

const NEXT_STATUS = {
  pending: 'accepted',
  accepted: 'preparing',
  preparing: 'ready',
  ready: 'out_for_delivery',
  out_for_delivery: 'delivered',
}

export default function FoodOrders() {
  const [hotel, setHotel] = useState(null)
  const [orders, setOrders] = useState([])
  const [analytics, setAnalytics] = useState({})
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState('')
  const [toast, setToast] = useState('')
  const knownIds = useRef(new Set())
  const initialLoadDone = useRef(false)

  const showToast = useCallback((message) => {
    setToast(String(message || ''))
    window.setTimeout(() => setToast(''), 3000)
  }, [])

  const loadOrders = useCallback(async (hotelId) => {
    const data = await loadDay15FoodOrders(hotelId)
    const newOrders = data.filter((order) => !knownIds.current.has(order.id))
    data.forEach((order) => knownIds.current.add(order.id))
    setOrders(data)
    if (initialLoadDone.current && newOrders.some((order) => order.order_status === 'pending')) {
      playKitchenBell()
      showToast('New guest food order received.')
    }
    initialLoadDone.current = true
  }, [showToast])

  const loadAnalytics = useCallback(async (hotelId) => {
    const from = new Date()
    from.setHours(0, 0, 0, 0)
    const to = new Date(from)
    to.setDate(to.getDate() + 1)
    const result = await getFoodOperationsAnalytics({
      hotelId,
      from: from.toISOString(),
      to: to.toISOString(),
    })
    setAnalytics(result || {})
  }, [])

  const initialize = useCallback(async () => {
    setLoading(true)
    try {
      const selectedHotel = await getCurrentHotel()
      if (!selectedHotel) throw new Error('No hotel is selected.')
      setHotel(selectedHotel)
      await Promise.all([loadOrders(selectedHotel.id), loadAnalytics(selectedHotel.id)])
    } catch (error) {
      console.error('Food operations initialization failed:', error)
      showToast(error.message || 'Unable to load food operations.')
    } finally {
      setLoading(false)
    }
  }, [loadAnalytics, loadOrders, showToast])

  useEffect(() => {
    void initialize()
  }, [initialize])

  useEffect(() => {
    if (!hotel?.id) return undefined
    const channel = supabase
      .channel(`day15_food_orders_${hotel.id}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'food_orders',
        filter: `hotel_id=eq.${hotel.id}`,
      }, () => {
        void Promise.all([loadOrders(hotel.id), loadAnalytics(hotel.id)])
      })
      .subscribe()
    const interval = window.setInterval(() => void loadOrders(hotel.id), 15000)
    return () => {
      window.clearInterval(interval)
      supabase.removeChannel(channel)
    }
  }, [hotel?.id, loadAnalytics, loadOrders])

  const terminalOrders = useMemo(
    () => orders.filter((order) => ['delivered', 'cancelled'].includes(order.order_status)),
    [orders]
  )

  async function moveOrder(order, nextStatus) {
    if (!hotel?.id || busyId) return
    setBusyId(order.id)
    try {
      const defaultEta = nextStatus === 'accepted'
        ? Math.max(10, Number(order.estimated_minutes || 25))
        : order.estimated_minutes
      await updateFoodOrderStatus({
        hotelId: hotel.id,
        orderId: order.id,
        status: nextStatus,
        estimatedMinutes: ['accepted', 'preparing'].includes(nextStatus) ? defaultEta : null,
      })
      await Promise.all([loadOrders(hotel.id), loadAnalytics(hotel.id)])
      showToast(`Order moved to ${nextStatus.replaceAll('_', ' ')}.`)
    } catch (error) {
      showToast(error.message || 'Unable to update the order.')
    } finally {
      setBusyId('')
    }
  }

  async function changeEta(order, value) {
    if (!hotel?.id || busyId) return
    setBusyId(order.id)
    try {
      await updateFoodOrderStatus({
        hotelId: hotel.id,
        orderId: order.id,
        status: order.order_status,
        estimatedMinutes: value,
      })
      await loadOrders(hotel.id)
      showToast('Kitchen ETA updated and shared with the guest.')
    } catch (error) {
      showToast(error.message || 'Unable to update ETA.')
    } finally {
      setBusyId('')
    }
  }

  async function cancelOrder(order) {
    if (!window.confirm('Cancel this food order?')) return
    const reason = window.prompt('Cancellation reason:', 'Item unavailable')
    if (reason === null) return
    setBusyId(order.id)
    try {
      await updateFoodOrderStatus({
        hotelId: hotel.id,
        orderId: order.id,
        status: 'cancelled',
        note: reason,
      })
      await Promise.all([loadOrders(hotel.id), loadAnalytics(hotel.id)])
      showToast('Order cancelled and guest notified.')
    } catch (error) {
      showToast(error.message || 'Unable to cancel the order.')
    } finally {
      setBusyId('')
    }
  }

  async function printKot(order) {
    setBusyId(order.id)
    try {
      const ticket = await getFoodOrderKot({ hotelId: hotel.id, orderId: order.id })
      const popup = window.open('', '_blank', 'width=520,height=760')
      if (!popup) throw new Error('Allow pop-ups to print the kitchen ticket.')
      popup.document.write(renderKot(ticket, hotel?.hotel_name || 'StayQR Hotel'))
      popup.document.close()
      popup.focus()
      popup.print()
      showToast(`${ticket.ticket_number} prepared for printing.`)
    } catch (error) {
      showToast(error.message || 'Unable to print the KOT.')
    } finally {
      setBusyId('')
    }
  }

  async function reconcileFolio(order) {
    setBusyId(order.id)
    try {
      const result = await postFoodOrderToFolio({ hotelId: hotel.id, orderId: order.id })
      await loadOrders(hotel.id)
      showToast(result?.idempotent ? 'Folio posting already existed.' : 'Food order posted to the folio.')
    } catch (error) {
      showToast(error.message || 'Unable to post the order to the folio.')
    } finally {
      setBusyId('')
    }
  }

  if (loading) return <div className="day15-loading">Loading kitchen operations…</div>

  return (
    <div className="day15-foodops">
      <header className="day15-page-header">
        <div><span>Day 15 · Food & Kitchen</span><h1>Kitchen Command</h1><p>{hotel?.hotel_name} · Trusted status transitions, KOT and exact-once folio posting.</p></div>
        <button onClick={() => Promise.all([loadOrders(hotel.id), loadAnalytics(hotel.id)])}>Refresh</button>
      </header>

      <section className="day15-stat-grid">
        <Metric label="Orders today" value={analytics.orders || 0} />
        <Metric label="Delivered" value={analytics.delivered_orders || 0} />
        <Metric label="Cancelled" value={analytics.cancelled_orders || 0} />
        <Metric label="Revenue" value={money(analytics.revenue)} />
        <Metric label="Avg. order" value={money(analytics.average_order_value)} />
        <Metric label="Avg. prep" value={`${Math.round(Number(analytics.average_prep_minutes || 0))} min`} />
      </section>

      <section className="day15-kitchen-board">
        {COLUMNS.map(([status, label]) => {
          const columnOrders = orders.filter((order) => order.order_status === status)
          return (
            <div className="day15-kitchen-column" key={status}>
              <div className="day15-column-head"><strong>{label}</strong><span>{columnOrders.length}</span></div>
              <div className="day15-column-body">
                {columnOrders.length === 0 ? <p>No orders</p> : columnOrders.map((order) => (
                  <KitchenCard
                    key={order.id}
                    order={order}
                    busy={busyId === order.id}
                    onMove={() => moveOrder(order, NEXT_STATUS[status])}
                    onEta={(value) => changeEta(order, value)}
                    onCancel={() => cancelOrder(order)}
                    onPrint={() => printKot(order)}
                  />
                ))}
              </div>
            </div>
          )
        })}
      </section>

      <section className="day15-terminal-section">
        <div className="day15-section-title"><h2>Completed activity</h2><span>Delivered orders post exactly once to the guest folio.</span></div>
        <div className="day15-terminal-grid">
          {terminalOrders.slice(0, 30).map((order) => (
            <article key={order.id} className={`day15-terminal-card ${order.order_status}`}>
              <div><strong>Room {order.rooms?.room_number || '—'}</strong><span>{order.guests?.full_name || 'Guest'}</span></div>
              <div><Status status={order.order_status} /><strong>{money(order.total_amount, order.currency_code)}</strong></div>
              {order.order_status === 'delivered' && (
                <button disabled={busyId === order.id} onClick={() => reconcileFolio(order)}>{order.folio_item_id ? 'Verify folio' : 'Post to folio'}</button>
              )}
              <button disabled={busyId === order.id} onClick={() => printKot(order)}>Print KOT</button>
            </article>
          ))}
        </div>
      </section>

      {Array.isArray(analytics.popular_items) && analytics.popular_items.length > 0 && (
        <section className="day15-popular">
          <div className="day15-section-title"><h2>Popular items today</h2></div>
          {analytics.popular_items.map((item) => <div key={item.item_name}><span>{item.item_name}</span><strong>{item.quantity} sold · {money(item.revenue)}</strong></div>)}
        </section>
      )}

      {toast && <div className="day15-toast">{toast}</div>}
    </div>
  )
}

function KitchenCard({ order, busy, onMove, onEta, onCancel, onPrint }) {
  return (
    <article className="day15-kitchen-card">
      <div className="day15-order-head"><div><span>Room</span><strong>{order.rooms?.room_number || '—'}</strong></div><div><span>Order</span><strong>{String(order.id).slice(0, 6).toUpperCase()}</strong></div></div>
      <p className="day15-guest-name">{order.guests?.full_name || 'Guest'} · {new Date(order.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>
      <div className="day15-kitchen-items">
        {(order.food_order_items || []).map((item) => (
          <div key={item.id}><strong>{item.quantity} × {item.item_name_snapshot}</strong>{(item.food_order_item_modifiers || []).length > 0 && <span>{item.food_order_item_modifiers.map((modifier) => modifier.modifier_name_snapshot).join(', ')}</span>}</div>
        ))}
      </div>
      <div className="day15-order-total"><span>Total</span><strong>{money(order.total_amount, order.currency_code)}</strong></div>
      <label className="day15-eta">ETA<select value={order.estimated_minutes || ''} disabled={busy} onChange={(event) => onEta(event.target.value)}><option value="">Not set</option><option value="10">10 min</option><option value="15">15 min</option><option value="20">20 min</option><option value="30">30 min</option><option value="45">45 min</option><option value="60">60 min</option></select></label>
      <div className="day15-card-actions"><button disabled={busy} onClick={onPrint}>KOT</button><button className="primary" disabled={busy} onClick={onMove}>{busy ? 'Updating…' : `Move to ${String(NEXT_STATUS[order.order_status] || '').replaceAll('_', ' ')}`}</button></div>
      {['pending', 'accepted'].includes(order.order_status) && <button className="day15-danger-link" disabled={busy} onClick={onCancel}>Cancel order</button>}
    </article>
  )
}

function Metric({ label, value }) { return <div className="day15-metric"><span>{label}</span><strong>{value}</strong></div> }
function Status({ status }) { return <span className={`day15-status ${status}`}>{String(status || '').replaceAll('_', ' ')}</span> }
function money(value, currency = 'INR') { return new Intl.NumberFormat('en-IN', { style: 'currency', currency: currency || 'INR', maximumFractionDigits: 2 }).format(Number(value || 0)) }

function playKitchenBell() {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return
    const context = new AudioContextClass()
    const oscillator = context.createOscillator()
    const gain = context.createGain()
    oscillator.connect(gain)
    gain.connect(context.destination)
    oscillator.frequency.value = 880
    gain.gain.setValueAtTime(0.001, context.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.22, context.currentTime + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.35)
    oscillator.start()
    oscillator.stop(context.currentTime + 0.36)
  } catch (error) { console.warn('Kitchen alert unavailable:', error) }
}

function renderKot(ticket, hotelName) {
  const items = (ticket.items || []).map((item) => `<tr><td><strong>${escapeHtml(item.quantity)} × ${escapeHtml(item.item_name)}</strong>${(item.modifiers || []).length ? `<small>${item.modifiers.map(escapeHtml).join(', ')}</small>` : ''}</td></tr>`).join('')
  return `<!doctype html><html><head><title>${escapeHtml(ticket.ticket_number)}</title><style>body{font-family:Arial,sans-serif;width:300px;margin:20px auto;color:#000}h1,h2,p{margin:4px 0;text-align:center}hr{border:0;border-top:1px dashed #000;margin:14px 0}table{width:100%;border-collapse:collapse}td{padding:9px 0;border-bottom:1px dashed #aaa}small{display:block;margin:4px 0 0 18px}.meta{display:flex;justify-content:space-between;margin:8px 0}.footer{margin-top:18px;font-size:11px;text-align:center}@media print{button{display:none}}</style></head><body><h1>${escapeHtml(hotelName)}</h1><h2>${escapeHtml(ticket.ticket_number)}</h2><p>Kitchen Order Ticket</p><hr><div class="meta"><span>Room</span><strong>${escapeHtml(ticket.room?.room_number || '—')}</strong></div><div class="meta"><span>Guest</span><strong>${escapeHtml(ticket.guest?.full_name || 'Guest')}</strong></div><div class="meta"><span>Order</span><strong>${escapeHtml(String(ticket.order_id).slice(0,8).toUpperCase())}</strong></div><hr><table>${items}</table><p class="footer">Printed through StayQR · Print ${escapeHtml(ticket.print_count)}</p></body></html>`
}
function escapeHtml(value) { return String(value ?? '').replace(/[&<>'"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character]) }
