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
      hotel_name: cleanText(info.hotel_name) || currentHotel.hotel_name,
      address: cleanText(info.address) || cleanText(currentHotel.location),
      reception_phone: cleanText(info.reception_phone),
      emergency_phone: cleanText(info.emergency_phone),
      checkin_time: cleanText(info.checkin_time),
      checkout_time: cleanText(info.checkout_time),
      breakfast_time: cleanText(info.breakfast_time),
      wifi_name: cleanText(info.wifi_name),
      wifi_password: cleanText(info.wifi_password),
      hotel_rules: cleanText(info.hotel_rules),
      about: cleanText(info.about),
      google_review_url: cleanText(info.google_review_url),
      reward_title: cleanText(info.reward_title),
      reward_description: cleanText(info.reward_description),
      reward_enabled: info.reward_enabled ?? false,
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

        <Input label="Google Review URL" name="google_review_url" value={info?.google_review_url} onChange={handleChange} />
        <Input label="Reward Title" name="reward_title" value={info?.reward_title} onChange={handleChange} />

        <Textarea label="About Hotel" name="about" value={info?.about} onChange={handleChange} />
        <Textarea label="Hotel Rules" name="hotel_rules" value={info?.hotel_rules} onChange={handleChange} />
        <Textarea label="Reward Description" name="reward_description" value={info?.reward_description} onChange={handleChange} />

        <div style={field}>
          <label style={labelStyle}>Rewards Enabled</label>

          <select
            style={input}
            name="reward_enabled"
            value={String(info?.reward_enabled ?? false)}
            onChange={(e) =>
              setInfo({
                ...info,
                reward_enabled: e.target.value === "true",
              })
            }
          >
            <option value="true">Enabled</option>
            <option value="false">Disabled</option>
          </select>
        </div>

        <button style={saveBtn} onClick={saveHotelInfo} disabled={saving}>
          {saving ? "Saving..." : "Save Hotel Profile"}
        </button>
      </div>
    </div>
  );
}

const defaultHotelInfo = {
  hotel_name: "",
  address: "",
  reception_phone: "",
  emergency_phone: "",
  checkin_time: "",
  checkout_time: "",
  breakfast_time: "",
  wifi_name: "",
  wifi_password: "",
  hotel_rules: "",
  about: "",
  google_review_url: "",
  reward_title: "",
  reward_description: "",
  reward_enabled: false,
};

function cleanText(value) {
  const text = String(value || "").trim();
  return text || null;
}

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