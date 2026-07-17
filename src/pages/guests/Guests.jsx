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
    setExtendDateTime(
      new Date(currentValue).toISOString().slice(0, 16)
    );
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
      Math.ceil(
        (checkOutDate.getTime() - checkInDate.getTime()) /
          3600000
      )
    );

    const stayNights = Math.max(
      1,
      Math.ceil(stayHours / 24)
    );

    let createdInvoiceId = null;

    try {
      /*
       * Do not allow checkout while any kitchen order
       * is still being processed or delivered.
       */
      const { data: openFoodOrders, error: openFoodError } =
        await supabase
          .from("food_orders")
          .select("id, order_status")
          .eq("hotel_id", session.hotel_id)
          .eq("guest_id", guest.id)
          .gte("created_at", stayStart)
          .in("order_status", [
            "pending",
            "accepted",
            "preparing",
            "out_for_delivery",
          ]);

      if (openFoodError) throw openFoodError;

      if (openFoodOrders?.length > 0) {
        alert(
          `${openFoodOrders.length} food order(s) are still open.\n\nComplete or cancel them before checkout.`
        );
        return;
      }

      /*
       * Prevent duplicate invoice for this exact guest session.
       */
      const {
        data: existingInvoice,
        error: existingInvoiceError,
      } = await supabase
        .from("invoices")
        .select("id, invoice_number")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_session_id", session.id)
        .limit(1)
        .maybeSingle();

      if (existingInvoiceError) {
        throw existingInvoiceError;
      }

      if (existingInvoice) {
        alert(
          `Invoice already exists for this stay.\nInvoice No: ${existingInvoice.invoice_number}`
        );
        return;
      }

      /*
       * Fetch all payment demand records created during this stay.
       */
      const { data: payments, error: paymentError } =
        await supabase
          .from("payments")
          .select("*")
          .eq("hotel_id", session.hotel_id)
          .eq("guest_id", guest.id)
          .gte("created_at", stayStart);

      if (paymentError) throw paymentError;

      const paymentIds = (payments || []).map(
        (payment) => payment.id
      );

      /*
       * Fetch actual split/partial payment collections.
       */
      let paymentCollections = [];

      if (paymentIds.length > 0) {
        const {
          data: collectionData,
          error: collectionError,
        } = await supabase
          .from("payment_collections")
          .select("*")
          .eq("hotel_id", session.hotel_id)
          .in("payment_id", paymentIds);

        if (collectionError) throw collectionError;

        paymentCollections = collectionData || [];
      }

      const roomAmount =
        payments
          ?.filter(
            (payment) =>
              payment.payment_type === "room_charge"
          )
          .reduce(
            (sum, payment) =>
              sum + Number(payment.amount || 0),
            0
          ) || 0;

      /*
       * Correctly calculate paid amount from collection history.
       * Old paid records without collection rows are supported.
       */
      const previouslyPaidAmount = (payments || []).reduce(
        (total, payment) => {
          const collectionTotal = paymentCollections
            .filter(
              (collection) =>
                String(collection.payment_id) ===
                String(payment.id)
            )
            .reduce(
              (sum, collection) =>
                sum + Number(collection.amount || 0),
              0
            );

          if (
            collectionTotal === 0 &&
            payment.payment_status === "paid"
          ) {
            return total + Number(payment.amount || 0);
          }

          return total + collectionTotal;
        },
        0
      );

      /*
       * Fetch delivered food orders with full item details.
       */
      const { data: foodOrders, error: foodError } =
        await supabase
          .from("food_orders")
          .select(`
            *,
            food_order_items (
              id,
              menu_item_id,
              quantity,
              price,
              menu_items (
                item_name
              )
            )
          `)
          .eq("hotel_id", session.hotel_id)
          .eq("guest_id", guest.id)
          .eq("order_status", "delivered")
          .gte("created_at", stayStart);

      if (foodError) throw foodError;

      const foodAmount =
        foodOrders?.reduce(
          (sum, order) =>
            sum + Number(order.total_amount || 0),
          0
        ) || 0;

      const foodOrderCount = foodOrders?.length || 0;

      const totalFoodItems =
        foodOrders?.reduce((orderTotal, order) => {
          const itemCount =
            order.food_order_items?.reduce(
              (itemTotal, item) =>
                itemTotal + Number(item.quantity || 0),
              0
            ) || 0;

          return orderTotal + itemCount;
        }, 0) || 0;

      /*
       * Fetch manual/additional charges for this stay.
       */
      const {
        data: manualCharges,
        error: chargeError,
      } = await supabase
        .from("manual_charges")
        .select("*")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .gte("created_at", stayStart);

      if (chargeError) throw chargeError;

      const manualAmount =
        manualCharges?.reduce(
          (sum, charge) =>
            sum + Number(charge.charge_amount || 0),
          0
        ) || 0;

      /*
       * Service charges can be integrated later when a
       * charge amount is added to service_requests.
       */
      const serviceAmount = 0;

      const subtotalAmount =
        roomAmount +
        foodAmount +
        manualAmount +
        serviceAmount;

      const taxPercent = 0;
      const taxAmount = 0;

      const discountType = "fixed";
      const discountValue = 0;
      const discountAmount = 0;

      const totalAmount = Math.max(
        0,
        subtotalAmount + taxAmount - discountAmount
      );

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
          `Subtotal: ₹${subtotalAmount}\n` +
          `Tax: ₹${taxAmount}\n` +
          `Discount: ₹${discountAmount}\n\n` +
          `Previously Paid: ₹${previouslyPaidAmount}\n` +
          `Amount to Collect: ₹${amountToCollect}\n\n` +
          `Grand Total: ₹${totalAmount}\n\n` +
          `Confirm payment settlement, create invoice and checkout?`
      );

      if (!confirmCheckout) return;

      const invoiceNumber = generateInvoiceNumber();

      const invoicePaymentStatus =
        amountToCollect <= 0
          ? "paid"
          : previouslyPaidAmount > 0
            ? "partial"
            : "pending";

      const invoiceStatus =
        amountToCollect <= 0
          ? "paid"
          : previouslyPaidAmount > 0
            ? "partially_paid"
            : "issued";

      /*
       * Create the main invoice record.
       */
      const {
        data: createdInvoice,
        error: invoiceError,
      } = await supabase
        .from("invoices")
        .insert([
          {
            hotel_id: session.hotel_id,
            room_id: room.id,
            guest_id: guest.id,
            guest_session_id: session.id,

            invoice_number: invoiceNumber,

            room_amount: roomAmount,
            food_amount: foodAmount,
            manual_amount: manualAmount,
            service_amount: serviceAmount,

            subtotal_amount: subtotalAmount,

            tax_percent: taxPercent,
            tax_amount: taxAmount,

            discount_type: discountType,
            discount_value: discountValue,
            discount_amount: discountAmount,

            total_amount: totalAmount,

            previous_paid_amount: previouslyPaidAmount,
            amount_to_collect: amountToCollect,

            payment_status: invoicePaymentStatus,
            paid_amount: previouslyPaidAmount,
            pending_amount: amountToCollect,

            invoice_status: invoiceStatus,

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

      createdInvoiceId = createdInvoice.id;

      /*
       * Build detailed invoice line items.
       */
      const invoiceItems = [];

      if (roomAmount > 0) {
        invoiceItems.push({
          invoice_id: createdInvoice.id,
          hotel_id: session.hotel_id,
          guest_id: guest.id,
          room_id: room.id,

          item_type: "room",
          description: `${
            room.room_type || "Hotel Room"
          } · ${stayNights} night(s)`,

          quantity: 1,
          unit_price: roomAmount,
          amount: roomAmount,

          source_id: session.id,
        });
      }

      foodOrders?.forEach((order) => {
        order.food_order_items?.forEach((item) => {
          const quantity = Number(item.quantity || 0);
          const unitPrice = Number(item.price || 0);
          const amount = quantity * unitPrice;

          if (quantity <= 0 || amount <= 0) return;

          invoiceItems.push({
            invoice_id: createdInvoice.id,
            hotel_id: session.hotel_id,
            guest_id: guest.id,
            room_id: room.id,

            item_type: "food",
            description:
              item.menu_items?.item_name ||
              "Food Item",

            quantity,
            unit_price: unitPrice,
            amount,

            source_id: order.id,
          });
        });
      });

      manualCharges?.forEach((charge) => {
        const amount = Number(
          charge.charge_amount || 0
        );

        if (amount <= 0) return;

        invoiceItems.push({
          invoice_id: createdInvoice.id,
          hotel_id: session.hotel_id,
          guest_id: guest.id,
          room_id: room.id,

          item_type: "manual_charge",
          description:
            charge.charge_name ||
            "Additional Charge",

          quantity: 1,
          unit_price: amount,
          amount,

          source_id: charge.id,
        });
      });

      if (serviceAmount > 0) {
        invoiceItems.push({
          invoice_id: createdInvoice.id,
          hotel_id: session.hotel_id,
          guest_id: guest.id,
          room_id: room.id,

          item_type: "service",
          description: "Hotel Service Charges",

          quantity: 1,
          unit_price: serviceAmount,
          amount: serviceAmount,

          source_id: null,
        });
      }

      if (invoiceItems.length > 0) {
        const { error: invoiceItemsError } =
          await supabase
            .from("invoice_items")
            .insert(invoiceItems);

        if (invoiceItemsError) {
          /*
           * Remove incomplete invoice if its line items fail.
           */
          await supabase
            .from("invoices")
            .delete()
            .eq("id", createdInvoice.id)
            .eq("hotel_id", session.hotel_id);

          createdInvoiceId = null;
          throw invoiceItemsError;
        }
      }

      /*
       * Link stay payment demand records to this invoice.
       */
      if (paymentIds.length > 0) {
        const { error: paymentLinkError } =
          await supabase
            .from("payments")
            .update({
              invoice_id: createdInvoice.id,
            })
            .eq("hotel_id", session.hotel_id)
            .in("id", paymentIds);

        if (paymentLinkError) {
          throw paymentLinkError;
        }
      }

      /*
       * Link actual collection transactions to the invoice.
       */
      if (paymentCollections.length > 0) {
        const collectionIds = paymentCollections.map(
          (collection) => collection.id
        );

        const { error: collectionLinkError } =
          await supabase
            .from("payment_collections")
            .update({
              invoice_id: createdInvoice.id,
            })
            .eq("hotel_id", session.hotel_id)
            .in("id", collectionIds);

        if (collectionLinkError) {
          throw collectionLinkError;
        }
      }

      /*
       * Mark delivered food orders as billed.
       */
      const { error: foodUpdateError } =
        await supabase
          .from("food_orders")
          .update({
            payment_status:
              amountToCollect <= 0 ? "paid" : "pending",
          })
          .eq("hotel_id", session.hotel_id)
          .eq("guest_id", guest.id)
          .eq("order_status", "delivered")
          .gte("created_at", stayStart);

      if (foodUpdateError) throw foodUpdateError;

      /*
       * Mark manual charges according to settlement.
       */
      const { error: chargesUpdateError } =
        await supabase
          .from("manual_charges")
          .update({
            payment_status:
              amountToCollect <= 0 ? "paid" : "pending",
          })
          .eq("hotel_id", session.hotel_id)
          .eq("guest_id", guest.id)
          .gte("created_at", stayStart);

      if (chargesUpdateError) {
        throw chargesUpdateError;
      }

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
        .update({
          status: "cleaning",
        })
        .eq("id", room.id)
        .eq("hotel_id", session.hotel_id);

      if (roomError) throw roomError;

      /*
       * Avoid duplicate room-cleaning tasks.
       */
      const {
        data: existingCleaningTask,
        error: cleaningTaskCheckError,
      } = await supabase
        .from("housekeeping_tasks")
        .select("id")
        .eq("hotel_id", session.hotel_id)
        .eq("room_id", room.id)
        .eq("task_type", "room_cleaning")
        .in("status", ["pending", "in_progress"])
        .limit(1)
        .maybeSingle();

      if (cleaningTaskCheckError) {
        throw cleaningTaskCheckError;
      }

      if (!existingCleaningTask) {
        const { error: housekeepingError } =
          await supabase
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

        if (housekeepingError) {
          throw housekeepingError;
        }
      }

      alert(
        `Checkout completed successfully.\nInvoice created: ${invoiceNumber}\nPending balance: ₹${amountToCollect}`
      );

      await fetchGuests(currentHotel?.id);
    } catch (error) {
      console.error("Final checkout error:", error);

      /*
       * Clean up invoice if a later critical checkout step failed.
       * Existing invoice items are deleted through ON DELETE CASCADE.
       */
      if (createdInvoiceId) {
        console.warn(
          "Checkout failed after invoice creation. Invoice retained for review:",
          createdInvoiceId
        );
      }

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
            {currentHotel?.hotel_name || "Hotel"} · Manage
            active guests, final billing, stay extension and
            checkout.
          </p>
        </div>

        <button
          onClick={() =>
            fetchGuests(currentHotel?.id)
          }
        >
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
                    <td>
                      {session.guests?.full_name || "-"}
                    </td>

                    <td>
                      Room{" "}
                      {session.rooms?.room_number || "-"}
                      <br />

                      <small>
                        {session.rooms?.room_type || ""}
                      </small>
                    </td>

                    <td>
                      {session.guests?.phone || "-"}
                    </td>

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
                          onClick={() =>
                            openExtendModal(session)
                          }
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
              Select the new checkout date and time for
              this guest.
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
              <button
                style={saveBtn}
                onClick={handleExtendStay}
              >
                Save Extension
              </button>

              <button
                style={cancelBtn}
                onClick={closeExtendModal}
              >
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

  const datePart = now
    .toISOString()
    .slice(0, 10)
    .replace(/-/g, "");

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
  boxSizing: "border-box",
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