import { useState } from "react";

export default function Amenities() {
  const [amenities] = useState([
    {
      id: 1,
      name: "Restaurant",
      timing: "7:00 AM - 11:00 PM",
      description: "Multi-cuisine dining experience.",
      icon: "🍽️",
    },
    {
      id: 2,
      name: "Parking",
      timing: "24 Hours",
      description: "Free secure parking for guests.",
      icon: "🚗",
    },
    {
      id: 3,
      name: "WiFi",
      timing: "24 Hours",
      description: "High-speed complimentary internet.",
      icon: "📶",
    },
    {
      id: 4,
      name: "Laundry",
      timing: "8:00 AM - 8:00 PM",
      description: "Same-day laundry service available.",
      icon: "🧺",
    },
    {
      id: 5,
      name: "Room Service",
      timing: "24 Hours",
      description: "Food & support delivered to room.",
      icon: "🛎️",
    },
    {
      id: 6,
      name: "Gym",
      timing: "6:00 AM - 10:00 PM",
      description: "Modern fitness center.",
      icon: "🏋️",
    },
  ]);

  return (
    <div style={page}>
      <h1 style={title}>Amenities</h1>

      <div style={grid}>
        {amenities.map((item) => (
          <div key={item.id} style={card}>
            <div style={icon}>{item.icon}</div>

            <h3 style={name}>{item.name}</h3>

            <p style={timing}>{item.timing}</p>

            <p style={description}>
              {item.description}
            </p>
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
  fontSize: "38px",
  marginBottom: "25px",
};

const grid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit,minmax(250px,1fr))",
  gap: "20px",
};

const card = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "24px",
};

const icon = {
  fontSize: "42px",
  marginBottom: "15px",
};

const name = {
  color: "#d4af37",
  marginBottom: "8px",
};

const timing = {
  color: "#fff",
  fontWeight: "600",
};

const description = {
  color: "#999",
  marginTop: "10px",
};