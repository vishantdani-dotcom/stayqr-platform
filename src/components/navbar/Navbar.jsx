// src/components/navbar/Navbar.jsx

import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { normalizeRole } from '../../lib/currentStaff'
import {
  getNotifications,
  getUnreadCount,
  markAllNotificationsRead,
  markNotificationRead,
} from '../../lib/notifications'
import './Navbar.css'

export default function Navbar({
  sidebarCollapsed,
  onMobileMenuToggle,
  activeSection,
  currentStaff,
  currentRole,
}) {
  const [notifOpen, setNotifOpen] = useState(false)
  const [notifications, setNotifications] = useState([])

  const hotelId = currentStaff?.hotel_id || currentStaff?.hotels?.id

  const userName = currentStaff?.full_name || 'Admin'

  const hotelName =
    currentStaff?.hotels?.hotel_name ||
    currentStaff?.hotel_name ||
    'StayQR Hotel'

  const roleName = formatRole(normalizeRole(currentRole || currentStaff?.role || 'manager'))

  const unreadCount = getUnreadCount(notifications)

  useEffect(() => {
    if (!hotelId) return

    loadNotifications(hotelId)

    const channel = supabase
      .channel(`notifications_${hotelId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'notifications',
          filter: `hotel_id=eq.${hotelId}`,
        },
        () => loadNotifications(hotelId)
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [hotelId])

  async function loadNotifications(id) {
    const data = await getNotifications(id)
    setNotifications(data || [])
  }

  async function handleOpenNotifications() {
    setNotifOpen((prev) => !prev)
  }

  async function handleMarkAllRead() {
    if (!hotelId) return
    await markAllNotificationsRead(hotelId)
    await loadNotifications(hotelId)
  }

  async function handleNotificationClick(notification) {
    if (!notification?.id || notification.is_read) return
    await markNotificationRead(notification.id)
    await loadNotifications(hotelId)
  }

  const handleLogout = async () => {
    const confirmLogout = window.confirm('Logout from StayQR?')
    if (!confirmLogout) return

    await supabase.auth.signOut()
    window.location.reload()
  }

  const sectionLabels = {
    dashboard: 'Dashboard',
    reservations: 'Reservations',
    calendar: 'Booking Calendar',
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
            onClick={handleOpenNotifications}
            title="Notifications"
          >
            <BellIcon />
            {unreadCount > 0 && (
              <span className="notif-live-count">
                {unreadCount > 9 ? '9+' : unreadCount}
              </span>
            )}
          </button>

          {notifOpen && (
            <div className="notif-dropdown">
              <div className="notif-header">
                <span>Notifications</span>

                <div className="notif-header-actions">
                  <span className="notif-count">
                    {unreadCount} new
                  </span>

                  {unreadCount > 0 && (
                    <button
                      className="notif-mark-read"
                      onClick={handleMarkAllRead}
                    >
                      Mark all read
                    </button>
                  )}
                </div>
              </div>

              {notifications.length === 0 ? (
                <div className="notif-empty">
                  <div>🔔</div>
                  <p>No notifications yet</p>
                  <span>Live hotel updates will appear here.</span>
                </div>
              ) : (
                notifications.map((n) => (
                  <button
                    key={n.id}
                    className={`notif-item ${n.is_read ? 'read' : 'unread'}`}
                    onClick={() => handleNotificationClick(n)}
                  >
                    <div className={`notif-item-icon ${n.type}`}>
                      {getNotificationIcon(n.type)}
                    </div>

                    <div className="notif-item-body">
                      <p className="notif-item-title">{n.title}</p>
                      <p className="notif-item-message">{n.message}</p>
                      <p className="notif-item-time">
                        {timeAgo(n.created_at)}
                      </p>
                    </div>

                    {!n.is_read && <span className="notif-unread-dot" />}
                  </button>
                ))
              )}
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

function getNotificationIcon(type) {
  const icons = {
    service_status: '🛎️',
    service_request: '🛎️',
    checkout: '🚪',
    food_order: '🍽️',
    payment: '💳',
    housekeeping: '🧹',
    review: '⭐',
    general: '🔔',
  }

  return icons[type] || '🔔'
}

function timeAgo(dateValue) {
  if (!dateValue) return ''

  const diffMs = Date.now() - new Date(dateValue).getTime()
  const diffSec = Math.floor(diffMs / 1000)
  const diffMin = Math.floor(diffSec / 60)
  const diffHr = Math.floor(diffMin / 60)
  const diffDay = Math.floor(diffHr / 24)

  if (diffSec < 30) return 'Just now'
  if (diffMin < 1) return `${diffSec} sec ago`
  if (diffMin < 60) return `${diffMin} min ago`
  if (diffHr < 24) return `${diffHr} hr ago`
  return `${diffDay} day ago`
}

function formatRole(role) {
  return String(role || 'Staff')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

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