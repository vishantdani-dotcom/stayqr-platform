import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import "./Guests.css";

export default function Guests() {
  const [sessions, setSessions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [checkoutLoadingId, setCheckoutLoadingId] = useState(null);

  const [extendModalOpen, setExtendModalOpen] = useState(false);
  const [selectedSession, setSelectedSession] = useState(null);
  const [extendDateTime, setExtendDateTime] = useState("");

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
    await fetchGuests(hotel.id);
  }

  async function fetchGuests(hotelId = currentHotel?.id) {
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
      console.error("Fetch guests error:", error);
      alert(error.message);
      setLoading(false);
      return;
    }

    setSessions(data || []);
    setLoading(false);
  }

  function openExtendModal(session) {
    const currentValue =
      session.extended_until ||
      session.checkout_time ||
      new Date().toISOString();

    setSelectedSession(session);
    setExtendDateTime(new Date(currentValue).toISOString().slice(0, 16));
    setExtendModalOpen(true);
  }

  function closeExtendModal() {
    setExtendModalOpen(false);
    setSelectedSession(null);
    setExtendDateTime("");
  }

  async function handleExtendStay() {
    if (!selectedSession || !extendDateTime) {
      alert("Please select new checkout date and time");
      return;
    }

    try {
      const selectedDate = new Date(extendDateTime);

      if (Number.isNaN(selectedDate.getTime())) {
        alert("Please select a valid checkout date and time");
        return;
      }

      const { error } = await supabase
        .from("guest_sessions")
        .update({
          extended_until: selectedDate.toISOString(),
          status: "active",
        })
        .eq("id", selectedSession.id)
        .eq("hotel_id", selectedSession.hotel_id);

      if (error) throw error;

      alert("Stay extended successfully");
      closeExtendModal();
      await fetchGuests(currentHotel?.id);
    } catch (error) {
      console.error("Extend stay error:", error);
      alert(error.message);
    }
  }

  async function handleFinalCheckout(session) {
    const guest = session.guests;
    const room = session.rooms;

    if (!guest || !room) {
      alert("Guest or room details missing");
      return;
    }

    if (!session.checkin_time) {
      alert("Guest check-in time is missing");
      return;
    }

    setCheckoutLoadingId(session.id);

    const stayStart = session.checkin_time;
    const stayEnd = new Date().toISOString();

    const checkInDate = new Date(stayStart);
    const checkOutDate = new Date(stayEnd);

    if (
      Number.isNaN(checkInDate.getTime()) ||
      Number.isNaN(checkOutDate.getTime())
    ) {
      alert("Invalid stay date information");
      setCheckoutLoadingId(null);
      return;
    }

    const stayHours = Math.max(
      1,
      Math.ceil((checkOutDate.getTime() - checkInDate.getTime()) / 3600000)
    );

    const stayNights = Math.max(1, Math.ceil(stayHours / 24));

    try {
      /*
       * Prevent checkout while kitchen orders are still open.
       */
      const { data: openFoodOrders, error: openFoodError } = await supabase
        .from("food_orders")
        .select("id, order_status")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .gte("created_at", stayStart)
        .in("order_status", ["pending", "accepted", "preparing"]);

      if (openFoodError) throw openFoodError;

      if (openFoodOrders?.length > 0) {
        alert(
          `${openFoodOrders.length} food order(s) are still pending, accepted or preparing.\n\nComplete or cancel them before checkout.`
        );
        return;
      }

      /*
       * Prevent duplicate invoice only for this particular stay.
       * A returning guest can still receive a new invoice in a future stay.
       */
      const { data: existingInvoice, error: existingInvoiceError } =
        await supabase
          .from("invoices")
          .select("id, invoice_number")
          .eq("hotel_id", session.hotel_id)
          .eq("guest_id", guest.id)
          .eq("room_id", room.id)
          .gte("created_at", stayStart)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

      if (existingInvoiceError) throw existingInvoiceError;

      if (existingInvoice) {
        alert(
          `Invoice already exists for this stay.\nInvoice No: ${existingInvoice.invoice_number}`
        );
        return;
      }

      /*
       * Fetch all payments for this stay.
       */
      const { data: payments, error: paymentError } = await supabase
        .from("payments")
        .select("*")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .gte("created_at", stayStart);

      if (paymentError) throw paymentError;

      const roomAmount =
        payments
          ?.filter((payment) => payment.payment_type === "room_charge")
          .reduce(
            (sum, payment) => sum + Number(payment.amount || 0),
            0
          ) || 0;

      const previouslyPaidAmount =
        payments
          ?.filter((payment) => payment.payment_status === "paid")
          .reduce(
            (sum, payment) => sum + Number(payment.amount || 0),
            0
          ) || 0;

      /*
       * Fetch only delivered food orders and their real item quantities.
       */
      const { data: foodOrders, error: foodError } = await supabase
        .from("food_orders")
        .select(`
          *,
          food_order_items (
            quantity
          )
        `)
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .eq("order_status", "delivered")
        .gte("created_at", stayStart);

      if (foodError) throw foodError;

      const foodAmount =
        foodOrders?.reduce(
          (sum, order) => sum + Number(order.total_amount || 0),
          0
        ) || 0;

      const foodOrderCount = foodOrders?.length || 0;

      const totalFoodItems =
        foodOrders?.reduce((orderTotal, order) => {
          const orderItemCount =
            order.food_order_items?.reduce(
              (itemTotal, item) =>
                itemTotal + Number(item.quantity || 0),
              0
            ) || 0;

          return orderTotal + orderItemCount;
        }, 0) || 0;

      /*
       * Fetch manual charges for this stay.
       */
      const { data: manualCharges, error: chargeError } = await supabase
        .from("manual_charges")
        .select("*")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .gte("created_at", stayStart);

      if (chargeError) throw chargeError;

      const manualAmount =
        manualCharges?.reduce(
          (sum, charge) => sum + Number(charge.charge_amount || 0),
          0
        ) || 0;

      const serviceAmount = 0;

      const totalAmount =
        roomAmount + foodAmount + manualAmount + serviceAmount;

      const amountToCollect = Math.max(
        0,
        totalAmount - previouslyPaidAmount
      );

      const confirmCheckout = window.confirm(
        `Final Checkout Bill\n\n` +
          `Guest: ${guest.full_name}\n` +
          `Room: ${room.room_number}\n` +
          `Stay: ${stayNights} night(s) / ${stayHours} hour(s)\n\n` +
          `Room Charges: ₹${roomAmount}\n` +
          `Food Charges: ₹${foodAmount}\n` +
          `Manual Charges: ₹${manualAmount}\n` +
          `Service Charges: ₹${serviceAmount}\n\n` +
          `Food Orders: ${foodOrderCount}\n` +
          `Food Items: ${totalFoodItems}\n\n` +
          `Previously Paid: ₹${previouslyPaidAmount}\n` +
          `Amount to Collect: ₹${amountToCollect}\n\n` +
          `Final Total: ₹${totalAmount}\n\n` +
          `Confirm that payment has been collected, create the invoice and checkout the guest?`
      );

      if (!confirmCheckout) return;

      const invoiceNumber = generateInvoiceNumber();

      /*
       * Final checkout assumes reception has collected the remaining amount.
       * Invoice and related stay records therefore become paid.
       */
      const { data: createdInvoice, error: invoiceError } = await supabase
        .from("invoices")
        .insert([
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
            paid_amount: totalAmount,
            pending_amount: 0,

            checkin_time: stayStart,
            checkout_time: stayEnd,
            stay_hours: stayHours,
            stay_nights: stayNights,

            food_order_count: foodOrderCount,
            food_item_count: totalFoodItems,
          },
        ])
        .select()
        .single();

      if (invoiceError) throw invoiceError;

      console.log("Created invoice:", createdInvoice);

      /*
       * Mark payments from this stay as paid.
       */
      const { error: paymentUpdateError } = await supabase
        .from("payments")
        .update({ payment_status: "paid" })
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .gte("created_at", stayStart);

      if (paymentUpdateError) throw paymentUpdateError;

      /*
       * Mark only delivered food orders as paid.
       * Pending/preparing orders are never included or marked as paid.
       */
      const { error: foodUpdateError } = await supabase
        .from("food_orders")
        .update({ payment_status: "paid" })
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .eq("order_status", "delivered")
        .gte("created_at", stayStart);

      if (foodUpdateError) throw foodUpdateError;

      /*
       * Mark manual charges for this stay as paid.
       */
      const { error: chargesUpdateError } = await supabase
        .from("manual_charges")
        .update({ payment_status: "paid" })
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .gte("created_at", stayStart);

      if (chargesUpdateError) throw chargesUpdateError;

      /*
       * Complete guest session and expire QR access.
       */
      const { error: sessionError } = await supabase
        .from("guest_sessions")
        .update({
          status: "completed",
          expired_at: stayEnd,
        })
        .eq("id", session.id)
        .eq("hotel_id", session.hotel_id)
        .eq("status", "active");

      if (sessionError) throw sessionError;

      /*
       * Send room to cleaning.
       */
      const { error: roomError } = await supabase
        .from("rooms")
        .update({ status: "cleaning" })
        .eq("id", room.id)
        .eq("hotel_id", session.hotel_id);

      if (roomError) throw roomError;

      /*
       * Avoid duplicate pending cleaning tasks for the same room.
       */
      const { data: existingCleaningTask, error: cleaningTaskCheckError } =
        await supabase
          .from("housekeeping_tasks")
          .select("id")
          .eq("hotel_id", session.hotel_id)
          .eq("room_id", room.id)
          .eq("task_type", "room_cleaning")
          .in("status", ["pending", "in_progress"])
          .limit(1)
          .maybeSingle();

      if (cleaningTaskCheckError) throw cleaningTaskCheckError;

      if (!existingCleaningTask) {
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
      }

      alert(
        `Checkout completed successfully.\nInvoice created: ${invoiceNumber}`
      );

      await fetchGuests(currentHotel?.id);
    } catch (error) {
      console.error("Final checkout error:", error);
      alert(error.message || "Checkout failed");
    } finally {
      setCheckoutLoadingId(null);
    }
  }

  return (
    <div className="rooms-page">
      <div className="rooms-header">
        <div>
          <h1>Guests</h1>

          <p>
            {currentHotel?.hotel_name || "Hotel"} · Manage active guests,
            final billing, stay extension and checkout.
          </p>
        </div>

        <button onClick={() => fetchGuests(currentHotel?.id)}>
          Refresh
        </button>
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
              {sessions.map((session) => {
                const checkoutLoading =
                  checkoutLoadingId === session.id;

                return (
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
                        ? new Date(
                            session.checkin_time
                          ).toLocaleString("en-IN")
                        : "-"}
                    </td>

                    <td>
                      {session.extended_until
                        ? new Date(
                            session.extended_until
                          ).toLocaleString("en-IN")
                        : session.checkout_time
                          ? new Date(
                              session.checkout_time
                            ).toLocaleString("en-IN")
                          : "-"}
                    </td>

                    <td>
                      <div
                        style={{
                          display: "flex",
                          gap: "8px",
                          flexWrap: "wrap",
                        }}
                      >
                        <button
                          className="checkout-btn"
                          disabled={checkoutLoading}
                          onClick={() =>
                            handleFinalCheckout(session)
                          }
                        >
                          {checkoutLoading
                            ? "Processing..."
                            : "Final Bill & Checkout"}
                        </button>

                        <button
                          className="checkout-btn"
                          disabled={checkoutLoading}
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
                );
              })}
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

            <label style={label}>
              New Checkout Date &amp; Time
            </label>

            <input
              type="datetime-local"
              value={extendDateTime}
              onChange={(event) =>
                setExtendDateTime(event.target.value)
              }
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