// src/components/navbar/Navbar.jsx

import { useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { normalizeRole } from '../../lib/currentStaff'
import { clearSelectedTenantHotel } from '../../lib/tenantContext'
import HotelSwitcher from '../hotel/HotelSwitcher'
import GlobalSearch from '../search/GlobalSearch'
import {
  getNotificationInbox,
  markInboxAllRead,
  markInboxNotificationRead,
  subscribeToNotificationInbox,
} from '../../lib/day17Operations'
import './Navbar.css'

export default function Navbar({
  sidebarCollapsed,
  onMobileMenuToggle,
  activeSection,
  currentStaff,
  currentRole,
  tenantContext,
  onHotelChange,
  switchingHotelId,
  hotelSwitchError,
  onNavigate,
}) {
  const [searchOpen, setSearchOpen] = useState(false)
  const [notifOpen, setNotifOpen] = useState(false)
  const [userMenuOpen, setUserMenuOpen] = useState(false)
  const [notifications, setNotifications] = useState([])
  const userMenuRef = useRef(null)
  const notificationRef = useRef(null)
  const notificationRequestRef = useRef(0)
  const activeHotelIdRef = useRef(null)

  const hotelId = tenantContext?.selectedHotelId || currentStaff?.hotel_id || currentStaff?.hotels?.id
  const userName = currentStaff?.full_name || 'Admin'
  const hotelName = tenantContext?.selectedHotel?.hotel_name || currentStaff?.hotels?.hotel_name || currentStaff?.hotel_name || 'StayQR Hotel'
  const roleName = formatRole(normalizeRole(currentRole || currentStaff?.role || 'manager'))
  const unreadCount = notifications.filter((item) => item.status === 'unread').length
  activeHotelIdRef.current = hotelId || null

  useEffect(() => {
    notificationRequestRef.current += 1
    setNotifications([])
    setNotifOpen(false)

    if (!hotelId) return undefined

    loadNotifications(hotelId)
    return subscribeToNotificationInbox(hotelId, () => loadNotifications(hotelId))
  }, [hotelId])

  useEffect(() => {
    const handlePointerDown = (event) => {
      if (userMenuRef.current && !userMenuRef.current.contains(event.target)) {
        setUserMenuOpen(false)
      }

      if (notificationRef.current && !notificationRef.current.contains(event.target)) {
        setNotifOpen(false)
      }
    }

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') {
        setUserMenuOpen(false)
        setNotifOpen(false)
      }
    }

    document.addEventListener('mousedown', handlePointerDown)
    document.addEventListener('keydown', handleKeyDown)

    return () => {
      document.removeEventListener('mousedown', handlePointerDown)
      document.removeEventListener('keydown', handleKeyDown)
    }
  }, [])

  useEffect(() => {
    const handleSearchShortcut = (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        setSearchOpen(true)
        setNotifOpen(false)
        setUserMenuOpen(false)
      }
    }
    document.addEventListener('keydown', handleSearchShortcut)
    return () => document.removeEventListener('keydown', handleSearchShortcut)
  }, [])

  async function loadNotifications(id) {
    if (!id) return

    const requestId = notificationRequestRef.current + 1
    notificationRequestRef.current = requestId
    const data = await getNotificationInbox(id, 30)

    if (
      notificationRequestRef.current !== requestId ||
      activeHotelIdRef.current !== id
    ) {
      return
    }

    setNotifications(data?.items || [])
  }

  function handleOpenNotifications() {
    setUserMenuOpen(false)
    setNotifOpen((prev) => !prev)
  }

  async function handleMarkAllRead() {
    if (!hotelId) return
    await markInboxAllRead(hotelId)
    await loadNotifications(hotelId)
  }

  async function handleNotificationClick(notification) {
    if (!notification?.id || notification.status === 'read') return
    await markInboxNotificationRead(notification.id)
    await loadNotifications(hotelId)
  }

  const handleLogout = async () => {
    const confirmLogout = window.confirm('Logout from StayQR?')
    if (!confirmLogout) return

    clearSelectedTenantHotel()
    await supabase.auth.signOut()
    window.location.reload()
  }

  const sectionLabels = {
    dashboard: 'Dashboard',
    reservations: 'Reservations',
    calendar: 'Booking Calendar',
    operations: 'Arrivals & Departures',
    rooms: 'Rooms',
    guests: 'Guests',
    checkin: 'Check-In / Out',
    qr: 'QR Guides',
    payments: 'Payments',
    folios: 'Folio & Settlement',
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
    operationscenter: 'Operations Centre',
    superadmin: 'Super Admin',
    onboarding: 'Hotel Setup',
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
        <button
  className="navbar-menu-btn"
  onClick={onMobileMenuToggle}
  type="button"
  aria-label="Toggle navigation menu"
>
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
        <button
          className="navbar-icon-btn"
          title="Search (Ctrl/Command + K)"
          type="button"
          onClick={() => {
            setSearchOpen(true)
            setNotifOpen(false)
            setUserMenuOpen(false)
          }}
          aria-label="Search hotel workspace"
        >
          <SearchIcon />
        </button>

        <div className="notif-wrapper" ref={notificationRef}>
          <button
            className="navbar-icon-btn notif-btn"
            onClick={handleOpenNotifications}
            title="Notifications"
            type="button"
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
                  <span className="notif-count">{unreadCount} new</span>

                  {unreadCount > 0 && (
                    <button className="notif-mark-read" onClick={handleMarkAllRead} type="button">
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
                notifications.map((notification) => (
                  <button
                    key={notification.id}
                    className={`notif-item ${notification.status === 'read' ? 'read' : 'unread'}`}
                    onClick={() => handleNotificationClick(notification)}
                    type="button"
                  >
                    <div className={`notif-item-icon ${notification.severity || 'info'}`}>
                      {getNotificationIcon(notification.severity || 'info')}
                    </div>

                    <div className="notif-item-body">
                      <p className="notif-item-title">{notification.title}</p>
                      <p className="notif-item-message">{notification.message}</p>
                      <p className="notif-item-time">{timeAgo(notification.created_at)}</p>
                    </div>

                    {notification.status === 'unread' && <span className="notif-unread-dot" />}
                  </button>
                ))
              )}
            </div>
          )}
        </div>

        <div className="navbar-divider" />

        <div className="navbar-profile-wrapper" ref={userMenuRef}>
          <button
            className={`navbar-user ${userMenuOpen ? 'open' : ''}`}
            onClick={() => {
              setNotifOpen(false)
              setUserMenuOpen((current) => !current)
            }}
            type="button"
            aria-expanded={userMenuOpen}
            aria-haspopup="menu"
          >
            <div className="navbar-user-info">
              <span className="navbar-user-name">{userName}</span>
              <span className="navbar-user-role">{roleName}</span>
              <span className="navbar-user-hotel">{hotelName}</span>
            </div>

            <div className="navbar-avatar">{userName.charAt(0).toUpperCase()}</div>
            <UserChevronIcon open={userMenuOpen} />
          </button>

          {userMenuOpen && (
            <div className="navbar-user-menu" role="menu">
              <div className="navbar-user-menu-header">
                <div className="navbar-user-menu-avatar">
                  {userName.charAt(0).toUpperCase()}
                </div>
                <div>
                  <strong>{userName}</strong>
                  <span>{roleName}</span>
                </div>
              </div>

              <div className="navbar-user-menu-section">
                <span className="navbar-user-menu-label">Active property</span>
                <HotelSwitcher
                  tenantContext={tenantContext}
                  onHotelChange={onHotelChange}
                  switchingHotelId={switchingHotelId}
                  error={hotelSwitchError}
                  variant="navbar"
                />
              </div>

              <button className="navbar-logout-btn" onClick={handleLogout} type="button">
                <LogoutIcon />
                Logout
              </button>
            </div>
          )}
        </div>
      </div>
      <GlobalSearch
        open={searchOpen}
        hotelId={hotelId}
        onClose={() => setSearchOpen(false)}
        onNavigate={onNavigate}
      />
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
function UserChevronIcon({ open }) {
  return (
    <svg
      className={`navbar-user-chevron ${open ? 'open' : ''}`}
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <polyline points="6 9 12 15 18 9" />
    </svg>
  )
}

function LogoutIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M10 17l5-5-5-5" />
      <path d="M15 12H3" />
      <path d="M21 19V5a2 2 0 0 0-2-2h-6" />
    </svg>
  )
}

