import { createLocalQrDataUrl, createLocalQrSvg } from '../src/lib/localQr.js'

const sampleUrl = `https://stayqr.in/guest/example-hotel/123e4567-e89b-42d3-a456-426614174000.${'a'.repeat(64)}`
const svg = createLocalQrSvg(sampleUrl, { label: 'StayQR local QR test' })
const dataUrl = createLocalQrDataUrl(sampleUrl)

const assertions = [
  ['SVG document generated', svg.startsWith('<svg') && svg.endsWith('</svg>')],
  ['QR module path generated', /<path d="M/.test(svg)],
  ['Quiet-zone background generated', /<rect width="100%"/.test(svg)],
  ['SVG data URL generated', dataUrl.startsWith('data:image/svg+xml;charset=utf-8,')],
  ['No remote image endpoint used', !/https?:\/\//.test(dataUrl)],
]

let failed = 0
for (const [name, passed] of assertions) {
  console.log(`${passed ? 'PASS' : 'FAIL'} — ${name}`)
  if (!passed) failed += 1
}

if (failed > 0) process.exitCode = 1
else console.log(`\nLocal QR engine test passed ${assertions.length}/${assertions.length}.`)
