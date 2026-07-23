import { useEffect, useRef, useState } from 'react'
import './HotelSwitcher.css'

const BLOCKED_HOTEL_STATUSES = new Set(['suspended', 'inactive', 'archived'])

export default function HotelSwitcher({
  tenantContext,
  onHotelChange,
  switchingHotelId = null,
  error = '',
  variant = 'sidebar',
  onOpenChange,
}) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef(null)

  const hotels = tenantContext?.hotels || []
  const selectedHotel = tenantContext?.selectedHotel || null
  const canSwitch = Boolean(
    hotels.length > 1 || tenantContext?.isPlatformAdmin
  )
  const isSwitching = Boolean(switchingHotelId)

  useEffect(() => {
    const handlePointerDown = (event) => {
      if (!rootRef.current?.contains(event.target)) {
        setOpen(false)
        onOpenChange?.(false)
      }
    }

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') {
        setOpen(false)
        onOpenChange?.(false)
      }
    }

    document.addEventListener('mousedown', handlePointerDown)
    document.addEventListener('keydown', handleKeyDown)

    return () => {
      document.removeEventListener('mousedown', handlePointerDown)
      document.removeEventListener('keydown', handleKeyDown)
    }
  }, [onOpenChange])

  useEffect(() => {
    setOpen(false)
    onOpenChange?.(false)
  }, [selectedHotel?.id, onOpenChange])

  const toggleOpen = () => {
    if (!canSwitch || isSwitching) return
    setOpen((current) => {
      const next = !current
      onOpenChange?.(next)
      return next
    })
  }

  const handleSelect = async (hotel) => {
    if (!hotel?.id || hotel.id === selectedHotel?.id || isSwitching) return

    await onHotelChange?.(hotel.id)
  }

  const selectedStatus = normalizeStatus(selectedHotel?.status)

  return (
    <div
      ref={rootRef}
      className={`hotel-switcher hotel-switcher-${variant} ${open ? 'is-open' : ''}`}
    >
      <button
        type="button"
        className="hotel-switcher-trigger"
        onClick={toggleOpen}
        disabled={!selectedHotel || isSwitching}
        aria-haspopup={canSwitch ? 'listbox' : undefined}
        aria-expanded={canSwitch ? open : undefined}
        title={canSwitch ? 'Switch hotel' : selectedHotel?.hotel_name || 'Hotel'}
      >
        <span className={`hotel-switcher-status status-${selectedStatus}`} />

        <span className="hotel-switcher-copy">
          <span className="hotel-switcher-name">
            {selectedHotel?.hotel_name || 'No hotel selected'}
          </span>
          <span className="hotel-switcher-meta">
            {isSwitching
              ? 'Switching property…'
              : canSwitch
                ? `${hotels.length} properties · Click to switch`
                : selectedHotel?.location || 'Current property'}
          </span>
        </span>

        {isSwitching ? (
          <span className="hotel-switcher-spinner" aria-label="Switching hotel" />
        ) : canSwitch ? (
          <ChevronIcon open={open} />
        ) : null}
      </button>

      {open && canSwitch && (
        <div className="hotel-switcher-panel" role="listbox" aria-label="Available hotels">
          <div className="hotel-switcher-panel-header">
            <div>
              <strong>Switch property</strong>
              <span>
                {tenantContext?.isPlatformAdmin
                  ? 'Platform Admin access'
                  : 'Your hotel access'}
              </span>
            </div>
            <span className="hotel-switcher-count">{hotels.length}</span>
          </div>

          <div className="hotel-switcher-list">
            {hotels.length === 0 ? (
              <div className="hotel-switcher-empty">No authorized hotels found.</div>
            ) : (
              hotels.map((hotel) => {
                const isSelected = hotel.id === selectedHotel?.id
                const status = normalizeStatus(hotel.status)
                const isBlocked = BLOCKED_HOTEL_STATUSES.has(status)
                const isTargetSwitching = switchingHotelId === hotel.id

                return (
                  <button
                    key={hotel.id}
                    type="button"
                    role="option"
                    aria-selected={isSelected}
                    className={`hotel-switcher-option ${isSelected ? 'selected' : ''}`}
                    onClick={() => handleSelect(hotel)}
                    disabled={isSelected || isSwitching}
                  >
                    <span className={`hotel-switcher-status status-${status}`} />
                    <span className="hotel-switcher-option-copy">
                      <span className="hotel-switcher-option-name">
                        {hotel.hotel_name || 'Unnamed hotel'}
                      </span>
                      <span className="hotel-switcher-option-meta">
                        {hotel.location || 'Location not set'}
                        {hotel.subscription_status
                          ? ` · ${formatLabel(hotel.subscription_status)}`
                          : ''}
                      </span>
                    </span>
                    <span className={`hotel-switcher-option-state ${isBlocked ? 'blocked' : ''}`}>
                      {isTargetSwitching
                        ? 'Switching…'
                        : isSelected
                          ? 'Current'
                          : formatLabel(status)}
                    </span>
                  </button>
                )
              })
            )}
          </div>

          {error && <div className="hotel-switcher-error">{error}</div>}
        </div>
      )}
    </div>
  )
}

function normalizeStatus(value) {
  return String(value || 'active')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
}

function formatLabel(value) {
  return String(value || '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}

function ChevronIcon({ open }) {
  return (
    <svg
      className={`hotel-switcher-chevron ${open ? 'open' : ''}`}
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <polyline points="6 9 12 15 18 9" />
    </svg>
  )
}
