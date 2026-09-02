export function getHotelDateKey(value, timeZone = 'Asia/Kolkata') {
  if (!value) return ''
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  let formatter
  try {
    formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    })
  } catch {
    formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'UTC', year: 'numeric', month: '2-digit', day: '2-digit',
    })
  }
  const parts = Object.fromEntries(formatter.formatToParts(date).map(({ type, value: part }) => [type, part]))
  return `${parts.year}-${parts.month}-${parts.day}`
}

// Food sales are not cash collections. Only delivered orders contribute value;
// cancelled and open orders still count as orders placed on the hotel business day.
export function summarizeDashboardFoodOrders(orders, { hotelId, timeZone, now = new Date() }) {
  if (!hotelId) return { todayOrders: 0, todayRevenue: 0 }
  const day = getHotelDateKey(now, timeZone)
  const today = orders.filter((order) =>
    order.hotel_id === hotelId && day && getHotelDateKey(order.created_at, timeZone) === day
  )
  const cents = today.reduce((sum, order) => {
    const amount = Number(order.total_amount)
    if (order.order_status !== 'delivered' || !Number.isFinite(amount) || amount < 0) return sum
    return sum + Math.round(amount * 100)
  }, 0)
  return { todayOrders: today.length, todayRevenue: cents / 100 }
}
