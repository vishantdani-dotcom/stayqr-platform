// src/App.jsx

import { useCallback, useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import {
  clearTenantContextCache,
  loadTenantContext,
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

import './styles/globals.css'
import './App.css'

export default function App() {
  const [session, setSession] = useState(null)
  const [currentStaff, setCurrentStaff] = useState(null)
  const [currentRole, setCurrentRole] = useState('')
  const [authLoading, setAuthLoading] = useState(true)
  const [authError, setAuthError] = useState('')
  const [activeSection, setActiveSection] = useState('dashboard')
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  const loadUserContext = useCallback(async () => {
    setAuthError('')

    try {
      const context = await loadTenantContext({ force: true })

      if (!context) {
        setCurrentStaff(null)
        setCurrentRole('')
        setAuthError('Your StayQR session could not be resolved.')
        return
      }

      if (!context.selectedHotel && !context.isPlatformAdmin) {
        setCurrentStaff(null)
        setCurrentRole('')
        setAuthError(
          'Your login is not assigned to an active hotel. Ask the hotel owner or StayQR support to assign access.'
        )
        return
      }

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
        setCurrentStaff(null)
        setCurrentRole('')
        setAuthError('')
        setAuthLoading(false)
      }
    })

    return () => subscription.unsubscribe()
  }, [initAuth, loadUserContext])

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

  const handleNavigate = (section) => {
    if (!canAccessSection(currentRole, section)) {
      alert('You do not have access to this section.')
      return
    }

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
        return <Dashboard />
      case 'rooms':
        return <Rooms />
      case 'checkin':
        return <CheckIn />
      case 'guests':
        return <Guests />
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
        />

        <main className="app-content">{renderPage()}</main>
      </div>
    </div>
  )
}

function TenantAccessError({ message }) {
  const handleLogout = async () => {
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
