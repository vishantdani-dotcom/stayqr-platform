// src/App.jsx

import { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'

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
import MenuManagement from "./pages/menumanagement/MenuManagement";
import StaffManagement from "./pages/staff/StaffManagement";

import './styles/globals.css'
import './App.css'

export default function App() {
  const [session, setSession] = useState(null)
  const [authLoading, setAuthLoading] = useState(true)
  const [activeSection, setActiveSection] = useState('dashboard')
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setAuthLoading(false)
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session)
    })

    return () => subscription.unsubscribe()
  }, [])

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

        case "menu":
    return <MenuManagement />;

    case "staff":
  return <StaffManagement />;

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
        />

        <main className="app-content">{renderPage()}</main>
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

        <h2 className="cs-title gold-text">
          {labels[section] || section}
        </h2>

        <p className="cs-sub">This section is coming in Phase 2.</p>

        <p className="cs-desc">StayQR SaaS Platform</p>
      </div>
    </div>
  )
}