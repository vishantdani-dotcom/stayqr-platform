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
import {
  getNotificationCategory,
  getNotificationCategoryLabel,
  getNotificationDestination,
  getNotificationTone,
  timeAgo,
} from '../../lib/notificationPresentation'
import {
  createKitchenOrderNotification,
  createServiceRequestNotification,
  filterNotificationInboxForRole,
  getAccountNotificationSoundKey,
  isLocalDepartmentNotification,
  isServiceRequestForRole,
  mergeNotificationItems,
} from '../../lib/departmentNotificationRouting'
import './Navbar.css'

const NOTIFICATION_SOUND_ASSETS = Object.freeze({
  dashboard: '/assets/stayqr-rev61f4-main-dashboard.wav',
  housekeeping: '/assets/stayqr-rev61f4-housekeeping.wav',
  kitchen: '/assets/stayqr-rev61f4-kitchen.wav',
})

function ensureNotificationAudio(audioMap, soundKey) {
  const safeKey = NOTIFICATION_SOUND_ASSETS[soundKey] ? soundKey : 'dashboard'
  let audio = audioMap.get(safeKey)
  if (!audio) {
    audio = new Audio(NOTIFICATION_SOUND_ASSETS[safeKey])
    audio.preload = 'auto'
    audio.volume = 1
    audio.dataset.stayqrNotificationSound = `rev60-${safeKey}`
    audioMap.set(safeKey, audio)
  }
  return audio
}

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
  onReturnToPlatform,
  onLogout,
}) {
  const [searchOpen, setSearchOpen] = useState(false)
  const [notifOpen, setNotifOpen] = useState(false)
  const [userMenuOpen, setUserMenuOpen] = useState(false)
  const [notifications, setNotifications] = useState([])
  const [notifBusy, setNotifBusy] = useState(false)
  const [notifError, setNotifError] = useState('')
  const userMenuRef = useRef(null)
  const notificationRef = useRef(null)
  const notificationRequestRef = useRef(0)
  const notificationAudioRefsRef = useRef(new Map())
  const notificationAudioArmedRef = useRef(false)
  const notificationInboxPrimedRef = useRef(false)
  const seenNotificationIdsRef = useRef(new Set())

  const hotelId = tenantContext?.selectedHotelId || currentStaff?.hotel_id || currentStaff?.hotels?.id
  const userName = currentStaff?.full_name || 'Admin'
  const hotelName = tenantContext?.selectedHotel?.hotel_name || currentStaff?.hotels?.hotel_name || currentStaff?.hotel_name || 'StayQR Hotel'
  const normalizedRole = normalizeRole(currentStaff?.role || currentRole || 'manager')
  const isPlatformAccount = Boolean(tenantContext?.isPlatformAdmin)
  const isPlatformSupportMode = Boolean(tenantContext?.isPlatformSupportMode)
  const roleName = formatRole(normalizedRole)
  const unreadCount = notifications.filter((item) => item.status === 'unread').length

  useEffect(() => {
    notificationRequestRef.current += 1
    setNotifications([])
    setNotifError('')
    setNotifOpen(false)
    notificationInboxPrimedRef.current = false
    seenNotificationIdsRef.current = new Set()

    if (!hotelId) return undefined

    loadNotifications(hotelId)
    return subscribeToNotificationInbox(hotelId, () => loadNotifications(hotelId))
  }, [hotelId])

  useEffect(() => {
    if (!hotelId) return undefined

    const housekeepingAccount =
      ['housekeeping', 'housekeeper'].includes(normalizedRole)

    const channel = supabase
      .channel(
        `housekeeping_h2_service_lifecycle_${hotelId}_${normalizedRole}`
      )
      .on(
        'postgres_changes',
        {
          event: housekeepingAccount ? '*' : 'INSERT',
          schema: 'public',
          table: 'service_requests',
          filter: `hotel_id=eq.${hotelId}`,
        },
        (payload) => {
          const request = payload?.new
          if (!request?.id) return
          if (!isServiceRequestForRole(request, normalizedRole)) return

          const baseNotification =
            createServiceRequestNotification(request)

          let notification = baseNotification

          if (housekeepingAccount) {
            const status = String(request?.status || 'pending')
              .trim()
              .toLowerCase()

            const statusCopy = {
              pending: {
                eventKey: 'service_request.created',
                label: 'Request received',
                message:
                  request?.request_details ||
                  'A new Housekeeping request was received.',
              },
              accepted: {
                eventKey: 'service_request.accepted',
                label: 'Request accepted',
                message: 'The Housekeeping request was accepted.',
              },
              in_progress: {
                eventKey: 'service_request.in_progress',
                label: 'Request in progress',
                message: 'The Housekeeping request is now in progress.',
              },
              escalated: {
                eventKey: 'service_request.escalated',
                label: 'Request escalated',
                message: 'The Housekeeping request was escalated.',
              },
              completed: {
                eventKey: 'service_request.completed',
                label: 'Request completed',
                message: 'The Housekeeping request was completed.',
              },
              cancelled: {
                eventKey: 'service_request.cancelled',
                label: 'Request cancelled',
                message: 'The guest cancelled the Housekeeping request.',
              },
            }

            const copy =
              statusCopy[status] || {
                eventKey: 'service_request.updated',
                label: 'Request updated',
                message: 'The Housekeeping request was updated.',
              }

            notification = {
              ...baseNotification,
              id: `local-service-request:${request.id}:${status}`,
              event_key: copy.eventKey,
              title:
                `${request.request_type || 'Housekeeping'} · ${copy.label}`,
              message: copy.message,
              created_at:
                request?.updated_at ||
                request?.cancelled_at ||
                request?.completed_at ||
                request?.created_at ||
                new Date().toISOString(),
              metadata: {
                ...baseNotification.metadata,
                request_status: status,
                lifecycle_event: true,
              },
            }
          } else if (payload?.eventType !== 'INSERT') {
            return
          }

          if (!seenNotificationIdsRef.current.has(notification.id)) {
            seenNotificationIdsRef.current.add(notification.id)
            setNotifications((current) =>
              mergeNotificationItems([notification], current)
            )
          }

          // H2 intentionally preserves the existing ringtone behavior:
          // only a newly INSERTED request attempts the existing sound path.
          // H3 will repair Housekeeping audio after lifecycle notifications pass.
          if (payload?.eventType !== 'INSERT') return

          const soundKey =
            getAccountNotificationSoundKey(normalizedRole)
          const sharedPlayer =
            window.__stayqrPlayDepartmentNotificationSound

          if (typeof sharedPlayer === 'function') {
            sharedPlayer(soundKey)
          } else {
            try {
              const audio = ensureNotificationAudio(
                notificationAudioRefsRef.current,
                soundKey
              )
              audio.pause?.()
              audio.currentTime = 0
              void audio.play().catch(() => {})
            } catch {
              // Notification remains visible if browser audio is unavailable.
            }
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [hotelId, normalizedRole])
  useEffect(() => {
    if (
      !hotelId ||
      !['restaurant', 'kitchen', 'chef'].includes(normalizedRole)
    ) {
      return undefined
    }

    const channel = supabase
      .channel(
        `rev61f4_kitchen_notifications_${hotelId}_${normalizedRole}`
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'food_orders',
          filter: `hotel_id=eq.${hotelId}`,
        },
        (payload) => {
          const order = payload?.new
          if (!order?.id) return

          const notification = createKitchenOrderNotification(order)

          if (!seenNotificationIdsRef.current.has(notification.id)) {
            seenNotificationIdsRef.current.add(notification.id)
            setNotifications((current) =>
              mergeNotificationItems([notification], current)
            )
          }

          const sharedPlayer =
            window.__stayqrPlayDepartmentNotificationSound

          if (typeof sharedPlayer === 'function') {
            sharedPlayer('kitchen')
          } else {
            try {
              const audio = ensureNotificationAudio(
                notificationAudioRefsRef.current,
                'kitchen'
              )
              audio.pause?.()
              audio.currentTime = 0
              void audio.play().catch(() => {})
            } catch {
              // Keep the Kitchen notification visible if audio is unavailable.
            }
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [hotelId, normalizedRole])
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
    const audioMap = notificationAudioRefsRef.current

    const preloadAudio = () => {
      Object.keys(NOTIFICATION_SOUND_ASSETS).forEach((soundKey) => {
        try {
          ensureNotificationAudio(audioMap, soundKey).load?.()
        } catch {
          // Notification audio is progressive enhancement.
        }
      })
    }

    const playDepartmentSound = (requestedKey) => {
      const soundKey =
        NOTIFICATION_SOUND_ASSETS[requestedKey]
          ? requestedKey
          : 'dashboard'

      const browserAlreadyActivated =
        Boolean(navigator.userActivation?.hasBeenActive)

      if (
        !notificationAudioArmedRef.current &&
        !browserAlreadyActivated
      ) {
        return false
      }

      notificationAudioArmedRef.current = true

      try {
        const audio = ensureNotificationAudio(audioMap, soundKey)
        audio.pause?.()
        audio.currentTime = 0
        void audio.play().catch(() => {})
        return true
      } catch {
        return false
      }
    }

    const armAudio = () => {
      notificationAudioArmedRef.current = true
      preloadAudio()
    }

    preloadAudio()

    if (navigator.userActivation?.hasBeenActive) {
      armAudio()
    }

    window.__stayqrPlayDepartmentNotificationSound =
      playDepartmentSound
    window.__stayqrDepartmentToneVersion =
      'rev61f4-lint-safe-routing'

    window.addEventListener(
      'pointerdown',
      armAudio,
      { passive: true }
    )
    window.addEventListener('keydown', armAudio)

    return () => {
      window.removeEventListener('pointerdown', armAudio)
      window.removeEventListener('keydown', armAudio)

      if (
        window.__stayqrPlayDepartmentNotificationSound ===
        playDepartmentSound
      ) {
        delete window.__stayqrPlayDepartmentNotificationSound
      }

      if (
        window.__stayqrDepartmentToneVersion ===
        'rev61f4-lint-safe-routing'
      ) {
        delete window.__stayqrDepartmentToneVersion
      }

      audioMap.forEach((audio) => {
        audio.pause?.()
        audio.currentTime = 0
      })

      audioMap.clear()
      notificationAudioArmedRef.current = false
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

  function playNotificationChime(notification) {
    const sourceType = String(notification?.source_type || '')
      .trim()
      .toLowerCase()

    if (
      sourceType === 'service_request' ||
      sourceType === 'food_order'
    ) {
      return
    }

    const browserAlreadyActivated =
      Boolean(navigator.userActivation?.hasBeenActive)

    if (
      !notificationAudioArmedRef.current &&
      !browserAlreadyActivated
    ) {
      return
    }

    notificationAudioArmedRef.current = true

    try {
      const soundKey =
        getAccountNotificationSoundKey(normalizedRole)
      const sharedPlayer =
        window.__stayqrPlayDepartmentNotificationSound

      if (typeof sharedPlayer === 'function') {
        sharedPlayer(soundKey)
      } else {
        const audio = ensureNotificationAudio(
          notificationAudioRefsRef.current,
          soundKey
        )
        audio.pause?.()
        audio.currentTime = 0
        void audio.play().catch(() => {})
      }

      if (
        document.visibilityState !== 'visible' &&
        window.Notification?.permission === 'granted'
      ) {
        new window.Notification(
          notification?.title || 'StayQR',
          {
            body:
              notification?.message ||
              'New hotel activity',
            tag: notification?.id
              ? `stayqr-${notification.id}`
              : 'stayqr-notification',
          }
        )
      }
    } catch {
      // Keep notification inbox functional even when audio is unavailable.
    }
  }

  async function loadNotifications(id) {
    if (!id) return

    const requestId = notificationRequestRef.current + 1
    notificationRequestRef.current = requestId

    try {
      const data = await getNotificationInbox(id, 30)

      if (notificationRequestRef.current !== requestId) {
        return
      }

      const nextItems = await filterNotificationInboxForRole({
        items: data?.items || [],
        hotelId: id,
        role: normalizedRole,
      })
      const newUnreadItems = nextItems.filter((item) =>
        item?.id && item.status === 'unread' && !seenNotificationIdsRef.current.has(item.id)
      )

      if (notificationInboxPrimedRef.current && newUnreadItems.length > 0) {
        // get_notification_inbox is recipient-scoped, so only alerts visible to this logged-in staff account chime.
        playNotificationChime(newUnreadItems[0])
      }

      seenNotificationIdsRef.current = new Set([
        ...seenNotificationIdsRef.current,
        ...nextItems.map((item) => item?.id).filter(Boolean),
      ])
      notificationInboxPrimedRef.current = true
      setNotifications((current) =>
        mergeNotificationItems(nextItems, current)
      )
      setNotifError('')
    } catch (error) {
      if (notificationRequestRef.current === requestId) {
        console.error('Notification inbox load failed:', error)
        setNotifError('Notifications could not be refreshed. Try again.')
      }
    }
  }

  function handleOpenNotifications() {
    setUserMenuOpen(false)
    setNotifOpen((prev) => {
      const next = !prev
      if (next && hotelId) loadNotifications(hotelId)
      return next
    })
  }

  async function handleMarkAllRead() {
    if (!hotelId || notifBusy) return
    setNotifBusy(true)
    setNotifError('')
    try {
      await markInboxAllRead(hotelId)
      await loadNotifications(hotelId)
      setNotifications((current) =>
        current.map((item) =>
          isLocalDepartmentNotification(item)
            ? {
                ...item,
                status: 'read',
                read_at: new Date().toISOString(),
              }
            : item
        )
      )
    } catch (error) {
      console.error('Mark all notifications read failed:', error)
      setNotifError('Could not mark notifications as read.')
    } finally {
      setNotifBusy(false)
    }
  }

  async function handleNotificationClick(notification) {
    if (!notification?.id || notifBusy) return
    setNotifBusy(true)
    setNotifError('')

    const localDepartmentEvent =
      isLocalDepartmentNotification(notification)

    try {
      if (notification.status === 'unread') {
        if (localDepartmentEvent) {
          setNotifications((current) =>
            current.map((item) =>
              item.id === notification.id
                ? {
                    ...item,
                    status: 'read',
                    read_at: new Date().toISOString(),
                  }
                : item
            )
          )
        } else {
          await markInboxNotificationRead(notification.id)
        }
      }

      const destination = getNotificationDestination(notification)
      setNotifOpen(false)
      if (onNavigate) {
        onNavigate(destination.section, destination.detail)
      }

      if (!localDepartmentEvent) {
        await loadNotifications(hotelId)
      }
    } catch (error) {
      console.error('Notification action failed:', error)
      setNotifError('Could not open this notification. Try again.')
    } finally {
      setNotifBusy(false)
    }
  }
  const handleLogout = async () => {
    if (onLogout) {
      await onLogout()
      return
    }
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
    folios: 'Guest Bills',
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
      className={`navbar${sidebarCollapsed ? ' navbar--sidebar-collapsed' : ''}`}
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
            aria-label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications'}
            aria-expanded={notifOpen}
            aria-haspopup="dialog"
          >
            <BellIcon />
            {unreadCount > 0 && (
              <span className="notif-live-count" aria-hidden="true">
                {unreadCount > 9 ? '9+' : unreadCount}
              </span>
            )}
          </button>

          {notifOpen && (
            <div
              className="notif-dropdown"
              role="dialog"
              aria-label="Hotel notifications"
            >
              <div className="notif-header">
                <span className="notif-heading-copy">
                  <strong>Notifications</strong>
                  <small>Live hotel activity</small>
                </span>

                <div className="notif-header-actions">
                  <span className="notif-count">
                    {unreadCount > 0 ? `${unreadCount} unread` : 'All caught up'}
                  </span>

                  {unreadCount > 0 && (
                    <button className="notif-mark-read" onClick={handleMarkAllRead} type="button" disabled={notifBusy}>
                      Mark all as read
                    </button>
                  )}
                </div>
              </div>

              {notifError && (
                <div className="notif-inline-error" role="status">
                  <span>{notifError}</span>
                  <button type="button" onClick={() => hotelId && loadNotifications(hotelId)}>Retry</button>
                </div>
              )}

              <div className="notif-list" aria-live="polite">
                {notifications.length === 0 ? (
                  <div className="notif-empty">
                    <div className="notif-empty-icon"><BellIcon /></div>
                    <p>No notifications yet</p>
                    <span>New hotel activity will appear here.</span>
                  </div>
                ) : (
                  notifications.slice(0, 10).map((notification) => (
                    <button
                      key={notification.id}
                      className={`notif-item ${notification.status === 'read' ? 'read' : 'unread'}`}
                      onClick={() => handleNotificationClick(notification)}
                      type="button"
                    >
                      <span className={`notif-item-icon ${getNotificationTone(notification)}`} aria-hidden="true">
                        <NotificationTypeIcon category={getNotificationCategory(notification)} />
                      </span>

                      <span className="notif-item-body">
                        <span className="notif-item-title">{notification.title}</span>
                        <span className="notif-item-message">{notification.message}</span>
                        <span className="notif-item-meta">
                          <span>{getNotificationCategoryLabel(notification)}</span>
                          <span aria-hidden="true">•</span>
                          <span>{timeAgo(notification.created_at)}</span>
                          {notification.status === 'unread' && <span className="notif-new-label">New</span>}
                        </span>
                      </span>

                      {notification.status === 'unread' && <span className="notif-unread-dot" aria-hidden="true" />}
                    </button>
                  ))
                )}
              </div>

              {onNavigate && (
                <div className="notif-footer">
                  <button
                    className="notif-open-centre"
                    type="button"
                    onClick={() => {
                      setNotifOpen(false)
                      onNavigate('operationscenter')
                    }}
                  >
                    <span>View all notifications</span>
                    <ChevronRightIcon />
                  </button>
                </div>
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
                {isPlatformAccount ? (
                  <div className="navbar-platform-scope">
                    <strong>{isPlatformSupportMode ? `View as ${hotelName}` : 'StayQR platform scope'}</strong>
                    <span>
                      {isPlatformSupportMode
                        ? 'Audited, time-bound hotel support session is active.'
                        : 'Hotel access requires a timed, audited support session.'}
                    </span>
                    {isPlatformSupportMode && (
                      <button type="button" className="navbar-platform-return" onClick={onReturnToPlatform}>
                        Return to Super Admin
                      </button>
                    )}
                  </div>
                ) : (
                  <>
                    <span className="navbar-user-menu-label">Active property</span>
                    <HotelSwitcher
                      tenantContext={tenantContext}
                      onHotelChange={onHotelChange}
                      switchingHotelId={switchingHotelId}
                      error={hotelSwitchError}
                      variant="navbar"
                    />
                  </>
                )}
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

function formatRole(role) {
  return String(role || 'Staff')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}


function NotificationTypeIcon({ category }) {
  const common = {
    width: 18,
    height: 18,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.9,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
  }

  const paths = {
    payment: (<>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M3 10h18" />
      <path d="M7 15h3" />
    </>),
    food: (<>
      <path d="M4 3v7a3 3 0 0 0 3 3V3" />
      <path d="M7 13v8" />
      <path d="M15 3v18" />
      <path d="M15 3c3 1 5 3.5 5 7h-5" />
    </>),
    service: (<>
      <path d="M12 3a6 6 0 0 0-6 6c0 5-2 5-2 7h16c0-2-2-2-2-7a6 6 0 0 0-6-6Z" />
      <path d="M10 20h4" />
    </>),
    housekeeping: (<>
      <path d="m3 21 6-6" />
      <path d="m14 4 6 6" />
      <path d="M15 5 5 15l4 4L19 9Z" />
    </>),
    maintenance: (<>
      <path d="M14.7 6.3a4 4 0 0 0-5 5L3 18l3 3 6.7-6.7a4 4 0 0 0 5-5l-2.4 2.4-3-3 2.4-2.4Z" />
    </>),
    reservation: (<>
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <path d="M16 3v4M8 3v4M3 11h18" />
      <path d="m9 16 2 2 4-4" />
    </>),
    guest: (<>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21a8 8 0 0 1 16 0" />
    </>),
    invoice: (<>
      <path d="M6 2h9l4 4v16H6Z" />
      <path d="M14 2v5h5M9 13h6M9 17h6" />
    </>),
    room: (<>
      <path d="M3 21V9l9-6 9 6v12" />
      <path d="M9 21v-7h6v7" />
    </>),
    support: (<>
      <circle cx="12" cy="12" r="9" />
      <path d="M9.5 9a2.7 2.7 0 0 1 5.2 1c0 2-2.7 2.2-2.7 4" />
      <path d="M12 18h.01" />
    </>),
    general: (<>
      <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" />
      <path d="M10 21h4" />
    </>),
  }

  return <svg {...common} aria-hidden="true">{paths[category] || paths.general}</svg>
}

function ChevronRightIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="m9 18 6-6-6-6" />
    </svg>
  )
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

