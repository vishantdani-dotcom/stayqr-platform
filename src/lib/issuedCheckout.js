// An issued invoice is immutable. Only its live same-stay ledger proves payment.
export function issuedCheckoutTotals(invoice, folio, hotelId, sessionId) {
  if (!invoice) return null
  if (!invoice.finalized_at || invoice.hotel_id !== hotelId || invoice.guest_session_id !== sessionId
    || !folio || folio.hotel_id !== hotelId || folio.guest_session_id !== sessionId || folio.id !== invoice.folio_id) {
    throw new Error('The issued invoice must have a finalized, same-stay folio. Review Guest Bills.')
  }
  const cents = (value) => {
    const amount = Number(value)
    if (value == null || !Number.isFinite(amount) || amount < 0) throw new Error('Invalid issued invoice or folio amounts.')
    return Math.round(amount * 100)
  }
  const discount = cents(invoice.discount_amount)
  let subtotal = cents(invoice.subtotal_amount)
  if (String(invoice.metadata?.day13_checkout_compatibility) !== 'true') {
    if (invoice.invoice_origin !== 'authoritative' || invoice.metadata?.source !== 'folio') {
      throw new Error('Unknown issued invoice accounting format. Review Guest Bills.')
    }
    subtotal += discount
  }
  const tax = cents(invoice.tax_amount)
  const total = cents(invoice.total_amount)
  if (subtotal + tax - discount !== total || cents(folio.charges_amount) !== subtotal) {
    throw new Error('The issued invoice and live charges differ. Review Guest Bills.')
  }
  const paid = Math.max(0, cents(folio.collection_amount) - cents(folio.refund_amount))
  return {
    subtotal: subtotal / 100,
    taxPercent: Number(invoice.tax_percent ?? 0),
    taxAmount: tax / 100,
    discountValue: Number(invoice.discount_value ?? 0),
    discountAmount: discount / 100,
    grandTotal: total / 100,
    previouslyPaid: paid / 100,
    amountToCollect: Math.max(0, total - paid) / 100,
    excessPaid: Math.max(0, paid - total) / 100,
  }
}
