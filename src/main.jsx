import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './styles/globals.css'
import App from './App.jsx'
import AppErrorBoundary from './components/system/AppErrorBoundary.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AppErrorBoundary scope="application-shell" resetKey="application-shell" fullScreen>
      <App />
    </AppErrorBoundary>
  </StrictMode>,
)
