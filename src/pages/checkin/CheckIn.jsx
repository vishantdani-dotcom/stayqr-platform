import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import "./CheckIn.css";

export default function CheckIn() {
  const [currentHotel, setCurrentHotel] = useState(null);
  const [guestName, setGuestName] = useState("");
  const [phone, setPhone] = useState("");
  const [roomNumber, setRoomNumber] = useState("");
  const [checkoutTime, setCheckoutTime] = useState("");
  const [roomCharge, setRoomCharge] = useState("");
  const [rooms, setRooms] = useState([]);
  const [loading, setLoading] = useState(false);
  const [pageLoading, setPageLoading] = useState(true);
  const [error, setError] = useState("");

  const setDefaultCheckoutTime = () => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(11, 0, 0, 0);

    const formatted = tomorrow.toISOString().slice(0, 16);
    setCheckoutTime(formatted);
  };

  const fetchAvailableRooms = async (hotelId) => {
    if (!hotelId) return;

    const { data, error: roomsError } = await supabase
      .from("rooms")
      .select("*")
      .eq("hotel_id", hotelId)
      .eq("status", "available")
      .order("room_number");

    if (roomsError) throw roomsError;

    setRooms(data || []);
  };

  useEffect(() => {
    let cancelled = false;

    async function initPage() {
      setPageLoading(true);
      setError("");
      setDefaultCheckoutTime();

      try {
        const hotel = await getCurrentHotel();

        if (!hotel) {
          throw new Error("No active hotel is assigned to this account.");
        }

        if (cancelled) return;

        setCurrentHotel(hotel);
        await fetchAvailableRooms(hotel.id);
      } catch (initError) {
        console.error("Check-in initialization error:", initError);
        if (!cancelled) {
          setError(initError.message || "Unable to load check-in.");
        }
      } finally {
        if (!cancelled) setPageLoading(false);
      }
    }

    initPage();

    return () => {
      cancelled = true;
    };
  }, []);

  const handleCheckIn = async () => {
    try {
      if (!currentHotel?.id) {
        alert("No active hotel is assigned to this account.");
        return;
      }

      if (!guestName || !phone || !roomNumber || !checkoutTime || !roomCharge) {
        alert("Please fill all fields including room charge");
        return;
      }

      const numericRoomCharge = Number(roomCharge);

      if (!Number.isFinite(numericRoomCharge) || numericRoomCharge < 0) {
        alert("Enter a valid non-negative room charge.");
        return;
      }

      setLoading(true);

      const selectedRoom = rooms.find(
        (room) => String(room.room_number) === String(roomNumber)
      );

      if (!selectedRoom) {
        throw new Error("Selected room is no longer available. Refresh and try again.");
      }

      const { data: guestData, error: guestError } = await supabase
        .from("guests")
        .insert([
          {
            hotel_id: currentHotel.id,
            full_name: guestName.trim(),
            phone: phone.trim(),
            room_number: selectedRoom.room_number,
          },
        ])
        .select()
        .single();

      if (guestError) throw guestError;

      const { error: sessionError } = await supabase
        .from("guest_sessions")
        .insert([
          {
            hotel_id: currentHotel.id,
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
            hotel_id: currentHotel.id,
            room_id: selectedRoom.id,
            guest_id: guestData.id,
            amount: numericRoomCharge,
            payment_type: "room_charge",
            payment_status: "pending",
            notes: `Room ${selectedRoom.room_number} charge for ${guestName.trim()}`,
          },
        ]);

      if (paymentError) throw paymentError;

      const { data: updatedRoom, error: roomError } = await supabase
        .from("rooms")
        .update({ status: "occupied" })
        .eq("id", selectedRoom.id)
        .eq("hotel_id", currentHotel.id)
        .eq("status", "available")
        .select("id")
        .maybeSingle();

      if (roomError) throw roomError;

      if (!updatedRoom) {
        throw new Error("The room was taken by another operation. Please review the guest record before retrying.");
      }

      alert("Guest checked in, QR activated, and room payment created.");

      setGuestName("");
      setPhone("");
      setRoomNumber("");
      setRoomCharge("");
      setDefaultCheckoutTime();

      await fetchAvailableRooms(currentHotel.id);
    } catch (checkInError) {
      console.error("Check-in error:", checkInError);
      alert(checkInError.message || "Unable to complete check-in.");
    } finally {
      setLoading(false);
    }
  };

  if (pageLoading) {
    return (
      <div className="checkin-page">
        <div className="checkin-card">
          <h1>Guest Check-In</h1>
          <p>Loading hotel and available rooms...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="checkin-page">
        <div className="checkin-card">
          <h1>Guest Check-In</h1>
          <p>{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="checkin-page">
      <div className="checkin-card">
        <h1>Guest Check-In</h1>

        <p>
          {currentHotel?.hotel_name
            ? `${currentHotel.hotel_name} — register guest, assign room, activate QR session and create payment.`
            : "Register guest, assign room, activate QR session and create payment."}
        </p>

        <input
          type="text"
          placeholder="Guest Full Name"
          value={guestName}
          onChange={(e) => setGuestName(e.target.value)}
        />

        <input
          type="tel"
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
          min="0"
          step="0.01"
          placeholder="Room Charge Amount"
          value={roomCharge}
          onChange={(e) => setRoomCharge(e.target.value)}
        />

        <button onClick={handleCheckIn} disabled={loading || rooms.length === 0}>
          {loading ? "Checking In..." : "Check In & Create Payment"}
        </button>

        {!rooms.length && (
          <p>No available rooms were found for this hotel.</p>
        )}
      </div>
    </div>
  );
}
