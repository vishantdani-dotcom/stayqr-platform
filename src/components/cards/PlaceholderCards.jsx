// src/components/cards/PlaceholderCards.jsx
import './PlaceholderCards.css'

const PLACEHOLDER_CARDS = [
  {
    id: 'guests',
    title: 'Recent Guests',
    icon: GuestsIcon,
    preview: [
      { initial: 'R', name: 'Rajesh Mehta', room: '101', status: 'Checked In',  statusColor: 'green'  },
      { initial: 'P', name: 'Priya Sharma', room: '204', status: 'Checked Out', statusColor: 'gray'   },
      { initial: 'A', name: 'Amit Kumar',   room: '302', status: 'Due Today',   statusColor: 'orange' },
    ],
    cta: 'View All Guests',
    badge: '12 this week',
    badgeColor: 'gold',
    comingSoon: false,
  },
  {
    id: 'payments',
    title: 'Recent Payments',
    icon: PaymentsIcon,
    preview: [
      { initial: '₹', name: 'Room 101 · Mehta',  amount: '₹4,200', status: 'Paid',    statusColor: 'green'  },
      { initial: '₹', name: 'Room 204 · Sharma', amount: '₹7,800', status: 'Pending', statusColor: 'orange' },
      { initial: '₹', name: 'Room 302 · Kumar',  amount: '₹3,500', status: 'Paid',    statusColor: 'green'  },
    ],
    cta: 'View All Payments',
    badge: '₹15.5k today',
    badgeColor: 'green',
    comingSoon: false,
  },
  {
    id: 'services',
    title: 'Service Requests',
    icon: ServicesIcon,
    preview: [
      { initial: '🧹', name: 'Housekeeping',  room: 'Room 101', status: 'Pending',    statusColor: 'orange' },
      { initial: '🍽️', name: 'Room Service',  room: 'Room 204', status: 'In Progress', statusColor: 'blue'   },
      { initial: '🔧', name: 'Maintenance',   room: 'Room 305', status: 'Completed',  statusColor: 'green'  },
    ],
    cta: 'View All Requests',
    badge: '5 active',
    badgeColor: 'orange',
    comingSoon: false,
  },
]

export default function PlaceholderCards() {
  return (
    <div className="placeholder-cards-grid">
      {PLACEHOLDER_CARDS.map((card, i) => {
        const Icon = card.icon
        return (
          <div
            key={card.id}
            className="placeholder-card glass-card gold-border"
            style={{ animationDelay: `${i * 0.1}s` }}
          >
            {/* Header */}
            <div className="pc-header">
              <div className="pc-header-left">
                <div className="pc-icon">
                  <Icon />
                </div>
                <div>
                  <h4 className="pc-title">{card.title}</h4>
                  <span className={`pc-badge pc-badge--${card.badgeColor}`}>{card.badge}</span>
                </div>
              </div>
              <button className="pc-more-btn" type="button" aria-label="More options">
                <MoreIcon />
              </button>
            </div>

            {/* Preview list */}
            <div className="pc-list">
              {card.preview.map((item, j) => (
                <div key={j} className="pc-list-item">
                  <div className="pc-list-avatar">{item.initial}</div>
                  <div className="pc-list-body">
                    <span className="pc-list-name">{item.name}</span>
                    {item.room && <span className="pc-list-sub">{item.room}</span>}
                    {item.amount && <span className="pc-list-amount">{item.amount}</span>}
                  </div>
                  <span className={`pc-status pc-status--${item.statusColor}`}>
                    {item.status}
                  </span>
                </div>
              ))}
            </div>

            {/* Footer CTA */}
            <div className="pc-footer">
              <button className="pc-cta">{card.cta} →</button>
            </div>
          </div>
        )
      })}
    </div>
  )
}

function GuestsIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
      <circle cx="9" cy="7" r="4"/>
      <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
      <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
    </svg>
  )
}
function PaymentsIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="1" y="4" width="22" height="16" rx="2" ry="2"/>
      <line x1="1" y1="10" x2="23" y2="10"/>
    </svg>
  )
}
function ServicesIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
      <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
    </svg>
  )
}
function MoreIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
      <circle cx="12" cy="5" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="12" cy="19" r="1.5"/>
    </svg>
  )
}
