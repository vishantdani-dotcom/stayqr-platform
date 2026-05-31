// src/components/buttons/QuickActions.jsx
import './QuickActions.css'

const ACTIONS = [
  {
    id: 'checkin',
    label: 'Check In Guest',
    description: 'Register a new guest arrival',
    icon: CheckInIcon,
    variant: 'gold',
    shortcut: '⌘ I',
  },
  {
    id: 'addroom',
    label: 'Add Room',
    description: 'Create a new room entry',
    icon: AddRoomIcon,
    variant: 'default',
    shortcut: '⌘ R',
  },
  {
    id: 'generateqr',
    label: 'Generate QR',
    description: 'Create QR code for a room',
    icon: QrGenerateIcon,
    variant: 'default',
    shortcut: '⌘ Q',
  },
]

export default function QuickActions({ onAction }) {
  return (
    <div className="quick-actions-wrap glass-card gold-border">
      <div className="qa-header">
        <div className="qa-title-row">
          <div className="qa-icon-wrap">
            <LightningIcon />
          </div>
          <div>
            <h3 className="qa-title">Quick Actions</h3>
            <p className="qa-sub">One-click operations</p>
          </div>
        </div>
      </div>
      <div className="qa-buttons">
        {ACTIONS.map(action => {
          const Icon = action.icon
          return (
            <button
              key={action.id}
              className={`qa-btn qa-btn--${action.variant}`}
              onClick={() => onAction?.(action.id)}
            >
              <div className={`qa-btn-icon qa-btn-icon--${action.variant}`}>
                <Icon />
              </div>
              <div className="qa-btn-body">
                <span className="qa-btn-label">{action.label}</span>
                <span className="qa-btn-desc">{action.description}</span>
              </div>
              <span className="qa-btn-shortcut">{action.shortcut}</span>
              <ArrowIcon />
            </button>
          )
        })}
      </div>
    </div>
  )
}

function CheckInIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><polyline points="10 17 15 12 10 7"/>
      <line x1="15" y1="12" x2="3" y2="12"/>
    </svg>
  )
}
function AddRoomIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="3" y="3" width="18" height="18" rx="2"/><line x1="12" y1="8" x2="12" y2="16"/>
      <line x1="8" y1="12" x2="16" y2="12"/>
    </svg>
  )
}
function QrGenerateIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="3" y="3" width="5" height="5"/><rect x="16" y="3" width="5" height="5"/><rect x="3" y="16" width="5" height="5"/>
      <path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/>
      <path d="M12 7v3a2 2 0 0 1-2 2H7"/>
    </svg>
  )
}
function LightningIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
    </svg>
  )
}
function ArrowIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/>
    </svg>
  )
}
