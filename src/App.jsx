// src/App.jsx
import { useState } from 'react'
import Sidebar from './components/sidebar/Sidebar'
import Navbar from './components/navbar/Navbar'
import Dashboard from './pages/dashboard/Dashboard'
import './styles/globals.css'
import './App.css'

export default function App() {
  const [activeSection, setActiveSection] = useState('dashboard')
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  const handleNavigate = (section) => {
    setActiveSection(section)
    setMobileMenuOpen(false)
  }

  const handleMobileMenuToggle = () => {
    setMobileMenuOpen(prev => !prev)
    // On mobile, expand the sidebar when opening
    if (!mobileMenuOpen) setSidebarCollapsed(false)
  }

  // Render page content based on active section
  // Extend this switch as you build more pages
  const renderPage = () => {
    switch (activeSection) {
      case 'dashboard':
        return <Dashboard />
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
        onToggle={() => setSidebarCollapsed(prev => !prev)}
        mobileOpen={mobileMenuOpen}
      />

      {/* Mobile overlay */}
      {mobileMenuOpen && (
        <div
          className="mobile-overlay"
          onClick={() => setMobileMenuOpen(false)}
        />
      )}

      <div
        className="app-main"
        style={{ marginLeft: sidebarCollapsed ? 64 : 'var(--sidebar-w)' }}
      >
        <Navbar
          sidebarCollapsed={sidebarCollapsed}
          onMobileMenuToggle={handleMobileMenuToggle}
          activeSection={activeSection}
        />
        <main className="app-content">
          {renderPage()}
        </main>
      </div>
    </div>
  )
}

function ComingSoonPage({ section }) {
  const labels = {
    rooms:     'Rooms',
    guests:    'Guests',
    checkin:   'Check-In / Out',
    qr:        'QR Guides',
    payments:  'Payments',
    services:  'Service Requests',
    amenities: 'Amenities',
    hotel:     'Hotel Profile',
    settings:  'Settings',
  }

  return (
    <div className="coming-soon-page">
      <div className="cs-content">
        <div className="cs-icon">🏗️</div>
        <h2 className="cs-title gold-text">{labels[section] || section}</h2>
        <p className="cs-sub">This section is coming in Phase 2.</p>
        <p className="cs-desc">
          The foundation is ready. Expand <code>src/App.jsx</code> to add more pages.
        </p>
      </div>
    </div>
  )
}
