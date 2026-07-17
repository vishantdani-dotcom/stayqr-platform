import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import "./Guests.css";

export default function Guests() {
  const [sessions, setSessions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [checkoutLoadingId, setCheckoutLoadingId] =
    useState(null);

  const [extendModalOpen, setExtendModalOpen] =
    useState(false);
  const [selectedSession, setSelectedSession] =
    useState(null);
  const [extendDateTime, setExtendDateTime] =
    useState("");

  const [settlementModalOpen, setSettlementModalOpen] =
    useState(false);
  const [settlementLoading, setSettlementLoading] =
    useState(false);
  const [settlementData, setSettlementData] =
    useState(null);

  const [taxPercent, setTaxPercent] = useState("0");
  const [discountType, setDiscountType] =
    useState("fixed");
  const [discountValue, setDiscountValue] =
    useState("0");
  const [invoiceNotes, setInvoiceNotes] = useState("");
  const [
    remainingPaymentCollected,
    setRemainingPaymentCollected,
  ] = useState(false);

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

  async function fetchGuests(
    hotelId = currentHotel?.id
  ) {
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
      .order("checkin_time", {
        ascending: false,
      });

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
      new Date(currentValue)
        .toISOString()
        .slice(0, 16)
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
      alert(
        "Please select new checkout date and time"
      );
      return;
    }

    try {
      const selectedDate = new Date(extendDateTime);

      if (Number.isNaN(selectedDate.getTime())) {
        alert(
          "Please select a valid checkout date and time"
        );
        return;
      }

      const { error } = await supabase
        .from("guest_sessions")
        .update({
          extended_until: selectedDate.toISOString(),
          status: "active",
        })
        .eq("id", selectedSession.id)
        .eq(
          "hotel_id",
          selectedSession.hotel_id
        );

      if (error) throw error;

      alert("Stay extended successfully");

      closeExtendModal();

      await fetchGuests(currentHotel?.id);
    } catch (error) {
      console.error("Extend stay error:", error);
      alert(error.message);
    }
  }

  function resetSettlementState() {
    setSettlementModalOpen(false);
    setSettlementLoading(false);
    setSettlementData(null);

    setTaxPercent("0");
    setDiscountType("fixed");
    setDiscountValue("0");
    setInvoiceNotes("");
    setRemainingPaymentCollected(false);
  }

  function closeSettlementModal() {
    if (settlementLoading) return;
    resetSettlementState();
  }

  async function openSettlementModal(session) {
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

    try {
      const stayStart = session.checkin_time;
      const stayEnd = new Date().toISOString();

      const checkInDate = new Date(stayStart);
      const checkOutDate = new Date(stayEnd);

      if (
        Number.isNaN(checkInDate.getTime()) ||
        Number.isNaN(checkOutDate.getTime())
      ) {
        throw new Error(
          "Invalid stay date information"
        );
      }

      const stayHours = Math.max(
        1,
        Math.ceil(
          (checkOutDate.getTime() -
            checkInDate.getTime()) /
            3600000
        )
      );

      const stayNights = Math.max(
        1,
        Math.ceil(stayHours / 24)
      );

      /*
       * Prevent checkout while food orders are open.
       */
      const {
        data: openFoodOrders,
        error: openFoodError,
      } = await supabase
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
        throw new Error(
          `${openFoodOrders.length} food order(s) are still active. Complete or cancel them before checkout.`
        );
      }

      /*
       * Prevent duplicate invoice for this stay.
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
        throw new Error(
          `Invoice already exists for this stay: ${existingInvoice.invoice_number}`
        );
      }

      /*
       * Fetch payment demand records.
       */
      const {
        data: payments,
        error: paymentError,
      } = await supabase
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
       * Fetch partial and split collections.
       */
      let paymentCollections = [];

      if (paymentIds.length > 0) {
        const {
          data: collectionData,
          error: collectionsError,
        } = await supabase
          .from("payment_collections")
          .select("*")
          .eq("hotel_id", session.hotel_id)
          .in("payment_id", paymentIds);

        if (collectionsError) {
          throw collectionsError;
        }

        paymentCollections = collectionData || [];
      }

      const collectedPaymentIds = new Set(
        paymentCollections.map((collection) =>
          String(collection.payment_id)
        )
      );

      const collectionPaidAmount =
        paymentCollections.reduce(
          (sum, collection) =>
            sum +
            Number(collection.amount || 0),
          0
        );

      /*
       * Support older paid records without collection rows.
       */
      const legacyPaidAmount = (payments || [])
        .filter(
          (payment) =>
            payment.payment_status === "paid" &&
            !collectedPaymentIds.has(
              String(payment.id)
            )
        )
        .reduce(
          (sum, payment) =>
            sum + Number(payment.amount || 0),
          0
        );

      const previouslyPaidAmount =
        collectionPaidAmount + legacyPaidAmount;

      const roomAmount = (payments || [])
        .filter(
          (payment) =>
            payment.payment_type ===
            "room_charge"
        )
        .reduce(
          (sum, payment) =>
            sum + Number(payment.amount || 0),
          0
        );

      /*
       * Fetch delivered food orders with item details.
       */
      const {
        data: foodOrders,
        error: foodError,
      } = await supabase
        .from("food_orders")
        .select(`
          *,
          food_order_items (
            id,
            menu_item_id,
            quantity,
            price,
            menu_items (
              item_name,
              category
            )
          )
        `)
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .eq("order_status", "delivered")
        .gte("created_at", stayStart);

      if (foodError) throw foodError;

      const foodAmount = (
        foodOrders || []
      ).reduce(
        (sum, order) =>
          sum +
          Number(order.total_amount || 0),
        0
      );

      const foodOrderCount =
        foodOrders?.length || 0;

      const totalFoodItems = (
        foodOrders || []
      ).reduce((orderTotal, order) => {
        const orderItemCount = (
          order.food_order_items || []
        ).reduce(
          (itemTotal, item) =>
            itemTotal +
            Number(item.quantity || 0),
          0
        );

        return orderTotal + orderItemCount;
      }, 0);

      /*
       * Fetch manual charges.
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

      const manualAmount = (
        manualCharges || []
      ).reduce(
        (sum, charge) =>
          sum +
          Number(charge.charge_amount || 0),
        0
      );

      /*
       * Fetch chargeable completed services.
       */
      const {
        data: completedServices,
        error: serviceError,
      } = await supabase
        .from("service_requests")
        .select("*")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .eq("status", "completed")
        .gte("created_at", stayStart);

      if (serviceError) throw serviceError;

      const chargeableServices = (
        completedServices || []
      ).filter(
        (service) =>
          Number(
            service.service_amount ||
              service.charge_amount ||
              service.amount ||
              0
          ) > 0
      );

      const serviceAmount =
        chargeableServices.reduce(
          (sum, service) =>
            sum +
            Number(
              service.service_amount ||
                service.charge_amount ||
                service.amount ||
                0
            ),
          0
        );

      const subtotalAmount =
        roomAmount +
        foodAmount +
        manualAmount +
        serviceAmount;

      setSettlementData({
        session,
        guest,
        room,

        stayStart,
        stayEnd,
        stayHours,
        stayNights,

        payments: payments || [],
        paymentIds,
        paymentCollections,

        roomAmount,
        foodAmount,
        manualAmount,
        serviceAmount,
        subtotalAmount,

        previouslyPaidAmount,

        foodOrders: foodOrders || [],
        foodOrderCount,
        totalFoodItems,

        manualCharges:
          manualCharges || [],

        chargeableServices,
      });

      setTaxPercent("0");
      setDiscountType("fixed");
      setDiscountValue("0");
      setInvoiceNotes(
        "Final checkout invoice generated by StayQR."
      );
      setRemainingPaymentCollected(false);
      setSettlementModalOpen(true);
    } catch (error) {
      console.error(
        "Prepare settlement error:",
        error
      );

      alert(
        error.message ||
          "Unable to prepare final settlement"
      );
    } finally {
      setCheckoutLoadingId(null);
    }
  }

  const settlementCalculation = useMemo(() => {
    const subtotal = Number(
      settlementData?.subtotalAmount || 0
    );

    const safeTaxPercent = Math.min(
      100,
      Math.max(0, Number(taxPercent || 0))
    );

    const taxAmount =
      subtotal * (safeTaxPercent / 100);

    const safeDiscountValue = Math.max(
      0,
      Number(discountValue || 0)
    );

    let discountAmount = 0;

    if (discountType === "percentage") {
      const safeDiscountPercent = Math.min(
        100,
        safeDiscountValue
      );

      discountAmount =
        (subtotal + taxAmount) *
        (safeDiscountPercent / 100);
    } else {
      discountAmount = safeDiscountValue;
    }

    const amountBeforeDiscount =
      subtotal + taxAmount;

    discountAmount = Math.min(
      amountBeforeDiscount,
      discountAmount
    );

    const grandTotal = Math.max(
      0,
      amountBeforeDiscount - discountAmount
    );

    const previouslyPaid = Number(
      settlementData?.previouslyPaidAmount || 0
    );

    const amountToCollect = Math.max(
      0,
      grandTotal - previouslyPaid
    );

    const excessPaid = Math.max(
      0,
      previouslyPaid - grandTotal
    );

    return {
      subtotal,
      taxPercent: safeTaxPercent,
      taxAmount,
      discountValue: safeDiscountValue,
      discountAmount,
      grandTotal,
      previouslyPaid,
      amountToCollect,
      excessPaid,
    };
  }, [
    settlementData,
    taxPercent,
    discountType,
    discountValue,
  ]);

  async function completeFinalSettlement() {
    if (!settlementData) return;

    const {
      session,
      guest,
      room,
      stayStart,
      stayEnd,
      stayHours,
      stayNights,
      payments,
      paymentIds,
      paymentCollections,
      roomAmount,
      foodAmount,
      manualAmount,
      serviceAmount,
      foodOrders,
      foodOrderCount,
      totalFoodItems,
      manualCharges,
      chargeableServices,
    } = settlementData;

    const {
      subtotal,
      taxPercent: finalTaxPercent,
      taxAmount,
      discountValue: finalDiscountValue,
      discountAmount,
      grandTotal,
      previouslyPaid,
      amountToCollect,
      excessPaid,
    } = settlementCalculation;

    if (
      Number(taxPercent || 0) < 0 ||
      Number(taxPercent || 0) > 100
    ) {
      alert(
        "Tax percentage must be between 0 and 100."
      );
      return;
    }

    if (Number(discountValue || 0) < 0) {
      alert(
        "Discount value cannot be negative."
      );
      return;
    }

    if (
      discountType === "percentage" &&
      Number(discountValue || 0) > 100
    ) {
      alert(
        "Discount percentage cannot exceed 100%."
      );
      return;
    }

    if (
      amountToCollect > 0 &&
      !remainingPaymentCollected
    ) {
      alert(
        `Please confirm that the remaining ₹${formatMoney(
          amountToCollect
        )} has been collected before checkout.`
      );
      return;
    }

    if (excessPaid > 0) {
      const proceedWithExcess =
        window.confirm(
          `Previous payments exceed the final bill by ₹${formatMoney(
            excessPaid
          )}.\n\nPlease verify whether a refund or adjustment is required. Continue checkout?`
        );

      if (!proceedWithExcess) return;
    }

    setSettlementLoading(true);
    setCheckoutLoadingId(session.id);

    try {
      const invoiceNumber =
        generateInvoiceNumber();

      /*
       * Settlement confirmation means the final invoice
       * is fully paid before checkout.
       */
      const finalPaidAmount = grandTotal;
      const pendingAmount = 0;

      const {
        data: createdInvoice,
        error: invoiceError,
      } = await supabase
        .from("invoices")
        .insert([
          {
            hotel_id: session.hotel_id,
            guest_session_id: session.id,
            room_id: room.id,
            guest_id: guest.id,

            invoice_number: invoiceNumber,

            room_amount: roomAmount,
            food_amount: foodAmount,
            manual_amount: manualAmount,
            service_amount: serviceAmount,

            subtotal_amount: subtotal,

            tax_percent: finalTaxPercent,
            tax_amount: taxAmount,

            discount_type: discountType,
            discount_value:
              finalDiscountValue,
            discount_amount: discountAmount,

            previous_paid_amount:
              previouslyPaid,
            amount_to_collect:
              amountToCollect,

            total_amount: grandTotal,

            payment_status: "paid",
            invoice_status: "paid",

            paid_amount: finalPaidAmount,
            pending_amount: pendingAmount,
            settled_at: stayEnd,

            checkin_time: stayStart,
            checkout_time: stayEnd,
            stay_hours: stayHours,
            stay_nights: stayNights,

            food_order_count:
              foodOrderCount,
            food_item_count:
              totalFoodItems,

            invoice_notes:
              invoiceNotes.trim() || null,
          },
        ])
        .select()
        .single();

      if (invoiceError) throw invoiceError;

      /*
       * Create detailed invoice line items.
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

          quantity: stayNights,

          unit_price:
            stayNights > 0
              ? roomAmount / stayNights
              : roomAmount,

          amount: roomAmount,

          source_id: session.id,
        });
      }

      foodOrders.forEach((order) => {
        (
          order.food_order_items || []
        ).forEach((item) => {
          const quantity = Number(
            item.quantity || 0
          );

          const unitPrice = Number(
            item.price || 0
          );

          const amount =
            quantity * unitPrice;

          if (
            quantity <= 0 ||
            amount <= 0
          ) {
            return;
          }

          invoiceItems.push({
            invoice_id:
              createdInvoice.id,
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

      manualCharges.forEach((charge) => {
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

      chargeableServices.forEach(
        (service) => {
          const amount = Number(
            service.service_amount ||
              service.charge_amount ||
              service.amount ||
              0
          );

          if (amount <= 0) return;

          invoiceItems.push({
            invoice_id:
              createdInvoice.id,
            hotel_id:
              session.hotel_id,
            guest_id: guest.id,
            room_id: room.id,

            item_type: "service",

            description:
              service.request_type ||
              "Hotel Service",

            quantity: 1,
            unit_price: amount,
            amount,

            source_id: service.id,
          });
        }
      );

      if (taxAmount > 0) {
        invoiceItems.push({
          invoice_id: createdInvoice.id,
          hotel_id: session.hotel_id,
          guest_id: guest.id,
          room_id: room.id,

          item_type: "tax",

          description: `Tax ${formatMoney(
            finalTaxPercent
          )}%`,

          quantity: 1,
          unit_price: taxAmount,
          amount: taxAmount,

          source_id: null,
        });
      }

      if (discountAmount > 0) {
        invoiceItems.push({
          invoice_id: createdInvoice.id,
          hotel_id: session.hotel_id,
          guest_id: guest.id,
          room_id: room.id,

          item_type: "discount",

          description:
            discountType === "percentage"
              ? `Discount ${formatMoney(
                  finalDiscountValue
                )}%`
              : "Fixed Discount",

          quantity: 1,
          unit_price: -discountAmount,
          amount: -discountAmount,

          source_id: null,
        });
      }

      if (invoiceItems.length > 0) {
        const {
          error: invoiceItemsError,
        } = await supabase
          .from("invoice_items")
          .insert(invoiceItems);

        if (invoiceItemsError) {
          /*
           * Prevent incomplete invoices.
           */
          await supabase
            .from("invoices")
            .delete()
            .eq("id", createdInvoice.id)
            .eq(
              "hotel_id",
              session.hotel_id
            );

          throw invoiceItemsError;
        }
      }

      /*
       * Link payment records to invoice.
       */
      if (paymentIds.length > 0) {
        const {
          error: paymentUpdateError,
        } = await supabase
          .from("payments")
          .update({
            payment_status: "paid",
            invoice_id: createdInvoice.id,
            paid_at: stayEnd,
          })
          .eq("hotel_id", session.hotel_id)
          .in("id", paymentIds);

        if (paymentUpdateError) {
          throw paymentUpdateError;
        }

        const {
          error: collectionUpdateError,
        } = await supabase
          .from("payment_collections")
          .update({
            invoice_id: createdInvoice.id,
          })
          .eq("hotel_id", session.hotel_id)
          .in("payment_id", paymentIds);

        if (collectionUpdateError) {
          throw collectionUpdateError;
        }
      }

      /*
       * Mark delivered food orders paid.
       */
      const { error: foodUpdateError } =
        await supabase
          .from("food_orders")
          .update({
            payment_status: "paid",
          })
          .eq("hotel_id", session.hotel_id)
          .eq("guest_id", guest.id)
          .eq("order_status", "delivered")
          .gte("created_at", stayStart);

      if (foodUpdateError) {
        throw foodUpdateError;
      }

      /*
       * Mark manual charges paid.
       */
      const {
        error: chargeUpdateError,
      } = await supabase
        .from("manual_charges")
        .update({
          payment_status: "paid",
        })
        .eq("hotel_id", session.hotel_id)
        .eq("guest_id", guest.id)
        .gte("created_at", stayStart);

      if (chargeUpdateError) {
        throw chargeUpdateError;
      }

      /*
       * Complete guest session and expire QR.
       */
      const { error: sessionError } =
        await supabase
          .from("guest_sessions")
          .update({
            status: "completed",
            expired_at: stayEnd,
          })
          .eq("id", session.id)
          .eq(
            "hotel_id",
            session.hotel_id
          )
          .eq("status", "active");

      if (sessionError) {
        throw sessionError;
      }

      /*
       * Send room to cleaning.
       */
      const { error: roomError } =
        await supabase
          .from("rooms")
          .update({
            status: "cleaning",
          })
          .eq("id", room.id)
          .eq(
            "hotel_id",
            session.hotel_id
          );

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
        .eq(
          "task_type",
          "room_cleaning"
        )
        .in("status", [
          "pending",
          "in_progress",
        ])
        .limit(1)
        .maybeSingle();

      if (cleaningTaskCheckError) {
        throw cleaningTaskCheckError;
      }

      if (!existingCleaningTask) {
        const {
          error: housekeepingError,
        } = await supabase
          .from("housekeeping_tasks")
          .insert([
            {
              hotel_id:
                session.hotel_id,
              room_id: room.id,
              room_number:
                room.room_number,
              task_type:
                "room_cleaning",
              status: "pending",
            },
          ]);

        if (housekeepingError) {
          throw housekeepingError;
        }
      }

      alert(
        `Checkout completed successfully.\n\nInvoice: ${invoiceNumber}\nGrand Total: ₹${formatMoney(
          grandTotal
        )}\nTax: ₹${formatMoney(
          taxAmount
        )}\nDiscount: ₹${formatMoney(
          discountAmount
        )}`
      );

      resetSettlementState();

      await fetchGuests(currentHotel?.id);
    } catch (error) {
      console.error(
        "Final settlement error:",
        error
      );

      alert(
        error.message ||
          "Final checkout failed"
      );
    } finally {
      setSettlementLoading(false);
      setCheckoutLoadingId(null);
    }
  }

  return (
    <div className="rooms-page">
      <div className="rooms-header">
        <div>
          <h1>Guests</h1>

          <p>
            {currentHotel?.hotel_name || "Hotel"} ·
            Manage active guests, final billing,
            tax, discounts, stay extension and
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
                  checkoutLoadingId ===
                  session.id;

                return (
                  <tr key={session.id}>
                    <td>
                      {session.guests
                        ?.full_name || "-"}
                    </td>

                    <td>
                      Room{" "}
                      {session.rooms
                        ?.room_number || "-"}
                      <br />

                      <small>
                        {session.rooms
                          ?.room_type || ""}
                      </small>
                    </td>

                    <td>
                      {session.guests?.phone ||
                        "-"}
                    </td>

                    <td>
                      {session.checkin_time
                        ? new Date(
                            session.checkin_time
                          ).toLocaleString(
                            "en-IN"
                          )
                        : "-"}
                    </td>

                    <td>
                      {session.extended_until
                        ? new Date(
                            session.extended_until
                          ).toLocaleString(
                            "en-IN"
                          )
                        : session.checkout_time
                          ? new Date(
                              session.checkout_time
                            ).toLocaleString(
                              "en-IN"
                            )
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
                          disabled={
                            checkoutLoading
                          }
                          onClick={() =>
                            openSettlementModal(
                              session
                            )
                          }
                        >
                          {checkoutLoading
                            ? "Preparing..."
                            : "Final Bill & Checkout"}
                        </button>

                        <button
                          className="checkout-btn"
                          disabled={
                            checkoutLoading
                          }
                          style={{
                            background:
                              "#d4af37",
                            color: "#000",
                          }}
                          onClick={() =>
                            openExtendModal(
                              session
                            )
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
          <div style={smallModal}>
            <h2 style={modalTitle}>
              Extend Stay
            </h2>

            <p style={modalSub}>
              Select the new checkout date and time
              for this guest.
            </p>

            <label style={label}>
              New Checkout Date &amp; Time
            </label>

            <input
              type="datetime-local"
              value={extendDateTime}
              onChange={(event) =>
                setExtendDateTime(
                  event.target.value
                )
              }
              style={input}
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

      {settlementModalOpen &&
        settlementData && (
          <div style={modalOverlay}>
            <div style={settlementModal}>
              <div style={settlementHeader}>
                <div>
                  <p style={kicker}>
                    FINAL CHECKOUT
                  </p>

                  <h2 style={settlementTitle}>
                    Tax, Discount &amp;
                    Settlement
                  </h2>

                  <p style={modalSub}>
                    {
                      settlementData.guest
                        .full_name
                    }{" "}
                    · Room{" "}
                    {
                      settlementData.room
                        .room_number
                    }
                  </p>
                </div>

                <button
                  type="button"
                  style={modalCloseButton}
                  disabled={settlementLoading}
                  onClick={
                    closeSettlementModal
                  }
                >
                  ✕
                </button>
              </div>

              <div style={settlementGrid}>
                <div style={settlementSection}>
                  <h3 style={sectionTitle}>
                    Charge Breakdown
                  </h3>

                  <SettlementRow
                    label="Room Charges"
                    value={
                      settlementData.roomAmount
                    }
                  />

                  <SettlementRow
                    label="Food Charges"
                    value={
                      settlementData.foodAmount
                    }
                  />

                  <SettlementRow
                    label="Manual Charges"
                    value={
                      settlementData.manualAmount
                    }
                  />

                  <SettlementRow
                    label="Service Charges"
                    value={
                      settlementData.serviceAmount
                    }
                  />

                  <div style={divider} />

                  <SettlementRow
                    label="Subtotal"
                    value={
                      settlementCalculation.subtotal
                    }
                    strong
                  />

                  <div style={stayInfoBox}>
                    <span>
                      Stay duration
                    </span>

                    <strong>
                      {
                        settlementData.stayNights
                      }{" "}
                      night(s) ·{" "}
                      {
                        settlementData.stayHours
                      }{" "}
                      hour(s)
                    </strong>
                  </div>
                </div>

                <div style={settlementSection}>
                  <h3 style={sectionTitle}>
                    Tax &amp; Discount
                  </h3>

                  <label style={label}>
                    Tax / GST Percentage
                  </label>

                  <input
                    style={input}
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    value={taxPercent}
                    onChange={(event) =>
                      setTaxPercent(
                        event.target.value
                      )
                    }
                    placeholder="Example: 12"
                  />

                  <label style={label}>
                    Discount Type
                  </label>

                  <select
                    style={input}
                    value={discountType}
                    onChange={(event) =>
                      setDiscountType(
                        event.target.value
                      )
                    }
                  >
                    <option value="fixed">
                      Fixed Amount
                    </option>

                    <option value="percentage">
                      Percentage
                    </option>
                  </select>

                  <label style={label}>
                    {discountType ===
                    "percentage"
                      ? "Discount Percentage"
                      : "Discount Amount"}
                  </label>

                  <input
                    style={input}
                    type="number"
                    min="0"
                    max={
                      discountType ===
                      "percentage"
                        ? "100"
                        : undefined
                    }
                    step="0.01"
                    value={discountValue}
                    onChange={(event) =>
                      setDiscountValue(
                        event.target.value
                      )
                    }
                    placeholder={
                      discountType ===
                      "percentage"
                        ? "Example: 10"
                        : "Example: 500"
                    }
                  />

                  <label style={label}>
                    Invoice Notes
                  </label>

                  <textarea
                    style={textarea}
                    value={invoiceNotes}
                    onChange={(event) =>
                      setInvoiceNotes(
                        event.target.value
                      )
                    }
                    placeholder="Optional invoice or checkout notes"
                  />
                </div>
              </div>

              <div style={settlementSummary}>
                <SettlementRow
                  label="Subtotal"
                  value={
                    settlementCalculation.subtotal
                  }
                />

                <SettlementRow
                  label={`Tax (${formatMoney(
                    settlementCalculation.taxPercent
                  )}%)`}
                  value={
                    settlementCalculation.taxAmount
                  }
                />

                <SettlementRow
                  label="Discount"
                  value={
                    settlementCalculation.discountAmount
                  }
                  negative
                />

                <div style={divider} />

                <SettlementRow
                  label="Grand Total"
                  value={
                    settlementCalculation.grandTotal
                  }
                  strong
                />

                <SettlementRow
                  label="Previously Paid"
                  value={
                    settlementCalculation.previouslyPaid
                  }
                  positive
                />

                <SettlementRow
                  label="Remaining to Collect"
                  value={
                    settlementCalculation.amountToCollect
                  }
                  danger={
                    settlementCalculation.amountToCollect >
                    0
                  }
                  strong
                />

                {settlementCalculation.excessPaid >
                  0 && (
                  <div style={warningBox}>
                    Previous payments exceed the final
                    invoice by ₹
                    {formatMoney(
                      settlementCalculation.excessPaid
                    )}
                    . Verify refund or adjustment.
                  </div>
                )}
              </div>

              {settlementCalculation.amountToCollect >
                0 && (
                <label style={confirmationBox}>
                  <input
                    type="checkbox"
                    checked={
                      remainingPaymentCollected
                    }
                    onChange={(event) =>
                      setRemainingPaymentCollected(
                        event.target.checked
                      )
                    }
                  />

                  <span>
                    I confirm that the remaining ₹
                    {formatMoney(
                      settlementCalculation.amountToCollect
                    )}{" "}
                    has been collected from the guest.
                  </span>
                </label>
              )}

              {settlementCalculation.amountToCollect ===
                0 && (
                <div style={paidConfirmationBox}>
                  ✅ The invoice is already fully
                  covered by previous payments.
                </div>
              )}

              <div style={settlementActions}>
                <button
                  type="button"
                  style={cancelBtn}
                  disabled={settlementLoading}
                  onClick={
                    closeSettlementModal
                  }
                >
                  Cancel
                </button>

                <button
                  type="button"
                  style={saveBtn}
                  disabled={settlementLoading}
                  onClick={
                    completeFinalSettlement
                  }
                >
                  {settlementLoading
                    ? "Completing Checkout..."
                    : "Confirm Settlement & Checkout"}
                </button>
              </div>
            </div>
          </div>
        )}
    </div>
  );
}

function SettlementRow({
  label,
  value,
  strong = false,
  negative = false,
  positive = false,
  danger = false,
}) {
  return (
    <div
      style={{
        ...summaryRow,
        fontSize: strong ? "17px" : "14px",
        fontWeight: strong ? 900 : 600,
        color: positive
          ? "#2ecc71"
          : danger
            ? "#ff767b"
            : "#fff",
      }}
    >
      <span>{label}</span>

      <strong>
        {negative &&
        Number(value || 0) > 0
          ? "- "
          : ""}
        ₹
        {formatMoney(
          Math.abs(Number(value || 0))
        )}
      </strong>
    </div>
  );
}

function generateInvoiceNumber() {
  const now = new Date();

  const datePart = now
    .toISOString()
    .slice(0, 10)
    .replace(/-/g, "");

  const timePart = String(
    now.getTime()
  ).slice(-6);

  return `INV-${datePart}-${timePart}`;
}

function formatMoney(value) {
  const amount = Number(value || 0);

  return amount.toLocaleString("en-IN", {
    minimumFractionDigits:
      Number.isInteger(amount) ? 0 : 2,
    maximumFractionDigits: 2,
  });
}

const modalOverlay = {
  position: "fixed",
  inset: 0,
  zIndex: 9999,
  display: "flex",
  alignItems: "flex-start",
  justifyContent: "center",
  overflowY: "auto",
  padding: "30px 20px",
  background: "rgba(0,0,0,0.82)",
};

const smallModal = {
  width: "90%",
  maxWidth: "460px",
  padding: "28px",
  border: "1px solid #333",
  borderRadius: "18px",
  background: "#0f0f0f",
  color: "#fff",
};

const settlementModal = {
  width: "100%",
  maxWidth: "980px",
  padding: "28px",
  border: "1px solid #333",
  borderRadius: "20px",
  background: "#0f0f0f",
  color: "#fff",
  boxShadow: "0 30px 90px rgba(0,0,0,.6)",
};

const settlementHeader = {
  display: "flex",
  alignItems: "flex-start",
  justifyContent: "space-between",
  gap: "20px",
  marginBottom: "25px",
};

const kicker = {
  margin: "0 0 7px",
  color: "#d4af37",
  fontSize: "11px",
  fontWeight: 900,
  letterSpacing: "2px",
};

const settlementTitle = {
  margin: "0 0 7px",
  fontSize: "31px",
};

const modalTitle = {
  color: "#d4af37",
  fontSize: "28px",
  marginBottom: "8px",
};

const modalSub = {
  margin: 0,
  color: "#aaa",
};

const modalCloseButton = {
  width: "38px",
  height: "38px",
  border: "1px solid #444",
  borderRadius: "10px",
  background: "#1a1a1a",
  color: "#fff",
  cursor: "pointer",
};

const settlementGrid = {
  display: "grid",
  gridTemplateColumns:
    "repeat(auto-fit,minmax(300px,1fr))",
  gap: "20px",
};

const settlementSection = {
  padding: "20px",
  border: "1px solid #252525",
  borderRadius: "15px",
  background: "#0a0a0a",
};

const sectionTitle = {
  margin: "0 0 18px",
  color: "#d4af37",
  fontSize: "18px",
};

const label = {
  display: "block",
  marginBottom: "8px",
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: 800,
};

const input = {
  width: "100%",
  boxSizing: "border-box",
  marginBottom: "17px",
  padding: "13px",
  border: "1px solid #333",
  borderRadius: "10px",
  outline: "none",
  background: "#111",
  color: "#fff",
};

const textarea = {
  ...input,
  minHeight: "95px",
  resize: "vertical",
};

const stayInfoBox = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "15px",
  marginTop: "15px",
  padding: "13px",
  borderRadius: "10px",
  background: "rgba(212,175,55,.08)",
  color: "#d4af37",
  fontSize: "12px",
};

const settlementSummary = {
  width: "100%",
  maxWidth: "520px",
  boxSizing: "border-box",
  margin: "24px 0 0 auto",
  padding: "20px",
  border: "1px solid rgba(212,175,55,.3)",
  borderRadius: "15px",
  background: "rgba(212,175,55,.06)",
};

const summaryRow = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "20px",
  padding: "7px 0",
};

const divider = {
  height: "1px",
  margin: "10px 0",
  background: "#333",
};

const warningBox = {
  marginTop: "13px",
  padding: "12px",
  border: "1px solid rgba(255,170,0,.35)",
  borderRadius: "10px",
  background: "rgba(255,170,0,.08)",
  color: "#ffaa00",
  fontSize: "12px",
};

const confirmationBox = {
  display: "flex",
  alignItems: "flex-start",
  gap: "11px",
  marginTop: "20px",
  padding: "15px",
  border: "1px solid rgba(212,175,55,.35)",
  borderRadius: "12px",
  background: "rgba(212,175,55,.07)",
  color: "#fff",
  cursor: "pointer",
};

const paidConfirmationBox = {
  marginTop: "20px",
  padding: "15px",
  border: "1px solid rgba(46,204,113,.35)",
  borderRadius: "12px",
  background: "rgba(46,204,113,.1)",
  color: "#2ecc71",
  fontWeight: 800,
};

const settlementActions = {
  display: "flex",
  justifyContent: "flex-end",
  gap: "10px",
  marginTop: "22px",
};

const modalActions = {
  display: "flex",
  gap: "10px",
  justifyContent: "flex-end",
};

const saveBtn = {
  padding: "11px 17px",
  border: "none",
  borderRadius: "10px",
  background: "#d4af37",
  color: "#000",
  fontWeight: 800,
  cursor: "pointer",
};

const cancelBtn = {
  padding: "11px 17px",
  border: "1px solid #444",
  borderRadius: "10px",
  background: "#222",
  color: "#fff",
  cursor: "pointer",
};