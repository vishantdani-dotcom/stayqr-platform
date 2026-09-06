import { navigateToSection } from '../../lib/bookingCalendar'
import './RoomsTable.css'

export default function RoomsTable({
  rooms = [],
  loading = false,
  error = null,
  onView,
}) {
  if (loading) return <p className="rooms-table-state">Loading rooms…</p>
  if (error) return <p className="rooms-table-state rooms-table-state--error">{error}</p>

  const openRoomWorkspace = (room) => {
    if (typeof onView === 'function') {
      onView(room)
      return
    }

    navigateToSection('rooms', {
      roomId: room?.id || null,
      roomNumber: room?.room_number || null,
      source: 'dashboard-room-status',
    })
  }

  return (
    <div className="rooms-table">
      <div className="rooms-table-head">
        <div>
          <span className="rooms-table-eyebrow">ROOM STATUS</span>
          <h2>Rooms</h2>
        </div>
        <span className="rooms-table-count">{rooms.length} {rooms.length === 1 ? 'room' : 'rooms'}</span>
      </div>

      <div className="rooms-table-scroll">
        <table>
          <thead>
            <tr>
              <th>Room</th>
              <th>Type</th>
              <th>Status</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            {rooms.map((room) => (
              <tr key={room.id}>
                <td><strong>{room.room_number}</strong></td>
                <td>{room.room_type_name || room.room_type || '—'}</td>
                <td>
                  <span className={`room-status room-status-${room.status}`}>
                    {String(room.status || 'unknown').replaceAll('_', ' ')}
                  </span>
                </td>
                <td>
                  <button
                    className="rooms-table-view-btn"
                    type="button"
                    onClick={() => openRoomWorkspace(room)}
                    aria-label={`Open Room ${room.room_number || ''} in Rooms`}
                  >
                    View in Rooms
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                      <path d="M5 12h14M13 6l6 6-6 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  </button>
                </td>
              </tr>
            ))}
            {!rooms.length && (
              <tr>
                <td colSpan="4" className="rooms-table-empty">No rooms found for this property.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
