// src/App.jsx

import { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'
import {
  getCurrentStaff,
  normalizeRole,
  canAccessSection,
} from './lib/currentStaff'

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
  const [activeSection, setActiveSection] = useState('dashboard')
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  useEffect(() => {
    initAuth()

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession)

      if (newSession) {
        loadStaff()
      } else {
        setCurrentStaff(null)
        setCurrentRole('')
        setAuthLoading(false)
      }
    })

    return () => subscription.unsubscribe()
  }, [])

  async function initAuth() {
    setAuthLoading(true)

    const { data } = await supabase.auth.getSession()
    setSession(data.session)

    if (data.session) {
      await loadStaff()
    } else {
      setAuthLoading(false)
    }
  }

  async function loadStaff() {
    const staff = await getCurrentStaff()

    if (!staff) {
      await supabase.auth.signOut()
      setCurrentStaff(null)
      setCurrentRole('')
      setAuthLoading(false)
      return
    }

    const role = normalizeRole(staff.role)

    setCurrentStaff(staff)
    setCurrentRole(role)

    if (!canAccessSection(role, activeSection)) {
      setActiveSection('dashboard')
    }

    setAuthLoading(false)
  }

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

function AccessDenied({ section }) {
  return (
    <div className="coming-soon-page">
      <div className="cs-content">
        <div className="cs-icon">🔒</div>

        <h2 className="cs-title gold-text">Access Restricted</h2>

        <p className="cs-sub">
          You do not have permission to access {section}.
        </p>

        <p className="cs-desc">StayQR Role-Based Access</p>
      </div>
    </div>
  )
}

function ComingSoonPage({ section }) {
  const labels = {
    qr: 'QR Guides',
    payments: 'Payments',
    amenities: 'Amenities',
    hotel: 'Hotel Profile',
    reports: 'Reports',
    invoices: 'Invoices',
    charges: 'Charges',
    housekeeping: 'Housekeeping',
    settings: 'Settings',
  }

  return (
    <div className="coming-soon-page">
      <div className="cs-content">
        <div className="cs-icon">🏗️</div>

        <h2 className="cs-title gold-text">{labels[section] || section}</h2>

        <p className="cs-sub">This section is coming in Phase 2.</p>

        <p className="cs-desc">StayQR SaaS Platform</p>
      </div>
    </div>
  )
}