// src/App.jsx

import { useCallback, useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import {
  clearSelectedTenantHotel,
  clearTenantContextCache,
  loadTenantContext,
  selectTenantHotel,
} from './lib/tenantContext'
import { canAccessSection } from './lib/currentStaff'

import Sidebar from './components/sidebar/Sidebar'
import Navbar from './components/navbar/Navbar'

import Dashboard from './pages/dashboard/Dashboard'
import Rooms from './pages/rooms/Rooms'
import CheckIn from './pages/checkin/CheckIn'
import Guests from './pages/guests/Guests'
import GuestGuide from './pages/guestguide/GuestGuide'
import FoodMenu from './pages/food/FoodMenu'
import FoodOrders from './pages/foodorders/FoodOrders'
import ServiceRequests from './pages/services/ServiceRequests'
import Payments from './pages/payments/Payments'
import Amenities from './pages/amenities/Amenities'
import Charges from './pages/charges/Charges'
import Housekeeping from './pages/housekeeping/Housekeeping'
import Login from './pages/auth/Login'
import HotelProfile from './pages/hotel/HotelProfile'
import Reports from './pages/reports/Reports'
import Invoices from './pages/invoices/Invoices'
import QRGenerator from './pages/qr/QRGenerator'
import SuperAdmin from './pages/superadmin/SuperAdmin'
import MenuManagement from './pages/menumanagement/MenuManagement'
import StaffManagement from './pages/staff/StaffManagement'
import Reservations from './pages/reservations/Reservations'
import BookingCalendar from './pages/calendar/BookingCalendar'
import ReservationOperations from './pages/operations/ReservationOperations'
import { NAVIGATE_EVENT } from './lib/bookingCalendar'

import './styles/globals.css'
import './App.css'

export default function App() {
  const [session, setSession] = useState(null)
  const [tenantContext, setTenantContext] = useState(null)
  const [currentStaff, setCurrentStaff] = useState(null)
  const [currentRole, setCurrentRole] = useState('')
  const [authLoading, setAuthLoading] = useState(true)
  const [authError, setAuthError] = useState('')
  const [activeSection, setActiveSection] = useState('dashboard')
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [navigationRequest, setNavigationRequest] = useState(null)
  const [switchingHotelId, setSwitchingHotelId] = useState(null)
  const [hotelSwitchError, setHotelSwitchError] = useState('')

  const loadUserContext = useCallback(async () => {
    setAuthError('')

    try {
      const context = await loadTenantContext({ force: true })

      if (!context) {
        setTenantContext(null)
        setCurrentStaff(null)
        setCurrentRole('')
        setAuthError('Your StayQR session could not be resolved.')
        return
      }

      if (!context.selectedHotel && !context.isPlatformAdmin) {
        setTenantContext(context)
        setCurrentStaff(null)
        setCurrentRole('')
        setAuthError(
          'Your login is not assigned to an active hotel. Ask the hotel owner or StayQR support to assign access.'
        )
        return
      }

      setTenantContext(context)
      setCurrentStaff(context.currentStaff)
      setCurrentRole(context.currentRole)
      setActiveSection((currentSection) =>
        canAccessSection(context.currentRole, currentSection)
          ? currentSection
          : context.isPlatformAdmin
            ? 'superadmin'
            : 'dashboard'
      )
    } catch (error) {
      console.error('StayQR tenant context error:', error)
      setTenantContext(null)
      setCurrentStaff(null)
      setCurrentRole('')
      setAuthError(
        'StayQR could not load your hotel access. Please try again or contact support.'
      )
    }
  }, [])

  const initAuth = useCallback(async () => {
    setAuthLoading(true)

    const { data, error } = await supabase.auth.getSession()

    if (error) {
      console.error('Initial auth session error:', error)
      setAuthError('StayQR could not verify your login session.')
      setAuthLoading(false)
      return
    }

    setSession(data.session)

    if (data.session) {
      await loadUserContext()
    }

    setAuthLoading(false)
  }, [loadUserContext])

  useEffect(() => {
    initAuth()

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, newSession) => {
      clearTenantContextCache()
      setSession(newSession)

      if (newSession) {
        loadUserContext().finally(() => setAuthLoading(false))
      } else {
        setTenantContext(null)
        setCurrentStaff(null)
        setCurrentRole('')
        setAuthError('')
        setAuthLoading(false)
      }
    })

    return () => subscription.unsubscribe()
  }, [initAuth, loadUserContext])

  useEffect(() => {
    const handleExternalNavigation = (event) => {
      const section = event.detail?.section
      if (!section || !canAccessSection(currentRole, section)) return
      setNavigationRequest({
        ...event.detail,
        requestId: `${Date.now()}-${Math.random()}`,
      })
      setActiveSection(section)
      setMobileMenuOpen(false)
    }

    window.addEventListener(NAVIGATE_EVENT, handleExternalNavigation)
    return () => window.removeEventListener(NAVIGATE_EVENT, handleExternalNavigation)
  }, [currentRole])

  if (window.location.pathname.startsWith('/guest/')) {
    return <GuestGuide />
  }

  if (window.location.pathname.startsWith('/food/')) {
    return <FoodMenu />
  }

  if (authLoading) {
    return (
      <div
        style={{
          height: '100vh',
          background: '#050505',
          color: '#fff',
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          fontSize: '18px',
        }}
      >
        Loading StayQR...
      </div>
    )
  }

  if (!session) {
    return <Login />
  }

  if (authError) {
    return <TenantAccessError message={authError} />
  }

  const handleHotelChange = async (hotelId) => {
    if (
      !hotelId ||
      hotelId === tenantContext?.selectedHotelId ||
      switchingHotelId
    ) {
      return
    }

    setSwitchingHotelId(hotelId)
    setHotelSwitchError('')

    try {
      const nextContext = await selectTenantHotel(hotelId)

      if (!nextContext?.selectedHotel) {
        throw new Error('StayQR could not resolve the selected hotel.')
      }

      setTenantContext(nextContext)
      setCurrentStaff(nextContext.currentStaff)
      setCurrentRole(nextContext.currentRole)
      setNavigationRequest(null)
      setMobileMenuOpen(false)
      setActiveSection((currentSection) =>
        canAccessSection(nextContext.currentRole, currentSection)
          ? currentSection
          : nextContext.isPlatformAdmin
            ? 'superadmin'
            : 'dashboard'
      )
    } catch (error) {
      console.error('Hotel switch failed:', error)
      setHotelSwitchError(
        error?.message || 'StayQR could not switch the active hotel.'
      )
    } finally {
      setSwitchingHotelId(null)
    }
  }

  const handleNavigate = (section) => {
    if (!canAccessSection(currentRole, section)) {
      alert('You do not have access to this section.')
      return
    }

    setNavigationRequest(null)
    setActiveSection(section)
    setMobileMenuOpen(false)
  }

  const handleMobileMenuToggle = () => {
    setMobileMenuOpen((prev) => !prev)

    if (!mobileMenuOpen) {
      setSidebarCollapsed(false)
    }
  }

  const renderPage = () => {
    if (!canAccessSection(currentRole, activeSection)) {
      return <AccessDenied section={activeSection} />
    }

    switch (activeSection) {
      case 'dashboard':
        return <Dashboard hotel={tenantContext?.selectedHotel || null} />
      case 'rooms':
        return <Rooms />
      case 'reservations':
        return (
          <Reservations
            initialReservationId={navigationRequest?.reservationId || null}
            navigationRequestId={navigationRequest?.requestId || null}
          />
        )
      case 'calendar':
        return <BookingCalendar />
      case 'operations':
        return <ReservationOperations />
      case 'checkin':
        return <CheckIn />
      case 'guests':
        return (
          <Guests
            initialGuestSessionId={navigationRequest?.guestSessionId || null}
            navigationRequestId={navigationRequest?.requestId || null}
          />
        )
      case 'services':
        return <ServiceRequests />
      case 'qr':
        return <QRGenerator />
      case 'payments':
        return <Payments />
      case 'foodorders':
        return <FoodOrders />
      case 'charges':
        return <Charges />
      case 'housekeeping':
        return <Housekeeping />
      case 'amenities':
        return <Amenities />
      case 'hotel':
        return <HotelProfile />
      case 'reports':
        return <Reports />
      case 'invoices':
        return <Invoices />
      case 'menu':
        return <MenuManagement />
      case 'staff':
        return <StaffManagement />
      case 'superadmin':
        return <SuperAdmin />
      default:
        return <ComingSoonPage section={activeSection} />
    }
  }

  return (
    <div className="app-shell">
      <Sidebar
        activeSection={activeSection}
        onNavigate={handleNavigate}
        collapsed={sidebarCollapsed}
        onToggle={() => setSidebarCollapsed((prev) => !prev)}
        mobileOpen={mobileMenuOpen}
        currentStaff={currentStaff}
        currentRole={currentRole}
        tenantContext={tenantContext}
        onHotelChange={handleHotelChange}
        switchingHotelId={switchingHotelId}
        hotelSwitchError={hotelSwitchError}
      />

      {mobileMenuOpen && (
        <div
          className="mobile-overlay"
          onClick={() => setMobileMenuOpen(false)}
        />
      )}

      <div
        className="app-main"
        style={{
          marginLeft: sidebarCollapsed ? 64 : 'var(--sidebar-w)',
        }}
      >
        <Navbar
          sidebarCollapsed={sidebarCollapsed}
          onMobileMenuToggle={handleMobileMenuToggle}
          activeSection={activeSection}
          currentStaff={currentStaff}
          currentRole={currentRole}
          tenantContext={tenantContext}
          onHotelChange={handleHotelChange}
          switchingHotelId={switchingHotelId}
          hotelSwitchError={hotelSwitchError}
        />

        <main
          className="app-content"
          key={tenantContext?.selectedHotelId || 'no-selected-hotel'}
        >
          {renderPage()}
        </main>
      </div>

      {switchingHotelId && (
        <div className="tenant-switch-overlay" role="status" aria-live="polite">
          <div className="tenant-switch-card">
            <span className="tenant-switch-spinner" />
            <div>
              <strong>Switching property</strong>
              <span>Reloading authoritative hotel data…</span>
            </div>
          </div>
        </div>
      )}

      {hotelSwitchError && !switchingHotelId && (
        <div className="tenant-switch-error" role="alert">
          <span>{hotelSwitchError}</span>
          <button type="button" onClick={() => setHotelSwitchError('')}>
            ×
          </button>
        </div>
      )}
    </div>
  )
}

function TenantAccessError({ message }) {
  const handleLogout = async () => {
    clearSelectedTenantHotel()
    clearTenantContextCache()
    await supabase.auth.signOut()
    window.location.reload()
  }

  return (
    <div className="coming-soon-page">
      <div className="cs-content">
        <div className="cs-icon">⚠️</div>
        <h2 className="cs-title gold-text">Hotel Access Required</h2>
        <p className="cs-sub">{message}</p>
        <button
          type="button"
          onClick={handleLogout}
          style={{
            marginTop: '18px',
            background: '#D4AF37',
            color: '#000',
            border: 'none',
            padding: '10px 18px',
            borderRadius: '8px',
            cursor: 'pointer',
            fontWeight: '700',
          }}
        >
          Return to Login
        </button>
      </div>
    </div>
  )
}

function AccessDenied({ section }) {
  return (
    <div className="coming-soon-page">
      <div className="cs-content">
        <div className="cs-icon">🔒</div>
        <h2 className="cs-title gold-text">Access Restricted</h2>
        <p className="cs-sub">
          You do not have permission to open the {section} section.
        </p>
      </div>
    </div>
  )
}

function ComingSoonPage({ section }) {
  return (
    <div className="coming-soon-page">
      <div className="cs-content">
        <div className="cs-icon">🚧</div>
        <h2 className="cs-title gold-text">Coming Soon</h2>
        <p className="cs-sub">
          The {section} module is being prepared for StayQR v1.0.
        </p>
      </div>
    </div>
  )
}
