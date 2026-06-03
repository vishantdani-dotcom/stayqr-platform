import { supabase } from "../../lib/supabase";
import "./RoomsTable.css";

export default function RoomsTable({
  rooms = [],
  loading = false,
  error = null,
  onRefresh,
}) {
  const handleDeleteRoom = async (room) => {
    const confirmDelete = window.confirm(
      `Delete Room ${room.room_number}?`
    );

    if (!confirmDelete) return;

    const { error } = await supabase
      .from("rooms")
      .delete()
      .eq("id", room.id);

    if (error) {
      alert(error.message);
      return;
    }

    alert("Room deleted successfully");

    onRefresh?.();
  };

  const handleStatusChange = async (room, status) => {
    const { error } = await supabase
      .from("rooms")
      .update({ status })
      .eq("id", room.id);

    if (error) {
      alert(error.message);
      return;
    }

    onRefresh?.();
  };

  if (loading) {
    return <p>Loading rooms...</p>;
  }

  if (error) {
    return <p>{error}</p>;
  }

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

              <td>{room.room_type}</td>

              <td>
                <span
                  className={`room-status room-status-${room.status}`}
                >
                  {room.status}
                </span>
              </td>

              <td>
                <select
                  value={room.status}
                  onChange={(e) =>
                    handleStatusChange(
                      room,
                      e.target.value
                    )
                  }
                >
                  <option value="available">
                    Available
                  </option>

                  <option value="occupied">
                    Occupied
                  </option>

                  <option value="maintenance">
                    Maintenance
                  </option>
                </select>

                <button
                  className="delete-room-btn"
                  onClick={() =>
                    handleDeleteRoom(room)
                  }
                >
                  Delete
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}