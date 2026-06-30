// src/components/navbar/Navbar.jsx

import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { normalizeRole } from '../../lib/currentStaff'
import './Navbar.css'

export default function Navbar({
  sidebarCollapsed,
  onMobileMenuToggle,
  activeSection,
  currentStaff,
  currentRole,
}) {
  const [notifOpen, setNotifOpen] = useState(false)

  const userName = currentStaff?.full_name || 'Admin'

  const hotelName =
    currentStaff?.hotels?.hotel_name ||
    currentStaff?.hotel_name ||
    'StayQR Hotel'

  const roleName = normalizeRole(currentRole || currentStaff?.role || 'manager')

  const handleLogout = async () => {
    const confirmLogout = window.confirm('Logout from StayQR?')
    if (!confirmLogout) return

    await supabase.auth.signOut()
    window.location.reload()
  }

  const sectionLabels = {
    dashboard: 'Dashboard',
    rooms: 'Rooms',
    guests: 'Guests',
    checkin: 'Check-In / Out',
    qr: 'QR Guides',
    payments: 'Payments',
    services: 'Service Requests',
    amenities: 'Amenities',
    hotel: 'Hotel Profile',
    reports: 'Reports',
    invoices: 'Invoices',
    charges: 'Charges',
    housekeeping: 'Housekeeping',
    foodorders: 'Food Orders',
    menu: 'Menu Management',
    staff: 'Staff',
    settings: 'Settings',
    superadmin: 'Super Admin',
  }

  const now = new Date()
  const dateStr = now.toLocaleDateString('en-IN', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  })

  return (
    <header
      className="navbar"
      style={{ left: sidebarCollapsed ? 64 : 'var(--sidebar-w)' }}
    >
      <div className="navbar-left">
        <button className="navbar-menu-btn" onClick={onMobileMenuToggle}>
          <MenuIcon />
        </button>

        <div className="navbar-breadcrumb">
          <span className="breadcrumb-home">StayQR</span>
          <span className="breadcrumb-sep">/</span>
          <span className="breadcrumb-current">
            {sectionLabels[activeSection] || 'Dashboard'}
          </span>
        </div>
      </div>

      <div className="navbar-center">
        <div className="navbar-date">{dateStr}</div>
      </div>

      <div className="navbar-right">
        <button className="navbar-icon-btn" title="Search">
          <SearchIcon />
        </button>

        <div className="notif-wrapper">
          <button
            className="navbar-icon-btn notif-btn"
            onClick={() => setNotifOpen(!notifOpen)}
            title="Notifications"
          >
            <BellIcon />
            <span className="notif-dot" />
          </button>

          {notifOpen && (
            <div className="notif-dropdown">
              <div className="notif-header">
                <span>Notifications</span>
                <span className="notif-count">3 new</span>
              </div>

              {NOTIFS.map((n) => (
                <div key={n.id} className="notif-item">
                  <div className={`notif-item-icon ${n.type}`}>{n.icon}</div>

                  <div className="notif-item-body">
                    <p className="notif-item-title">{n.title}</p>
                    <p className="notif-item-time">{n.time}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="navbar-divider" />

        <div className="navbar-user">
          <div className="navbar-user-info">
            <span className="navbar-user-name">{userName}</span>
            <span className="navbar-user-role">{roleName}</span>
            <span className="navbar-user-hotel">{hotelName}</span>
          </div>

          <button
            onClick={handleLogout}
            style={{
              background: '#D4AF37',
              color: '#000',
              border: 'none',
              padding: '8px 14px',
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: '700',
              marginLeft: '10px',
            }}
          >
            Logout
          </button>

          <div className="navbar-avatar">
            {userName.charAt(0).toUpperCase()}
          </div>
        </div>
      </div>
    </header>
  )
}

const NOTIFS = [
  {
    id: 1,
    type: 'green',
    icon: '🛎️',
    title: 'Room 101 checked in',
    time: '2 min ago',
  },
  {
    id: 2,
    type: 'gold',
    icon: '⭐',
    title: 'New Google review activity',
    time: '18 min ago',
  },
  {
    id: 3,
    type: 'orange',
    icon: '🔧',
    title: 'Service request — Room 204',
    time: '1 hr ago',
  },
]

function MenuIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <line x1="3" y1="6" x2="21" y2="6" />
      <line x1="3" y1="12" x2="21" y2="12" />
      <line x1="3" y1="18" x2="21" y2="18" />
    </svg>
  )
}

function SearchIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <circle cx="11" cy="11" r="8" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
  )
}

function BellIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
  )
}