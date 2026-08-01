import { QRCode, QRErrorCorrectLevel } from '../vendor/qrCodeEngine.js'

const DEFAULT_OPTIONS = Object.freeze({
  background: '#ffffff',
  foreground: '#050505',
  quietZone: 4,
  scale: 8,
})

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
}

export function createLocalQrSvg(value, options = {}) {
  const text = String(value || '').trim()

  if (!text) {
    throw new Error('A non-empty value is required to generate a QR code.')
  }

  const settings = { ...DEFAULT_OPTIONS, ...options }
  const qr = new QRCode(-1, QRErrorCorrectLevel.M)
  qr.addData(text)
  qr.make()

  const moduleCount = qr.getModuleCount()
  const quietZone = Math.max(4, Number(settings.quietZone) || 4)
  const scale = Math.max(1, Number(settings.scale) || 8)
  const viewBoxSize = moduleCount + quietZone * 2
  const pixelSize = viewBoxSize * scale
  const darkModules = []

  for (let row = 0; row < moduleCount; row += 1) {
    for (let column = 0; column < moduleCount; column += 1) {
      if (qr.isDark(row, column)) {
        darkModules.push(
          `M${column + quietZone} ${row + quietZone}h1v1h-1z`
        )
      }
    }
  }

  const label = escapeXml(settings.label || 'StayQR secure guest access QR code')

  return [
    `<svg xmlns="http://www.w3.org/2000/svg"`,
    ` width="${pixelSize}" height="${pixelSize}"`,
    ` viewBox="0 0 ${viewBoxSize} ${viewBoxSize}"`,
    ` role="img" aria-label="${label}" shape-rendering="crispEdges">`,
    `<rect width="100%" height="100%" fill="${escapeXml(settings.background)}"/>`,
    `<path d="${darkModules.join('')}" fill="${escapeXml(settings.foreground)}"/>`,
    '</svg>',
  ].join('')
}

export function createLocalQrDataUrl(value, options = {}) {
  const svg = createLocalQrSvg(value, options)
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
}

export function downloadLocalQrSvg({ value, filename, label }) {
  const svg = createLocalQrSvg(value, { label })
  const blob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' })
  const objectUrl = URL.createObjectURL(blob)
  const anchor = document.createElement('a')

  anchor.href = objectUrl
  anchor.download = filename || 'stayqr-secure-access.svg'
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  URL.revokeObjectURL(objectUrl)
}
