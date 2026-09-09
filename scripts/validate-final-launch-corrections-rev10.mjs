import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');
let passed = 0;
let failed = 0;
function check(name, condition, detail = '') {
  if (condition) { console.log(`PASS ${name}${detail ? ` :: ${detail}` : ''}`); passed += 1; }
  else { console.error(`FAIL ${name}${detail ? ` :: ${detail}` : ''}`); failed += 1; }
}

const client = read('src/lib/idDocumentIntelligence.js');
const edge = read('supabase/functions/id-document-ocr/index.ts');
const capture = read('src/components/guests/SimpleGuestIdCapture.jsx');
const checkin = read('src/pages/checkin/CheckIn.jsx');
const guests = read('src/pages/guests/Guests.jsx');
const sidebar = read('src/components/sidebar/Sidebar.jsx');
const navbar = read('src/components/navbar/Navbar.jsx');
const bills = read('src/pages/folios/FolioSettlement.jsx');
const services = read('src/pages/services/ServiceRequests.jsx');
const guestCss = read('src/pages/guests/Guests.css');
const migration = read('supabase/migrations/202609060116_stay_owned_checkout_and_ocr_launch_hardening_REV1.sql');
const acceptance = read('supabase/staging/202609060116_stay_owned_checkout_and_ocr_launch_hardening_ACCEPTANCE_REV1.sql');

const mod = await import(`${pathToFileURL(path.join(root, 'src/lib/idDocumentIntelligence.js')).href}?rev10=${Date.now()}`);
const noisy = mod.extractIdentityFromText(`Government of India\nVerified\nDOB: 21/02/2002\nMALE\n1234 5678 6767\nDocuments to support identity and address should be updated in Aadhaar`, 'aadhaar');
check('OCR rejects Verified as guest name', !noisy.extractedFields.full_name, noisy.extractedFields.full_name || 'blank');
check('OCR rejects Aadhaar disclaimer as address', !noisy.extractedFields.address_line1, noisy.extractedFields.address_line1 || 'blank');
check('OCR keeps valid DOB from noisy card', noisy.extractedFields.date_of_birth === '2002-02-21');
check('OCR keeps valid gender from noisy card', noisy.extractedFields.gender === 'male');
check('OCR keeps masked Aadhaar last four', noisy.documentNumberMasked === 'XXXX XXXX 6767');
check('Noisy Aadhaar requires review', noisy.reviewRequired === true);

const good = mod.extractIdentityFromText(`Government of India\nAarav Mehta\nDOB: 22/03/1992\nMALE\n1234 5678 9012\nAddress: 42 MG Road\nBengaluru Karnataka 560038`, 'aadhaar');
check('Good Aadhaar name still extracts', good.extractedFields.full_name === 'Aarav Mehta');
check('Good Aadhaar address still extracts', /42 MG Road/i.test(good.extractedFields.address_line1 || ''));
check('Good Aadhaar is not forced to manual review', good.reviewRequired === false);
const clientTimeoutMatch = client.match(/CLIENT_OCR_TIMEOUT_MS\s*=\s*(\d+)/);
check('Client allows fallback provider latency', Boolean(clientTimeoutMatch && Number(clientTimeoutMatch[1]) >= 30000));
check('Client exposes quality score', client.includes('qualityScore: quality.score'));
check('Client marks reviewRequired', client.includes('reviewRequired: quality.reviewRequired'));
check('Edge has OCR.Space and Google fallback candidates', edge.includes("addProvider('google_vision')") && edge.includes("addProvider('ocr_space')"));
check('Edge chooses provider by extraction quality', edge.includes('qualityScore') && edge.includes('candidates.sort'));
check('Edge preserves raw OCR non-storage', edge.includes('rawOcrTextStored: false') && edge.includes('raw OCR text and provider response are intentionally not returned or persisted'));
check('Capture UI visibly supports Review required', capture.includes('Review required'));
check('Partial OCR results remain editable instead of hard failure', checkin.includes('Some ID details were extracted, but review is required'));

const checkoutStart = guests.indexOf('async function openSettlementModal');
const checkoutEnd = guests.indexOf('const settlementCalculation', checkoutStart);
const checkoutSource = guests.slice(checkoutStart, checkoutEnd);
check('Checkout preview loads authoritative stay folio', checkoutSource.includes('.from("folios")') && checkoutSource.includes('.eq("guest_session_id", session.id)'));
check('Checkout preview loads posted folio charge items', checkoutSource.includes('.from("folio_items")') && checkoutSource.includes('.eq("posting_status", "posted")'));
check('Checkout preview no longer totals food by current room', !checkoutSource.includes('.eq("room_id", room.id)'));
check('Checkout subtotal uses folio charges_amount', checkoutSource.includes('checkoutFolio.charges_amount'));
check('Checkout open-food guard uses guest_session_id', checkoutSource.includes('.eq("guest_session_id", session.id)'));
check('Checkout UI renamed Final Bill & Checkout', guests.includes('FINAL BILL & CHECKOUT'));
check('Checkout UI labels Food & Dining', guests.includes('label="Food & Dining"'));
check('Checkout UI labels Final Bill', guests.includes('label="Final Bill"'));
check('Checkout CTA simplifies zero-balance checkout', guests.includes('"Complete Checkout"'));
check('Checkout CTA can collect balance and checkout', guests.includes('Collect ₹'));
check('Guest Bills sidebar label is live', sidebar.includes("label: 'Guest Bills'"));
check('Guest Bills navbar label is live', navbar.includes("folios: 'Guest Bills'"));
check('Guest Bills page heading is live', bills.includes('<h1>Guest Bills</h1>'));
check('Guest Bills uses Billing access wording', bills.includes("'Billing access'"));
check('Guest Bills removes settlement jargon from page eyebrow', bills.includes('folio-eyebrow\">Stay billing') && !bills.includes('Folio & settlement'));
check('Checkout service request opens Guest Bill wording', services.includes('Open Guest Bill') && !services.includes('Open settlement'));
check('Final checkout has phone-specific polish hook', guests.includes('guest-final-checkout-modal') && guestCss.includes('.guest-final-checkout-modal'));
check('Final checkout mobile actions become full width', guestCss.includes('.guest-final-checkout-actions button') && guestCss.includes('width: 100% !important'));

check('Migration 116 is transactional', /^--[\s\S]*?begin;/i.test(migration) && /\ncommit;\s*$/i.test(migration));
check('Migration 116 uses advisory lock', migration.includes('stayqr:202609060116:stay-owned-checkout'));
check('Legacy checkout derives charge groups from folio_items', migration.includes("sum(fi.amount) filter (where fi.charge_category = 'food')"));
check('Legacy checkout subtotal uses folio charges', migration.includes('subtotal := round(coalesce(checkout_folio.charges_amount, 0), 2)'));
check('Invoice lines snapshot authoritative folio items', migration.includes('folio_item_id, snapshot_json, metadata') && migration.includes("'source', 'authoritative_folio'"));
check('Room-move food orders settle by stay/source mapping', migration.includes('fo.guest_session_id = target_guest_session_id') && migration.includes("fi.source_table = 'food_orders'"));
check('Room-move manual charges settle by folio source mapping', migration.includes("fi.source_table = 'manual_charges'"));
check('Old current-room food subtotal filter is absent', !migration.includes('and fo.room_id = session_row.room_id'));
check('Existing-invoice open-order guard is stay aware', migration.split('CREATE OR REPLACE FUNCTION public.checkout_guest_session_day20_legacy')[0].includes('fo.guest_session_id = target_guest_session_id'));
check('Acceptance package contains 14 checks', (acceptance.match(/select\s+'\d{2}_/gi) || []).length === 14);
check('Meta/Cashfree provider configuration is outside REV10', !migration.includes('meta_whatsapp') && !migration.includes('cashfree'));

console.log(JSON.stringify({ checks: passed + failed, passed, failed }));
if (failed) process.exit(1);
