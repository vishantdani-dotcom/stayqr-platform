import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './styles/globals.css'
import './styles/responsive.css'
import './styles/finalPolish.css'
import './styles/finalModern.css'
import './styles/finalRev18.css'
import './styles/finalRev19.css'
import './styles/finalRev20.css'
import './styles/finalRev21.css'
import './styles/finalRev22.css'
import './styles/finalRev24.css'
import './styles/finalRev26.css'
import './styles/finalRev27.css'
import './styles/finalRev28.css'
import './styles/finalRev29.css'
import './finalRev29Runtime.js'
import App from './App.jsx'
import AppErrorBoundary from './components/system/AppErrorBoundary.jsx'
import { installOperationalMonitoring } from './lib/day18Monitoring.js'

installOperationalMonitoring()

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AppErrorBoundary scope="application-shell" resetKey="application-shell" fullScreen>
      <App />
    </AppErrorBoundary>
  </StrictMode>,
)
