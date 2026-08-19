// src/components/cards/HotelOverviewCard.jsx
import './HotelOverviewCard.css'

export default function HotelOverviewCard({ hotel, analytics, loading = false }) {
  const totalRooms = Number(analytics?.totalRooms || 0)
  const occupiedRooms = Number(analytics?.occupiedRooms || 0)
  const occupancyRate = totalRooms > 0
    ? Math.round((occupiedRooms / totalRooms) * 100)
    : 0

  const status = String(hotel?.status || 'active').toLowerCase()
  const statusLabel = formatLabel(status)
  const subscriptionLabel = hotel?.subscription_status
    ? formatLabel(hotel.subscription_status)
    : 'Subscription not set'

  return (
    <div className="hotel-overview-card glass-card gold-border">
      <div className="hotel-card-top-bar" />

      <div className="hotel-card-inner">
        <div className="hotel-card-left">
          <div className="hotel-icon">
            {hotel?.logo_url ? (
              <img src={hotel.logo_url} alt={`${hotel?.hotel_name || 'Hotel'} logo`} />
            ) : (
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <rect x="4" y="2" width="16" height="20" rx="2" />
                <path d="M9 22v-4h6v4" />
                <path d="M8 6h.01M16 6h.01M8 10h.01M16 10h.01M8 14h.01M16 14h.01" />
              </svg>
            )}
          </div>

          <div className="hotel-info">
            <div className="hotel-tag">PROPERTY OVERVIEW</div>
            <h2 className="hotel-name gold-text">
              {hotel?.hotel_name || (loading ? 'Loading property…' : 'Hotel not selected')}
            </h2>

            <div className="hotel-meta-row">
              <div className="hotel-meta-item">
                <span className="hotel-meta-icon">📍</span>
                <span>{hotel?.location || 'Location not set'}</span>
              </div>
              <div className="hotel-meta-item">
                <span className="hotel-meta-icon">🌐</span>
                <span>{hotel?.timezone || 'Timezone not set'}</span>
              </div>
            </div>

            <div className="hotel-tags">
              <span className="hotel-tag-pill">{subscriptionLabel}</span>
              <span className="hotel-tag-pill">QR Powered</span>
              <span className={`hotel-tag-pill hotel-status-pill status-${status}`}>
                ● {statusLabel}
              </span>
            </div>
          </div>
        </div>

        <div className="hotel-card-right">
          <div className="occupancy-block">
            <div className="occupancy-label">Today&apos;s Occupancy</div>
            <div className="occupancy-ring-wrapper">
              <OccupancyRing value={occupancyRate} />
              <div className="occupancy-center">
                <span className="occupancy-pct">{occupancyRate}%</span>
                <span className="occupancy-sub">Occupied</span>
              </div>
            </div>
          </div>

          <div className="hotel-quick-stats">
            <QuickStat value={totalRooms} label="Total Rooms" />
            <div className="hqs-divider" />
            <QuickStat
              value={analytics?.checkInsToday || 0}
              label="Check-ins Today"
              className="green-val"
            />
            <div className="hqs-divider" />
            <QuickStat
              value={analytics?.checkOutsDue || 0}
              label="Check-outs Due"
              className="orange-val"
            />
          </div>
        </div>
      </div>
    </div>
  )
}

function QuickStat({ value, label, className = '' }) {
  return (
    <div className="hqs-item">
      <span className={`hqs-value ${className}`}>{value}</span>
      <span className="hqs-label">{label}</span>
    </div>
  )
}

function OccupancyRing({ value }) {
  const radius = 42
  const circumference = 2 * Math.PI * radius
  const safeValue = Math.min(100, Math.max(0, Number(value || 0)))
  const offset = circumference - (safeValue / 100) * circumference

  return (
    <svg className="occupancy-svg" viewBox="0 0 100 100" width="100" height="100" aria-hidden="true">
      <circle cx="50" cy="50" r={radius} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="8" />
      <circle
        cx="50"
        cy="50"
        r={radius}
        fill="none"
        stroke="url(#goldGrad)"
        strokeWidth="8"
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={offset}
        transform="rotate(-90 50 50)"
        style={{ transition: 'stroke-dashoffset 1s ease' }}
      />
      <defs>
        <linearGradient id="goldGrad" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="#C9A84C" />
          <stop offset="100%" stopColor="#F0D080" />
        </linearGradient>
      </defs>
    </svg>
  )
}

function formatLabel(value) {
  return String(value || '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}
