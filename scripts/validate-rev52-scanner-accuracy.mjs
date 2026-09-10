import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const checks = []
const pass = (name, ok, detail='') => checks.push({name, ok:Boolean(ok), detail})

const client = read('src/lib/idDocumentIntelligence.js')
const navbar = read('src/components/navbar/Navbar.jsx')
const edge = read('supabase/functions/id-document-ocr-v2/index.ts')
const core = read('supabase/functions/_shared/idOcrCore.js')
const soundPath = path.join(root, 'public/assets/stayqr-notification.wav')
const soundHash = fs.existsSync(soundPath) ? crypto.createHash('sha256').update(fs.readFileSync(soundPath)).digest('hex') : ''

pass('Client uses dedicated v2 OCR function', /functions\.invoke\(["']id-document-ocr-v2["']/.test(client))
pass('Client keeps accepted 45s provider window', /CLIENT_OCR_TIMEOUT_MS\s*=\s*45000/.test(client))
pass('Client provider size matches Azure F0 4 MB boundary', /MAX_PROVIDER_IMAGE_BYTES\s*=\s*4\s*\*\s*1024\s*\*\s*1024/.test(client))
pass('REV51 enhanced retry remains present', /createEnhancedOcrVariant/.test(client) && /retryApplied/.test(client))
pass('Strong provider evidence overrides filename-only mismatch', /strongProviderEvidence/.test(client) && /identityConsensus\s*===\s*["']strong["']/.test(client))

pass('Approved notification WAV exists', fs.existsSync(soundPath))
pass('Approved notification WAV exact hash', soundHash === 'c2be68e9eb59f744e7153678fc3e3c3c03692461a16cf41e7153b7e0478df248', soundHash)
pass('Navbar uses approved notification WAV', /stayqr-notification\.wav/.test(navbar))
pass('Navbar plays selected asset at full app volume', /audio\.volume\s*=\s*1/.test(navbar))
pass('Navbar no longer synthesizes replacement oscillator', !/createOscillator\s*\(/.test(navbar))
pass('Recipient-scoped inbox chime logic preserved', /recipient-scoped/.test(navbar) && /newUnreadItems/.test(navbar))

pass('Azure Document Intelligence primary model present', /prebuilt-idDocument/.test(edge))
pass('Azure v4 GA API present', /api-version=2024-11-30/.test(edge))
pass('Azure secrets remain server-side', /AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT/.test(edge) && /AZURE_DOCUMENT_INTELLIGENCE_KEY/.test(edge))
pass('Google DOCUMENT_TEXT_DETECTION fallback present', /DOCUMENT_TEXT_DETECTION/.test(edge))
pass('OCR.Space fallback present', /api\.ocr\.space\/parse\/image/.test(edge))
pass('All OCR providers are evaluated together', /Promise\.all\(providerTasks\)/.test(edge))
pass('Function authenticates caller JWT', /auth\.getUser\(jwt\)/.test(edge))
pass('Function enforces hotel staff scope', /from\(['"]staff['"]\)/.test(edge) && /eq\(['"]hotel_id['"],\s*hotelId\)/.test(edge))
pass('Platform admin support remains explicit', /from\(['"]platform_admins['"]\)/.test(edge))
pass('Provider failures do not leak raw provider bodies', !/console\.log\([^)]*(?:content|ParsedText|fullTextAnnotation)/i.test(edge))
pass('Raw OCR is explicitly non-persistent', /rawOcrTextStored:\s*false/.test(core))

pass('Aadhaar Verhoeff validation is implemented', /isValidAadhaar/.test(core) && /const d = \[/.test(core) && /const p = \[/.test(core))
pass('Invalid Aadhaar cannot be returned as valid', /if \(!isValidAadhaar\(digits\)\)/.test(core))
pass('PAN format validation exists', /PAN_RE/.test(core))
pass('Passport MRZ path exists', /parseMrzName/.test(core))
pass('Provider identity agreement is required for consensus', /identityAgrees/.test(core) && /identityConsensus/.test(core))
pass('Conflicting providers trigger low consensus', /consensus = 'low'/.test(core))
pass('Structured Azure result can earn strong consensus', /best\.structured/.test(core) && /consensus = 'strong'/.test(core))
pass('No full document number is exposed in final analysis', /documentNumberMasked:\s*best\.documentNumberMasked/.test(core) && !/documentNumberFull:\s*best\.documentNumberFull/.test(core))

const failed = checks.filter((c) => !c.ok)
checks.forEach((c, i) => console.log(`${c.ok ? 'PASS' : 'FAIL'} ${String(i+1).padStart(2,'0')} ${c.name}${c.detail ? ` :: ${c.detail}` : ''}`))
console.log(JSON.stringify({checks:checks.length, passed:checks.length-failed.length, failed:failed.length}))
if (failed.length) process.exit(1)
