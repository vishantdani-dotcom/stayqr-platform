import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";

export default function Charges() {
  const [charges, setCharges] = useState([]);
  const [guests, setGuests] = useState([]);
  const [currentHotel, setCurrentHotel] = useState(null);

  const [guestId, setGuestId] = useState("");
  const [chargeName, setChargeName] = useState("");
  const [chargeAmount, setChargeAmount] = useState("");
  const [notes, setNotes] = useState("");

  useEffect(() => {
    initPage();
  }, []);

  async function initPage() {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      return;
    }

    setCurrentHotel(hotel);
    loadData(hotel.id);
  }

  async function loadData(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    const { data: guestData } = await supabase
      .from("guests")
      .select("*")
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    const { data: chargesData } = await supabase
      .from("manual_charges")
      .select(`
        *,
        guests (
          full_name
        )
      `)
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    setGuests(guestData || []);
    setCharges(chargesData || []);
  }

  async function addCharge() {
    if (!currentHotel?.id) {
      alert("No hotel assigned");
      return;
    }

    if (!guestId || !chargeName || !chargeAmount) {
      alert("Please fill all fields");
      return;
    }

    const selectedGuest = guests.find(
      (g) => String(g.id) === String(guestId)
    );

    const { error } = await supabase
      .from("manual_charges")
      .insert([
        {
          hotel_id: currentHotel.id,
          guest_id: guestId,
          room_id: selectedGuest?.room_id || null,
          charge_name: chargeName,
          charge_amount: Number(chargeAmount),
          notes,
          payment_status: "pending",
        },
      ]);

    if (error) {
      alert(error.message);
      return;
    }

    alert("Charge added successfully");

    setGuestId("");
    setChargeName("");
    setChargeAmount("");
    setNotes("");

    loadData(currentHotel.id);
  }

  const totalRevenue = charges.reduce(
    (sum, c) => sum + Number(c.charge_amount || 0),
    0
  );

  return (
    <div style={page}>
      <h1 style={title}>Manual Charges</h1>

      <p style={hotelName}>
        {currentHotel?.hotel_name || "Hotel"}
      </p>

      <div style={statsGrid}>
        <StatCard title="Total Charges" value={charges.length} />
        <StatCard title="Additional Revenue" value={`₹${totalRevenue}`} />
      </div>

      <div style={formCard}>
        <h3>Add Charge</h3>

        <select
          value={guestId}
          onChange={(e) => setGuestId(e.target.value)}
          style={input}
        >
          <option value="">Select Guest</option>

          {guests.map((guest) => (
            <option key={guest.id} value={guest.id}>
              {guest.full_name} {guest.room_number ? `- Room ${guest.room_number}` : ""}
            </option>
          ))}
        </select>

        <input
          style={input}
          placeholder="Charge Name"
          value={chargeName}
          onChange={(e) => setChargeName(e.target.value)}
        />

        <input
          style={input}
          placeholder="Amount"
          type="number"
          value={chargeAmount}
          onChange={(e) => setChargeAmount(e.target.value)}
        />

        <textarea
          style={input}
          placeholder="Notes"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
        />

        <button style={button} onClick={addCharge}>
          Add Charge
        </button>
      </div>

      <div style={tableCard}>
        <table style={table}>
          <thead>
            <tr>
              <th style={th}>Guest</th>
              <th style={th}>Charge</th>
              <th style={th}>Amount</th>
              <th style={th}>Status</th>
              <th style={th}>Notes</th>
              <th style={th}>Date</th>
            </tr>
          </thead>

          <tbody>
            {charges.map((charge) => (
              <tr key={charge.id}>
                <td style={td}>{charge.guests?.full_name || "-"}</td>
                <td style={td}>{charge.charge_name}</td>
                <td style={td}>₹{charge.charge_amount}</td>
                <td style={td}>{charge.payment_status || "pending"}</td>
                <td style={td}>{charge.notes || "-"}</td>
                <td style={td}>
                  {new Date(charge.created_at).toLocaleString("en-IN")}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function StatCard({ title, value }) {
  return (
    <div style={statCard}>
      <div style={statTitle}>{title}</div>
      <div style={statValue}>{value}</div>
    </div>
  );
}

const page = {
  padding: "30px",
  color: "#fff",
};

const title = {
  fontSize: "40px",
  marginBottom: "6px",
};

const hotelName = {
  color: "#d4af37",
  marginBottom: "20px",
};

const statsGrid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))",
  gap: "20px",
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
  marginBottom: "10px",
};

const statValue = {
  fontSize: "28px",
  fontWeight: "700",
};

const formCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "16px",
  padding: "25px",
  marginBottom: "25px",
};

const input = {
  width: "100%",
  marginBottom: "15px",
  padding: "12px",
  background: "#111",
  color: "#fff",
  border: "1px solid #333",
  borderRadius: "10px",
};

const button = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  padding: "12px 18px",
  borderRadius: "10px",
  fontWeight: "700",
  cursor: "pointer",
};

const tableCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "16px",
  overflowX: "auto",
};

const table = {
  width: "100%",
  borderCollapse: "collapse",
};

const th = {
  padding: "15px",
  textAlign: "left",
  borderBottom: "1px solid #222",
  color: "#d4af37",
};

const td = {
  padding: "15px",
  borderBottom: "1px solid #222",
};