import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";

export default function QRGenerator() {
  const [rooms, setRooms] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);

  useEffect(() => {
    initPage();
  }, []);

  async function initPage() {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    fetchRooms(hotel.id);
  }

  async function fetchRooms(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    setLoading(true);

    const { data, error } = await supabase
      .from("rooms")
      .select("*")
      .eq("hotel_id", hotelId)
      .order("room_number");

    if (error) {
      alert(error.message);
      setLoading(false);
      return;
    }

    setRooms(data || []);
    setLoading(false);
  }

  const getGuestUrl = (roomNumber) => {
    return `${window.location.origin}/guest/${roomNumber}`;
  };

  const getQRUrl = (roomNumber) => {
    return `https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${encodeURIComponent(
      getGuestUrl(roomNumber)
    )}`;
  };

  if (loading) {
    return (
      <div style={{ padding: "30px", color: "#fff" }}>
        Loading QR Codes...
      </div>
    );
  }

  return (
    <div style={page}>
      <h1 style={title}>Room QR Generator</h1>

      <p style={hotelName}>
        {currentHotel?.hotel_name || "Hotel"}
      </p>

      <div style={grid}>
        {rooms.map((room) => (
          <div key={room.id} style={card}>
            <h3>Room {room.room_number}</h3>

            <img
              src={getQRUrl(room.room_number)}
              alt={`Room ${room.room_number}`}
              style={qr}
            />

            <p style={url}>
              {getGuestUrl(room.room_number)}
            </p>

            <a
              href={getQRUrl(room.room_number)}
              target="_blank"
              rel="noreferrer"
              style={button}
            >
              Download QR
            </a>
          </div>
        ))}
      </div>
    </div>
  );
}

const page = {
  padding: "30px",
  color: "#fff",
};

const title = {
  fontSize: "42px",
  marginBottom: "6px",
};

const hotelName = {
  color: "#d4af37",
  marginBottom: "25px",
};

const grid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit,minmax(280px,1fr))",
  gap: "24px",
};

const card = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "24px",
  textAlign: "center",
};

const qr = {
  width: "220px",
  height: "220px",
  margin: "20px auto",
  display: "block",
  borderRadius: "10px",
  background: "#fff",
  padding: "10px",
};

const url = {
  color: "#999",
  marginBottom: "15px",
  fontSize: "12px",
  wordBreak: "break-word",
};

const button = {
  display: "inline-block",
  background: "#d4af37",
  color: "#000",
  textDecoration: "none",
  padding: "10px 18px",
  borderRadius: "10px",
  fontWeight: "700",
};