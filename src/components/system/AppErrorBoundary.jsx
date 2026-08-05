import { Component } from 'react'
import './SystemStates.css'

function getSafeRoute() {
  const pathname = window.location.pathname

  if (pathname.startsWith('/guest/')) return '/guest/:token'
  if (pathname.startsWith('/food/')) return '/food/:token'
  if (pathname.startsWith('/invoice/verify/')) return '/invoice/verify/:token'
  if (pathname.startsWith('/auth/')) return pathname

  return '/app'
}

function createSafeIncident(scope) {
  const normalizedScope = String(scope || 'application')
    .replace(/[^a-z0-9:_-]/gi, '-')
    .slice(0, 48)

  return `${normalizedScope}-${Date.now().toString(36)}`
}

export default class AppErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = {
      hasError: false,
      incidentId: '',
    }
  }

  static getDerivedStateFromError() {
    return { hasError: true }
  }

  componentDidCatch(error, errorInfo) {
    const incidentId = createSafeIncident(this.props.scope)
    const safeDiagnostic = {
      component: 'AppErrorBoundary',
      errorName: error?.name || 'Error',
      incidentId,
      route: getSafeRoute(),
      scope: this.props.scope || 'application',
      stackFrames: errorInfo?.componentStack
        ? errorInfo.componentStack.trim().split('\n').length
        : 0,
      timestamp: new Date().toISOString(),
    }

    this.setState({ incidentId })

    console.error('[StayQR boundary]', safeDiagnostic)
    window.dispatchEvent(
      new CustomEvent('stayqr:client-error', { detail: safeDiagnostic })
    )
  }

  componentDidUpdate(previousProps) {
    if (
      this.state.hasError &&
      previousProps.resetKey !== this.props.resetKey
    ) {
      this.setState({
        hasError: false,
        incidentId: '',
      })
    }
  }

  handleRetry = () => {
    this.setState({
      hasError: false,
      incidentId: '',
    })
  }

  handleReload = () => {
    window.location.reload()
  }

  render() {
    if (!this.state.hasError) {
      return this.props.children
    }

    const containerClass = this.props.fullScreen
      ? 'system-state system-state--fullscreen'
      : 'system-state'

    return (
      <section className={containerClass} role="alert" aria-live="assertive">
        <div className="system-state__card system-state__card--error">
          <div className="system-state__mark" aria-hidden="true">
            !
          </div>
          <p className="system-state__eyebrow">StayQR protected your session</p>
          <h1 className="system-state__title">This screen could not load safely</h1>
          <p className="system-state__message">
            Your hotel data was not changed. Try the screen again, or reload StayQR
            to download the latest application files.
          </p>

          <div className="system-state__actions">
            <button
              className="system-state__button system-state__button--primary"
              type="button"
              onClick={this.handleRetry}
            >
              Try again
            </button>
            <button
              className="system-state__button"
              type="button"
              onClick={this.handleReload}
            >
              Reload StayQR
            </button>
          </div>

          {this.state.incidentId && (
            <p className="system-state__incident">
              Support reference: <code>{this.state.incidentId}</code>
            </p>
          )}
        </div>
      </section>
    )
  }
}
