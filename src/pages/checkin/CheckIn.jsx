import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { navigateToSection } from "../../lib/bookingCalendar";
import { recordGuestDocumentExtraction } from "../../lib/guestCompliance";
import SimpleGuestIdCapture from "../../components/guests/SimpleGuestIdCapture";
import "./CheckIn.css";

const EMPTY_GUEST = {
  full_name: "",
  phone: "",
  email: "",
  id_type: "",
  id_number: "",
  date_of_birth: "",
  gender: "",
  nationality: "Indian",
  country_of_residence: "India",
  address_line1: "",
  address_line2: "",
  city: "",
  state_region: "",
  postal_code: "",
  preferred_language: "english",
  purpose_of_visit: "",
  is_foreign_guest: false,
};

const EMPTY_STAY_DETAILS = {
  purpose_of_visit: "",
  arrival_from: "",
  next_destination: "",
  arrival_mode: "",
  arrival_transport_number: "",
  departure_mode: "",
  departure_transport_number: "",
  passport_number: "",
  passport_issue_country: "",
  passport_issued_on: "",
  passport_expires_on: "",
  visa_number: "",
  visa_type: "",
  visa_issue_place: "",
  visa_issued_on: "",
  visa_expires_on: "",
  date_of_arrival_in_india: "",
  intended_duration_in_india_days: "",
  form_c_status: "not_required",
  early_checkin: false,
  late_checkout: false,
  special_notes: "",
};

const createCompanion = () => ({
  client_id: createRequestId(),
  full_name: "",
  phone: "",
  email: "",
  id_type: "",
  id_number: "",
  relationship: "",
  guest_category: "adult",
  form_c_required: false,
});

function createRequestId() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }

  return `walkin-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function toLocalDateTimeInput(date) {
  const pad = (value) => String(value).padStart(2, "0");

  return [
    date.getFullYear(),
    "-",
    pad(date.getMonth() + 1),
    "-",
    pad(date.getDate()),
    "T",
    pad(date.getHours()),
    ":",
    pad(date.getMinutes()),
  ].join("");
}

function getDefaultTimes() {
  const checkin = new Date();
  checkin.setSeconds(0, 0);

  const checkout = new Date(checkin);
  checkout.setDate(checkout.getDate() + 1);
  checkout.setHours(11, 0, 0, 0);

  return {
    checkinTime: toLocalDateTimeInput(checkin),
    checkoutTime: toLocalDateTimeInput(checkout),
  };
}

function normalizePhone(value) {
  const digits = String(value || "").replace(/[^0-9]/g, "");
  return digits || null;
}

function normalizeEmail(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return normalized || null;
}

function normalizeIdType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return normalized || null;
}

function normalizeIdNumber(value) {
  const normalized = String(value || "")
    .replace(/[^A-Za-z0-9]/g, "")
    .toUpperCase();
  return normalized || null;
}

function compactObject(value) {
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== "" && item !== null)
  );
}

const GUEST_DOCUMENT_BUCKET = "guest-documents";
const MAX_ID_FILE_SIZE = 15 * 1024 * 1024;
const ALLOWED_ID_MIME_TYPES = new Set(["image/jpeg", "image/png", "application/pdf"]);

function createUuid() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (char) => {
    const random = Math.floor(Math.random() * 16);
    const value = char === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

function sanitizeStorageFileName(value) {
  return String(value || "guest-id")
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^[-.]+|[-.]+$/g, "")
    .slice(0, 120) || "guest-id";
}

function addDaysIso(days) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString();
}

function isExistingStorageObjectError(error) {
  const text = `${error?.message || ""} ${error?.error || ""}`.toLowerCase();
  return text.includes("already exists") || text.includes("duplicate");
}

export default function CheckIn() {
  const defaults = useMemo(() => getDefaultTimes(), []);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [rooms, setRooms] = useState([]);
  const [roomId, setRoomId] = useState("");
  const [roomCharge, setRoomCharge] = useState("");
  const [checkinTime, setCheckinTime] = useState(defaults.checkinTime);
  const [checkoutTime, setCheckoutTime] = useState(defaults.checkoutTime);
  const [guest, setGuest] = useState(EMPTY_GUEST);
  const [selectedGuest, setSelectedGuest] = useState(null);
  const [guestMatches, setGuestMatches] = useState([]);
  const [companions, setCompanions] = useState([]);
  const [stayDetails, setStayDetails] = useState(EMPTY_STAY_DETAILS);
  const [notes, setNotes] = useState("");
  const [requestId, setRequestId] = useState(createRequestId);
  const [idCapture, setIdCapture] = useState(null);
  const [idDocumentId, setIdDocumentId] = useState(createUuid);
  const [idRequestId, setIdRequestId] = useState(createUuid);
  const [showMoreOptions, setShowMoreOptions] = useState(false);
  const [idSaveWarning, setIdSaveWarning] = useState("");
  const [pageLoading, setPageLoading] = useState(true);
  const [loading, setLoading] = useState(false);
  const [searchingGuest, setSearchingGuest] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [result, setResult] = useState(null);

  const occupancy = useMemo(() => {
    const companionAdults = companions.filter(
      (item) => item.guest_category === "adult"
    ).length;
    const companionChildren = companions.filter((item) =>
      ["child", "infant"].includes(item.guest_category)
    ).length;

    return {
      adults: companionAdults + 1,
      children: companionChildren,
      total: companionAdults + companionChildren + 1,
    };
  }, [companions]);

  const selectedRoom = useMemo(
    () => rooms.find((room) => room.id === roomId) || null,
    [roomId, rooms]
  );

  const fetchAvailableRooms = async (hotelId) => {
    if (!hotelId) return;

    const { data, error: roomsError } = await supabase
      .from("rooms")
      .select("id, room_number, room_type_id, status")
      .eq("hotel_id", hotelId)
      .eq("status", "available")
      .order("room_number");

    if (roomsError) throw roomsError;

    const roomRows = data || [];
    const roomTypeIds = [...new Set(roomRows.map((room) => room.room_type_id).filter(Boolean))];
    let rateByType = new Map();
    if (roomTypeIds.length) {
      const { data: typeRows, error: typesError } = await supabase
        .from("room_types")
        .select("id, name, base_rate")
        .eq("hotel_id", hotelId)
        .in("id", roomTypeIds);
      if (!typesError) {
        rateByType = new Map((typeRows || []).map((item) => [item.id, item]));
      }
    }

    setRooms(roomRows.map((room) => ({
      ...room,
      room_type: rateByType.get(room.room_type_id) || null,
    })));
  };

  useEffect(() => {
    let cancelled = false;

    async function initPage() {
      setPageLoading(true);
      setError("");

      try {
        const hotel = await getCurrentHotel();

        if (!hotel) {
          throw new Error("No active hotel is assigned to this account.");
        }

        if (cancelled) return;

        setCurrentHotel(hotel);
        await fetchAvailableRooms(hotel.id);
      } catch (initError) {
        console.error("Check-in initialization error:", initError);
        if (!cancelled) {
          setError(initError.message || "Unable to load check-in.");
        }
      } finally {
        if (!cancelled) setPageLoading(false);
      }
    }

    initPage();

    return () => {
      cancelled = true;
    };
  }, []);

  const clearSelectedGuest = () => {
    setSelectedGuest(null);
    setGuestMatches([]);
  };

  const updateGuest = (field, value) => {
    setGuest((current) => ({ ...current, [field]: value }));

    if (
      selectedGuest &&
      ["phone", "email", "id_type", "id_number"].includes(field)
    ) {
      clearSelectedGuest();
    }
  };

  const applyGuestMatch = (match) => {
    setSelectedGuest(match);
    setGuest((current) => ({
      ...current,
      full_name: match.full_name || current.full_name,
      phone: match.phone || current.phone,
      email: match.email || current.email,
      id_type: match.id_type || current.id_type,
      id_number: match.id_number || current.id_number,
      date_of_birth: match.date_of_birth || current.date_of_birth,
      gender: match.gender || current.gender,
      nationality: match.nationality || current.nationality,
      country_of_residence:
        match.country_of_residence || current.country_of_residence,
      address_line1: match.address_line1 || current.address_line1,
      address_line2: match.address_line2 || current.address_line2,
      city: match.city || current.city,
      state_region: match.state_region || current.state_region,
      postal_code: match.postal_code || current.postal_code,
      preferred_language:
        match.preferred_language || current.preferred_language,
      purpose_of_visit: match.purpose_of_visit || current.purpose_of_visit,
      is_foreign_guest:
        typeof match.is_foreign_guest === "boolean"
          ? match.is_foreign_guest
          : current.is_foreign_guest,
    }));
    setGuestMatches([]);
    setMessage(`Existing guest selected: ${match.full_name}`);
  };

  const findExistingGuest = async () => {
    if (!currentHotel?.id) return;

    const normalizedType = normalizeIdType(guest.id_type);
    const normalizedNumber = normalizeIdNumber(guest.id_number);
    const normalizedEmail = normalizeEmail(guest.email);
    const normalizedPhone = normalizePhone(guest.phone);

    let query = supabase
      .from("guests")
      .select(
        "id, full_name, phone, email, id_type, id_number, date_of_birth, gender, nationality, country_of_residence, address_line1, address_line2, city, state_region, postal_code, preferred_language, purpose_of_visit, is_foreign_guest, identity_verification_status"
      )
      .eq("hotel_id", currentHotel.id)
      .limit(10);

    if (normalizedType && normalizedNumber) {
      query = query
        .eq("normalized_id_type", normalizedType)
        .eq("normalized_id_number", normalizedNumber);
    } else if (normalizedEmail) {
      query = query.eq("normalized_email", normalizedEmail);
    } else if (normalizedPhone) {
      query = query.eq("normalized_phone", normalizedPhone);
    } else {
      setError("Enter a phone, email, or identity document before searching.");
      return;
    }

    setSearchingGuest(true);
    setError("");
    setMessage("");

    try {
      const { data, error: searchError } = await query;
      if (searchError) throw searchError;

      const matches = data || [];
      setGuestMatches(matches);

      if (matches.length === 1) {
        applyGuestMatch(matches[0]);
      } else if (matches.length === 0) {
        setSelectedGuest(null);
        setMessage("No existing guest matched. A new guest profile will be created.");
      } else {
        setMessage(
          `${matches.length} guest profiles matched. Select the correct profile before check-in.`
        );
      }
    } catch (searchError) {
      console.error("Guest search error:", searchError);
      setError(searchError.message || "Unable to search guest profiles.");
    } finally {
      setSearchingGuest(false);
    }
  };

  const addCompanion = () => {
    setCompanions((current) => [...current, createCompanion()]);
  };

  const updateCompanion = (clientId, field, value) => {
    setCompanions((current) =>
      current.map((item) =>
        item.client_id === clientId ? { ...item, [field]: value } : item
      )
    );
  };

  const removeCompanion = (clientId) => {
    setCompanions((current) =>
      current.filter((item) => item.client_id !== clientId)
    );
  };

  const updateStayDetail = (field, value) => {
    setStayDetails((current) => ({ ...current, [field]: value }));
  };

  const validateForm = () => {
    if (!currentHotel?.id) return "No active hotel is assigned to this account.";
    if (!guest.full_name.trim()) return "Guest full name is required.";
    if (!roomId) return "Select an available room.";
    if (!checkinTime || !checkoutTime) {
      return "Check-in and checkout times are required.";
    }

    const checkinDate = new Date(checkinTime);
    const checkoutDate = new Date(checkoutTime);

    if (
      Number.isNaN(checkinDate.getTime()) ||
      Number.isNaN(checkoutDate.getTime()) ||
      checkoutDate <= checkinDate
    ) {
      return "Checkout time must be after check-in time.";
    }

    const numericRoomCharge = Number(roomCharge);
    if (!Number.isFinite(numericRoomCharge) || numericRoomCharge < 0) {
      return "Enter a valid non-negative room charge.";
    }

    if (guest.id_number.trim() && !guest.id_type.trim()) {
      return "Select an ID type when an ID number is entered.";
    }

    const invalidCompanion = companions.find(
      (item) =>
        !item.full_name.trim() ||
        (item.id_number.trim() && !item.id_type.trim())
    );

    if (invalidCompanion) {
      return "Every companion needs a name, and an ID type when an ID number is entered.";
    }

    return null;
  };

  const resetForm = () => {
    const nextDefaults = getDefaultTimes();
    setGuest(EMPTY_GUEST);
    setSelectedGuest(null);
    setGuestMatches([]);
    setCompanions([]);
    setStayDetails(EMPTY_STAY_DETAILS);
    setRoomId("");
    setRoomCharge("");
    setCheckinTime(nextDefaults.checkinTime);
    setCheckoutTime(nextDefaults.checkoutTime);
    setNotes("");
    setRequestId(createRequestId());
    setIdCapture(null);
    setIdDocumentId(createUuid());
    setIdRequestId(createUuid());
    setShowMoreOptions(false);
    setIdSaveWarning("");
    setError("");
    setMessage("");
    setResult(null);
  };

  const handleRoomChange = (nextRoomId) => {
    setRoomId(nextRoomId);
    const nextRoom = rooms.find((room) => room.id === nextRoomId);
    const suggestedRate = Number(nextRoom?.room_type?.base_rate);
    if (Number.isFinite(suggestedRate) && suggestedRate >= 0) {
      setRoomCharge(String(suggestedRate));
    } else if (!roomCharge) {
      setRoomCharge("0");
    }
  };

  const handleIdExtracted = (analysis) => {
    if (!analysis) return;
    const fields = analysis.extractedFields || {};
    setGuest((current) => ({
      ...current,
      full_name: fields.full_name || current.full_name,
      id_type: analysis.documentType && analysis.documentType !== "other" ? analysis.documentType : current.id_type,
      id_number: analysis.documentNumberMasked || current.id_number,
      date_of_birth: fields.date_of_birth || current.date_of_birth,
      gender: fields.gender || current.gender,
      nationality: fields.nationality || current.nationality,
      country_of_residence: fields.country_of_residence || current.country_of_residence,
      address_line1: fields.address_line1 || current.address_line1,
      city: fields.city || current.city,
      state_region: fields.state_region || current.state_region,
      postal_code: fields.postal_code || current.postal_code,
    }));
    const extractedCount = Object.keys(fields).filter((key) => fields[key]).length + (analysis.documentNumberMasked ? 1 : 0);
    setSelectedGuest(null);
    setGuestMatches([]);
    if (analysis.status === "extracted" && extractedCount > 0) {
      setMessage("ID details extracted. Review the auto-filled fields before completing check-in.");
      setError("");
    } else {
      setMessage("");
      setError(analysis.message || "StayQR could not read enough details from this ID. Retake a clearer photo or enter the fields manually.");
    }
  };

  const saveCapturedIdAfterCheckin = async (checkinResult) => {
    const file = idCapture?.file;
    if (!file || !currentHotel?.id || !checkinResult?.guest_id) return null;
    if (!ALLOWED_ID_MIME_TYPES.has(file.type)) throw new Error("Only JPG, PNG and PDF ID files are supported in quick check-in.");
    if (file.size <= 0 || file.size > MAX_ID_FILE_SIZE) throw new Error("ID image must be between 1 byte and 15 MB.");

    const safeName = sanitizeStorageFileName(file.name);
    const storagePath = `${currentHotel.id}/${checkinResult.guest_id}/${idDocumentId}/${safeName}`;
    const { error: storageError } = await supabase.storage
      .from(GUEST_DOCUMENT_BUCKET)
      .upload(storagePath, file, { contentType: file.type, upsert: false });
    if (storageError && !isExistingStorageObjectError(storageError)) throw storageError;

    const analysis = idCapture.analysis || null;
    const documentType = analysis?.documentType && analysis.documentType !== "other"
      ? analysis.documentType
      : guest.id_type || "other";

    const { data: registration, error: registrationError } = await supabase.rpc("register_guest_document", {
      target_hotel_id: currentHotel.id,
      payload: {
        document_id: idDocumentId,
        request_id: idRequestId,
        guest_id: checkinResult.guest_id,
        guest_session_id: checkinResult.guest_session_id || null,
        document_type: documentType,
        storage_bucket: GUEST_DOCUMENT_BUCKET,
        storage_path: storagePath,
        original_file_name: file.name,
        mime_type: file.type,
        file_size_bytes: file.size,
        document_number_masked: analysis?.documentNumberMasked || guest.id_number || null,
        issue_country: "India",
        capture_source: idCapture.captureSource === "camera" ? "camera" : "upload",
        document_side: "single",
        quality_status: idCapture.qualityStatus || "not_assessed",
        quality_score: idCapture.qualityScore ?? null,
        quality_flags: idCapture.qualityFlags || [],
        retention_until: addDaysIso(365),
        retention_basis: "hotel_policy",
        metadata: {
          workflow: "simple_front_desk_id_capture_rev1",
          raw_ocr_text_stored: false,
          raw_qr_payload_stored: false,
          government_verification_claimed: false,
        },
      },
    });
    if (registrationError) throw registrationError;

    const savedDocument = registration?.document || registration;
    const savedDocumentId = savedDocument?.id || idDocumentId;
    if (analysis) {
      await recordGuestDocumentExtraction({
        hotelId: currentHotel.id,
        documentId: savedDocumentId,
        analysis,
      });
    }
    return savedDocumentId;
  };

  const handleCheckIn = async () => {
    const validationError = validateForm();
    if (validationError) {
      setError(validationError);
      return;
    }

    setLoading(true);
    setError("");
    setMessage("");

    try {
      const guestPayload = compactObject({
        ...guest,
        id: selectedGuest?.id || "",
      });

      const companionPayload = companions.map((item) =>
        compactObject({
          full_name: item.full_name.trim(),
          phone: item.phone.trim(),
          email: item.email.trim(),
          id_type: item.id_type.trim(),
          id_number: item.id_number.trim(),
          relationship: item.relationship.trim(),
          guest_category: item.guest_category,
          form_c_required: item.form_c_required,
        })
      );

      const payload = {
        request_id: requestId,
        room_id: roomId,
        checkin_time: new Date(checkinTime).toISOString(),
        checkout_time: new Date(checkoutTime).toISOString(),
        room_charge: Number(roomCharge),
        adults: occupancy.adults,
        children: occupancy.children,
        guest: guestPayload,
        companions: companionPayload,
        stay_details: compactObject({
          ...stayDetails,
          purpose_of_visit:
            stayDetails.purpose_of_visit || guest.purpose_of_visit,
        }),
        notes: notes.trim(),
      };

      const { data, error: rpcError } = await supabase.rpc(
        "check_in_walk_in_guest",
        {
          target_hotel_id: currentHotel.id,
          payload,
        }
      );

      if (rpcError) throw rpcError;

      let documentWarning = "";
      if (idCapture?.file) {
        try {
          await saveCapturedIdAfterCheckin(data);
        } catch (documentError) {
          console.error("Quick check-in ID save error:", documentError);
          documentWarning = documentError.message || "The guest was checked in, but the ID image could not be saved.";
          setIdSaveWarning(documentWarning);
        }
      }

      setResult(data);
      setMessage(
        data?.idempotent
          ? "This request was already completed earlier. The existing result was returned safely."
          : `Guest checked in to Room ${data?.room_number || selectedRoom?.room_number || ""}.${documentWarning ? " Check the ID save warning below." : ""}`
      );

      await fetchAvailableRooms(currentHotel.id);
    } catch (checkInError) {
      console.error("Atomic walk-in check-in error:", checkInError);
      setError(checkInError.message || "Unable to complete walk-in check-in.");
    } finally {
      setLoading(false);
    }
  };

  if (pageLoading) {
    return (
      <div className="checkin-page simple-frontdesk">
        <div className="checkin-card checkin-card--compact">
          <h1>Guest Check-in</h1>
          <p>Loading hotel and available rooms…</p>
        </div>
      </div>
    );
  }

  if (error && !currentHotel) {
    return (
      <div className="checkin-page simple-frontdesk">
        <div className="checkin-card checkin-card--compact">
          <h1>Guest Check-in</h1>
          <div className="checkin-alert checkin-alert--error">{error}</div>
        </div>
      </div>
    );
  }

  return (
    <div className="checkin-page simple-frontdesk">
      <div className="checkin-shell">
        <header className="simple-checkin-header">
          <div>
            <h1>Guest Check-in</h1>
            <p>Quick and simple guest registration</p>
          </div>
          <div className="simple-checkin-header-actions">
            <span>{currentHotel?.hotel_name || "StayQR hotel"}</span>
            <button type="button" onClick={() => navigateToSection("operations")}>Reservation arrivals</button>
          </div>
        </header>

        {error && <div className="checkin-alert checkin-alert--error">{error}</div>}
        {message && <div className="checkin-alert checkin-alert--success">{message}</div>}

        {result ? (
          <section className="simple-checkin-success">
            <span className="simple-checkin-success-icon">✓</span>
            <div>
              <p>Check-in complete</p>
              <h2>{guest.full_name || "Guest"} · Room {result.room_number}</h2>
              <span>The guest profile, stay and room inventory were saved together.</span>
              {idCapture?.file && !idSaveWarning && <small>ID document saved privately with the guest profile.</small>}
              {idSaveWarning && <div className="checkin-alert checkin-alert--warning">{idSaveWarning}</div>}
            </div>
            <button type="button" onClick={resetForm}>Check in another guest</button>
          </section>
        ) : (
          <>
            <section className="simple-checkin-card">
              <div className="simple-section-title">
                <span>1</span>
                <div><h2>Guest basics</h2><p>Enter the essentials. Scan an ID below to auto-fill more details.</p></div>
                <button
                  type="button"
                  className="checkin-button-secondary simple-existing-guest"
                  onClick={findExistingGuest}
                  disabled={searchingGuest}
                >
                  {searchingGuest ? "Searching…" : "Find existing guest"}
                </button>
              </div>

              {selectedGuest && (
                <div className="checkin-selected-guest">
                  <div><span>Existing guest selected</span><strong>{selectedGuest.full_name}</strong></div>
                  <button type="button" onClick={clearSelectedGuest}>Use new profile</button>
                </div>
              )}
              {guestMatches.length > 1 && (
                <div className="checkin-match-list">
                  {guestMatches.map((match) => (
                    <button type="button" key={match.id} onClick={() => applyGuestMatch(match)}>
                      <strong>{match.full_name}</strong><span>{match.phone || match.email || "Guest profile"}</span>
                    </button>
                  ))}
                </div>
              )}

              <div className="simple-basics-grid">
                <label><span>Full name *</span><input value={guest.full_name} onChange={(event) => updateGuest("full_name", event.target.value)} placeholder="Guest full name" /></label>
                <label><span>Phone number</span><input type="tel" value={guest.phone} onChange={(event) => updateGuest("phone", event.target.value)} placeholder="+91 98765 43210" /></label>
                <label><span>Email (optional)</span><input type="email" value={guest.email} onChange={(event) => updateGuest("email", event.target.value)} placeholder="guest@example.com" /></label>
                <label><span>Room number *</span><select value={roomId} onChange={(event) => handleRoomChange(event.target.value)}><option value="">Select room</option>{rooms.map((room) => <option key={room.id} value={room.id}>Room {room.room_number}{room.room_type?.name ? ` · ${room.room_type.name}` : ""}</option>)}</select></label>
                <label><span>Check-in *</span><input type="datetime-local" value={checkinTime} onChange={(event) => setCheckinTime(event.target.value)} /></label>
                <label><span>Check-out *</span><input type="datetime-local" value={checkoutTime} onChange={(event) => setCheckoutTime(event.target.value)} /></label>
              </div>
              {!rooms.length && <div className="checkin-alert checkin-alert--warning">No available rooms were found for this hotel.</div>}
            </section>

            <SimpleGuestIdCapture
              hotelId={currentHotel?.id || null}
              value={idCapture}
              onChange={setIdCapture}
              onExtracted={handleIdExtracted}
              disabled={loading}
            />

            {(idCapture?.analysis || guest.id_type || guest.id_number) && (
              <section className="simple-checkin-card simple-autofill-card">
                <div className="simple-section-title">
                  <span>3</span>
                  <div><h2>ID details (auto-filled)</h2><p>Review anything StayQR extracted. Edit only if needed.</p></div>
                  {idCapture?.analysis && <em>Auto-filled</em>}
                </div>
                <div className="simple-id-edit-grid">
                  <label><span>ID type</span><select value={guest.id_type} onChange={(event) => updateGuest("id_type", event.target.value)}><option value="">Select ID</option><option value="aadhaar">Aadhaar</option><option value="passport">Passport</option><option value="pan">PAN</option><option value="driving_licence">Driving licence</option><option value="voter_id">Voter ID</option><option value="other">Other</option></select></label>
                  <label><span>ID number</span><input value={guest.id_number} onChange={(event) => updateGuest("id_number", event.target.value)} placeholder="Masked / extracted ID" /></label>
                  <label><span>Date of birth</span><input type="date" value={guest.date_of_birth} onChange={(event) => updateGuest("date_of_birth", event.target.value)} /></label>
                  <label><span>Gender</span><select value={guest.gender} onChange={(event) => updateGuest("gender", event.target.value)}><option value="">Not specified</option><option value="male">Male</option><option value="female">Female</option><option value="non_binary">Non-binary</option><option value="other">Other</option><option value="prefer_not_to_say">Prefer not to say</option></select></label>
                  <label><span>Nationality</span><input value={guest.nationality} onChange={(event) => updateGuest("nationality", event.target.value)} /></label>
                  <label className="wide"><span>Address</span><input value={guest.address_line1} onChange={(event) => updateGuest("address_line1", event.target.value)} placeholder="Address from ID" /></label>
                </div>
                <div className="simple-privacy-note">Only masked ID details are shown here. Review extracted details before completing check-in.</div>
              </section>
            )}

            <section className="simple-more-wrap">
              <button type="button" className="simple-more-toggle" onClick={() => setShowMoreOptions((current) => !current)}>
                <span>{showMoreOptions ? "−" : "+"}</span>
                {showMoreOptions ? "Hide extra check-in options" : "More check-in options"}
                <small>Charge, language, companions, travel and foreign guest details</small>
              </button>

              {showMoreOptions && (
                <div className="simple-more-panel">
                  <div className="simple-more-grid">
                    <label><span>Room charge</span><input type="number" min="0" step="0.01" value={roomCharge} onChange={(event) => setRoomCharge(event.target.value)} /></label>
                    <label><span>Preferred language</span><select value={guest.preferred_language} onChange={(event) => updateGuest("preferred_language", event.target.value)}><option value="english">English</option><option value="hindi">Hindi</option><option value="marathi">Marathi</option></select></label>
                    <label><span>Purpose of visit</span><input value={guest.purpose_of_visit} onChange={(event) => updateGuest("purpose_of_visit", event.target.value)} /></label>
                    <label><span>City</span><input value={guest.city} onChange={(event) => updateGuest("city", event.target.value)} /></label>
                    <label><span>State / region</span><input value={guest.state_region} onChange={(event) => updateGuest("state_region", event.target.value)} /></label>
                    <label><span>PIN / postal code</span><input value={guest.postal_code} onChange={(event) => updateGuest("postal_code", event.target.value)} /></label>
                    <label className="wide"><span>Address line 2</span><input value={guest.address_line2} onChange={(event) => updateGuest("address_line2", event.target.value)} /></label>
                    <label className="wide"><span>Front desk note</span><input value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Optional note" /></label>
                  </div>

                  <div className="simple-advanced-divider">
                    <div><strong>Companions</strong><span>{occupancy.total} total guest{occupancy.total === 1 ? "" : "s"}</span></div>
                    <button type="button" onClick={addCompanion}>+ Add companion</button>
                  </div>
                  {companions.map((companion, index) => (
                    <div className="simple-companion-card" key={companion.client_id}>
                      <div className="simple-companion-head"><strong>Companion {index + 1}</strong><button type="button" onClick={() => removeCompanion(companion.client_id)}>Remove</button></div>
                      <div className="simple-more-grid">
                        <label><span>Full name *</span><input value={companion.full_name} onChange={(event) => updateCompanion(companion.client_id, "full_name", event.target.value)} /></label>
                        <label><span>Phone</span><input value={companion.phone} onChange={(event) => updateCompanion(companion.client_id, "phone", event.target.value)} /></label>
                        <label><span>Category</span><select value={companion.guest_category} onChange={(event) => updateCompanion(companion.client_id, "guest_category", event.target.value)}><option value="adult">Adult</option><option value="child">Child</option><option value="infant">Infant</option></select></label>
                        <label><span>Relationship</span><input value={companion.relationship} onChange={(event) => updateCompanion(companion.client_id, "relationship", event.target.value)} /></label>
                        <label><span>ID type</span><select value={companion.id_type} onChange={(event) => updateCompanion(companion.client_id, "id_type", event.target.value)}><option value="">Select ID</option><option value="aadhaar">Aadhaar</option><option value="passport">Passport</option><option value="driving_licence">Driving licence</option><option value="voter_id">Voter ID</option><option value="other">Other</option></select></label>
                        <label><span>ID number</span><input value={companion.id_number} onChange={(event) => updateCompanion(companion.client_id, "id_number", event.target.value)} /></label>
                      </div>
                      <label className="simple-inline-check"><input type="checkbox" checked={companion.form_c_required} onChange={(event) => updateCompanion(companion.client_id, "form_c_required", event.target.checked)} /><span>Form C required for this companion</span></label>
                    </div>
                  ))}

                  <details className="simple-nested-options">
                    <summary>Travel & timing</summary>
                    <div className="simple-more-grid">
                      <label><span>Arriving from</span><input value={stayDetails.arrival_from} onChange={(event) => updateStayDetail("arrival_from", event.target.value)} /></label>
                      <label><span>Next destination</span><input value={stayDetails.next_destination} onChange={(event) => updateStayDetail("next_destination", event.target.value)} /></label>
                      <label><span>Arrival mode</span><input value={stayDetails.arrival_mode} onChange={(event) => updateStayDetail("arrival_mode", event.target.value)} placeholder="Flight, train, road…" /></label>
                      <label><span>Arrival transport number</span><input value={stayDetails.arrival_transport_number} onChange={(event) => updateStayDetail("arrival_transport_number", event.target.value)} /></label>
                      <label><span>Departure mode</span><input value={stayDetails.departure_mode} onChange={(event) => updateStayDetail("departure_mode", event.target.value)} /></label>
                      <label><span>Departure transport number</span><input value={stayDetails.departure_transport_number} onChange={(event) => updateStayDetail("departure_transport_number", event.target.value)} /></label>
                    </div>
                    <div className="simple-inline-check-row">
                      <label className="simple-inline-check"><input type="checkbox" checked={stayDetails.early_checkin} onChange={(event) => updateStayDetail("early_checkin", event.target.checked)} /><span>Early check-in</span></label>
                      <label className="simple-inline-check"><input type="checkbox" checked={stayDetails.late_checkout} onChange={(event) => updateStayDetail("late_checkout", event.target.checked)} /><span>Late checkout planned</span></label>
                    </div>
                    <label className="simple-textarea-field"><span>Special stay notes</span><textarea value={stayDetails.special_notes} onChange={(event) => updateStayDetail("special_notes", event.target.value)} placeholder="Optional stay-specific notes" /></label>
                  </details>

                  <label className="simple-foreign-toggle"><input type="checkbox" checked={guest.is_foreign_guest} onChange={(event) => { updateGuest("is_foreign_guest", event.target.checked); updateStayDetail("form_c_status", event.target.checked ? "pending" : "not_required"); }} /><span><strong>Foreign guest / Form C details</strong><small>Open only when required.</small></span></label>
                  {guest.is_foreign_guest && (
                    <details className="simple-nested-options" open>
                      <summary>Passport, visa & Form C</summary>
                      <div className="simple-more-grid">
                        <label><span>Passport number</span><input value={stayDetails.passport_number} onChange={(event) => updateStayDetail("passport_number", event.target.value)} /></label>
                        <label><span>Passport issue country</span><input value={stayDetails.passport_issue_country} onChange={(event) => updateStayDetail("passport_issue_country", event.target.value)} /></label>
                        <label><span>Passport issued on</span><input type="date" value={stayDetails.passport_issued_on} onChange={(event) => updateStayDetail("passport_issued_on", event.target.value)} /></label>
                        <label><span>Passport expires</span><input type="date" value={stayDetails.passport_expires_on} onChange={(event) => updateStayDetail("passport_expires_on", event.target.value)} /></label>
                        <label><span>Visa number</span><input value={stayDetails.visa_number} onChange={(event) => updateStayDetail("visa_number", event.target.value)} /></label>
                        <label><span>Visa type</span><input value={stayDetails.visa_type} onChange={(event) => updateStayDetail("visa_type", event.target.value)} /></label>
                        <label><span>Visa issue place</span><input value={stayDetails.visa_issue_place} onChange={(event) => updateStayDetail("visa_issue_place", event.target.value)} /></label>
                        <label><span>Visa issued on</span><input type="date" value={stayDetails.visa_issued_on} onChange={(event) => updateStayDetail("visa_issued_on", event.target.value)} /></label>
                        <label><span>Visa expires</span><input type="date" value={stayDetails.visa_expires_on} onChange={(event) => updateStayDetail("visa_expires_on", event.target.value)} /></label>
                        <label><span>Date of arrival in India</span><input type="date" value={stayDetails.date_of_arrival_in_india} onChange={(event) => updateStayDetail("date_of_arrival_in_india", event.target.value)} /></label>
                        <label><span>Intended stay in India (days)</span><input type="number" min="1" value={stayDetails.intended_duration_in_india_days} onChange={(event) => updateStayDetail("intended_duration_in_india_days", event.target.value)} /></label>
                        <label><span>Form C status</span><select value={stayDetails.form_c_status} onChange={(event) => updateStayDetail("form_c_status", event.target.value)}><option value="pending">Pending</option><option value="ready">Ready</option><option value="submitted">Submitted</option><option value="not_required">Not required</option></select></label>
                      </div>
                    </details>
                  )}
                </div>
              )}
            </section>

            <footer className="simple-checkin-footer">
              <div><strong>{selectedRoom ? `Room ${selectedRoom.room_number}` : "Select a room"}</strong><span>{occupancy.total} guest{occupancy.total === 1 ? "" : "s"}{roomCharge !== "" ? ` · ₹${Number(roomCharge || 0).toLocaleString("en-IN")}` : ""}</span></div>
              <button type="button" className="simple-primary-action" onClick={handleCheckIn} disabled={loading || !rooms.length}>{loading ? "Completing check-in…" : "Complete check-in"}</button>
            </footer>
          </>
        )}
      </div>
    </div>
  );
}
