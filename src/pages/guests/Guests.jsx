import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import "./Guests.css";

export default function Guests() {
  const [sessions, setSessions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);

  const [extendModalOpen, setExtendModalOpen] = useState(false);
  const [selectedSession, setSelectedSession] = useState(null);
  const [extendDateTime, setExtendDateTime] = useState("");

  useEffect(() => {
    initPage();
  }, []);

  const initPage = async () => {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    fetchGuests(hotel.id);
  };

  const fetchGuests = async (hotelId = currentHotel?.id) => {
    if (!hotelId) return;

    setLoading(true);

    const { data, error } = await supabase
      .from("guest_sessions")
      .select(`
        *,
        guests (
          id,
          full_name,
          phone
        ),
        rooms (
          id,
          room_number,
          room_type
        )
      `)
      .eq("hotel_id", hotelId)
      .eq("status", "active")
      .order("checkin_time", { ascending: false });

    if (error) {
      console.error(error);
      alert(error.message);
      setLoading(false);
      return;
    }

    setSessions(data || []);
    setLoading(false);
  };

  const openExtendModal = (session) => {
    const currentValue =
      session.extended_until || session.checkout_time || new Date().toISOString();

    setSelectedSession(session);
    setExtendDateTime(new Date(currentValue).toISOString().slice(0, 16));
    setExtendModalOpen(true);
  };

  const closeExtendModal = () => {
    setExtendModalOpen(false);
    setSelectedSession(null);
    setExtendDateTime("");
  };

  const handleExtendStay = async () => {
    if (!selectedSession || !extendDateTime) {
      alert("Please select new checkout date and time");
      return;
    }

    try {
      const { error } = await supabase
        .from("guest_sessions")
        .update({
          extended_until: new Date(extendDateTime).toISOString(),
          status: "active",
        })
        .eq("id", selectedSession.id)
        .eq("hotel_id", selectedSession.hotel_id);

      if (error) throw error;

      alert("Stay extended successfully");
      closeExtendModal();
      fetchGuests(currentHotel?.id);
    } catch (err) {
      console.error(err);
      alert(err.message);
    }
  };

  const handleFinalCheckout = async (session) => {
    const guest = session.guests;
    const room = session.rooms;

    if (!guest || !room) {
      alert("Guest or room details missing");
      return;
    }

    const stayStart = session.checkin_time;
    const stayEnd = new Date().toISOString();

    try {
      let paymentsQuery = supabase
        .from("payments")
        .select("*")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id);

      if (stayStart) {
        paymentsQuery = paymentsQuery.gte("created_at", stayStart);
      }

      const { data: payments, error: paymentError } = await paymentsQuery;

      if (paymentError) throw paymentError;

      const roomAmount =
        payments
          ?.filter((p) => p.payment_type === "room_charge")
          .reduce((sum, p) => sum + Number(p.amount || 0), 0) || 0;

      let foodQuery = supabase
        .from("food_orders")
        .select("*")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id);

      if (stayStart) {
        foodQuery = foodQuery.gte("created_at", stayStart);
      }

      const { data: foodOrders, error: foodError } = await foodQuery;

      if (foodError) throw foodError;

      const foodAmount =
        foodOrders?.reduce(
          (sum, order) => sum + Number(order.total_amount || 0),
          0
        ) || 0;

      let chargesQuery = supabase
        .from("manual_charges")
        .select("*")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id);

      if (stayStart) {
        chargesQuery = chargesQuery.gte("created_at", stayStart);
      }

      const { data: manualCharges, error: chargeError } = await chargesQuery;

      if (chargeError) throw chargeError;

      const manualAmount =
        manualCharges?.reduce(
          (sum, charge) => sum + Number(charge.charge_amount || 0),
          0
        ) || 0;

      const serviceAmount = 0;
      const totalAmount = roomAmount + foodAmount + manualAmount + serviceAmount;

      const confirmCheckout = window.confirm(
        `Final Checkout Bill\n\nGuest: ${guest.full_name}\nRoom: ${room.room_number}\n\nRoom Charges: ₹${roomAmount}\nFood Charges: ₹${foodAmount}\nManual Charges: ₹${manualAmount}\nService Charges: ₹${serviceAmount}\n\nTotal: ₹${totalAmount}\n\nCreate invoice, mark paid, and checkout guest?`
      );

      if (!confirmCheckout) return;

      const invoiceNumber = generateInvoiceNumber();

      const { error: invoiceError } = await supabase.from("invoices").insert([
        {
          hotel_id: session.hotel_id,
          room_id: room.id,
          guest_id: guest.id,
          invoice_number: invoiceNumber,
          room_amount: roomAmount,
          food_amount: foodAmount,
          manual_amount: manualAmount,
          service_amount: serviceAmount,
          total_amount: totalAmount,
          payment_status: "paid",
        },
      ]);

      if (invoiceError) throw invoiceError;

      let paymentUpdateQuery = supabase
        .from("payments")
        .update({ payment_status: "paid" })
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id);

      if (stayStart) {
        paymentUpdateQuery = paymentUpdateQuery.gte("created_at", stayStart);
      }

      const { error: paymentUpdateError } = await paymentUpdateQuery;

      if (paymentUpdateError) throw paymentUpdateError;

      let foodUpdateQuery = supabase
        .from("food_orders")
        .update({ payment_status: "paid" })
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id);

      if (stayStart) {
        foodUpdateQuery = foodUpdateQuery.gte("created_at", stayStart);
      }

      const { error: foodUpdateError } = await foodUpdateQuery;

      if (foodUpdateError) throw foodUpdateError;

      let chargesUpdateQuery = supabase
        .from("manual_charges")
        .update({ payment_status: "paid" })
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id);

      if (stayStart) {
        chargesUpdateQuery = chargesUpdateQuery.gte("created_at", stayStart);
      }

      const { error: chargesUpdateError } = await chargesUpdateQuery;

      if (chargesUpdateError) throw chargesUpdateError;

      const { error: sessionError } = await supabase
        .from("guest_sessions")
        .update({
          status: "completed",
          expired_at: stayEnd,
        })
        .eq("id", session.id)
        .eq("hotel_id", session.hotel_id);

      if (sessionError) throw sessionError;

      const { error: roomError } = await supabase
        .from("rooms")
        .update({ status: "cleaning" })
        .eq("id", room.id)
        .eq("hotel_id", session.hotel_id);

      if (roomError) throw roomError;

      const { error: housekeepingError } = await supabase
        .from("housekeeping_tasks")
        .insert([
          {
            hotel_id: session.hotel_id,
            room_id: room.id,
            room_number: room.room_number,
            task_type: "room_cleaning",
            status: "pending",
          },
        ]);

      if (housekeepingError) throw housekeepingError;

      alert(
        `Checkout completed successfully.\nInvoice created: ${invoiceNumber}`
      );

      fetchGuests(currentHotel?.id);
    } catch (err) {
      console.error(err);
      alert(err.message);
    }
  };

  return (
    <div className="rooms-page">
      <div className="rooms-header">
        <div>
          <h1>Guests</h1>
          <p>
            {currentHotel?.hotel_name || "Hotel"} · Manage active guests, final
            billing, stay extension and checkout.
          </p>
        </div>

        <button onClick={() => fetchGuests(currentHotel?.id)}>Refresh</button>
      </div>

      <div className="rooms-card">
        {loading ? (
          <p>Loading guests...</p>
        ) : sessions.length === 0 ? (
          <p>No active guests found.</p>
        ) : (
          <table className="rooms-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Room</th>
                <th>Phone</th>
                <th>Check-In Time</th>
                <th>Checkout Time</th>
                <th>Action</th>
              </tr>
            </thead>

            <tbody>
              {sessions.map((session) => (
                <tr key={session.id}>
                  <td>{session.guests?.full_name || "-"}</td>

                  <td>
                    Room {session.rooms?.room_number || "-"}
                    <br />
                    <small>{session.rooms?.room_type || ""}</small>
                  </td>

                  <td>{session.guests?.phone || "-"}</td>

                  <td>
                    {session.checkin_time
                      ? new Date(session.checkin_time).toLocaleString("en-IN")
                      : "-"}
                  </td>

                  <td>
                    {session.extended_until
                      ? new Date(session.extended_until).toLocaleString("en-IN")
                      : session.checkout_time
                      ? new Date(session.checkout_time).toLocaleString("en-IN")
                      : "-"}
                  </td>

                  <td>
                    <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
                      <button
                        className="checkout-btn"
                        onClick={() => handleFinalCheckout(session)}
                      >
                        Final Bill & Checkout
                      </button>

                      <button
                        className="checkout-btn"
                        style={{
                          background: "#d4af37",
                          color: "#000",
                        }}
                        onClick={() => openExtendModal(session)}
                      >
                        Extend Stay
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {extendModalOpen && (
        <div style={modalOverlay}>
          <div style={modal}>
            <h2 style={modalTitle}>Extend Stay</h2>

            <p style={modalSub}>
              Select the new checkout date and time for this guest.
            </p>

            <label style={label}>New Checkout Date & Time</label>

            <input
              type="datetime-local"
              value={extendDateTime}
              onChange={(e) => setExtendDateTime(e.target.value)}
              style={dateInput}
            />

            <div style={modalActions}>
              <button style={saveBtn} onClick={handleExtendStay}>
                Save Extension
              </button>

              <button style={cancelBtn} onClick={closeExtendModal}>
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function generateInvoiceNumber() {
  const now = new Date();
  const datePart = now.toISOString().slice(0, 10).replace(/-/g, "");
  const timePart = String(now.getTime()).slice(-6);
  return `INV-${datePart}-${timePart}`;
}

const modalOverlay = {
  position: "fixed",
  inset: 0,
  background: "rgba(0,0,0,0.75)",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  zIndex: 9999,
};

const modal = {
  background: "#0f0f0f",
  border: "1px solid #333",
  borderRadius: "18px",
  padding: "28px",
  width: "90%",
  maxWidth: "460px",
  color: "#fff",
};

const modalTitle = {
  color: "#d4af37",
  fontSize: "28px",
  marginBottom: "8px",
};

const modalSub = {
  color: "#aaa",
  marginBottom: "20px",
};

const label = {
  display: "block",
  color: "#d4af37",
  marginBottom: "8px",
  fontSize: "13px",
};

const dateInput = {
  width: "100%",
  padding: "14px",
  borderRadius: "10px",
  border: "1px solid #333",
  background: "#111",
  color: "#fff",
  marginBottom: "20px",
};

const modalActions = {
  display: "flex",
  gap: "10px",
  justifyContent: "flex-end",
};

const saveBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "10px 16px",
  fontWeight: 800,
  cursor: "pointer",
};

const cancelBtn = {
  background: "#222",
  color: "#fff",
  border: "1px solid #444",
  borderRadius: "10px",
  padding: "10px 16px",
  cursor: "pointer",
};