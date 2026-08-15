// src/App.jsx

import { lazy, Suspense, useCallback, useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import {
  clearSelectedTenantHotel,
  clearTenantContextCache,
  loadTenantContext,
  selectTenantHotel,
} from './lib/tenantContext'
import { canAccessSection } from './lib/currentStaff'
import { NAVIGATE_EVENT } from './lib/bookingCalendar'
import { setMonitoringContext } from './lib/day18Monitoring'

import Sidebar from './components/sidebar/Sidebar'
import Navbar from './components/navbar/Navbar'

import AppErrorBoundary from './components/system/AppErrorBoundary'
import RouteLoadingFallback from './components/system/RouteLoadingFallback'

const Dashboard = lazy(() => import('./pages/dashboard/Dashboard'))
const Rooms = lazy(() => import('./pages/rooms/Rooms'))
const CheckIn = lazy(() => import('./pages/checkin/CheckIn'))
const Guests = lazy(() => import('./pages/guests/Guests'))
const GuestGuide = lazy(() => import('./pages/guestguide/GuestGuide'))
const FoodMenu = lazy(() => import('./pages/food/FoodMenu'))
const FoodOrders = lazy(() => import('./pages/foodorders/FoodOrders'))
const ServiceRequests = lazy(() => import('./pages/services/ServiceRequests'))
const Payments = lazy(() => import('./pages/payments/Payments'))
const FolioSettlement = lazy(() => import('./pages/folios/FolioSettlement'))
const Amenities = lazy(() => import('./pages/amenities/Amenities'))
const Charges = lazy(() => import('./pages/charges/Charges'))
const Housekeeping = lazy(() => import('./pages/housekeeping/Housekeeping'))
const Maintenance = lazy(() => import('./pages/maintenance/Maintenance'))
const Login = lazy(() => import('./pages/auth/Login'))
const AuthAction = lazy(() => import('./pages/auth/AuthAction'))
const HotelProfile = lazy(() => import('./pages/hotel/HotelProfile'))
const GuestGuideBuilder = lazy(() => import('./pages/guestbuilder/GuestGuideBuilder'))
const Reports = lazy(() => import('./pages/reports/Reports'))
const OperationsCenter = lazy(() => import('./pages/operationscenter/OperationsCenter'))
const Invoices = lazy(() => import('./pages/invoices/Invoices'))
const InvoiceVerification = lazy(() => import('./pages/invoices/InvoiceVerification'))
const QRGenerator = lazy(() => import('./pages/qr/QRGenerator'))
const SuperAdmin = lazy(() => import('./pages/superadmin/SuperAdmin'))
const MenuManagement = lazy(() => import('./pages/menumanagement/MenuManagement'))
const StaffManagement = lazy(() => import('./pages/staff/StaffManagement'))
const Reservations = lazy(() => import('./pages/reservations/Reservations'))
const BookingCalendar = lazy(() => import('./pages/calendar/BookingCalendar'))
const ReservationOperations = lazy(() => import('./pages/operations/ReservationOperations'))
const HotelOnboarding = lazy(() => import('./pages/onboarding/HotelOnboarding'))
const PrivacyPolicy = lazy(() => import('./pages/legal/PrivacyPolicy'))

const SECTION_TITLES = {
  dashboard: 'dashboard',
  rooms: 'rooms and inventory',
  reservations: 'reservations',
  calendar: 'booking calendar',
  operations: 'front-desk operations',
  checkin: 'check-in',
  guests: 'guests',
  services: 'service requests',
  qr: 'QR management',
  payments: 'payments',
  folios: 'folio settlement',
  foodorders: 'food orders',
  charges: 'charges',
  housekeeping: 'housekeeping',
  maintenance: 'maintenance',
  amenities: 'amenities',
  hotel: 'hotel profile',
  guidebuilder: 'guest guide builder',
  reports: 'reports',
  operationscenter: 'operations centre',
  invoices: 'invoices',
  menu: 'menu management',
  staff: 'staff management',
  superadmin: 'platform administration',
  onboarding: 'hotel onboarding',
}

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
  const [onboardingRequired, setOnboardingRequired] = useState(false)
  const monitoringHotelId = tenantContext?.selectedHotelId || null
  const monitoringUserId =
    session?.user?.id || tenantContext?.user?.id || null

  useEffect(() => {
    setMonitoringContext({
      hotelId: monitoringHotelId,
      userId: monitoringUserId,
      role: currentRole || null,
    })
  }, [currentRole, monitoringHotelId, monitoringUserId])

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
        setCurrentRole('onboarding')
        setOnboardingRequired(true)
        setActiveSection('onboarding')
        return
      }

      setOnboardingRequired(false)
      setTenantContext(context)
      setCurrentStaff(context.currentStaff)
      setCurrentRole(context.currentRole)
      setActiveSection((currentSection) =>
        canAccessSection(context.currentRole, currentSection, context.permissions)
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
      setOnboardingRequired(false)
      setAuthError(
        'StayQR could not load your hotel access. Please try again or contact support.'
      )
    }
  }, [])

  const handleOnboardingReady = useCallback(async (hotelId) => {
    if (!hotelId) return

    setHotelSwitchError('')
    setSwitchingHotelId(hotelId)

    try {
      clearTenantContextCache()
      const nextContext = await selectTenantHotel(hotelId)

      if (!nextContext?.selectedHotel) {
        throw new Error('StayQR could not activate the onboarded hotel.')
      }

      setTenantContext(nextContext)
      setCurrentStaff(nextContext.currentStaff)
      setCurrentRole(nextContext.currentRole)
      setOnboardingRequired(false)
      setNavigationRequest(null)
      setActiveSection('onboarding')
    } catch (error) {
      console.error('Onboarded hotel activation failed:', error)
      setHotelSwitchError(
        error?.message || 'StayQR could not activate the new hotel.'
      )
      throw error
    } finally {
      setSwitchingHotelId(null)
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
        setOnboardingRequired(false)
        setAuthError('')
        setAuthLoading(false)
      }
    })

    return () => subscription.unsubscribe()
  }, [initAuth, loadUserContext])

  useEffect(() => {
    const handleExternalNavigation = (event) => {
      const section = event.detail?.section
      if (!section || !canAccessSection(currentRole, section, tenantContext?.permissions || [])) return
      setNavigationRequest({
        ...event.detail,
        requestId: `${Date.now()}-${Math.random()}`,
      })
      setActiveSection(section)
      setMobileMenuOpen(false)
    }

    window.addEventListener(NAVIGATE_EVENT, handleExternalNavigation)
    return () => window.removeEventListener(NAVIGATE_EVENT, handleExternalNavigation)
  }, [currentRole, tenantContext?.permissions])

  if (window.location.pathname === '/privacy') {
    return (
      <StandaloneRouteBoundary routeKey="privacy-policy" label="privacy policy">
        <PrivacyPolicy />
      </StandaloneRouteBoundary>
    )
  }

  if (window.location.pathname.startsWith('/invoice/verify/')) {
    return (
      <StandaloneRouteBoundary routeKey="invoice-verification" label="invoice verification">
        <InvoiceVerification />
      </StandaloneRouteBoundary>
    )
  }

  if (
  window.location.pathname.startsWith('/guest/') ||
  window.location.pathname.startsWith('/g/')
) {
    return (
      <StandaloneRouteBoundary routeKey="guest-guide" label="guest guide">
        <GuestGuide />
      </StandaloneRouteBoundary>
    )
  }

  if (window.location.pathname.startsWith('/food/')) {
    return (
      <StandaloneRouteBoundary routeKey="guest-food-menu" label="food menu">
        <FoodMenu />
      </StandaloneRouteBoundary>
    )
  }

  if (authLoading) {
    return <RouteLoadingFallback fullScreen label="your secure StayQR session" />
  }

  const authPath = window.location.pathname

  if (authPath === '/auth/complete-invite') {
    return (
      <StandaloneRouteBoundary routeKey="complete-invite" label="staff invitation">
        <AuthAction mode="invite" session={session} />
      </StandaloneRouteBoundary>
    )
  }

  if (authPath === '/auth/reset-password') {
    return (
      <StandaloneRouteBoundary routeKey="reset-password" label="password recovery">
        <AuthAction mode="recovery" session={session} />
      </StandaloneRouteBoundary>
    )
  }

  if (!session) {
    return (
      <StandaloneRouteBoundary routeKey="login" label="secure login">
        <Login />
      </StandaloneRouteBoundary>
    )
  }

  if (onboardingRequired) {
    return (
      <StandaloneRouteBoundary routeKey="required-onboarding" label="hotel onboarding">
        <HotelOnboarding
          session={session}
          tenantContext={tenantContext}
          onHotelReady={handleOnboardingReady}
          standalone
        />
      </StandaloneRouteBoundary>
    )
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
      setOnboardingRequired(false)
      setNavigationRequest(null)
      setMobileMenuOpen(false)
      setActiveSection((currentSection) =>
        canAccessSection(nextContext.currentRole, currentSection, nextContext.permissions)
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
    if (!canAccessSection(currentRole, section, tenantContext?.permissions || [])) {
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
    if (!canAccessSection(currentRole, activeSection, tenantContext?.permissions || [])) {
      return <AccessDenied section={activeSection} />
    }

    switch (activeSection) {
      case 'dashboard':
        return (
          <Dashboard
            hotel={tenantContext?.selectedHotel || null}
            staff={currentStaff}
          />
        )
      case 'rooms':
        return <Rooms hotel={tenantContext?.selectedHotel || null} />
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
      case 'folios':
        return (
          <FolioSettlement
            hotel={tenantContext?.selectedHotel || null}
            permissions={tenantContext?.permissions || []}
            currentRole={currentRole}
          />
        )
      case 'foodorders':
        return <FoodOrders />
      case 'charges':
        return <Charges />
      case 'housekeeping':
        return <Housekeeping hotel={tenantContext?.selectedHotel || null} />
      case 'maintenance':
        return <Maintenance hotel={tenantContext?.selectedHotel || null} />
      case 'amenities':
        return <Amenities />
      case 'hotel':
        return <HotelProfile />
      case 'guidebuilder':
        return <GuestGuideBuilder />
      case 'reports':
        return <Reports />
      case 'operationscenter':
        return (
          <OperationsCenter
            hotel={tenantContext?.selectedHotel || null}
            currentRole={currentRole}
          />
        )
      case 'invoices':
        return (
          <Invoices
            hotel={tenantContext?.selectedHotel || null}
            permissions={tenantContext?.permissions || []}
            currentRole={currentRole}
          />
        )
      case 'menu':
        return <MenuManagement />
      case 'staff':
        return <StaffManagement />
      case 'superadmin':
        return <SuperAdmin onNavigate={handleNavigate} />
      case 'onboarding':
        return (
          <HotelOnboarding
            session={session}
            tenantContext={tenantContext}
            onHotelReady={handleOnboardingReady}
          />
        )
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
        permissions={tenantContext?.permissions || []}
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
          <AppErrorBoundary
            scope={`section:${activeSection}`}
            resetKey={`${tenantContext?.selectedHotelId || 'none'}:${activeSection}:${navigationRequest?.requestId || 'default'}`}
          >
            <Suspense
              fallback={
                <RouteLoadingFallback
                  label={SECTION_TITLES[activeSection] || activeSection}
                />
              }
            >
              {renderPage()}
            </Suspense>
          </AppErrorBoundary>
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

function StandaloneRouteBoundary({ routeKey, label, children }) {
  return (
    <AppErrorBoundary scope={`route:${routeKey}`} resetKey={routeKey} fullScreen>
      <Suspense
        fallback={<RouteLoadingFallback fullScreen label={label} />}
      >
        {children}
      </Suspense>
    </AppErrorBoundary>
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
