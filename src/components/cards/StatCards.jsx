import './StatCards.css'

const STAT_CONFIG = [
  {
    key: 'total',
    label: 'Total Rooms',
    icon: TotalIcon,
    color: 'gold',
  },
  {
    key: 'available',
    label: 'Available Rooms',
    icon: AvailableIcon,
    color: 'green',
  },
  {
    key: 'occupied',
    label: 'Occupied Rooms',
    icon: OccupiedIcon,
    color: 'blue',
  },
  {
    key: 'guests',
    label: 'Total Guests',
    icon: GuestIcon,
    color: 'orange',
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
                  {config.key === 'total' && 'All rooms'}
                  {config.key === 'available' && 'Ready for guests'}
                  {config.key === 'occupied' && 'Currently in use'}
                  {config.key === 'guests' && 'Checked-in records'}
                </div>
              </div>
            </div>

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

function GuestIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
      <circle cx="9" cy="7" r="4"/>
      <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
      <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
    </svg>
  )
}