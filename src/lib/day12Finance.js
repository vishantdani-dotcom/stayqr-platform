import { supabase } from './supabase'

export const DAY12_PAYMENT_METHODS = [
  { value: 'cash', label: 'Cash' },
  { value: 'card', label: 'Card' },
  { value: 'upi', label: 'UPI' },
  { value: 'bank_transfer', label: 'Bank transfer' },
  { value: 'payment_link', label: 'Payment link' },
  { value: 'other', label: 'Other' },
]

export const DAY12_SUPPLY_MODES = [
  { value: 'intra_state', label: 'Intra-state — CGST + SGST' },
  { value: 'inter_state', label: 'Inter-state — IGST' },
  { value: 'exempt', label: 'Exempt supply' },
]

export const DAY12_TAX_CATEGORIES = [
  { value: 'room', label: 'Room' },
  { value: 'food', label: 'Food' },
  { value: 'service', label: 'Service' },
  { value: 'manual', label: 'Manual charge' },
  { value: 'other', label: 'Other' },
]

export function createDay12RequestId(prefix = 'day12') {
  const randomPart =
    typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`

  return `${prefix}:${randomPart}`
}

function assertResponse(response, label) {
  if (response.error) {
    throw new Error(response.error.message || `${label} failed.`)
  }

  return response.data || []
}

async function invoke(name, args) {
  const { data, error } = await supabase.rpc(name, args)

  if (error) {
    throw new Error(error.message || `${name} failed.`)
  }

  if (data?.ok === false) {
    throw new Error(data.reason || `${name} was rejected.`)
  }

  return data
}

function unique(values) {
  return [...new Set(values.filter(Boolean))]
}

async function loadByIds(table, columns, hotelId, ids) {
  const cleanIds = unique(ids)
  if (!hotelId || cleanIds.length === 0) return []

  return assertResponse(
    await supabase
      .from(table)
      .select(columns)
      .eq('hotel_id', hotelId)
      .in('id', cleanIds),
    `Load ${table}`
  )
}

export async function loadDay12Workspace(hotelId) {
  if (!hotelId) {
    return {
      invoices: [],
      receipts: [],
      shifts: [],
      shiftEntries: [],
      audits: [],
      exceptions: [],
      exports: [],
      taxRates: [],
      folios: [],
    }
  }

  const [
    invoiceResponse,
    receiptResponse,
    shiftResponse,
    entryResponse,
    auditResponse,
    exceptionResponse,
    exportResponse,
    taxRateResponse,
    folioResponse,
  ] = await Promise.all([
    supabase
      .from('invoices')
      .select('*, invoice_items(*)')
      .eq('hotel_id', hotelId)
      .order('created_at', { ascending: false }),
    supabase
      .from('receipts')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('issued_at', { ascending: false }),
    supabase
      .from('cashier_shifts')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('opened_at', { ascending: false })
      .limit(100),
    supabase
      .from('cashier_shift_entries')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('occurred_at', { ascending: false })
      .limit(500),
    supabase
      .from('night_audits')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('business_date', { ascending: false })
      .limit(100),
    supabase
      .from('night_audit_exceptions')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('created_at', { ascending: false })
      .limit(1000),
    supabase
      .from('accounting_exports')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('generated_at', { ascending: false })
      .limit(100),
    supabase
      .from('tax_rates')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('charge_category', { ascending: true }),
    supabase
      .from('folios')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('updated_at', { ascending: false }),
  ])

  const invoices = assertResponse(invoiceResponse, 'Load invoices')
  const receipts = assertResponse(receiptResponse, 'Load receipts')
  const shifts = assertResponse(shiftResponse, 'Load cashier shifts')
  const shiftEntries = assertResponse(entryResponse, 'Load cashier entries')
  const audits = assertResponse(auditResponse, 'Load night audits')
  const exceptions = assertResponse(exceptionResponse, 'Load night-audit exceptions')
  const exports = assertResponse(exportResponse, 'Load accounting exports')
  const taxRates = assertResponse(taxRateResponse, 'Load tax rates')
  const folios = assertResponse(folioResponse, 'Load folios')

  const guestIds = unique([
    ...invoices.map((invoice) => invoice.guest_id),
    ...folios.map((folio) => folio.guest_id),
  ])
  const roomIds = unique([
    ...invoices.map((invoice) => invoice.room_id),
    ...folios.map((folio) => folio.room_id),
  ])

  const [guests, rooms] = await Promise.all([
    loadByIds('guests', 'id, full_name, phone, email', hotelId, guestIds),
    loadByIds('rooms', 'id, room_number, room_type, status', hotelId, roomIds),
  ])

  const guestMap = Object.fromEntries(guests.map((guest) => [guest.id, guest]))
  const roomMap = Object.fromEntries(rooms.map((room) => [room.id, room]))
  const folioMap = Object.fromEntries(folios.map((folio) => [folio.id, folio]))
  const entryMap = shiftEntries.reduce((accumulator, entry) => {
    const current = accumulator[entry.cashier_shift_id] || []
    accumulator[entry.cashier_shift_id] = [...current, entry]
    return accumulator
  }, {})
  const exceptionMap = exceptions.reduce((accumulator, exceptionRecord) => {
    const current = accumulator[exceptionRecord.night_audit_id] || []
    accumulator[exceptionRecord.night_audit_id] = [...current, exceptionRecord]
    return accumulator
  }, {})
  const exportMap = exports.reduce((accumulator, exportRecord) => {
    const current = accumulator[exportRecord.night_audit_id] || []
    accumulator[exportRecord.night_audit_id] = [...current, exportRecord]
    return accumulator
  }, {})

  return {
    invoices: invoices.map((invoice) => ({
      ...invoice,
      invoice_items: [...(invoice.invoice_items || [])].sort(
        (first, second) =>
          Number(first.line_number || 9999) - Number(second.line_number || 9999)
      ),
      guest: guestMap[invoice.guest_id] || null,
      room: roomMap[invoice.room_id] || null,
    })),
    receipts: receipts.map((receipt) => {
      const folio = folioMap[receipt.folio_id] || null
      return {
        ...receipt,
        folio,
        guest: guestMap[folio?.guest_id] || null,
        room: roomMap[folio?.room_id] || null,
      }
    }),
    shifts: shifts.map((shift) => ({
      ...shift,
      entries: entryMap[shift.id] || [],
    })),
    shiftEntries,
    audits: audits.map((audit) => ({
      ...audit,
      exceptions: exceptionMap[audit.id] || [],
      exports: exportMap[audit.id] || [],
    })),
    exceptions,
    exports,
    taxRates,
    folios: folios.map((folio) => ({
      ...folio,
      guest: guestMap[folio.guest_id] || null,
      room: roomMap[folio.room_id] || null,
    })),
  }
}

export function loadInvoiceSnapshot(hotelId, invoiceId) {
  return invoke('get_invoice_snapshot', {
    target_hotel_id: hotelId,
    target_invoice_id: invoiceId,
  })
}

export function previewFolioInvoice(hotelId, folioId, supplyMode, invoiceDate) {
  return invoke('preview_folio_invoice', {
    target_hotel_id: hotelId,
    target_folio_id: folioId,
    supply_mode_value: supplyMode,
    invoice_date_value: invoiceDate,
  })
}

export function issueFolioInvoice(
  hotelId,
  folioId,
  supplyMode,
  invoiceDate,
  requestId
) {
  return invoke('issue_folio_invoice', {
    target_hotel_id: hotelId,
    target_folio_id: folioId,
    supply_mode_value: supplyMode,
    invoice_date_value: invoiceDate,
    request_id_value: requestId,
  })
}

export function upsertTaxRate(hotelId, values) {
  return invoke('upsert_tax_rate', {
    target_hotel_id: hotelId,
    target_tax_rate_id: values.id || null,
    code_value: values.code,
    name_value: values.name,
    charge_category_value: values.charge_category,
    hsn_sac_code_value: values.hsn_sac_code || null,
    rate_percent_value: Number(values.rate_percent),
    cess_percent_value: Number(values.cess_percent || 0),
    valid_from_value: values.valid_from,
    valid_to_value: values.valid_to || null,
    active_value: Boolean(values.is_active),
  })
}

export function openCashierShift(hotelId, openingCash, requestId) {
  return invoke('open_cashier_shift', {
    target_hotel_id: hotelId,
    opening_cash_value: Number(openingCash),
    request_id_value: requestId,
  })
}

export function closeCashierShift(
  hotelId,
  shiftId,
  declaredCash,
  notes,
  requestId
) {
  return invoke('close_cashier_shift', {
    target_hotel_id: hotelId,
    target_shift_id: shiftId,
    declared_cash_value: Number(declaredCash),
    close_notes_value: notes || null,
    request_id_value: requestId,
  })
}

export function getCashierShiftReport(hotelId, shiftId) {
  return invoke('get_cashier_shift_report', {
    target_hotel_id: hotelId,
    target_shift_id: shiftId,
  })
}

export function previewDayClose(hotelId, businessDate) {
  return invoke('preview_day_close', {
    h: hotelId,
    business_date_value: businessDate,
  })
}

export function closeNightAudit(
  hotelId,
  businessDate,
  acknowledgeExceptions,
  notes,
  requestId
) {
  return invoke('close_night_audit', {
    target_hotel_id: hotelId,
    business_date_value: businessDate,
    acknowledge_exceptions: Boolean(acknowledgeExceptions),
    close_notes_value: notes || null,
    request_id_value: requestId,
  })
}

export function generateAccountingCsv(hotelId, dateFrom, dateTo, requestId) {
  return invoke('generate_accounting_csv', {
    target_hotel_id: hotelId,
    date_from_value: dateFrom,
    date_to_value: dateTo,
    request_id_value: requestId,
  })
}

export function getNightAuditSnapshot(hotelId, nightAuditId) {
  return invoke('get_night_audit_snapshot', {
    target_hotel_id: hotelId,
    target_night_audit_id: nightAuditId,
  })
}
