import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";

export default function HotelProfile() {
  const [currentHotel, setCurrentHotel] = useState(null);
  const [info, setInfo] = useState(defaultHotelInfo);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

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
    fetchHotelInfo(hotel);
  }

  async function fetchHotelInfo(hotel) {
    setLoading(true);

    const { data, error } = await supabase
      .from("hotel_info")
      .select("*")
      .eq("hotel_id", hotel.id)
      .maybeSingle();

    if (error) {
      alert(error.message);
    } else if (data) {
      setInfo(data);
    } else {
      setInfo({
        ...defaultHotelInfo,
        hotel_id: hotel.id,
        hotel_name: hotel.hotel_name || defaultHotelInfo.hotel_name,
        address: hotel.location || defaultHotelInfo.address,
      });
    }

    setLoading(false);
  }

  function handleChange(e) {
    setInfo({
      ...info,
      [e.target.name]: e.target.value,
    });
  }

  async function saveHotelInfo() {
    if (!currentHotel?.id) {
      alert("No hotel assigned");
      return;
    }

    setSaving(true);

    const payload = {
      hotel_id: currentHotel.id,
      hotel_name: info.hotel_name || currentHotel.hotel_name || "StayQR Hotel",
      address: info.address || currentHotel.location || "Hotel Address",
      reception_phone: info.reception_phone || "+919503893141",
      emergency_phone: info.emergency_phone || "+919503893141",
      checkin_time: info.checkin_time || "2:00 PM",
      checkout_time: info.checkout_time || "11:00 AM",
      breakfast_time: info.breakfast_time || "8:00 AM - 10:30 AM",
      wifi_name: info.wifi_name || "Hotel_Guest_WiFi",
      wifi_password: info.wifi_password || "Ask Reception",
      hotel_rules:
        info.hotel_rules ||
        "Please maintain silence, avoid smoking inside rooms, and contact reception for assistance.",
      about:
        info.about ||
        `${currentHotel.hotel_name || "This hotel"} offers a smart and comfortable hospitality experience powered by StayQR.`,
    };

    let error;
    let savedData;

    if (info?.id) {
      const result = await supabase
        .from("hotel_info")
        .update(payload)
        .eq("id", info.id)
        .eq("hotel_id", currentHotel.id)
        .select()
        .single();

      error = result.error;
      savedData = result.data;
    } else {
      const result = await supabase
        .from("hotel_info")
        .insert([payload])
        .select()
        .single();

      error = result.error;
      savedData = result.data;
    }

    setSaving(false);

    if (error) {
      alert(error.message);
      return;
    }

    if (savedData) {
      setInfo(savedData);
    }

    alert("Hotel profile saved successfully");
    fetchHotelInfo(currentHotel);
  }

  if (loading) return <div style={page}>Loading Hotel Profile...</div>;

  return (
    <div style={page}>
      <h1 style={title}>Hotel Profile</h1>
      <p style={hotelName}>{currentHotel?.hotel_name || "Hotel"}</p>
      <p style={sub}>Manage hotel information shown on guest QR guide.</p>

      <div style={card}>
        <Input label="Hotel Name" name="hotel_name" value={info?.hotel_name} onChange={handleChange} />
        <Input label="Address" name="address" value={info?.address} onChange={handleChange} />
        <Input label="Reception Phone" name="reception_phone" value={info?.reception_phone} onChange={handleChange} />
        <Input label="Emergency Phone" name="emergency_phone" value={info?.emergency_phone} onChange={handleChange} />
        <Input label="Check-In Time" name="checkin_time" value={info?.checkin_time} onChange={handleChange} />
        <Input label="Check-Out Time" name="checkout_time" value={info?.checkout_time} onChange={handleChange} />
        <Input label="Breakfast Time" name="breakfast_time" value={info?.breakfast_time} onChange={handleChange} />
        <Input label="WiFi Name" name="wifi_name" value={info?.wifi_name} onChange={handleChange} />
        <Input label="WiFi Password" name="wifi_password" value={info?.wifi_password} onChange={handleChange} />

        <Textarea label="About Hotel" name="about" value={info?.about} onChange={handleChange} />
        <Textarea label="Hotel Rules" name="hotel_rules" value={info?.hotel_rules} onChange={handleChange} />

        <button style={saveBtn} onClick={saveHotelInfo} disabled={saving}>
          {saving ? "Saving..." : "Save Hotel Profile"}
        </button>
      </div>
    </div>
  );
}

const defaultHotelInfo = {
  hotel_name: "StayQR Hotel",
  address: "Hotel Address",
  reception_phone: "+919503893141",
  emergency_phone: "+919503893141",
  checkin_time: "2:00 PM",
  checkout_time: "11:00 AM",
  breakfast_time: "8:00 AM - 10:30 AM",
  wifi_name: "Hotel_Guest_WiFi",
  wifi_password: "Ask Reception",
  hotel_rules:
    "Please maintain silence, avoid smoking inside rooms, and contact reception for assistance.",
  about:
    "This hotel offers a smart and comfortable hospitality experience powered by StayQR.",
};

function Input({ label, name, value, onChange }) {
  return (
    <div style={field}>
      <label style={labelStyle}>{label}</label>
      <input style={input} name={name} value={value || ""} onChange={onChange} />
    </div>
  );
}

function Textarea({ label, name, value, onChange }) {
  return (
    <div style={{ ...field, gridColumn: "1 / -1" }}>
      <label style={labelStyle}>{label}</label>
      <textarea style={textarea} name={name} value={value || ""} onChange={onChange} />
    </div>
  );
}

const page = {
  padding: "32px",
  color: "#fff",
};

const title = {
  fontSize: "42px",
  marginBottom: "6px",
};

const hotelName = {
  color: "#d4af37",
  marginBottom: "6px",
};

const sub = {
  color: "#aaa",
  marginBottom: "28px",
};

const card = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "20px",
  padding: "28px",
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
  gap: "20px",
};

const field = {
  display: "flex",
  flexDirection: "column",
  gap: "8px",
};

const labelStyle = {
  color: "#d4af37",
  fontSize: "13px",
  fontWeight: "700",
};

const input = {
  background: "#050505",
  color: "#fff",
  border: "1px solid #333",
  borderRadius: "10px",
  padding: "12px",
};

const textarea = {
  ...input,
  minHeight: "110px",
  resize: "vertical",
};

const saveBtn = {
  gridColumn: "1 / -1",
  background: "#d4af37",
  color: "#000",
  border: "none",
  padding: "14px 18px",
  borderRadius: "12px",
  fontWeight: "800",
  cursor: "pointer",
};