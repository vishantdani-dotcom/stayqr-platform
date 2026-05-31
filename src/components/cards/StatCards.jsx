// src/components/cards/StatCards.jsx
import './StatCards.css'

const STAT_CONFIG = [
  {
    key: 'total',
    label: 'Total Rooms',
    icon: TotalIcon,
    color: 'gold',
    trend: null,
  },
  {
    key: 'available',
    label: 'Available Rooms',
    icon: AvailableIcon,
    color: 'green',
    trend: null,
  },
  {
    key: 'occupied',
    label: 'Occupied Rooms',
    icon: OccupiedIcon,
    color: 'blue',
    trend: null,
  },
  {
    key: 'sessions',
    label: 'Active Sessions',
    icon: SessionIcon,
    color: 'orange',
    trend: null,
  },
]

export default function StatCards({ stats, loading }) {
  return (
    <div className="stat-cards-grid">
      {STAT_CONFIG.map((config, i) => {
        const Icon = config.icon
        const value = stats?.[config.key]
        return (
          <div
            key={config.key}
            className={`stat-card glass-card stat-card--${config.color}`}
            style={{ animationDelay: `${i * 0.08}s` }}
          >
            <div className="stat-card-top-bar" />
            <div className="stat-card-inner">
              <div className="stat-card-left">
                <div className={`stat-icon stat-icon--${config.color}`}>
                  <Icon />
                </div>
                <div className="stat-label">{config.label}</div>
              </div>
              <div className="stat-card-right">
                {loading ? (
                  <div className="skeleton" style={{ width: 48, height: 36, borderRadius: 6 }} />
                ) : (
                  <div className="stat-value">{value ?? '—'}</div>
                )}
                <div className="stat-sub">
                  {config.key === 'total'     && 'All rooms'}
                  {config.key === 'available' && 'Ready for guests'}
                  {config.key === 'occupied'  && 'Currently in use'}
                  {config.key === 'sessions'  && 'QR scans active'}
                </div>
              </div>
            </div>
            {/* Decorative glow dot */}
            <div className={`stat-glow-dot stat-glow-dot--${config.color}`} />
          </div>
        )
      })}
    </div>
  )
}

function TotalIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/>
      <rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>
    </svg>
  )
}
function AvailableIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <polyline points="20 6 9 17 4 12"/>
    </svg>
  )
}
function OccupiedIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
      <circle cx="12" cy="7" r="4"/>
    </svg>
  )
}
function SessionIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="3" y="3" width="5" height="5"/><rect x="16" y="3" width="5" height="5"/>
      <rect x="3" y="16" width="5" height="5"/>
      <path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/>
      <path d="M12 7v3a2 2 0 0 1-2 2H7"/>
    </svg>
  )
}
