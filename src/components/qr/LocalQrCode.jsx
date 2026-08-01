import { useMemo } from 'react'
import { createLocalQrDataUrl } from '../../lib/localQr'

export default function LocalQrCode({ value, label, size = 184 }) {
  const dataUrl = useMemo(() => {
    if (!value) return ''

    try {
      return createLocalQrDataUrl(value, { label })
    } catch (error) {
      console.error('Local QR generation error:', error)
      return ''
    }
  }, [label, value])

  if (!dataUrl) {
    return (
      <div style={fallbackStyle} role="status">
        QR unavailable
      </div>
    )
  }

  return (
    <img
      src={dataUrl}
      width={size}
      height={size}
      alt={label || 'StayQR secure guest access QR code'}
      loading="lazy"
      draggable="false"
      style={{ ...imageStyle, width: size, height: size }}
    />
  )
}

const imageStyle = {
  display: 'block',
  maxWidth: '100%',
  background: '#fff',
  borderRadius: '14px',
  padding: '10px',
}

const fallbackStyle = {
  width: '184px',
  height: '184px',
  maxWidth: '100%',
  borderRadius: '14px',
  border: '1px dashed #4a4a4a',
  color: '#8b8b8b',
  display: 'grid',
  placeItems: 'center',
}
