import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import "./CheckIn.css";

const HOTEL_ID = "77d850d0-016d-4155-bc44-a6207d30e7b9";

export default function CheckIn() {
  const [guestName, setGuestName] = useState("");
  const [phone, setPhone] = useState("");
  const [roomNumber, setRoomNumber] = useState("");
  const [checkoutTime, setCheckoutTime] = useState("");
  const [roomCharge, setRoomCharge] = useState("");
  const [rooms, setRooms] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    fetchAvailableRooms();
    setDefaultCheckoutTime();
  }, []);

  const setDefaultCheckoutTime = () => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(11, 0, 0, 0);

    const formatted = tomorrow.toISOString().slice(0, 16);
    setCheckoutTime(formatted);
  };

  const fetchAvailableRooms = async () => {
    const { data, error } = await supabase
      .from("rooms")
      .select("*")
      .eq("status", "available")
      .order("room_number");

    if (error) {
      console.error("Rooms fetch error:", error);
      return;
    }

    setRooms(data || []);
  };

  const handleCheckIn = async () => {
    try {
      if (!guestName || !phone || !roomNumber || !checkoutTime || !roomCharge) {
        alert("Please fill all fields including room charge");
        return;
      }

      setLoading(true);

      const selectedRoom = rooms.find(
        (room) => room.room_number === roomNumber
      );

      if (!selectedRoom) {
        alert("Selected room not found");
        setLoading(false);
        return;
      }

      const { data: guestData, error: guestError } = await supabase
        .from("guests")
        .insert([
          {
            hotel_id: HOTEL_ID,
            full_name: guestName,
            phone,
            room_number: roomNumber,
          },
        ])
        .select()
        .single();

      if (guestError) throw guestError;

      const { error: sessionError } = await supabase
        .from("guest_sessions")
        .insert([
          {
            hotel_id: HOTEL_ID,
            room_id: selectedRoom.id,
            guest_id: guestData.id,
            checkin_time: new Date().toISOString(),
            checkout_time: new Date(checkoutTime).toISOString(),
            status: "active",
          },
        ]);

      if (sessionError) throw sessionError;

      const { error: paymentError } = await supabase
        .from("payments")
        .insert([
          {
            hotel_id: HOTEL_ID,
            room_id: selectedRoom.id,
            guest_id: guestData.id,
            amount: Number(roomCharge),
            payment_type: "room_charge",
            payment_status: "pending",
            notes: `Room ${roomNumber} charge for ${guestName}`,
          },
        ]);

      if (paymentError) throw paymentError;

      const { error: roomError } = await supabase
        .from("rooms")
        .update({
          status: "occupied",
        })
        .eq("id", selectedRoom.id);

      if (roomError) throw roomError;

      alert("Guest checked in, QR activated, and room payment created.");

      setGuestName("");
      setPhone("");
      setRoomNumber("");
      setRoomCharge("");
      setDefaultCheckoutTime();

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

        <p>Register guest, assign room, activate QR session and create payment.</p>

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
          <option value="">Select Available Room</option>

          {rooms.map((room) => (
            <option key={room.id} value={room.room_number}>
              Room {room.room_number}
            </option>
          ))}
        </select>

        <input
          type="datetime-local"
          value={checkoutTime}
          onChange={(e) => setCheckoutTime(e.target.value)}
        />

        <input
          type="number"
          placeholder="Room Charge Amount"
          value={roomCharge}
          onChange={(e) => setRoomCharge(e.target.value)}
        />

        <button onClick={handleCheckIn} disabled={loading}>
          {loading ? "Checking In..." : "Check In & Create Payment"}
        </button>
      </div>
    </div>
  );
}