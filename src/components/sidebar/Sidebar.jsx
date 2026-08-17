// src/components/sidebar/Sidebar.jsx
import './Sidebar.css'
import { normalizeRole, canAccessSection } from '../../lib/currentStaff'
import HotelSwitcher from '../hotel/HotelSwitcher'

const NAV_ITEMS = [
  {
    group: 'Main',
    items: [
      { id: 'dashboard', label: 'Dashboard', icon: GridIcon, badge: null },
      { id: 'reservations', label: 'Reservations', icon: CalendarIcon, badge: null },
      { id: 'calendar', label: 'Booking Calendar', icon: CalendarIcon, badge: null },
      { id: 'operations', label: 'Arrivals & Departures', icon: KeyIcon, badge: null },
      { id: 'rooms', label: 'Rooms', icon: DoorIcon, badge: null },
      { id: 'guests', label: 'Guests', icon: UsersIcon, badge: '3' },
      { id: 'checkin', label: 'Check-In/Out', icon: KeyIcon, badge: null },
      { id: 'menu', label: 'Menu Management', icon: 'ðŸ½ï¸', badge: null },
      { id: 'staff', label: 'Staff', icon: 'ðŸ‘¥', badge: null },
    ],
  },
  {
    group: 'Operations',
    items: [
      { id: 'qr', label: 'QR Guides', icon: QrIcon, badge: null },
      { id: 'payments', label: 'Payments', icon: CardIcon, badge: null },
      { id: 'folios', label: 'Folio & Settlement', icon: DollarIcon, badge: null },
      { id: 'services', label: 'Service Requests', icon: BellIcon, badge: '5' },
      { id: 'foodorders', label: 'Food Orders', icon: CardIcon, badge: null },
      { id: 'charges', label: 'Charges', icon: DollarIcon, badge: null },
      { id: 'housekeeping', label: 'Housekeeping', icon: BellIcon, badge: null },
      { id: 'maintenance', label: 'Maintenance', icon: SettingsIcon, badge: null },
      { id: 'amenities', label: 'Amenities', icon: StarIcon, badge: null },
    ],
  },
  {
    group: 'Settings',
    items: [
      { id: 'superadmin', label: 'Super Admin', icon: BuildingIcon, badge: null },
      { id: 'onboarding', label: 'Hotel Setup', icon: SettingsIcon, badge: null },
      { id: 'hotel', label: 'Hotel Profile', icon: BuildingIcon, badge: null },
      { id: 'guidebuilder', label: 'Guest Guide Builder', icon: QrIcon, badge: null },
      { id: 'operationscenter', label: 'Operations Centre', icon: BellIcon, badge: null },
      { id: 'reports', label: 'Reports', icon: ChartIcon, badge: null },
      { id: 'invoices', label: 'Invoices & Audit', icon: CardIcon, badge: null },
      { id: 'settings', label: 'Settings', icon: SettingsIcon, badge: null },
    ],
  },
]

export default function Sidebar({
  activeSection,
  onNavigate,
  collapsed,
  onToggle,
  mobileOpen,
  currentStaff,
  currentRole,
  permissions = [],
  tenantContext,
  onHotelChange,
  switchingHotelId,
  hotelSwitchError,
}) {
  const role = normalizeRole(currentRole || currentStaff?.role)
  const userName = currentStaff?.full_name || 'Admin'
  const userRole = currentStaff?.role || role

  const visibleGroups = NAV_ITEMS.map((group) => ({
    ...group,
    items: group.items.filter((item) => canAccessSection(role, item.id, permissions)),
  })).filter((group) => group.items.length > 0)

  return (
    <aside
      className={`sidebar ${collapsed ? 'collapsed' : ''} ${
        mobileOpen ? 'mobile-open' : ''
      }`}
    >
      <div className="sidebar-logo">
        <div className="sidebar-logo-icon">
          <QrSquareIcon />
        </div>

        {!collapsed && (
          <div className="sidebar-logo-text">
            <span className="sidebar-brand">StayQR</span>
            <span className="sidebar-brand-sub">Admin</span>
          </div>
        )}

        <button
          className="sidebar-toggle"
          onClick={onToggle}
          title={collapsed ? 'Expand' : 'Collapse'}
          type="button"
        >
          <ChevronIcon direction={collapsed ? 'right' : 'left'} />
        </button>
      </div>

      {!collapsed && (
        <div className="sidebar-hotel-switcher-wrap">
          <HotelSwitcher
            tenantContext={tenantContext}
            onHotelChange={onHotelChange}
            switchingHotelId={switchingHotelId}
            error={hotelSwitchError}
            variant="sidebar"
          />
        </div>
      )}

      <nav className="sidebar-nav">
        {visibleGroups.map((group) => (
          <div key={group.group} className="nav-group">
            {!collapsed && <p className="nav-group-label">{group.group}</p>}

            {group.items.map((item) => {
              const Icon = item.icon
              const isActive = activeSection === item.id
              const isEmojiIcon = typeof Icon === 'string'

              return (
                <button
                  key={item.id}
                  className={`nav-item ${isActive ? 'active' : ''}`}
                  onClick={() => onNavigate(item.id)}
                  title={collapsed ? item.label : undefined}
                  type="button"
                >
                  <span className="nav-item-icon">
                    {isEmojiIcon ? <span>{Icon}</span> : <Icon />}
                  </span>

                  {!collapsed && (
                    <span className="nav-item-label">{item.label}</span>
                  )}

                  {!collapsed && item.badge && (
                    <span className="nav-badge">{item.badge}</span>
                  )}

                  {collapsed && item.badge && <span className="nav-badge-dot" />}
                </button>
              )
            })}
          </div>
        ))}
      </nav>

      {!collapsed && (
        <div className="sidebar-footer">
          <div className="sidebar-user">
            <div className="user-avatar">
              {userName.charAt(0).toUpperCase()}
            </div>

            <div className="user-info">
              <span className="user-name">{userName}</span>
              <span className="user-role">{userRole}</span>
            </div>
          </div>

          <div
            style={{
              display: 'flex',
              gap: '10px',
              flexWrap: 'wrap',
              marginTop: '10px',
            }}
          >
            <a
              href="/privacy"
              target="_blank"
              rel="noreferrer"
              style={{
                color: '#a1a1aa',
                fontSize: '12px',
                textDecoration: 'none',
              }}
            >
              Privacy Policy
            </a>
            <a
              href="/terms"
              target="_blank"
              rel="noreferrer"
              style={{
                color: '#a1a1aa',
                fontSize: '12px',
                textDecoration: 'none',
              }}
            >
              Terms of Service
            </a>
            <a
              href="/dpa"
              target="_blank"
              rel="noreferrer"
              style={{
                color: '#a1a1aa',
                fontSize: '12px',
                textDecoration: 'none',
              }}
            >
              Data Processing Agreement
            </a>
            <a
              href="/sla"
              target="_blank"
              rel="noreferrer"
              style={{
                color: '#a1a1aa',
                fontSize: '12px',
                textDecoration: 'none',
              }}
            >
              SLA / Service Commitments
            </a>
          </div>
        </div>
      )}
    </aside>
  )
}

function GridIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="7" height="7" />
      <rect x="14" y="3" width="7" height="7" />
      <rect x="3" y="14" width="7" height="7" />
      <rect x="14" y="14" width="7" height="7" />
    </svg>
  )
}

function CalendarIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="17" rx="2" />
      <line x1="16" y1="2" x2="16" y2="6" />
      <line x1="8" y1="2" x2="8" y2="6" />
      <line x1="3" y1="10" x2="21" y2="10" />
      <path d="M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01" />
    </svg>
  )
}

function DoorIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 21h18M9 21V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v16" />
      <circle cx="15" cy="13" r="1" fill="currentColor" />
    </svg>
  )
}

function UsersIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  )
}

function KeyIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="7.5" cy="15.5" r="5.5" />
      <path d="m21 2-9.6 9.6" />
      <path d="m15.5 7.5 3 3L22 7l-3-3" />
    </svg>
  )
}

function QrIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="5" height="5" />
      <rect x="16" y="3" width="5" height="5" />
      <rect x="3" y="16" width="5" height="5" />
      <path d="M21 16h-3a2 2 0 0 0-2 2v3" />
      <path d="M21 21v.01" />
      <path d="M12 7v3a2 2 0 0 1-2 2H7" />
    </svg>
  )
}

function CardIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="1" y="4" width="22" height="16" rx="2" ry="2" />
      <line x1="1" y1="10" x2="23" y2="10" />
    </svg>
  )
}

function DollarIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="12" y1="1" x2="12" y2="23" />
      <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7H14.5a3.5 3.5 0 0 1 0 7H6" />
    </svg>
  )
}

function BellIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
  )
}

function StarIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
    </svg>
  )
}

function BuildingIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="4" y="2" width="16" height="20" rx="2" ry="2" />
      <path d="M9 22v-4h6v4" />
      <path d="M8 6h.01M16 6h.01M8 10h.01M16 10h.01M8 14h.01M16 14h.01" />
    </svg>
  )
}

function ChartIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="12" y1="20" x2="12" y2="10" />
      <line x1="18" y1="20" x2="18" y2="4" />
      <line x1="6" y1="20" x2="6" y2="16" />
    </svg>
  )
}

function SettingsIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.07 4.93a10 10 0 0 1 0 14.14M4.93 4.93a10 10 0 0 0 0 14.14" />
    </svg>
  )
}

function QrSquareIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="2" width="8" height="8" rx="1" />
      <rect x="14" y="2" width="8" height="8" rx="1" />
      <rect x="2" y="14" width="8" height="8" rx="1" />
      <path d="M14 14h2v2h-2z M18 14h2 M14 18h2 M18 18h2v2h-2z M20 16v2" />
    </svg>
  )
}

function ChevronIcon({ direction }) {
  const rotate = direction === 'right' ? '0deg' : '180deg'

  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ transform: `rotate(${rotate})`, transition: 'transform 0.3s' }}
    >
      <polyline points="9 18 15 12 9 6" />
    </svg>
  )
}
