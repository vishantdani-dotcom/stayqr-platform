import { auditGuestDocumentAccess } from './guestCompliance'
import { supabase } from './supabase'

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

function safeText(value, fallback = '—') {
  const text = String(value ?? '').trim()
  return text || fallback
}

function formatDateTime(value) {
  if (!value) return '—'
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return safeText(value)
  return parsed.toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function formatDate(value) {
  if (!value) return '—'
  const parsed = new Date(`${value}T00:00:00`)
  if (Number.isNaN(parsed.getTime())) return safeText(value)
  return parsed.toLocaleDateString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
}

function formatIdType(value) {
  const normalized = String(value || '').trim().toLowerCase()
  return {
    aadhaar: 'Aadhaar Card',
    passport: 'Passport',
    pan: 'PAN Card',
    driving_licence: 'Driving Licence',
    voter_id: 'Voter ID',
    visa: 'Visa',
    form_c: 'Form C',
    other: 'Other ID',
  }[normalized] || safeText(value, 'ID document')
}


function maskIdReference(value, idType = '') {
  const raw = String(value || '').trim()
  if (!raw) return ''
  if (/x/i.test(raw)) return raw

  const compact = raw.replace(/\s+/g, '')
  const last4 = compact.slice(-4)
  const normalized = String(idType || '').trim().toLowerCase()

  if (!last4) return 'Masked'
  if (normalized === 'aadhaar') return `XXXX XXXX ${last4}`
  if (normalized === 'pan') return `XXXXX${last4}`
  return `•••• ${last4}`
}

function guestRecordForPrint(guest, maskedReference = '') {
  if (!guest) return null
  return {
    ...guest,
    id_number: maskedReference || maskIdReference(guest.id_number, guest.id_type),
  }
}

function formatGender(value) {
  const normalized = String(value || '').trim().toLowerCase()
  return {
    male: 'Male',
    female: 'Female',
    non_binary: 'Non-binary',
    other: 'Other',
    prefer_not_to_say: 'Prefer not to say',
  }[normalized] || safeText(value)
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    if (!file) {
      resolve(null)
      return
    }

    const reader = new FileReader()
    reader.onload = () => resolve(typeof reader.result === 'string' ? reader.result : null)
    reader.onerror = () => reject(new Error(`Unable to read ${file.name || 'captured ID'} for printing.`))
    reader.readAsDataURL(file)
  })
}

function guestAddress(guest) {
  return [
    guest?.address_line1,
    guest?.address_line2,
    guest?.city,
    guest?.state_region,
    guest?.postal_code,
    guest?.country_of_residence,
  ]
    .map((item) => String(item || '').trim())
    .filter(Boolean)
    .join(', ')
}

function detailRow(label, value) {
  return `<div class="detail"><small>${escapeHtml(label)}</small><strong>${escapeHtml(safeText(value))}</strong></div>`
}

function guestDetailBlock(guest, title) {
  return `
    <section class="person-card">
      <div class="person-title"><span>${escapeHtml(title)}</span><strong>${escapeHtml(safeText(guest?.full_name, 'Guest'))}</strong></div>
      <div class="details-grid">
        ${detailRow('Phone', guest?.phone)}
        ${detailRow('Email', guest?.email)}
        ${detailRow('Date of birth', formatDate(guest?.date_of_birth))}
        ${detailRow('Gender', formatGender(guest?.gender))}
        ${detailRow('Nationality', guest?.nationality)}
        ${detailRow('ID type', formatIdType(guest?.id_type))}
        ${detailRow('ID reference', guest?.id_number || 'Not recorded')}
        ${detailRow('Address', guestAddress(guest))}
      </div>
    </section>`
}

function companionRows(companions = []) {
  if (!companions.length) {
    return '<tr><td colspan="5">No additional occupants recorded.</td></tr>'
  }

  return companions
    .map((companion, index) => `
      <tr>
        <td>${index + 1}</td>
        <td><strong>${escapeHtml(safeText(companion.full_name, 'Guest'))}</strong><br><small>${escapeHtml(safeText(companion.relationship, companion.guest_category || 'Occupant'))}</small></td>
        <td>${escapeHtml(safeText(companion.phone))}</td>
        <td>${escapeHtml(formatIdType(companion.id_type))}</td>
        <td>${escapeHtml(safeText(companion.id_number, 'Not recorded'))}</td>
      </tr>`)
    .join('')
}

function documentPages(documentEntries = []) {
  if (!documentEntries.length) return ''

  return documentEntries
    .map((entry) => {
      const capture = entry?.capture
      const file = capture?.file
      const mimeType = String(file?.type || entry?.mimeType || '').toLowerCase()
      const dataUrl = entry?.dataUrl
      const isImage = mimeType === 'image/jpeg' || mimeType === 'image/png'
      const isPdf = mimeType === 'application/pdf'
      const fileLabel = safeText(file?.name || entry?.fileName, 'Captured ID')

      let documentVisual = '<div class="document-missing">No printable ID image was available.</div>'
      if (isImage && dataUrl) {
        documentVisual = `<div class="document-image-wrap"><img src="${dataUrl}" alt="${escapeHtml(fileLabel)}"></div>`
      } else if (isPdf) {
        documentVisual = `
          <div class="document-pdf-note">
            <strong>PDF identity document captured</strong>
            <span>${escapeHtml(fileLabel)}</span>
            <p>The PDF remains securely stored in StayQR. Print the original PDF separately when a full-size statutory copy is required.</p>
          </div>`
      }

      return `
        <section class="document-page page-break">
          <div class="document-page-head">
            <div><small>ID COPY</small><h2>${escapeHtml(safeText(entry?.guestName, 'Guest'))}</h2></div>
            <div class="doc-meta"><span>${escapeHtml(formatIdType(entry?.idType))}</span><strong>${escapeHtml(safeText(entry?.idNumber, 'Masked reference not available'))}</strong></div>
          </div>
          ${documentVisual}
          <div class="document-signature-line"><span>Guest signature</span><span>Reception verified</span></div>
        </section>`
    })
    .join('')
}

function printStyles() {
  return `
    @page{size:A4;margin:10mm}
    *{box-sizing:border-box}
    html{background:#e9edf2}
    body{margin:0;padding:72px 16px 40px;background:#e9edf2;color:#111827;font-family:Arial,Helvetica,sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    .page,.document-page{width:210mm;min-height:297mm;margin:0 auto 24px;background:#fff;position:relative;box-shadow:0 22px 60px rgba(15,23,42,.14);border:1px solid #dce2e8}
    .page{padding:17mm 18mm 15mm}
    .document-page{padding:18mm}
    .page-break{break-before:page;page-break-before:always}
    .brand-head{display:flex;align-items:center;justify-content:space-between;gap:20px;padding:18px 20px;border-radius:14px;background:#0b1118;color:#fff;border-bottom:4px solid #e8b62f}
    .brand{display:flex;align-items:center;gap:14px}.brand img{width:52px;height:52px;object-fit:contain;border-radius:10px;background:#fff;padding:5px}.brand h1{margin:0;font-size:22px}.brand p{margin:4px 0 0;color:#cbd5e1;font-size:11px}
    .pack-title{text-align:right}.pack-title small{display:block;color:#e8b62f;font-size:9px;font-weight:800;letter-spacing:.14em}.pack-title strong{display:block;margin-top:5px;font-size:15px}.pack-title span{display:block;margin-top:4px;color:#cbd5e1;font-size:9px}
    .stay-summary{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:14px 0}.summary-box{border:1px solid #d7dde5;border-radius:10px;padding:11px}.summary-box small{display:block;color:#6b7280;font-size:8px;font-weight:700;text-transform:uppercase;letter-spacing:.08em}.summary-box strong{display:block;margin-top:5px;font-size:12px}
    .section-title{display:flex;align-items:center;gap:8px;margin:14px 0 8px;font-size:12px;font-weight:800}.section-title:after{content:"";height:1px;background:#d7dde5;flex:1}.section-dot{width:8px;height:8px;border-radius:50%;background:#e8b62f}
    .person-card{border:1px solid #d7dde5;border-radius:12px;padding:13px;margin-bottom:10px}.person-title{display:flex;justify-content:space-between;gap:16px;align-items:baseline;padding-bottom:8px;margin-bottom:8px;border-bottom:1px solid #e5e7eb}.person-title span{color:#6b7280;font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.07em}.person-title strong{font-size:15px}
    .details-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:9px}.detail{min-width:0}.detail small{display:block;color:#6b7280;font-size:8px;margin-bottom:3px}.detail strong{display:block;font-size:10px;font-weight:700;word-break:break-word}
    table{width:100%;border-collapse:collapse;font-size:9px}th{background:#111827;color:#fff;text-align:left;padding:8px}td{border-bottom:1px solid #e5e7eb;padding:8px;vertical-align:top}td small{color:#6b7280}
    .stay-notes{display:grid;grid-template-columns:1fr 1fr;gap:10px}.note-box{border:1px solid #d7dde5;border-radius:10px;padding:10px}.note-box small{display:block;color:#6b7280;font-size:8px}.note-box strong,.note-box p{font-size:10px;line-height:1.5}.note-box p{margin:5px 0 0}
    .declaration{margin-top:13px;padding:12px 14px;border-radius:10px;background:#f7f4e8;border:1px solid #eadca8;font-size:9px;line-height:1.55}
    .signatures{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px;margin-top:24px}.signature{padding-top:28px;border-top:1px solid #4b5563;font-size:8px;color:#4b5563;text-align:center}
    .audit-footer{position:absolute;left:18mm;right:18mm;bottom:10mm;display:flex;justify-content:space-between;gap:16px;border-top:1px solid #e5e7eb;padding-top:5px;color:#6b7280;font-size:7px}
    .document-page-head{display:flex;justify-content:space-between;gap:20px;align-items:flex-start;padding-bottom:10px;border-bottom:3px solid #e8b62f}.document-page-head small{color:#9a6e00;font-size:9px;font-weight:900;letter-spacing:.14em}.document-page-head h2{margin:4px 0 0;font-size:20px}.doc-meta{text-align:right}.doc-meta span{display:block;color:#6b7280;font-size:9px}.doc-meta strong{display:block;margin-top:4px;font-size:11px}
    .document-image-wrap{height:220mm;display:flex;align-items:center;justify-content:center;padding:12mm 4mm}.document-image-wrap img{max-width:100%;max-height:100%;object-fit:contain;border:1px solid #d7dde5;border-radius:8px;box-shadow:0 10px 28px rgba(15,23,42,.08)}
    .document-pdf-note,.document-missing{margin:70mm auto 0;max-width:130mm;padding:22px;border:1px solid #d7dde5;border-radius:12px;text-align:center}.document-pdf-note strong{display:block;font-size:16px}.document-pdf-note span{display:block;margin-top:8px;color:#6b7280;font-size:11px}.document-pdf-note p{font-size:10px;line-height:1.6;color:#4b5563}
    .document-signature-line{display:grid;grid-template-columns:1fr 1fr;gap:30px;margin-top:4mm}.document-signature-line span{padding-top:14px;border-top:1px solid #4b5563;text-align:center;font-size:8px;color:#4b5563}
    .screen-only{position:fixed;right:18px;top:18px;z-index:100;border:1px solid #d6a71e;border-radius:11px;background:linear-gradient(135deg,#f5c33b,#dca315);color:#111;padding:12px 17px;font-weight:900;cursor:pointer;box-shadow:0 12px 30px rgba(15,23,42,.20)}
    .screen-only:hover{transform:translateY(-1px)}.screen-only:disabled{opacity:.55;cursor:wait;transform:none}
    @media screen and (max-width:860px){
      body{padding:76px 10px 28px}
      .page,.document-page{width:100%;min-height:auto;margin-bottom:16px;border-radius:12px}
      .page,.document-page{padding:18px}
      .brand-head{align-items:flex-start}.pack-title{text-align:left}
      .stay-summary{grid-template-columns:repeat(2,minmax(0,1fr))}.details-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
      .audit-footer{position:static;margin-top:24px}.document-image-wrap{height:auto;min-height:54vh;padding:22px 0}
      .screen-only{top:12px;right:12px;left:12px;width:calc(100% - 24px);min-height:48px}
    }
    @media screen and (max-width:560px){
      body{padding:72px 7px 20px}
      .page,.document-page{padding:14px;border-radius:11px}
      .brand-head{flex-direction:column;padding:15px;gap:12px}
      .brand h1{font-size:18px}.brand p{font-size:10px}.pack-title strong{font-size:14px}
      .stay-summary{grid-template-columns:1fr 1fr;gap:7px}.summary-box{padding:9px}
      .person-title{align-items:flex-start;flex-direction:column;gap:4px}
      .details-grid{grid-template-columns:1fr}.stay-notes{grid-template-columns:1fr}
      table{display:block;overflow-x:auto;white-space:nowrap;-webkit-overflow-scrolling:touch}
      .signatures{grid-template-columns:1fr;gap:18px}.signature{padding-top:22px}
      .document-page-head{flex-direction:column;gap:9px}.doc-meta{text-align:left}
      .document-image-wrap{min-height:40vh;padding:16px 0}
      .document-signature-line{grid-template-columns:1fr;gap:20px}
      .audit-footer{flex-direction:column;gap:4px;font-size:7px}
    }
    @media print{
      html,body{background:#fff!important}
      body{padding:0!important}
      .screen-only{display:none!important}
      .page,.document-page{width:auto;min-height:277mm;margin:0;border:0;border-radius:0;box-shadow:none;break-after:page;page-break-after:always}
      .page{padding:7mm 8mm 5mm}
      .document-page{padding:8mm}
      .audit-footer{left:8mm;right:8mm;bottom:4mm}
      .document-page:last-child{break-after:auto;page-break-after:auto}
    }
  `
}
function buildRegistrationHtml({
  hotel,
  staff,
  guest,
  companions,
  stayDetails,
  result,
  roomCharge,
  checkinTime,
  checkoutTime,
  notes,
  documentEntries,
  includeDocuments,
}) {
  const hotelName = safeText(hotel?.hotel_name, 'StayQR Hotel')
  const roomNumber = safeText(result?.room_number)
  const checkInReference = safeText(result?.guest_session_id || result?.request_id)
  const printedAt = new Date().toLocaleString('en-IN')
  const printedBy = safeText(staff?.full_name, 'Authorized hotel staff')
  const role = safeText(staff?.role, 'staff').replace(/_/g, ' ')
  const logo = String(hotel?.logo_url || '').trim()
  const totalGuests = 1 + (companions?.length || 0)

  const hotelBrand = logo
    ? `<img src="${escapeHtml(logo)}" alt="${escapeHtml(hotelName)} logo">`
    : `<div style="width:52px;height:52px;border-radius:10px;background:#fff;color:#111;display:grid;place-items:center;font-weight:900">SQ</div>`

  const registrationPage = `
    <section class="page">
      <header class="brand-head">
        <div class="brand">${hotelBrand}<div><h1>${escapeHtml(hotelName)}</h1><p>${escapeHtml(safeText(hotel?.location, 'Guest registration'))}</p></div></div>
        <div class="pack-title"><small>STAYQR FRONT DESK</small><strong>Guest Registration & Check-in Pack</strong><span>Reference ${escapeHtml(checkInReference)}</span></div>
      </header>

      <div class="stay-summary">
        <div class="summary-box"><small>Room</small><strong>Room ${escapeHtml(roomNumber)}</strong></div>
        <div class="summary-box"><small>Check-in</small><strong>${escapeHtml(formatDateTime(result?.checkin_time || checkinTime))}</strong></div>
        <div class="summary-box"><small>Check-out</small><strong>${escapeHtml(formatDateTime(result?.checkout_time || checkoutTime))}</strong></div>
        <div class="summary-box"><small>Occupancy</small><strong>${totalGuests} guest${totalGuests === 1 ? '' : 's'}</strong></div>
      </div>

      <div class="section-title"><span class="section-dot"></span>Primary guest</div>
      ${guestDetailBlock(guest, 'Primary guest')}

      <div class="section-title"><span class="section-dot"></span>Additional occupants</div>
      <table><thead><tr><th>#</th><th>Guest</th><th>Phone</th><th>ID type</th><th>ID reference</th></tr></thead><tbody>${companionRows(companions)}</tbody></table>

      <div class="section-title"><span class="section-dot"></span>Stay details</div>
      <div class="stay-notes">
        <div class="note-box"><small>Purpose / arrival</small><p><strong>${escapeHtml(safeText(stayDetails?.purpose_of_visit || guest?.purpose_of_visit, 'Not specified'))}</strong><br>${escapeHtml(safeText(stayDetails?.arrival_from, 'Arrival origin not recorded'))}${stayDetails?.arrival_mode ? ` · ${escapeHtml(stayDetails.arrival_mode)}` : ''}</p></div>
        <div class="note-box"><small>Room charge / notes</small><p><strong>₹${Number(roomCharge || result?.room_charge || 0).toLocaleString('en-IN')}</strong><br>${escapeHtml(safeText(notes || stayDetails?.special_notes, 'No special notes'))}</p></div>
      </div>

      <div class="declaration">
        I confirm that the guest/stay information provided to the hotel is correct to the best of my knowledge. I acknowledge the hotel&apos;s check-in and stay policies. The hotel may retain this signed registration record and identity-document copy where required by its policy or applicable law.
      </div>

      <div class="signatures">
        <div class="signature">Primary guest signature</div>
        <div class="signature">Reception / authorized staff</div>
        <div class="signature">Hotel stamp</div>
      </div>

      <div class="audit-footer"><span>Printed by ${escapeHtml(printedBy)} · ${escapeHtml(role)}</span><span>${escapeHtml(printedAt)} · StayQR Check-in Pack</span></div>
    </section>`

  return `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(hotelName)} — Room ${escapeHtml(roomNumber)} check-in pack</title><style>${printStyles()}</style></head><body><button id="stayqr-print-button" class="screen-only" type="button">Print / Save PDF</button>${registrationPage}${includeDocuments ? documentPages(documentEntries) : ''}</body></html>`
}

function openPrintWindow() {
  const popup = window.open('', '_blank')
  if (!popup) {
    throw new Error('Allow pop-ups for StayQR to print the check-in pack.')
  }
  popup.opener = null
  popup.document.open()
  popup.document.write('<!doctype html><html><body style="font-family:Arial;padding:30px">Preparing secure check-in pack…</body></html>')
  popup.document.close()
  return popup
}

async function prepareDocumentEntries(entries = []) {
  return Promise.all(
    entries.map(async (entry) => {
      if (entry?.capture?.file) {
        return { ...entry, dataUrl: await readFileAsDataUrl(entry.capture.file) }
      }

      const mimeType = String(entry?.mimeType || '').toLowerCase()
      if (entry?.storagePath && (mimeType === 'image/jpeg' || mimeType === 'image/png')) {
        const { data, error } = await supabase.storage
          .from(entry?.storageBucket || 'guest-documents')
          .createSignedUrl(entry.storagePath, 300)
        if (error) throw error
        if (!data?.signedUrl) throw new Error(`Unable to open ${safeText(entry?.guestName, 'guest')} ID for printing.`)
        return { ...entry, dataUrl: data.signedUrl }
      }

      return { ...entry, dataUrl: null }
    })
  )
}

function bindPrintButton(popup) {
  const button = popup?.document?.getElementById('stayqr-print-button')
  if (!button) return

  button.addEventListener('click', () => {
    popup.focus()
    popup.print()
  })
}

function writePrintPreview(popup, html) {
  popup.document.open()
  popup.document.write(html)
  popup.document.close()

  const arm = () => bindPrintButton(popup)
  if (popup.document.readyState === 'complete') {
    arm()
  } else {
    popup.addEventListener('load', arm, { once: true })
  }
}

async function auditedPreparedDocuments(snapshot) {
  const documentEntries = Array.isArray(snapshot?.documentEntries)
    ? snapshot.documentEntries.filter((entry) => entry?.capture?.file || entry?.storagePath)
    : []

  for (const entry of documentEntries) {
    if (!entry?.documentId) {
      throw new Error(`${safeText(entry?.guestName, 'Guest')} ID was not saved securely, so StayQR will not print that document copy.`)
    }

    await auditGuestDocumentAccess({
      hotelId: snapshot?.hotel?.id,
      documentId: entry.documentId,
      action: 'print',
      reason: 'Front desk check-in pack print',
    })
  }

  return prepareDocumentEntries(documentEntries)
}

async function loadStoredCheckInPackSnapshot({ hotel, staff, sessionId }) {
  if (!hotel?.id || !sessionId) throw new Error('StayQR could not identify this active stay.')

  const sessionSelect = `
    id, hotel_id, guest_id, room_id, status, checkin_time, checkout_time, extended_until,
    guests (
      id, full_name, phone, email, id_type, id_number, date_of_birth, gender, nationality,
      country_of_residence, address_line1, address_line2, city, state_region, postal_code, purpose_of_visit
    ),
    rooms (id, room_number, room_type)
  `

  const { data: session, error: sessionError } = await supabase
    .from('guest_sessions')
    .select(sessionSelect)
    .eq('hotel_id', hotel.id)
    .eq('id', sessionId)
    .maybeSingle()
  if (sessionError) throw sessionError
  if (!session) throw new Error('The selected StayQR stay could not be found.')
  if (session.status !== 'active') throw new Error('Check-in paperwork reprint is available only for an active checked-in stay.')

  const [companionsResult, stayResult, paymentsResult, documentsResult] = await Promise.all([
    supabase
      .from('guest_companions')
      .select('guest_id, relationship, guest_category')
      .eq('hotel_id', hotel.id)
      .eq('guest_session_id', sessionId)
      .order('created_at', { ascending: true }),
    supabase
      .from('guest_stay_details')
      .select('*')
      .eq('hotel_id', hotel.id)
      .eq('guest_session_id', sessionId)
      .maybeSingle(),
    supabase
      .from('payments')
      .select('amount, payment_type, created_at')
      .eq('hotel_id', hotel.id)
      .eq('guest_session_id', sessionId)
      .eq('payment_type', 'room_charge')
      .order('created_at', { ascending: true })
      .limit(1),
    supabase
      .from('guest_documents')
      .select('id, guest_id, document_type, storage_bucket, storage_path, original_file_name, mime_type, document_number_masked, created_at')
      .eq('hotel_id', hotel.id)
      .eq('guest_session_id', sessionId)
      .is('deleted_at', null)
      .order('created_at', { ascending: true }),
  ])

  if (companionsResult.error) throw companionsResult.error
  if (stayResult.error) throw stayResult.error
  if (paymentsResult.error) throw paymentsResult.error
  if (documentsResult.error) throw documentsResult.error

  const memberships = companionsResult.data || []
  const companionIds = [...new Set(memberships.map((item) => item.guest_id).filter(Boolean))]
  let companionGuests = []

  if (companionIds.length) {
    const { data, error } = await supabase
      .from('guests')
      .select('id, full_name, phone, email, id_type, id_number, date_of_birth, gender, nationality, country_of_residence, address_line1, address_line2, city, state_region, postal_code, purpose_of_visit')
      .eq('hotel_id', hotel.id)
      .in('id', companionIds)
    if (error) throw error
    companionGuests = data || []
  }

  const documents = documentsResult.data || []
  const documentByGuest = new Map()
  for (const document of documents) {
    if (!documentByGuest.has(document.guest_id)) documentByGuest.set(document.guest_id, document)
  }

  const primaryDocument = documentByGuest.get(session.guest_id)
  const guest = guestRecordForPrint(
    session.guests,
    primaryDocument?.document_number_masked || maskIdReference(session.guests?.id_number, session.guests?.id_type)
  )

  const guestMap = new Map(companionGuests.map((item) => [item.id, item]))
  const companions = memberships.map((membership) => {
    const record = guestMap.get(membership.guest_id) || {}
    const document = documentByGuest.get(membership.guest_id)
    return {
      ...guestRecordForPrint(
        record,
        document?.document_number_masked || maskIdReference(record?.id_number, record?.id_type)
      ),
      relationship: membership.relationship,
      guest_category: membership.guest_category,
    }
  })

  const namesByGuestId = new Map([[session.guest_id, guest?.full_name || 'Primary guest']])
  for (const companion of companions) namesByGuestId.set(companion.id, companion.full_name || 'Guest')

  const documentEntries = documents.map((document) => ({
    documentId: document.id,
    guestName: namesByGuestId.get(document.guest_id) || 'Guest',
    idType: document.document_type,
    idNumber: document.document_number_masked || 'Masked reference not available',
    storageBucket: document.storage_bucket || 'guest-documents',
    storagePath: document.storage_path,
    mimeType: document.mime_type,
    fileName: document.original_file_name || 'Stored ID document',
  }))

  const roomCharge = Number(paymentsResult.data?.[0]?.amount || 0)
  const effectiveCheckout = session.extended_until || session.checkout_time

  return {
    hotel,
    staff,
    guest,
    companions,
    stayDetails: stayResult.data || {},
    result: {
      guest_session_id: session.id,
      room_number: session.rooms?.room_number,
      checkin_time: session.checkin_time,
      checkout_time: effectiveCheckout,
      room_charge: roomCharge,
    },
    roomCharge,
    checkinTime: session.checkin_time,
    checkoutTime: effectiveCheckout,
    notes: stayResult.data?.special_notes || '',
    documentEntries,
  }
}

export async function printCheckInPack(snapshot) {
  const popup = openPrintWindow()

  try {
    const preparedEntries = await auditedPreparedDocuments(snapshot)
    const html = buildRegistrationHtml({ ...snapshot, documentEntries: preparedEntries, includeDocuments: true })
    writePrintPreview(popup, html)
  } catch (error) {
    popup.close()
    throw error
  }
}

export function printRegistrationCard(snapshot) {
  const popup = openPrintWindow()
  const html = buildRegistrationHtml({ ...snapshot, documentEntries: [], includeDocuments: false })
  writePrintPreview(popup, html)
}

export async function printStoredCheckInPaperwork({ hotel, staff, sessionId, includeDocuments = true }) {
  const popup = openPrintWindow()

  try {
    const snapshot = await loadStoredCheckInPackSnapshot({ hotel, staff, sessionId })
    const preparedEntries = includeDocuments ? await auditedPreparedDocuments(snapshot) : []
    const html = buildRegistrationHtml({
      ...snapshot,
      documentEntries: preparedEntries,
      includeDocuments,
    })
    writePrintPreview(popup, html)
    return { documentCount: preparedEntries.length }
  } catch (error) {
    popup.close()
    throw error
  }
}
