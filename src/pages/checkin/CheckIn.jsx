import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import "./CheckIn.css";

const HOTEL_ID = "77d850d0-016d-4155-bc44-a6207d30e7b9";

export default function CheckIn() {
  const [guestName, setGuestName] = useState("");
  const [phone, setPhone] = useState("");
  const [roomNumber, setRoomNumber] = useState("");
  const [rooms, setRooms] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    fetchAvailableRooms();
  }, []);

  const fetchAvailableRooms = async () => {
    const { data } = await supabase
      .from("rooms")
      .select("*")
      .eq("status", "available")
      .order("room_number");

    setRooms(data || []);
  };

  const handleCheckIn = async () => {
    try {
      if (!guestName || !phone || !roomNumber) {
        alert("Please fill all fields");
        return;
      }

      setLoading(true);

      const { error: guestError } = await supabase
        .from("guests")
        .insert([
          {
            hotel_id: HOTEL_ID,
            full_name: guestName,
            phone,
            room_number: roomNumber,
          },
        ]);

      if (guestError) throw guestError;

      const { error: roomError } = await supabase
        .from("rooms")
        .update({
          status: "occupied",
        })
        .eq("room_number", roomNumber);

      if (roomError) throw roomError;

      alert("Guest Checked In Successfully");

      setGuestName("");
      setPhone("");
      setRoomNumber("");

      fetchAvailableRooms();
    } catch (err) {
      console.error(err);
      alert(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="checkin-page">
      <div className="checkin-card">
        <h1>Guest Check-In</h1>

        <p>
          Register a new guest and assign an available room.
        </p>

        <input
          type="text"
          placeholder="Guest Full Name"
          value={guestName}
          onChange={(e) => setGuestName(e.target.value)}
        />

        <input
          type="text"
          placeholder="Phone Number"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
        />

        <select
          value={roomNumber}
          onChange={(e) => setRoomNumber(e.target.value)}
        >
          <option value="">
            Select Available Room
          </option>

          {rooms.map((room) => (
            <option
              key={room.id}
              value={room.room_number}
            >
              Room {room.room_number}
            </option>
          ))}
        </select>

        <button
          onClick={handleCheckIn}
          disabled={loading}
        >
          {loading
            ? "Checking In..."
            : "Check In Guest"}
        </button>
      </div>
    </div>
  );
}