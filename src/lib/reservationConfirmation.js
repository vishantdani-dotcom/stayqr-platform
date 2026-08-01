import { jsPDF } from 'jspdf'

function safeText(value, fallback = '—') {
  const text = String(value ?? '').trim()
  return text || fallback
}

function normalizeStatus(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_')
}

function statusLabel(value) {
  const normalized = normalizeStatus(value)
  if (!normalized) return 'Unknown'
  return normalized
    .split('_')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ')
}

function activeReservationRooms(reservation) {
  return (reservation?.rooms || []).filter(
    (room) => !['cancelled', 'released'].includes(normalizeStatus(room.status))
  )
}

function confirmationStatus(reservation) {
  const rooms = activeReservationRooms(reservation)
  const checkedInRooms = rooms.filter(
    (room) => normalizeStatus(room.status) === 'checked_in'
  ).length
  const pendingRooms = rooms.filter((room) =>
    ['draft', 'tentative', 'confirmed', 'held'].includes(normalizeStatus(room.status))
  ).length

  if (checkedInRooms > 0 && pendingRooms > 0) {
    return 'Partially Checked In'
  }

  if (rooms.length > 0 && checkedInRooms === rooms.length) {
    return 'Checked In'
  }

  return statusLabel(reservation?.status || 'draft')
}

function money(value, currency = 'INR') {
  const amount = Number(value || 0)
  try {
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: currency || 'INR',
      maximumFractionDigits: 2,
    }).format(amount)
  } catch {
    return `${currency || 'INR'} ${amount.toFixed(2)}`
  }
}

// jsPDF's built-in Helvetica font does not contain the Indian rupee glyph.
// Use an ASCII currency code in downloaded PDFs so amounts never render as a
// broken superscript or missing-character box.
function pdfMoney(value, currency = 'INR') {
  const amount = Number(value || 0)
  let formatted
  try {
    formatted = new Intl.NumberFormat('en-IN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(amount)
  } catch {
    formatted = amount.toFixed(2)
  }
  return `${currency || 'INR'} ${formatted}`
}

function date(value) {
  if (!value) return '—'
  const parsed = new Date(`${value}T12:00:00`)
  if (Number.isNaN(parsed.getTime())) return String(value)
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(parsed)
}

function wrap(doc, text, width) {
  return doc.splitTextToSize(safeText(text), width)
}

function addLabelValue(doc, label, value, x, y, width = 78) {
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(115, 115, 115)
  doc.text(label.toUpperCase(), x, y)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(10)
  doc.setTextColor(25, 25, 25)
  const lines = wrap(doc, value, width)
  doc.text(lines, x, y + 5)
  return y + 5 + lines.length * 4.4
}

export function downloadReservationConfirmation(snapshot) {
  const hotel = snapshot?.hotel || {}
  const reservation = snapshot?.reservation || {}
  const rooms = activeReservationRooms(reservation)
  const currency = reservation.currency_code || hotel.currency_code || 'INR'
  const bookingStatus = confirmationStatus(reservation)
  const doc = new jsPDF({ unit: 'mm', format: 'a4' })
  const margin = 16
  let y = 18

  doc.setFillColor(15, 15, 15)
  doc.roundedRect(margin, y, 178, 30, 3, 3, 'F')
  doc.setTextColor(212, 175, 55)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(20)
  doc.text(safeText(hotel.hotel_name, 'StayQR Hotel'), margin + 8, y + 11)
  doc.setTextColor(240, 240, 240)
  doc.setFontSize(9)
  doc.setFont('helvetica', 'normal')
  doc.text('Reservation Confirmation', margin + 8, y + 18)
  doc.text(`Booking ${safeText(reservation.reservation_number)}`, margin + 8, y + 24)
  y += 39

  doc.setTextColor(25, 25, 25)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(13)
  doc.text('Guest & stay', margin, y)
  y += 7

  const leftX = margin
  const rightX = 108
  let leftY = addLabelValue(doc, 'Primary guest', reservation.guest?.full_name, leftX, y)
  leftY = addLabelValue(
    doc,
    'Phone / Email',
    reservation.guest?.phone || reservation.guest?.email,
    leftX,
    leftY + 4
  )
  let rightY = addLabelValue(
    doc,
    'Stay',
    `${date(reservation.arrival_date)} to ${date(reservation.departure_date)}`,
    rightX,
    y
  )
  rightY = addLabelValue(doc, 'Booking status', bookingStatus, rightX, rightY + 4)
  y = Math.max(leftY, rightY) + 8

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(13)
  doc.text('Rooms', margin, y)
  y += 6

  rooms.forEach((room, index) => {
    if (y > 250) {
      doc.addPage()
      y = 18
    }

    const roomStatus = statusLabel(room.status)
    const fill = index % 2 === 0 ? 247 : 242
    doc.setFillColor(fill, fill, fill)
    doc.roundedRect(margin, y, 178, 23, 2, 2, 'F')
    doc.setTextColor(25, 25, 25)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(10)
    doc.text(
      room.room_number
        ? `Room ${room.room_number} - ${safeText(room.room_type_name)}`
        : `${safeText(room.room_type_name)} - Unallocated`,
      margin + 5,
      y + 7
    )
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8.5)
    doc.text(
      `${safeText(room.rate_plan_name)} - ${room.adults || 0} adult(s), ${
        room.children || 0
      } child(ren)`,
      margin + 5,
      y + 13
    )
    doc.setFont('helvetica', 'bold')
    doc.setTextColor(85, 85, 85)
    doc.text(`Status: ${roomStatus}`, margin + 5, y + 19)
    doc.setTextColor(25, 25, 25)
    doc.text(pdfMoney(room.total_amount, currency), 188, y + 12, { align: 'right' })
    y += 27
  })

  if (y > 225) {
    doc.addPage()
    y = 18
  }

  const balance = Math.max(
    Number(reservation.total_amount || 0) - Number(reservation.deposit_collected || 0),
    0
  )

  doc.setDrawColor(220, 220, 220)
  doc.line(margin, y, 194, y)
  y += 7
  doc.setFontSize(10)
  doc.setFont('helvetica', 'normal')
  doc.text('Room subtotal', margin, y)
  doc.text(pdfMoney(reservation.room_subtotal, currency), 194, y, { align: 'right' })
  y += 6
  doc.text('Tax', margin, y)
  doc.text(pdfMoney(reservation.tax_amount, currency), 194, y, { align: 'right' })
  y += 6
  doc.text('Discount', margin, y)
  doc.text(`- ${pdfMoney(reservation.discount_amount, currency)}`, 194, y, { align: 'right' })
  y += 7
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(12)
  doc.text('Total', margin, y)
  doc.text(pdfMoney(reservation.total_amount, currency), 194, y, { align: 'right' })
  y += 7
  doc.setFontSize(10)
  doc.text('Deposit collected', margin, y)
  doc.text(pdfMoney(reservation.deposit_collected, currency), 194, y, { align: 'right' })
  y += 6
  doc.text('Balance due', margin, y)
  doc.text(pdfMoney(balance, currency), 194, y, { align: 'right' })
  y += 11

  const notes = [
    `Special requests: ${reservation.special_requests || 'None'}`,
    `Terms: ${
      hotel.invoice_terms || 'Please contact the hotel for cancellation and check-in terms.'
    }`,
    hotel.invoice_footer || null,
  ].filter(Boolean)

  if (notes.length) {
    if (y > 246) {
      doc.addPage()
      y = 18
    }
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(11)
    doc.text('Important information', margin, y)
    y += 6
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(9)
    notes.forEach((note) => {
      const lines = wrap(doc, note, 176)
      doc.text(lines, margin, y)
      y += lines.length * 4.3 + 3
    })
  }

  doc.setTextColor(105, 105, 105)
  doc.setFontSize(8)
  doc.text(
    `${safeText(hotel.address || hotel.location)} - ${safeText(hotel.phone)} - ${safeText(
      hotel.email
    )}`,
    105,
    288,
    { align: 'center', maxWidth: 180 }
  )

  doc.save(`${safeText(reservation.reservation_number, 'reservation')}-confirmation.pdf`)
}

export function printReservationConfirmation(snapshot) {
  const hotel = snapshot?.hotel || {}
  const reservation = snapshot?.reservation || {}
  const currency = reservation.currency_code || hotel.currency_code || 'INR'
  const bookingStatus = confirmationStatus(reservation)
  const rooms = activeReservationRooms(reservation)
  const balance = Math.max(
    Number(reservation.total_amount || 0) - Number(reservation.deposit_collected || 0),
    0
  )
  const roomRows = rooms
    .map(
      (room) => `
        <tr>
          <td>${escapeHtml(room.room_number ? `Room ${room.room_number}` : 'Unallocated')}</td>
          <td>${escapeHtml(room.room_type_name)}</td>
          <td>${escapeHtml(room.rate_plan_name)}</td>
          <td>${escapeHtml(statusLabel(room.status))}</td>
          <td>${room.adults || 0} / ${room.children || 0}</td>
          <td style="text-align:right">${escapeHtml(money(room.total_amount, currency))}</td>
        </tr>`
    )
    .join('')

  const html = `<!doctype html>
<html><head><title>${escapeHtml(reservation.reservation_number)} confirmation</title>
<style>
body{font-family:Arial,sans-serif;color:#181818;margin:32px}header{background:#111;color:#fff;padding:22px;border-radius:10px}h1{margin:0;color:#d4af37}small{color:#777}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:24px 0}.box{border:1px solid #ddd;padding:14px;border-radius:8px}table{width:100%;border-collapse:collapse}th,td{border-bottom:1px solid #ddd;padding:10px;text-align:left}.totals{margin-left:auto;width:320px;margin-top:24px}.row{display:flex;justify-content:space-between;padding:6px 0}.grand{font-size:18px;font-weight:bold;border-top:2px solid #111;margin-top:6px;padding-top:10px}@media print{button{display:none}}
</style></head><body>
<header><h1>${escapeHtml(hotel.hotel_name || 'StayQR Hotel')}</h1><p>Reservation Confirmation - ${escapeHtml(reservation.reservation_number)}</p></header>
<div class="grid"><div class="box"><small>Guest</small><h2>${escapeHtml(reservation.guest?.full_name)}</h2><p>${escapeHtml(reservation.guest?.phone || reservation.guest?.email)}</p></div><div class="box"><small>Stay</small><h2>${escapeHtml(date(reservation.arrival_date))} - ${escapeHtml(date(reservation.departure_date))}</h2><p>Booking status: ${escapeHtml(bookingStatus)}</p></div></div>
<table><thead><tr><th>Room</th><th>Type</th><th>Rate plan</th><th>Status</th><th>Adults / Children</th><th style="text-align:right">Amount</th></tr></thead><tbody>${roomRows}</tbody></table>
<div class="totals"><div class="row"><span>Subtotal</span><strong>${escapeHtml(money(reservation.room_subtotal, currency))}</strong></div><div class="row"><span>Tax</span><strong>${escapeHtml(money(reservation.tax_amount, currency))}</strong></div><div class="row"><span>Discount</span><strong>- ${escapeHtml(money(reservation.discount_amount, currency))}</strong></div><div class="row"><span>Deposit collected</span><strong>${escapeHtml(money(reservation.deposit_collected, currency))}</strong></div><div class="row grand"><span>Total</span><strong>${escapeHtml(money(reservation.total_amount, currency))}</strong></div><div class="row"><span>Balance due</span><strong>${escapeHtml(money(balance, currency))}</strong></div></div>
<p><strong>Special requests:</strong> ${escapeHtml(reservation.special_requests || 'None')}</p>
<p><strong>Terms:</strong> ${escapeHtml(hotel.invoice_terms || 'Please contact the hotel for cancellation and check-in terms.')}</p>
${hotel.invoice_footer ? `<p>${escapeHtml(hotel.invoice_footer)}</p>` : ''}
<p>${escapeHtml(hotel.address || hotel.location || '')} - ${escapeHtml(hotel.phone || '')} - ${escapeHtml(hotel.email || '')}</p>
<script>window.onload=()=>window.print()</script></body></html>`

  const popup = window.open('', '_blank')
  if (!popup) throw new Error('Allow pop-ups to print the confirmation.')
  popup.opener = null
  popup.document.open()
  popup.document.write(html)
  popup.document.close()
}

export function shareReservationConfirmationOnWhatsApp(snapshot) {
  const hotel = snapshot?.hotel || {}
  const reservation = snapshot?.reservation || {}
  const currency = reservation.currency_code || hotel.currency_code || 'INR'
  const bookingStatus = confirmationStatus(reservation)
  const rooms = activeReservationRooms(reservation)
    .map((room) => {
      const roomName = room.room_number
        ? `Room ${room.room_number} (${room.room_type_name})`
        : room.room_type_name
      return `${roomName} - ${statusLabel(room.status)}`
    })
    .join(', ')
  const balance = Math.max(
    Number(reservation.total_amount || 0) - Number(reservation.deposit_collected || 0),
    0
  )

  const message = [
    `*${hotel.hotel_name || 'StayQR Hotel'} - Reservation Confirmation*`,
    `Booking: ${reservation.reservation_number}`,
    `Status: ${bookingStatus}`,
    `Guest: ${reservation.guest?.full_name || 'Guest'}`,
    `Stay: ${date(reservation.arrival_date)} to ${date(reservation.departure_date)}`,
    `Room(s): ${rooms || 'To be assigned'}`,
    `Total: ${money(reservation.total_amount, currency)}`,
    `Deposit: ${money(reservation.deposit_collected, currency)}`,
    `Balance: ${money(balance, currency)}`,
    hotel.phone ? `Hotel contact: ${hotel.phone}` : null,
  ]
    .filter(Boolean)
    .join('\n')

  window.open(`https://wa.me/?text=${encodeURIComponent(message)}`, '_blank', 'noopener,noreferrer')
}

function escapeHtml(value) {
  return safeText(value, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}
