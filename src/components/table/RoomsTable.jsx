import './RoomsTable.css'

export default function RoomsTable({
  rooms = [],
  loading = false,
  error = null,
  onEdit,
  onArchive,
  onStatusChange,
}) {
  if (loading) return <p>Loading rooms…</p>
  if (error) return <p>{error}</p>

  return (
    <div className="rooms-table">
      <h2>Rooms</h2>
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
              <td>{room.room_number}</td>
              <td>{room.room_type_name || room.room_type || '—'}</td>
              <td>
                <span className={`room-status room-status-${room.status}`}>
                  {room.status}
                </span>
              </td>
              <td>
                <button type="button" onClick={() => onEdit?.(room)}>
                  Edit
                </button>
                <button type="button" onClick={() => onStatusChange?.(room)}>
                  Status
                </button>
                <button type="button" onClick={() => onArchive?.(room)}>
                  Archive
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
