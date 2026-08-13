import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { checkoutGuestSession } from "../../lib/day5Reservations";
import { notifyCalendarInvalidated } from "../../lib/bookingCalendar";
import GuestDirectory from "./GuestDirectory";
import "./Guests.css";

export default function Guests({
  initialGuestSessionId = null,
  navigationRequestId = null,
}) {
  const [sessions, setSessions] = useState([]);
  const [activeView, setActiveView] = useState("active");
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [focusedSessionId, setFocusedSessionId] = useState(null);
  const [checkoutLoadingId, setCheckoutLoadingId] =
    useState(null);

  const [moveModalOpen, setMoveModalOpen] =
    useState(false);
  const [moveLoading, setMoveLoading] =
    useState(false);
  const [moveSession, setMoveSession] =
    useState(null);
  const [moveRooms, setMoveRooms] =
    useState([]);
  const [moveTargetRoomId, setMoveTargetRoomId] =
    useState("");
  const [moveReason, setMoveReason] =
    useState("");
  const [moveRequestId, setMoveRequestId] =
    useState("");
  const [moveCurrentCharge, setMoveCurrentCharge] =
    useState(0);
  const [
    moveConfirmRateChange,
    setMoveConfirmRateChange,
  ] = useState(false);
  const [moveNewRoomCharge, setMoveNewRoomCharge] =
    useState("");

  const [extendModalOpen, setExtendModalOpen] =
    useState(false);
  const [extendLoading, setExtendLoading] =
    useState(false);
  const [selectedSession, setSelectedSession] =
    useState(null);
  const [extendCurrentCheckoutAt, setExtendCurrentCheckoutAt] =
    useState("");
  const [extendCurrentCheckoutLocal, setExtendCurrentCheckoutLocal] =
    useState("");
  const [extendDateTime, setExtendDateTime] =
    useState("");
  const [extendReason, setExtendReason] =
    useState("");
  const [extendRequestId, setExtendRequestId] =
    useState("");
  const [extendCurrentCharge, setExtendCurrentCharge] =
    useState(0);
  const [extendAdditionalCharge, setExtendAdditionalCharge] =
    useState("");
  const [extendConfirmCharge, setExtendConfirmCharge] =
    useState(false);

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
  const [settlementPaymentMethod, setSettlementPaymentMethod] = useState("cash");
  const [settlementTransactionReference, setSettlementTransactionReference] = useState("");
  const [notice, setNotice] = useState(null);
  const [
    remainingPaymentCollected,
    setRemainingPaymentCollected,
  ] = useState(false);

  const selectedMoveRoom = useMemo(
    () =>
      moveRooms.find(
        (room) => room.id === moveTargetRoomId
      ) || null,
    [moveRooms, moveTargetRoomId]
  );

  const isCrossTypeRoomMove =
    Boolean(
      moveSession?.rooms?.room_type_id &&
        selectedMoveRoom?.room_type_id &&
        moveSession.rooms.room_type_id !==
          selectedMoveRoom.room_type_id
    );

  useEffect(() => {
    initPage();
  }, []);

  useEffect(() => {
    if (!initialGuestSessionId || loading) return;

    setFocusedSessionId(initialGuestSessionId);
    const timer = window.setTimeout(() => {
      document
        .getElementById(`guest-session-${initialGuestSessionId}`)
        ?.scrollIntoView({ behavior: "smooth", block: "center" });
    }, 80);

    return () => window.clearTimeout(timer);
  }, [initialGuestSessionId, navigationRequestId, loading, sessions.length]);

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

    const sessionSelect = `
      *,
      guests (
        id,
        full_name,
        phone
      ),
      rooms (
        id,
        room_number,
        room_type,
        room_type_id
      )
    `;

    const { data, error } = await supabase
      .from("guest_sessions")
      .select(sessionSelect)
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

    let visibleSessions = data || [];

    if (
      initialGuestSessionId &&
      !visibleSessions.some((session) => session.id === initialGuestSessionId)
    ) {
      const { data: requestedSession, error: requestedSessionError } = await supabase
        .from("guest_sessions")
        .select(sessionSelect)
        .eq("hotel_id", hotelId)
        .eq("id", initialGuestSessionId)
        .maybeSingle();

      if (requestedSessionError) {
        console.error("Focused guest stay error:", requestedSessionError);
      } else if (requestedSession) {
        visibleSessions = [requestedSession, ...visibleSessions];
      }
    }

    setSessions(visibleSessions);
    setLoading(false);
  }

  function createStayExtensionRequestId() {
    if (globalThis.crypto?.randomUUID) {
      return globalThis.crypto.randomUUID();
    }

    return `extend-${Date.now()}-${Math.random()
      .toString(16)
      .slice(2)}`;
  }

  function resetExtendState() {
    setExtendModalOpen(false);
    setExtendLoading(false);
    setSelectedSession(null);
    setExtendCurrentCheckoutAt("");
    setExtendCurrentCheckoutLocal("");
    setExtendDateTime("");
    setExtendReason("");
    setExtendRequestId("");
    setExtendCurrentCharge(0);
    setExtendAdditionalCharge("");
    setExtendConfirmCharge(false);
  }

  async function openExtendModal(session) {
    if (
      session.reservation_id ||
      session.reservation_room_id
    ) {
      showNotice(
        "error",
        "Reservation-linked stays must use the reservation modification workflow."
      );
      return;
    }

    if (
      session.status !== "active" ||
      !session.room_id ||
      !session.rooms?.id
    ) {
      showNotice(
        "error",
        "Only an active direct stay with a physical room can be extended."
      );
      return;
    }

    const currentCheckoutAt =
      session.extended_until ||
      session.checkout_time;

    if (!currentCheckoutAt) {
      showNotice(
        "error",
        "The active stay has no checkout time."
      );
      return;
    }

    const hotelTimeZone =
      currentHotel?.timezone ||
      Intl.DateTimeFormat().resolvedOptions()
        .timeZone ||
      "UTC";

    setSelectedSession(session);
    setExtendLoading(true);

    try {
      const { data: roomCharge, error: chargeError } =
        await supabase
          .from("payments")
          .select("id, amount, payment_status")
          .eq("hotel_id", session.hotel_id)
          .eq("guest_session_id", session.id)
          .eq("payment_type", "room_charge")
          .limit(1)
          .maybeSingle();

      if (chargeError) throw chargeError;
      if (!roomCharge) {
        throw new Error(
          "The active stay room-charge record is missing."
        );
      }

      const currentCheckoutDate = new Date(
        currentCheckoutAt
      );

      if (
        Number.isNaN(
          currentCheckoutDate.getTime()
        )
      ) {
        throw new Error(
          "The active stay checkout time is invalid."
        );
      }

      const defaultNewCheckoutAt = new Date(
        currentCheckoutDate.getTime() +
          24 * 60 * 60 * 1000
      ).toISOString();

      setExtendCurrentCheckoutAt(
        currentCheckoutAt
      );
      setExtendCurrentCheckoutLocal(
        formatDateTimeLocalInTimeZone(
          currentCheckoutAt,
          hotelTimeZone
        )
      );
      setExtendDateTime(
        formatDateTimeLocalInTimeZone(
          defaultNewCheckoutAt,
          hotelTimeZone
        )
      );
      setExtendReason("");
      setExtendRequestId(
        createStayExtensionRequestId()
      );
      setExtendCurrentCharge(
        Number(roomCharge.amount || 0)
      );
      setExtendAdditionalCharge("");
      setExtendConfirmCharge(false);
      setExtendModalOpen(true);
    } catch (error) {
      setSelectedSession(null);
      console.error(
        "Prepare stay extension error:",
        error
      );
      showNotice(
        "error",
        error.message ||
          "Unable to prepare the stay extension."
      );
    } finally {
      setExtendLoading(false);
    }
  }

  function closeExtendModal() {
    if (extendLoading) return;
    resetExtendState();
  }

  async function handleExtendStay() {
    if (
      !selectedSession ||
      !extendCurrentCheckoutAt ||
      !extendDateTime
    ) {
      showNotice(
        "error",
        "Select a valid new checkout date and time."
      );
      return;
    }

    if (extendReason.trim().length < 3) {
      showNotice(
        "error",
        "Enter an extension reason of at least 3 characters."
      );
      return;
    }

    const parsedAdditionalCharge = Number(
      extendAdditionalCharge
    );

    if (
      !Number.isFinite(parsedAdditionalCharge) ||
      parsedAdditionalCharge < 0
    ) {
      showNotice(
        "error",
        "Enter a valid non-negative additional room charge."
      );
      return;
    }

    if (!extendConfirmCharge) {
      showNotice(
        "error",
        "Confirm the additional room charge before extending the stay."
      );
      return;
    }

    const hotelTimeZone =
      currentHotel?.timezone ||
      Intl.DateTimeFormat().resolvedOptions()
        .timeZone ||
      "UTC";

    let newCheckoutAt;

    try {
      newCheckoutAt =
        zonedDateTimeLocalToISOString(
          extendDateTime,
          hotelTimeZone
        );
    } catch (error) {
      showNotice(
        "error",
        error.message ||
          "The new checkout time is invalid for the hotel timezone."
      );
      return;
    }

    if (
      new Date(newCheckoutAt).getTime() <=
      new Date(extendCurrentCheckoutAt).getTime()
    ) {
      showNotice(
        "error",
        "The new checkout must be later than the current checkout."
      );
      return;
    }

    setExtendLoading(true);

    try {
      const { data, error } = await supabase.rpc(
        "extend_active_walkin_guest_stay",
        {
          target_hotel_id:
            selectedSession.hotel_id,
          target_guest_session_id:
            selectedSession.id,
          payload: {
            request_id: extendRequestId,
            expected_checkout_at:
              extendCurrentCheckoutAt,
            new_checkout_at: newCheckoutAt,
            additional_room_charge:
              parsedAdditionalCharge,
            confirm_room_charge:
              extendConfirmCharge,
            extension_reason:
              extendReason.trim(),
            source: "guests_active_stays",
            workflow:
              "day10_atomic_active_stay_extension",
          },
        }
      );

      if (error) throw error;

      notifyCalendarInvalidated({
        reason: "active_stay_extended",
        guestSessionId: selectedSession.id,
      });

      const roomNumber =
        data?.room_number ||
        selectedSession.rooms?.room_number ||
        "-";
      const finalCharge = Number(
        data?.room_charge?.current_amount ??
          extendCurrentCharge +
            parsedAdditionalCharge
      );
      const finalCheckout =
        data?.new_checkout_at ||
        newCheckoutAt;
      const wasIdempotent =
        data?.idempotent === true;

      resetExtendState();
      await fetchGuests(currentHotel?.id);

      showNotice(
        "success",
        wasIdempotent
          ? `Stay-extension request already applied for Room ${roomNumber}. Checkout remains ${formatDateTimeInTimeZone(
              finalCheckout,
              hotelTimeZone
            )}; room charge ₹${formatMoney(
              finalCharge
            )}.`
          : `Stay in Room ${roomNumber} extended to ${formatDateTimeInTimeZone(
              finalCheckout,
              hotelTimeZone
            )}. Room charge is now ₹${formatMoney(
              finalCharge
            )}.`
      );
    } catch (error) {
      console.error("Extend stay error:", error);
      showNotice(
        "error",
        error.message ||
          "The active stay could not be extended."
      );

      await fetchGuests(currentHotel?.id);
    } finally {
      setExtendLoading(false);
    }
  }

  function createRoomMoveRequestId() {
    if (globalThis.crypto?.randomUUID) {
      return globalThis.crypto.randomUUID();
    }

    return `move-${Date.now()}-${Math.random()
      .toString(16)
      .slice(2)}`;
  }

  function closeMoveModal() {
    if (moveLoading) return;

    setMoveModalOpen(false);
    setMoveSession(null);
    setMoveRooms([]);
    setMoveTargetRoomId("");
    setMoveReason("");
    setMoveRequestId("");
    setMoveCurrentCharge(0);
    setMoveConfirmRateChange(false);
    setMoveNewRoomCharge("");
  }

  async function openMoveModal(session) {
    if (
      session.reservation_id ||
      session.reservation_room_id
    ) {
      showNotice(
        "error",
        "Reservation-linked stays must use the reservation room workflow."
      );
      return;
    }

    if (
      session.status !== "active" ||
      !session.room_id ||
      !session.rooms?.id
    ) {
      showNotice(
        "error",
        "Only an active stay with a physical room can be moved."
      );
      return;
    }

    setMoveLoading(true);
    setMoveSession(session);

    try {
      const [
        { data: availableRooms, error: roomsError },
        { data: roomCharge, error: chargeError },
      ] = await Promise.all([
        supabase
          .from("rooms")
          .select(
            "id, room_number, room_type, room_type_id, status"
          )
          .eq("hotel_id", session.hotel_id)
          .eq("status", "available")
          .neq("id", session.room_id)
          .order("room_number"),
        supabase
          .from("payments")
          .select("id, amount, payment_status")
          .eq("hotel_id", session.hotel_id)
          .eq("guest_session_id", session.id)
          .eq("payment_type", "room_charge")
          .limit(1)
          .maybeSingle(),
      ]);

      if (roomsError) throw roomsError;
      if (chargeError) throw chargeError;

      setMoveRooms(availableRooms || []);
      setMoveTargetRoomId("");
      setMoveReason("");
      setMoveRequestId(createRoomMoveRequestId());
      setMoveCurrentCharge(
        Number(roomCharge?.amount || 0)
      );
      setMoveConfirmRateChange(false);
      setMoveNewRoomCharge(
        String(Number(roomCharge?.amount || 0))
      );
      setMoveModalOpen(true);
    } catch (error) {
      setMoveSession(null);
      console.error("Prepare room move error:", error);
      showNotice(
        "error",
        error.message ||
          "Unable to prepare the room move."
      );
    } finally {
      setMoveLoading(false);
    }
  }

  async function handleMoveRoom() {
    if (
      !moveSession ||
      !selectedMoveRoom ||
      !moveTargetRoomId
    ) {
      showNotice(
        "error",
        "Select an available target room."
      );
      return;
    }

    if (moveReason.trim().length < 3) {
      showNotice(
        "error",
        "Enter a room-move reason of at least 3 characters."
      );
      return;
    }

    if (
      isCrossTypeRoomMove &&
      !moveConfirmRateChange
    ) {
      showNotice(
        "error",
        "Confirm the rate change for this room-type change."
      );
      return;
    }

    const parsedNewCharge = Number(
      moveNewRoomCharge
    );

    if (
      isCrossTypeRoomMove &&
      (!Number.isFinite(parsedNewCharge) ||
        parsedNewCharge < 0)
    ) {
      showNotice(
        "error",
        "Enter a valid non-negative room charge."
      );
      return;
    }

    setMoveLoading(true);

    try {
      const { data, error } = await supabase.rpc(
        "move_active_walkin_guest_room",
        {
          target_hotel_id: moveSession.hotel_id,
          target_guest_session_id: moveSession.id,
          target_room_id: moveTargetRoomId,
          payload: {
            request_id: moveRequestId,
            expected_from_room_id:
              moveSession.room_id,
            move_reason: moveReason.trim(),
            effective_at: new Date().toISOString(),
            confirm_rate_change:
              isCrossTypeRoomMove
                ? moveConfirmRateChange
                : false,
            new_room_charge:
              isCrossTypeRoomMove
                ? parsedNewCharge
                : null,
            source: "guests_active_stays",
            workflow:
              "day10_atomic_active_room_move",
          },
        }
      );

      if (error) throw error;

      notifyCalendarInvalidated({
        reason: "active_stay_room_moved",
        guestSessionId: moveSession.id,
      });

      const fromRoom =
        data?.from_room?.room_number ||
        moveSession.rooms?.room_number ||
        "-";
      const toRoom =
        data?.to_room?.room_number ||
        selectedMoveRoom.room_number ||
        "-";
      const finalCharge = Number(
        data?.room_charge?.current_amount ??
          moveCurrentCharge
      );

      setMoveModalOpen(false);
      setMoveSession(null);
      setMoveRooms([]);
      setMoveTargetRoomId("");
      setMoveReason("");
      setMoveRequestId("");
      setMoveCurrentCharge(0);
      setMoveConfirmRateChange(false);
      setMoveNewRoomCharge("");

      await fetchGuests(currentHotel?.id);

      showNotice(
        "success",
        `Stay moved from Room ${fromRoom} to Room ${toRoom}. Room charge ₹${formatMoney(
          finalCharge
        )}; old room queued for cleaning.`
      );
    } catch (error) {
      console.error("Room move error:", error);
      showNotice(
        "error",
        error.message ||
          "The active stay could not be moved."
      );

      await fetchGuests(currentHotel?.id);
    } finally {
      setMoveLoading(false);
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
    setSettlementPaymentMethod("cash");
    setSettlementTransactionReference("");
    setRemainingPaymentCollected(false);
  }

  function closeSettlementModal() {
    if (settlementLoading) return;
    resetSettlementState();
  }

  function showNotice(type, message) {
    setNotice({ type, message });
    window.setTimeout(() => {
      setNotice((current) =>
        current?.message === message ? null : current
      );
    }, 6500);
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
        .eq("room_id", room.id)
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
       * Day 20 checkout:
       * Existing immutable invoices are validated and safely reused by the
       * authoritative checkout RPC. Do not block checkout client-side.
       */

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
        .eq("room_id", room.id)
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

      const legacyCheckoutPaidAmount =
        collectionPaidAmount + legacyPaidAmount;

      // DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1
      // Folio & Settlement is authoritative for direct/split collections.
      const {
        data: checkoutFolio,
        error: checkoutFolioError,
      } = await supabase
        .from("folios")
        .select("collection_amount, balance_amount")
        .eq("hotel_id", session.hotel_id)
        .eq("guest_session_id", session.id)
        .maybeSingle();

      if (checkoutFolioError) throw checkoutFolioError;

      const previouslyPaidAmount = Math.max(
        legacyCheckoutPaidAmount,
        Number(checkoutFolio?.collection_amount || 0)
      );

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
        .eq("room_id", room.id)
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
        .eq("room_id", room.id)
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
        .eq("room_id", room.id)
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

    const rawDiscountAmount =
      discountType === "percentage"
        ? (subtotal + taxAmount) *
          (Math.min(100, safeDiscountValue) / 100)
        : safeDiscountValue;

    const amountBeforeDiscount =
      subtotal + taxAmount;

    const discountAmount = Math.min(
      amountBeforeDiscount,
      rawDiscountAmount
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

    const { session } = settlementData;
    const {
      taxPercent: finalTaxPercent,
      discountValue: finalDiscountValue,
      amountToCollect,
      excessPaid,
    } = settlementCalculation;

    if (Number(taxPercent || 0) < 0 || Number(taxPercent || 0) > 100) {
      showNotice("error", "Tax percentage must be between 0 and 100.");
      return;
    }

    if (Number(discountValue || 0) < 0) {
      showNotice("error", "Discount value cannot be negative.");
      return;
    }

    if (
      discountType === "percentage" &&
      Number(discountValue || 0) > 100
    ) {
      showNotice("error", "Discount percentage cannot exceed 100%.");
      return;
    }

    if (
      ["upi", "card", "bank_transfer"].includes(
        settlementPaymentMethod
      ) &&
      !settlementTransactionReference.trim()
    ) {
      showNotice(
        "error",
        "Enter the transaction/reference number for the selected payment method."
      );
      return;
    }

    if (amountToCollect > 0 && !remainingPaymentCollected) {
      showNotice(
        "error",
        `Confirm collection of the remaining ₹${formatMoney(
          amountToCollect
        )} before checkout.`
      );
      return;
    }

    let allowExcessPaid = false;

    if (excessPaid > 0) {
      allowExcessPaid = window.confirm(
        `Previous payments exceed the final bill by ₹${formatMoney(
          excessPaid
        )}.\n\nPlease verify whether a refund or adjustment is required. Continue checkout?`
      );

      if (!allowExcessPaid) return;
    }

    setSettlementLoading(true);
    setCheckoutLoadingId(session.id);

    try {
      const result = await checkoutGuestSession({
        hotelId: session.hotel_id,
        guestSessionId: session.id,
        taxPercent: finalTaxPercent,
        discountType,
        discountValue: finalDiscountValue,
        remainingPaymentCollected,
        settlementPaymentMethod,
        settlementTransactionReference,
        invoiceNotes,
        allowExcessPaid,
      });

      notifyCalendarInvalidated({
        reason: "reservation_checked_out",
        reservationId: result.reservation_id || session.reservation_id,
      });

      showNotice(
        "success",
        `Checkout completed. Invoice ${result.invoice_number}. Final total ₹${formatMoney(
          result.grand_total
        )}; collected at checkout ₹${formatMoney(
          result.amount_collected_at_checkout
        )}. Room ${result.room_number} is now queued for cleaning.`
      );

      resetSettlementState();
      await fetchGuests(currentHotel?.id);
    } catch (error) {
      console.error("Final settlement error:", error);
      showNotice(
        "error",
        error.message || "Final checkout failed"
      );
      await fetchGuests(currentHotel?.id);
    } finally {
      setSettlementLoading(false);
      setCheckoutLoadingId(null);
    }
  }

  return (
    <div className="rooms-page">
      {notice && (
        <div className={`guests-toast ${notice.type}`} role="status">
          {notice.message}
        </div>
      )}
      <div className="rooms-header guests-page-header">
        <div>
          <h1>Guests</h1>

          <p>
            {currentHotel?.hotel_name || "Hotel"} ·
            Active stays, repeat-guest history, identity, notes, preferences and private KYC metadata.
          </p>
        </div>

        {activeView === "active" && (
          <button onClick={() => fetchGuests(currentHotel?.id)}>
            Refresh active stays
          </button>
        )}
      </div>

      <div className="guests-view-tabs" role="tablist" aria-label="Guest views">
        <button
          type="button"
          className={activeView === "active" ? "active" : ""}
          onClick={() => setActiveView("active")}
        >
          Active stays <span>{sessions.length}</span>
        </button>
        <button
          type="button"
          className={activeView === "directory" ? "active" : ""}
          onClick={() => setActiveView("directory")}
        >
          Guest directory & history
        </button>
      </div>

      {activeView === "directory" ? (
        <GuestDirectory currentHotel={currentHotel} onNotice={showNotice} />
      ) : (
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
                <th>Status</th>
                <th>Action</th>
              </tr>
            </thead>

            <tbody>
              {sessions.map((session) => {
                const checkoutLoading =
                  checkoutLoadingId ===
                  session.id;

                return (
                  <tr
                    key={session.id}
                    id={`guest-session-${session.id}`}
                    className={
                      focusedSessionId === session.id
                        ? "guest-session-focused"
                        : ""
                    }
                  >
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
                      <span className={`guest-session-status ${session.status || "unknown"}`}>
                        {String(session.status || "unknown")
                          .replace(/_/g, " ")
                          .replace(/\b\w/g, (character) => character.toUpperCase())}
                      </span>
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

                        {!session.reservation_id &&
                          !session.reservation_room_id && (
                          <button
                            className="checkout-btn guest-move-btn"
                            disabled={
                              checkoutLoading ||
                              moveLoading
                            }
                            onClick={() =>
                              openMoveModal(session)
                            }
                          >
                            {moveLoading &&
                            moveSession?.id ===
                              session.id
                              ? "Preparing..."
                              : "Move Room"}
                          </button>
                        )}

                        {!session.reservation_id &&
                          !session.reservation_room_id && (
                          <button
                            className="checkout-btn"
                            disabled={
                              checkoutLoading ||
                              moveLoading ||
                              extendLoading
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
                            {extendLoading &&
                            selectedSession?.id ===
                              session.id
                              ? "Preparing..."
                              : "Extend Stay"}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
      )}

      {moveModalOpen && moveSession && (
        <div style={modalOverlay}>
          <div style={roomMoveModal}>
            <div style={settlementHeader}>
              <div>
                <p style={kicker}>
                  AUTHORITATIVE ACTIVE-STAY ACTION
                </p>
                <h2 style={settlementTitle}>
                  Move Room
                </h2>
                <p style={modalSub}>
                  {moveSession.guests?.full_name ||
                    "Active guest"}{" "}
                  · Room{" "}
                  {moveSession.rooms?.room_number ||
                    "-"}
                </p>
              </div>

              <button
                type="button"
                style={modalCloseButton}
                disabled={moveLoading}
                onClick={closeMoveModal}
              >
                ✕
              </button>
            </div>

            <div className="guest-move-summary">
              <div>
                <span>Current room</span>
                <strong>
                  Room{" "}
                  {moveSession.rooms?.room_number ||
                    "-"}
                </strong>
                <small>
                  {moveSession.rooms?.room_type ||
                    "Room"}
                </small>
              </div>

              <div>
                <span>Current room charge</span>
                <strong>
                  ₹{formatMoney(moveCurrentCharge)}
                </strong>
                <small>
                  Same-type moves preserve this
                  amount.
                </small>
              </div>

              <div>
                <span>Effective checkout</span>
                <strong>
                  {new Date(
                    moveSession.extended_until ||
                      moveSession.checkout_time
                  ).toLocaleString("en-IN")}
                </strong>
                <small>
                  Availability is validated for the
                  remaining stay.
                </small>
              </div>
            </div>

            <label style={label}>
              Available target room
            </label>
            <select
              style={input}
              value={moveTargetRoomId}
              onChange={(event) => {
                setMoveTargetRoomId(
                  event.target.value
                );
                setMoveConfirmRateChange(false);
                setMoveNewRoomCharge(
                  String(moveCurrentCharge)
                );
              }}
              disabled={moveLoading}
            >
              <option value="">
                Select target room
              </option>
              {moveRooms.map((room) => (
                <option
                  key={room.id}
                  value={room.id}
                >
                  Room {room.room_number}
                  {room.room_type
                    ? ` · ${room.room_type}`
                    : ""}
                </option>
              ))}
            </select>

            {moveRooms.length === 0 && (
              <div style={warningBox}>
                No available target rooms were found.
                Refresh the active-stay list and try
                again.
              </div>
            )}

            {selectedMoveRoom && (
              <div
                className={`guest-move-rate-box ${
                  isCrossTypeRoomMove
                    ? "rate-change"
                    : "rate-preserved"
                }`}
              >
                <strong>
                  Room{" "}
                  {selectedMoveRoom.room_number}
                </strong>
                <span>
                  {selectedMoveRoom.room_type ||
                    "Room"}
                </span>

                {isCrossTypeRoomMove ? (
                  <p>
                    The selected room type differs from
                    the current room. A confirmed new
                    charge is required.
                  </p>
                ) : (
                  <p>
                    Same room type. The existing ₹
                    {formatMoney(moveCurrentCharge)}{" "}
                    room charge will be preserved.
                  </p>
                )}
              </div>
            )}

            {isCrossTypeRoomMove && (
              <>
                <label style={label}>
                  Confirmed new room charge
                </label>
                <input
                  style={input}
                  type="number"
                  min="0"
                  step="0.01"
                  value={moveNewRoomCharge}
                  onChange={(event) =>
                    setMoveNewRoomCharge(
                      event.target.value
                    )
                  }
                  disabled={moveLoading}
                />

                <label style={confirmationBox}>
                  <input
                    type="checkbox"
                    checked={moveConfirmRateChange}
                    onChange={(event) =>
                      setMoveConfirmRateChange(
                        event.target.checked
                      )
                    }
                    disabled={moveLoading}
                  />
                  <span>
                    I confirm the room-type and charge
                    change for this active stay.
                  </span>
                </label>
              </>
            )}

            <label style={label}>
              Operational reason
            </label>
            <textarea
              style={textarea}
              value={moveReason}
              onChange={(event) =>
                setMoveReason(event.target.value)
              }
              placeholder="Example: Guest requested a quieter room."
              disabled={moveLoading}
            />

            <div className="guest-move-request">
              <span>Idempotency request</span>
              <code>{moveRequestId}</code>
            </div>

            <div style={modalActions}>
              <button
                type="button"
                style={cancelBtn}
                disabled={moveLoading}
                onClick={closeMoveModal}
              >
                Cancel
              </button>

              <button
                type="button"
                style={{
                  ...saveBtn,
                  opacity:
                    moveLoading ||
                    !moveTargetRoomId ||
                    moveReason.trim().length < 3
                      ? 0.55
                      : 1,
                }}
                disabled={
                  moveLoading ||
                  !moveTargetRoomId ||
                  moveReason.trim().length < 3 ||
                  (isCrossTypeRoomMove &&
                    !moveConfirmRateChange)
                }
                onClick={handleMoveRoom}
              >
                {moveLoading
                  ? "Moving stay..."
                  : "Confirm room move"}
              </button>
            </div>
          </div>
        </div>
      )}

      {extendModalOpen && selectedSession && (
        <div style={modalOverlay}>
          <div style={stayExtensionModal}>
            <div style={settlementHeader}>
              <div>
                <p style={kicker}>
                  AUTHORITATIVE ACTIVE-STAY ACTION
                </p>
                <h2 style={settlementTitle}>
                  Extend Stay
                </h2>
                <p style={modalSub}>
                  {selectedSession.guests?.full_name ||
                    "Active guest"}{" "}
                  · Room{" "}
                  {selectedSession.rooms?.room_number ||
                    "-"}
                </p>
              </div>

              <button
                type="button"
                style={modalCloseButton}
                disabled={extendLoading}
                onClick={closeExtendModal}
              >
                ✕
              </button>
            </div>

            <div className="guest-extension-summary">
              <div>
                <span>Current checkout</span>
                <strong>
                  {formatDateTimeInTimeZone(
                    extendCurrentCheckoutAt,
                    currentHotel?.timezone ||
                      Intl.DateTimeFormat()
                        .resolvedOptions()
                        .timeZone ||
                      "UTC"
                  )}
                </strong>
                <small>
                  Hotel timezone:{" "}
                  {currentHotel?.timezone ||
                    Intl.DateTimeFormat()
                      .resolvedOptions()
                      .timeZone ||
                    "UTC"}
                </small>
              </div>

              <div>
                <span>Current room charge</span>
                <strong>
                  ₹{formatMoney(extendCurrentCharge)}
                </strong>
                <small>
                  Additional charge is added to the
                  same room-charge record.
                </small>
              </div>

              <div>
                <span>Room protection</span>
                <strong>
                  Room{" "}
                  {selectedSession.rooms?.room_number ||
                    "-"}
                </strong>
                <small>
                  Server validates availability for
                  the requested extension period.
                </small>
              </div>
            </div>

            <div className="guest-extension-grid">
              <div>
                <label style={label}>
                  New checkout date &amp; time
                </label>
                <input
                  type="datetime-local"
                  value={extendDateTime}
                  min={extendCurrentCheckoutLocal}
                  onChange={(event) =>
                    setExtendDateTime(
                      event.target.value
                    )
                  }
                  style={input}
                  disabled={extendLoading}
                />
              </div>

              <div>
                <label style={label}>
                  Additional room charge
                </label>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={extendAdditionalCharge}
                  onChange={(event) =>
                    setExtendAdditionalCharge(
                      event.target.value
                    )
                  }
                  placeholder="Enter confirmed amount"
                  style={input}
                  disabled={extendLoading}
                />
              </div>
            </div>

            <div className="guest-extension-charge-box">
              <div>
                <span>Current</span>
                <strong>
                  ₹{formatMoney(extendCurrentCharge)}
                </strong>
              </div>
              <div>
                <span>Additional</span>
                <strong>
                  ₹{formatMoney(
                    Number(extendAdditionalCharge || 0)
                  )}
                </strong>
              </div>
              <div>
                <span>Projected room charge</span>
                <strong>
                  ₹{formatMoney(
                    extendCurrentCharge +
                      Number(
                        extendAdditionalCharge || 0
                      )
                  )}
                </strong>
              </div>
            </div>

            <label style={label}>
              Operational reason
            </label>
            <textarea
              style={textarea}
              value={extendReason}
              onChange={(event) =>
                setExtendReason(event.target.value)
              }
              placeholder="Example: Guest requested one additional night."
              disabled={extendLoading}
            />

            <label style={confirmationBox}>
              <input
                type="checkbox"
                checked={extendConfirmCharge}
                onChange={(event) =>
                  setExtendConfirmCharge(
                    event.target.checked
                  )
                }
                disabled={extendLoading}
              />
              <span>
                I confirm the new checkout and the
                additional room charge for this active
                stay.
              </span>
            </label>

            <div className="guest-extension-request">
              <span>Idempotency request</span>
              <code>{extendRequestId}</code>
            </div>

            <div style={modalActions}>
              <button
                type="button"
                style={cancelBtn}
                disabled={extendLoading}
                onClick={closeExtendModal}
              >
                Cancel
              </button>

              <button
                type="button"
                style={{
                  ...saveBtn,
                  opacity:
                    extendLoading ||
                    !extendDateTime ||
                    extendReason.trim().length < 3 ||
                    !extendConfirmCharge ||
                    extendAdditionalCharge === ""
                      ? 0.55
                      : 1,
                }}
                disabled={
                  extendLoading ||
                  !extendDateTime ||
                  extendReason.trim().length < 3 ||
                  !extendConfirmCharge ||
                  extendAdditionalCharge === ""
                }
                onClick={handleExtendStay}
              >
                {extendLoading
                  ? "Extending stay..."
                  : "Confirm stay extension"}
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
                <div style={settlementCollectionBox}>
                  <label style={label}>Final Payment Method</label>
                  <select
                    style={input}
                    value={settlementPaymentMethod}
                    onChange={(event) =>
                      setSettlementPaymentMethod(event.target.value)
                    }
                  >
                    <option value="cash">Cash</option>
                    <option value="upi">UPI</option>
                    <option value="card">Card</option>
                    <option value="bank_transfer">Bank Transfer</option>
                    <option value="other">Other</option>
                  </select>

                  {["upi", "card", "bank_transfer"].includes(
                    settlementPaymentMethod
                  ) && (
                    <>
                      <label style={label}>Transaction / Reference Number</label>
                      <input
                        style={input}
                        type="text"
                        value={settlementTransactionReference}
                        onChange={(event) =>
                          setSettlementTransactionReference(event.target.value)
                        }
                        placeholder="Required for this payment method"
                      />
                    </>
                  )}
                </div>
              )}

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

function getTimeZoneDateParts(value, timeZone) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error("Invalid date value.");
  }

  const parts = new Intl.DateTimeFormat(
    "en-CA",
    {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }
  ).formatToParts(date);

  return Object.fromEntries(
    parts
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value])
  );
}

function formatDateTimeLocalInTimeZone(
  value,
  timeZone
) {
  const parts = getTimeZoneDateParts(
    value,
    timeZone
  );

  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

function formatDateTimeInTimeZone(
  value,
  timeZone
) {
  if (!value) return "-";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return new Intl.DateTimeFormat("en-IN", {
    timeZone,
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(date);
}

function zonedDateTimeLocalToISOString(
  localValue,
  timeZone
) {
  const match = String(localValue).match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/
  );

  if (!match) {
    throw new Error(
      "Select a complete checkout date and time."
    );
  }

  const [
    ,
    year,
    month,
    day,
    hour,
    minute,
  ] = match.map(Number);

  const requestedWallClock = Date.UTC(
    year,
    month - 1,
    day,
    hour,
    minute,
    0,
    0
  );

  let candidate = requestedWallClock;

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const parts = getTimeZoneDateParts(
      new Date(candidate),
      timeZone
    );
    const renderedWallClock = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
      0,
      0
    );

    candidate +=
      requestedWallClock - renderedWallClock;
  }

  const result = new Date(candidate).toISOString();

  if (
    formatDateTimeLocalInTimeZone(
      result,
      timeZone
    ) !== localValue
  ) {
    throw new Error(
      "The selected checkout time does not exist in the hotel timezone."
    );
  }

  return result;
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

const stayExtensionModal = {
  width: "100%",
  maxWidth: "820px",
  padding: "28px",
  border: "1px solid #333",
  borderRadius: "20px",
  background: "#0f0f0f",
  color: "#fff",
  boxShadow: "0 30px 90px rgba(0,0,0,.6)",
};

const roomMoveModal = {
  width: "100%",
  maxWidth: "760px",
  padding: "28px",
  border: "1px solid #333",
  borderRadius: "20px",
  background: "#0f0f0f",
  color: "#fff",
  boxShadow: "0 30px 90px rgba(0,0,0,.6)",
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

const settlementCollectionBox = {
  marginTop: "16px",
  padding: "16px",
  border: "1px solid #333",
  borderRadius: "14px",
  background: "rgba(255,255,255,.025)",
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