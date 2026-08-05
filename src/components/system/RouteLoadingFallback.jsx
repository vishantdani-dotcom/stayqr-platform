import './SystemStates.css'

export default function RouteLoadingFallback({ fullScreen = false, label = 'this section' }) {
  const containerClass = fullScreen
    ? 'system-state system-state--fullscreen'
    : 'system-state system-state--loading'

  return (
    <section className={containerClass} role="status" aria-live="polite" aria-busy="true">
      <div className="system-state__card system-state__card--loading">
        <span className="system-state__spinner" aria-hidden="true" />
        <div>
          <p className="system-state__eyebrow">StayQR</p>
          <p className="system-state__loading-copy">Loading {label}…</p>
        </div>
      </div>
    </section>
  )
}
