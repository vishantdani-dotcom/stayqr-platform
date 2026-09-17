import { auditGuestDocumentAccess } from './guestCompliance'

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
      const dataUrl = entry?.dataUrl
      const isImage = file?.type === 'image/jpeg' || file?.type === 'image/png'
      const isPdf = file?.type === 'application/pdf'
      const fileLabel = safeText(file?.name, 'Captured ID')

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
    body{margin:0;background:#fff;color:#111827;font-family:Arial,Helvetica,sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    .page{min-height:277mm;padding:7mm 8mm 5mm;position:relative}
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
    .audit-footer{position:absolute;left:8mm;right:8mm;bottom:4mm;display:flex;justify-content:space-between;gap:16px;border-top:1px solid #e5e7eb;padding-top:5px;color:#6b7280;font-size:7px}
    .document-page{min-height:277mm;padding:8mm;position:relative}.document-page-head{display:flex;justify-content:space-between;gap:20px;align-items:flex-start;padding-bottom:10px;border-bottom:3px solid #e8b62f}.document-page-head small{color:#9a6e00;font-size:9px;font-weight:900;letter-spacing:.14em}.document-page-head h2{margin:4px 0 0;font-size:20px}.doc-meta{text-align:right}.doc-meta span{display:block;color:#6b7280;font-size:9px}.doc-meta strong{display:block;margin-top:4px;font-size:11px}
    .document-image-wrap{height:220mm;display:flex;align-items:center;justify-content:center;padding:12mm 4mm}.document-image-wrap img{max-width:100%;max-height:100%;object-fit:contain;border:1px solid #d7dde5;border-radius:8px;box-shadow:0 10px 28px rgba(15,23,42,.08)}
    .document-pdf-note,.document-missing{margin:70mm auto 0;max-width:130mm;padding:22px;border:1px solid #d7dde5;border-radius:12px;text-align:center}.document-pdf-note strong{display:block;font-size:16px}.document-pdf-note span{display:block;margin-top:8px;color:#6b7280;font-size:11px}.document-pdf-note p{font-size:10px;line-height:1.6;color:#4b5563}
    .document-signature-line{display:grid;grid-template-columns:1fr 1fr;gap:30px;margin-top:4mm}.document-signature-line span{padding-top:14px;border-top:1px solid #4b5563;text-align:center;font-size:8px;color:#4b5563}
    .screen-only{position:fixed;right:16px;top:16px;z-index:10;border:0;border-radius:9px;background:#e8b62f;color:#111;padding:10px 14px;font-weight:800;cursor:pointer}
    @media print{.screen-only{display:none!important}}
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

  return `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(hotelName)} — Room ${escapeHtml(roomNumber)} check-in pack</title><style>${printStyles()}</style></head><body><button class="screen-only" onclick="window.print()">Print / Save PDF</button>${registrationPage}${includeDocuments ? documentPages(documentEntries) : ''}<script>
    (()=>{
      const waitForImages=()=>Promise.all(Array.from(document.images).map((img)=>img.complete?Promise.resolve():new Promise((resolve)=>{img.onload=resolve;img.onerror=resolve})))
      waitForImages().then(()=>setTimeout(()=>window.print(),180))
    })()
  </script></body></html>`
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
    entries.map(async (entry) => ({
      ...entry,
      dataUrl: entry?.capture?.file ? await readFileAsDataUrl(entry.capture.file) : null,
    }))
  )
}

export async function printCheckInPack(snapshot) {
  const popup = openPrintWindow()

  try {
    const documentEntries = Array.isArray(snapshot?.documentEntries)
      ? snapshot.documentEntries.filter((entry) => entry?.capture?.file)
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

    const preparedEntries = await prepareDocumentEntries(documentEntries)
    const html = buildRegistrationHtml({ ...snapshot, documentEntries: preparedEntries, includeDocuments: true })
    popup.document.open()
    popup.document.write(html)
    popup.document.close()
  } catch (error) {
    popup.close()
    throw error
  }
}

export function printRegistrationCard(snapshot) {
  const popup = openPrintWindow()
  const html = buildRegistrationHtml({ ...snapshot, documentEntries: [], includeDocuments: false })
  popup.document.open()
  popup.document.write(html)
  popup.document.close()
}
