import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'

export default function Payments() {
  const [payments, setPayments] = useState([])
  const [loading, setLoading] = useState(true)
  const [currentHotel, setCurrentHotel] = useState(null)

  useEffect(() => {
    initPage()
  }, [])

  async function initPage() {
    const hotel = await getCurrentHotel()

    if (!hotel) {
      alert('No hotel assigned')
      return
    }

    setCurrentHotel(hotel)
    loadPayments(hotel.id)
  }

  async function loadPayments(hotelId = currentHotel?.id) {
    if (!hotelId) return

    setLoading(true)

    const { data, error } = await supabase
      .from('payments')
      .select(`
        *,
        guests (
          full_name
        ),
        rooms (
          room_number
        )
      `)
      .eq('hotel_id', hotelId)
      .order('created_at', { ascending: false })

    if (error) {
      console.error(error)
    } else {
      setPayments(data || [])
    }

    setLoading(false)
  }

  async function markPaid(id) {
    const { error } = await supabase
      .from('payments')
      .update({
        payment_status: 'paid'
      })
      .eq('id', id)
      .eq('hotel_id', currentHotel?.id)

    if (error) {
      alert(error.message)
      return
    }

    loadPayments(currentHotel?.id)
  }

  const totalRevenue = payments
    .filter(p => p.payment_status === 'paid')
    .reduce((sum, p) => sum + Number(p.amount || 0), 0)

  const pendingRevenue = payments
    .filter(p => p.payment_status !== 'paid')
    .reduce((sum, p) => sum + Number(p.amount || 0), 0)

  return (
    <div style={page}>
      <h1 style={title}>Payments</h1>

      <p style={hotelName}>
        {currentHotel?.hotel_name || 'Hotel'}
      </p>

      <div style={statsGrid}>
        <div style={statCard}>
          <h4>Total Revenue</h4>
          <h2>₹{totalRevenue}</h2>
        </div>

        <div style={statCard}>
          <h4>Pending Revenue</h4>
          <h2>₹{pendingRevenue}</h2>
        </div>

        <div style={statCard}>
          <h4>Total Transactions</h4>
          <h2>{payments.length}</h2>
        </div>
      </div>

      {loading ? (
        <p>Loading Payments...</p>
      ) : (
        <div style={tableCard}>
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Room</th>
                <th style={th}>Guest</th>
                <th style={th}>Amount</th>
                <th style={th}>Type</th>
                <th style={th}>Status</th>
                <th style={th}>Date</th>
                <th style={th}>Action</th>
              </tr>
            </thead>

            <tbody>
              {payments.map(payment => (
                <tr key={payment.id}>
                  <td style={td}>
                    Room {payment.rooms?.room_number || '-'}
                  </td>

                  <td style={td}>
                    {payment.guests?.full_name || '-'}
                  </td>

                  <td style={td}>
                    ₹{payment.amount}
                  </td>

                  <td style={td}>
                    {payment.payment_type || '-'}
                  </td>

                  <td style={td}>
                    <span
                      style={{
                        color:
                          payment.payment_status === 'paid'
                            ? '#2ecc71'
                            : '#f1c40f',
                        fontWeight: 700,
                      }}
                    >
                      {payment.payment_status}
                    </span>
                  </td>

                  <td style={td}>
                    {new Date(
                      payment.created_at
                    ).toLocaleDateString('en-IN')}
                  </td>

                  <td style={td}>
                    {payment.payment_status !== 'paid' && (
                      <button
                        style={button}
                        onClick={() => markPaid(payment.id)}
                      >
                        Mark Paid
                      </button>
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
  padding: '30px',
  color: '#fff',
}

const hotelName = {
  color: '#d4af37',
  marginBottom: '20px',
}

const title = {
  fontSize: '34px',
  marginBottom: '10px',
}

const statsGrid = {
  display: 'grid',
  gridTemplateColumns: 'repeat(3,1fr)',
  gap: '20px',
  marginBottom: '25px',
}

const statCard = {
  background: '#0f0f0f',
  border: '1px solid #222',
  borderRadius: '14px',
  padding: '20px',
}

const tableCard = {
  background: '#0f0f0f',
  border: '1px solid #222',
  borderRadius: '14px',
  overflow: 'auto',
}

const table = {
  width: '100%',
  borderCollapse: 'collapse',
}

const th = {
  padding: '15px',
  textAlign: 'left',
  borderBottom: '1px solid #222',
  color: '#d4af37',
}

const td = {
  padding: '15px',
  borderBottom: '1px solid #1f1f1f',
}

const button = {
  background: '#d4af37',
  border: 'none',
  padding: '8px 14px',
  borderRadius: '8px',
  cursor: 'pointer',
  fontWeight: 700,
}