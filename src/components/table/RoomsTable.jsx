// src/components/table/RoomsTable.jsx
import './RoomsTable.css'

const STATUS_CONFIG = {
  available:   { label: 'Available',   color: 'green',  icon: '●' },
  occupied:    { label: 'Occupied',    color: 'blue',   icon: '●' },
  maintenance: { label: 'Maintenance', color: 'orange', icon: '●' },
  checkout:    { label: 'Check-out',   color: 'red',    icon: '●' },
  cleaning:    { label: 'Cleaning',    color: 'purple', icon: '●' },
}

const TYPE_LABELS = {
  standard:  'Standard',
  deluxe:    'Deluxe',
  suite:     'Suite',
  executive: 'Executive',
}

export default function RoomsTable({ rooms, loading, error, onRefresh }) {
  if (error) {
    return (
      <div className="rooms-table-wrap glass-card gold-border">
        <TableHeader onRefresh={onRefresh} />
        <div className="table-error-state">
          <div className="error-icon">⚠️</div>
          <p className="error-title">Failed to load rooms</p>
          <p className="error-msg">{error}</p>
          <button className="btn-retry" onClick={onRefresh}>Retry</button>
        </div>
      </div>
    )
  }

  return (
    <div className="rooms-table-wrap glass-card gold-border">
      <TableHeader count={rooms?.length} onRefresh={onRefresh} loading={loading} />

      <div className="table-scroll">
        <table className="rooms-table">
          <thead>
            <tr>
              <th>Room</th>
              <th>Type</th>
              <th>Status</th>
              <th>Guest</th>
              <th>Check-In</th>
              <th>Check-Out</th>
              <th>QR Active</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              Array.from({ length: 6 }).map((_, i) => (
                <tr key={i} className="skeleton-row">
                  {Array.from({ length: 8 }).map((_, j) => (
                    <td key={j}>
                      <div className="skeleton" style={{ height: 16, width: j === 0 ? 40 : j === 7 ? 80 : '100%', borderRadius: 4 }} />
                    </td>
                  ))}
                </tr>
              ))
            ) : rooms?.length === 0 ? (
              <tr>
                <td colSpan={8}>
                  <div className="table-empty-state">
                    <div className="empty-icon">🚪</div>
                    <p className="empty-title">No rooms found</p>
                    <p className="empty-sub">Add rooms to get started</p>
                  </div>
                </td>
              </tr>
            ) : (
              rooms?.map((room, i) => {
                const status = STATUS_CONFIG[room.status] || STATUS_CONFIG.available
                const TypeIcon = room.type === 'suite' || room.type === 'executive' ? '★' : '◆'
                return (
                  <tr key={room.id || i} className="table-row" style={{ animationDelay: `${i * 0.04}s` }}>
                    <td>
                      <div className="room-number-cell">
                        <span className="room-number">{room.room_number || room.number || `10${i + 1}`}</span>
                      </div>
                    </td>
                    <td>
                      <span className="room-type-badge">
                        <span className="type-icon">{TypeIcon}</span>
                        {TYPE_LABELS[room.type] || room.type || 'Standard'}
                      </span>
                    </td>
                    <td>
                      <span className={`status-badge status--${status.color}`}>
                        <span className="status-dot">{status.icon}</span>
                        {status.label}
                      </span>
                    </td>
                    <td>
                      <span className="guest-cell">
                        {room.guest_name || room.current_guest || (
                          <span className="no-guest">—</span>
                        )}
                      </span>
                    </td>
                    <td>
                      <span className="date-cell">
                        {room.check_in ? formatDate(room.check_in) : <span className="no-guest">—</span>}
                      </span>
                    </td>
                    <td>
                      <span className="date-cell">
                        {room.check_out ? formatDate(room.check_out) : <span className="no-guest">—</span>}
                      </span>
                    </td>
                    <td>
                      <span className={`qr-badge ${room.qr_active ? 'qr-on' : 'qr-off'}`}>
                        {room.qr_active ? '◉ Active' : '○ Off'}
                      </span>
                    </td>
                    <td>
                      <div className="action-btns">
                        <button className="action-btn" title="View Room">
                          <EyeIcon />
                        </button>
                        <button className="action-btn" title="Edit Room">
                          <EditIcon />
                        </button>
                        <button className="action-btn action-btn--gold" title="Generate QR">
                          <QrIcon />
                        </button>
                      </div>
                    </td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </div>

      {!loading && rooms?.length > 0 && (
        <div className="table-footer">
          <span className="table-footer-text">
            Showing {rooms.length} room{rooms.length !== 1 ? 's' : ''}
          </span>
          <button className="table-footer-btn">View All Rooms →</button>
        </div>
      )}
    </div>
  )
}

function TableHeader({ count, onRefresh, loading }) {
  return (
    <div className="table-header">
      <div className="table-header-left">
        <div className="table-title-icon">
          <DoorIcon />
        </div>
        <div>
          <h3 className="table-title">Room Management</h3>
          <p className="table-sub">All rooms · Live data from Supabase</p>
        </div>
      </div>
      <div className="table-header-right">
        {count !== undefined && (
          <span className="table-count-badge">{count} rooms</span>
        )}
        <button
          className={`table-refresh-btn ${loading ? 'spinning' : ''}`}
          onClick={onRefresh}
          title="Refresh"
          disabled={loading}
        >
          <RefreshIcon />
        </button>
      </div>
    </div>
  )
}

function formatDate(dateStr) {
  if (!dateStr) return '—'
  try {
    return new Date(dateStr).toLocaleDateString('en-IN', { month: 'short', day: 'numeric' })
  } catch {
    return dateStr
  }
}

/* ─── Icons ─── */
function EyeIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>
    </svg>
  )
}
function EditIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
      <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
    </svg>
  )
}
function QrIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="3" y="3" width="5" height="5"/><rect x="16" y="3" width="5" height="5"/><rect x="3" y="16" width="5" height="5"/>
      <path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/>
    </svg>
  )
}
function DoorIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M3 21h18M9 21V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v16"/><circle cx="15" cy="13" r="1" fill="currentColor"/>
    </svg>
  )
}
function RefreshIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/>
      <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
    </svg>
  )
}
