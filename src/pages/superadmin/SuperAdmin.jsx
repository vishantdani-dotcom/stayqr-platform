import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";

export default function SuperAdmin() {
  const [hotels, setHotels] = useState([]);
  const [plans, setPlans] = useState([]);
  const [subscriptions, setSubscriptions] = useState([]);
  const [loading, setLoading] = useState(true);

  const [hotelName, setHotelName] = useState("");
  const [location, setLocation] = useState("");
  const [planId, setPlanId] = useState("");

  useEffect(() => {
    loadData();
  }, []);

  async function loadData() {
    setLoading(true);

    const { data: hotelData, error: hotelError } = await supabase
      .from("hotels")
      .select("*")
      .order("created_at", { ascending: false });

    const { data: planData, error: planError } = await supabase
      .from("subscription_plans")
      .select("*")
      .order("price_monthly", { ascending: true });

    const { data: subscriptionData, error: subscriptionError } = await supabase
      .from("hotel_subscriptions")
      .select(`
        *,
        subscription_plans (
          plan_name,
          price_monthly
        )
      `)
      .order("created_at", { ascending: false });

    if (hotelError || planError || subscriptionError) {
      alert(
        hotelError?.message ||
          planError?.message ||
          subscriptionError?.message
      );
      setLoading(false);
      return;
    }

    setHotels(hotelData || []);
    setPlans(planData || []);
    setSubscriptions(subscriptionData || []);
    setLoading(false);
  }

  async function addHotel() {
    if (!hotelName || !location || !planId) {
      alert("Please fill hotel name, location and plan");
      return;
    }

    try {
      const { data: hotel, error: hotelError } = await supabase
        .from("hotels")
        .insert([
          {
            hotel_name: hotelName,
            location,
            status: "active",
          },
        ])
        .select()
        .single();

      if (hotelError) throw hotelError;

      const selectedPlan = plans.find((p) => p.id === planId);

      const endDate = new Date();
      endDate.setMonth(endDate.getMonth() + 1);

      const { error: subscriptionError } = await supabase
        .from("hotel_subscriptions")
        .insert([
          {
            hotel_id: hotel.id,
            plan_id: planId,
            status: "active",
            end_date: endDate.toISOString(),
          },
        ]);

      if (subscriptionError) throw subscriptionError;

      alert(
        `${hotelName} added successfully on ${selectedPlan?.plan_name || "selected"} plan`
      );

      setHotelName("");
      setLocation("");
      setPlanId("");

      loadData();
    } catch (err) {
      console.error(err);
      alert(err.message);
    }
  }

  function getHotelPlan(hotelId) {
    const sub = subscriptions.find((s) => s.hotel_id === hotelId);
    return sub?.subscription_plans?.plan_name || "No Plan";
  }

  function getHotelPlanPrice(hotelId) {
    const sub = subscriptions.find((s) => s.hotel_id === hotelId);
    return sub?.subscription_plans?.price_monthly || 0;
  }

  const activeHotels = hotels.filter((h) => h.status === "active").length;
  const monthlyRevenue = hotels.reduce((sum, hotel) => {
    return sum + Number(getHotelPlanPrice(hotel.id) || 0);
  }, 0);

  if (loading) {
    return <div style={page}>Loading Super Admin...</div>;
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <h1 style={title}>Super Admin</h1>
          <p style={subtitle}>Manage hotels, plans and subscriptions.</p>
        </div>

        <button style={refreshBtn} onClick={loadData}>
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Card title="Total Hotels" value={hotels.length} />
        <Card title="Active Hotels" value={activeHotels} />
        <Card title="Subscription Plans" value={plans.length} />
        <Card title="Monthly Revenue" value={`₹${monthlyRevenue}`} />
      </div>

      <div style={formCard}>
        <h2 style={sectionTitle}>Add New Hotel</h2>

        <input
          style={input}
          placeholder="Hotel Name"
          value={hotelName}
          onChange={(e) => setHotelName(e.target.value)}
        />

        <input
          style={input}
          placeholder="Location"
          value={location}
          onChange={(e) => setLocation(e.target.value)}
        />

        <select
          style={input}
          value={planId}
          onChange={(e) => setPlanId(e.target.value)}
        >
          <option value="">Select Plan</option>

          {plans.map((plan) => (
            <option key={plan.id} value={plan.id}>
              {plan.plan_name} - ₹{plan.price_monthly}/month - {plan.max_rooms} rooms
            </option>
          ))}
        </select>

        <button style={primaryBtn} onClick={addHotel}>
          Add Hotel & Activate Plan
        </button>
      </div>

      <div style={tableCard}>
        <h2 style={sectionTitle}>Hotels</h2>

        {hotels.length === 0 ? (
          <p>No hotels found.</p>
        ) : (
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Hotel</th>
                <th style={th}>Location</th>
                <th style={th}>Plan</th>
                <th style={th}>Status</th>
                <th style={th}>Created</th>
              </tr>
            </thead>

            <tbody>
              {hotels.map((hotel) => (
                <tr key={hotel.id}>
                  <td style={td}>{hotel.hotel_name}</td>
                  <td style={td}>{hotel.location || "-"}</td>
                  <td style={td}>{getHotelPlan(hotel.id)}</td>
                  <td style={td}>
                    <span style={badge(hotel.status)}>{hotel.status || "active"}</span>
                  </td>
                  <td style={td}>
                    {hotel.created_at
                      ? new Date(hotel.created_at).toLocaleString("en-IN")
                      : "-"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function Card({ title, value }) {
  return (
    <div style={statCard}>
      <div style={statTitle}>{title}</div>
      <div style={statValue}>{value}</div>
    </div>
  );
}

const page = {
  padding: "32px",
  color: "#fff",
};

const header = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "center",
  marginBottom: "25px",
};

const title = {
  fontSize: "42px",
  marginBottom: "6px",
};

const subtitle = {
  color: "#aaa",
};

const refreshBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "12px 18px",
  fontWeight: 800,
  cursor: "pointer",
};

const statsGrid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit,minmax(200px,1fr))",
  gap: "18px",
  marginBottom: "25px",
};

const statCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "16px",
  padding: "20px",
};

const statTitle = {
  color: "#d4af37",
  fontSize: "13px",
  marginBottom: "10px",
};

const statValue = {
  fontSize: "28px",
  fontWeight: "700",
};

const formCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "24px",
  marginBottom: "25px",
};

const sectionTitle = {
  color: "#d4af37",
  marginBottom: "18px",
};

const input = {
  width: "100%",
  padding: "13px",
  marginBottom: "14px",
  borderRadius: "10px",
  border: "1px solid #333",
  background: "#111",
  color: "#fff",
};

const primaryBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "12px 18px",
  fontWeight: 800,
  cursor: "pointer",
};

const tableCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "20px",
  overflowX: "auto",
};

const table = {
  width: "100%",
  borderCollapse: "collapse",
  minWidth: "900px",
};

const th = {
  color: "#d4af37",
  textAlign: "left",
  padding: "14px",
  borderBottom: "1px solid #222",
};

const td = {
  padding: "14px",
  borderBottom: "1px solid #1f1f1f",
};

const badge = (status) => ({
  padding: "7px 12px",
  borderRadius: "999px",
  background:
    status === "active"
      ? "rgba(46,204,113,.18)"
      : "rgba(255,170,0,.18)",
  color: status === "active" ? "#2ecc71" : "#ffaa00",
  fontWeight: 700,
  textTransform: "capitalize",
});