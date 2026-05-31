// src/components/cards/HotelOverviewCard.jsx
import './HotelOverviewCard.css'

export default function HotelOverviewCard() {
  const occupancyRate = 72

  return (
    <div className="hotel-overview-card glass-card gold-border">
      {/* Decorative top bar */}
      <div className="hotel-card-top-bar" />

      <div className="hotel-card-inner">
        {/* Left: Hotel info */}
        <div className="hotel-card-left">
          <div className="hotel-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <rect x="4" y="2" width="16" height="20" rx="2"/>
              <path d="M9 22v-4h6v4"/><path d="M8 6h.01M16 6h.01M8 10h.01M16 10h.01M8 14h.01M16 14h.01"/>
            </svg>
          </div>
          <div className="hotel-info">
            <div className="hotel-tag">PROPERTY OVERVIEW</div>
            <h2 className="hotel-name gold-text">VD Stay Inn</h2>
            <div className="hotel-meta-row">
              <div className="hotel-meta-item">
                <span className="hotel-meta-icon">📍</span>
                <span>Nagpur, Maharashtra</span>
              </div>
              <div className="hotel-meta-item">
                <span className="hotel-meta-icon">⭐</span>
                <span>4.8 · 124 reviews</span>
              </div>
            </div>
            <div className="hotel-tags">
              <span className="hotel-tag-pill">Luxury Smart Hospitality</span>
              <span className="hotel-tag-pill">QR Powered</span>
              <span className="hotel-tag-pill active-pill">● Live</span>
            </div>
          </div>
        </div>

        {/* Right: Stats */}
        <div className="hotel-card-right">
          <div className="occupancy-block">
            <div className="occupancy-label">Today's Occupancy</div>
            <div className="occupancy-ring-wrapper">
              <OccupancyRing value={occupancyRate} />
              <div className="occupancy-center">
                <span className="occupancy-pct">{occupancyRate}%</span>
                <span className="occupancy-sub">Occupied</span>
              </div>
            </div>
          </div>
          <div className="hotel-quick-stats">
            <div className="hqs-item">
              <span className="hqs-value">12</span>
              <span className="hqs-label">Total Rooms</span>
            </div>
            <div className="hqs-divider" />
            <div className="hqs-item">
              <span className="hqs-value green-val">3</span>
              <span className="hqs-label">Check-ins Today</span>
            </div>
            <div className="hqs-divider" />
            <div className="hqs-item">
              <span className="hqs-value orange-val">2</span>
              <span className="hqs-label">Check-outs Due</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function OccupancyRing({ value }) {
  const r = 42
  const circumference = 2 * Math.PI * r
  const offset = circumference - (value / 100) * circumference

  return (
    <svg className="occupancy-svg" viewBox="0 0 100 100" width="100" height="100">
      {/* Track */}
      <circle cx="50" cy="50" r={r} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="8" />
      {/* Progress */}
      <circle
        cx="50" cy="50" r={r}
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
