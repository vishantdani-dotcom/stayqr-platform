import './RoomsTable.css'

export default function RoomsTable({
  rooms = [],
  loading = false,
  error = null,
  onEdit,
  onArchive,
  onStatusChange,
}) {
  if (loading) return <div className="rooms-table rooms-table-state">Loading rooms…</div>
  if (error) return <div className="rooms-table rooms-table-state error">{error}</div>

  return (
    <section className="rooms-table" aria-label="Rooms overview">
      <div className="rooms-table-heading">
        <div>
          <span className="rooms-table-kicker">ROOM STATUS</span>
          <h2>Rooms</h2>
        </div>
        <span className="rooms-table-count">{rooms.length} room{rooms.length === 1 ? '' : 's'}</span>
      </div>

      {rooms.length === 0 ? (
        <div className="rooms-table-empty">No rooms are available in this property.</div>
      ) : (
        <>
          <div className="rooms-desktop-table">
            <table>
              <thead>
                <tr>
                  <th>Room</th>
                  <th>Type</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {rooms.map((room) => (
                  <tr key={room.id}>
                    <td><strong>{room.room_number}</strong></td>
                    <td>{room.room_type_name || room.room_type || '—'}</td>
                    <td>
                      <span className={`room-status room-status-${room.status}`}>
                        {formatStatus(room.status)}
                      </span>
                    </td>
                    <td>
                      <div className="rooms-row-actions">
                        {onEdit && <button type="button" onClick={() => onEdit(room)}>Edit</button>}
                        {onStatusChange && <button type="button" onClick={() => onStatusChange(room)}>Change status</button>}
                        {onArchive && <button type="button" className="danger" onClick={() => onArchive(room)}>Archive</button>}
                        {!onEdit && !onStatusChange && !onArchive && <span className="rooms-readonly-label">View in Rooms</span>}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="rooms-mobile-list">
            {rooms.map((room) => (
              <article className="room-mobile-card" key={room.id}>
                <div className="room-mobile-card-main">
                  <div className="room-mobile-number">
                    <span>ROOM</span>
                    <strong>{room.room_number}</strong>
                  </div>
                  <div className="room-mobile-copy">
                    <h3>{room.room_type_name || room.room_type || 'Room'}</h3>
                    <span className={`room-status room-status-${room.status}`}>{formatStatus(room.status)}</span>
                  </div>
                </div>
                {(onEdit || onStatusChange || onArchive) && (
                  <div className="room-mobile-actions">
                    {onEdit && <button type="button" onClick={() => onEdit(room)}>Edit</button>}
                    {onStatusChange && <button type="button" onClick={() => onStatusChange(room)}>Status</button>}
                    {onArchive && <button type="button" className="danger" onClick={() => onArchive(room)}>Archive</button>}
                  </div>
                )}
              </article>
            ))}
          </div>
        </>
      )}
    </section>
  )
}

function formatStatus(status) {
  return String(status || 'unknown')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}
