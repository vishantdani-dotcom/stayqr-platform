import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { navigateToSection } from "../../lib/bookingCalendar";
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
  const [showIdentity, setShowIdentity] = useState(false);
  const [showStayDetails, setShowStayDetails] = useState(false);
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

    setRooms(data || []);
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
    setShowIdentity(false);
    setShowStayDetails(false);
    setError("");
    setMessage("");
    setResult(null);
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

      setResult(data);
      setMessage(
        data?.idempotent
          ? "This request was already completed earlier. The existing result was returned safely."
          : `Guest checked in to Room ${data?.room_number || selectedRoom?.room_number || ""}.`
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
      <div className="checkin-page">
        <div className="checkin-card checkin-card--compact">
          <h1>Guest Check-In</h1>
          <p>Loading hotel and available rooms...</p>
        </div>
      </div>
    );
  }

  if (error && !currentHotel) {
    return (
      <div className="checkin-page">
        <div className="checkin-card checkin-card--compact">
          <h1>Guest Check-In</h1>
          <div className="checkin-alert checkin-alert--error">{error}</div>
        </div>
      </div>
    );
  }

  return (
    <div className="checkin-page">
      <div className="checkin-card">
        <div className="checkin-reservation-banner">
          <div>
            <span>Reservation arrivals</span>
            <strong>Use the reservation check-in workflow</strong>
            <small>
              Room allocation, deposit transfer and reservation status remain
              server-controlled.
            </small>
          </div>
          <button type="button" onClick={() => navigateToSection("operations")}>
            Open arrivals
          </button>
        </div>

        <div className="checkin-heading-row">
          <div>
            <span className="checkin-eyebrow">Atomic front-office workflow</span>
            <h1>Walk-In Guest Check-In</h1>
            <p>
              {currentHotel?.hotel_name} — guest identity, stay, room charge,
              companions, room history and inventory commit in one transaction.
            </p>
          </div>
          <div className="checkin-occupancy-card">
            <span>Occupancy</span>
            <strong>{occupancy.total}</strong>
            <small>
              {occupancy.adults} adult{occupancy.adults === 1 ? "" : "s"} ·{" "}
              {occupancy.children} child{occupancy.children === 1 ? "" : "ren"}
            </small>
          </div>
        </div>

        {error && <div className="checkin-alert checkin-alert--error">{error}</div>}
        {message && (
          <div className="checkin-alert checkin-alert--success">{message}</div>
        )}

        {result ? (
          <section className="checkin-result">
            <span className="checkin-eyebrow">Check-in completed</span>
            <h2>Room {result.room_number}</h2>
            <div className="checkin-result-grid">
              <div>
                <span>Guest session</span>
                <code>{result.guest_session_id}</code>
              </div>
              <div>
                <span>Payment</span>
                <code>{result.payment_id}</code>
              </div>
              <div>
                <span>Room charge</span>
                <strong>₹{Number(result.room_charge || 0).toFixed(2)}</strong>
              </div>
              <div>
                <span>Request</span>
                <code>{result.request_id}</code>
              </div>
            </div>
            <button type="button" onClick={resetForm}>
              Check in another guest
            </button>
          </section>
        ) : (
          <>
            <section className="checkin-section">
              <div className="checkin-section-title">
                <div>
                  <span>1</span>
                  <div>
                    <h2>Stay and room</h2>
                    <p>Select the physical room and exact stay window.</p>
                  </div>
                </div>
              </div>

              <div className="checkin-grid checkin-grid--three">
                <label>
                  <span>Available room *</span>
                  <select value={roomId} onChange={(event) => setRoomId(event.target.value)}>
                    <option value="">Select room</option>
                    {rooms.map((room) => (
                      <option key={room.id} value={room.id}>
                        Room {room.room_number}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  <span>Check-in time *</span>
                  <input
                    type="datetime-local"
                    value={checkinTime}
                    onChange={(event) => setCheckinTime(event.target.value)}
                  />
                </label>

                <label>
                  <span>Checkout time *</span>
                  <input
                    type="datetime-local"
                    value={checkoutTime}
                    onChange={(event) => setCheckoutTime(event.target.value)}
                  />
                </label>

                <label>
                  <span>Room charge *</span>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    placeholder="0.00"
                    value={roomCharge}
                    onChange={(event) => setRoomCharge(event.target.value)}
                  />
                </label>

                <label className="checkin-field-wide">
                  <span>Front-office note</span>
                  <input
                    type="text"
                    placeholder="Optional audit note for this check-in"
                    value={notes}
                    onChange={(event) => setNotes(event.target.value)}
                  />
                </label>
              </div>

              {!rooms.length && (
                <div className="checkin-alert checkin-alert--warning">
                  No available rooms were found for this hotel.
                </div>
              )}
            </section>

            <section className="checkin-section">
              <div className="checkin-section-title checkin-section-title--actions">
                <div>
                  <span>2</span>
                  <div>
                    <h2>Primary guest</h2>
                    <p>Reuse a verified guest or create one inside the transaction.</p>
                  </div>
                </div>
                <button
                  type="button"
                  className="checkin-button-secondary"
                  onClick={findExistingGuest}
                  disabled={searchingGuest}
                >
                  {searchingGuest ? "Searching..." : "Find existing guest"}
                </button>
              </div>

              {selectedGuest && (
                <div className="checkin-selected-guest">
                  <div>
                    <span>Existing guest selected</span>
                    <strong>{selectedGuest.full_name}</strong>
                    <small>
                      {selectedGuest.phone || selectedGuest.email || selectedGuest.id}
                    </small>
                  </div>
                  <button type="button" onClick={clearSelectedGuest}>
                    Clear selection
                  </button>
                </div>
              )}

              {guestMatches.length > 1 && (
                <div className="checkin-match-list">
                  {guestMatches.map((match) => (
                    <button
                      type="button"
                      key={match.id}
                      onClick={() => applyGuestMatch(match)}
                    >
                      <strong>{match.full_name}</strong>
                      <span>{match.phone || "No phone"}</span>
                      <small>{match.email || match.id_number || match.id}</small>
                    </button>
                  ))}
                </div>
              )}

              <div className="checkin-grid checkin-grid--two">
                <label>
                  <span>Full name *</span>
                  <input
                    type="text"
                    placeholder="Guest full name"
                    value={guest.full_name}
                    onChange={(event) => updateGuest("full_name", event.target.value)}
                  />
                </label>

                <label>
                  <span>Phone</span>
                  <input
                    type="tel"
                    placeholder="10-digit mobile number"
                    value={guest.phone}
                    onChange={(event) => updateGuest("phone", event.target.value)}
                  />
                </label>

                <label>
                  <span>Email</span>
                  <input
                    type="email"
                    placeholder="guest@example.com"
                    value={guest.email}
                    onChange={(event) => updateGuest("email", event.target.value)}
                  />
                </label>

                <label>
                  <span>Preferred language</span>
                  <select
                    value={guest.preferred_language}
                    onChange={(event) =>
                      updateGuest("preferred_language", event.target.value)
                    }
                  >
                    <option value="english">English</option>
                    <option value="hindi">Hindi</option>
                    <option value="marathi">Marathi</option>
                  </select>
                </label>
              </div>

              <button
                type="button"
                className="checkin-disclosure"
                onClick={() => setShowIdentity((current) => !current)}
              >
                {showIdentity ? "Hide identity and address" : "Add identity and address"}
              </button>

              {showIdentity && (
                <div className="checkin-grid checkin-grid--three checkin-subsection">
                  <label>
                    <span>ID type</span>
                    <select
                      value={guest.id_type}
                      onChange={(event) => updateGuest("id_type", event.target.value)}
                    >
                      <option value="">Select ID</option>
                      <option value="aadhaar">Aadhaar</option>
                      <option value="passport">Passport</option>
                      <option value="driving_licence">Driving licence</option>
                      <option value="voter_id">Voter ID</option>
                      <option value="pan">PAN</option>
                      <option value="other">Other</option>
                    </select>
                  </label>

                  <label>
                    <span>ID number</span>
                    <input
                      type="text"
                      value={guest.id_number}
                      onChange={(event) => updateGuest("id_number", event.target.value)}
                    />
                  </label>

                  <label>
                    <span>Date of birth</span>
                    <input
                      type="date"
                      value={guest.date_of_birth}
                      onChange={(event) =>
                        updateGuest("date_of_birth", event.target.value)
                      }
                    />
                  </label>

                  <label>
                    <span>Gender</span>
                    <select
                      value={guest.gender}
                      onChange={(event) => updateGuest("gender", event.target.value)}
                    >
                      <option value="">Not specified</option>
                      <option value="male">Male</option>
                      <option value="female">Female</option>
                      <option value="non_binary">Non-binary</option>
                      <option value="other">Other</option>
                      <option value="prefer_not_to_say">Prefer not to say</option>
                    </select>
                  </label>

                  <label>
                    <span>Nationality</span>
                    <input
                      type="text"
                      value={guest.nationality}
                      onChange={(event) => updateGuest("nationality", event.target.value)}
                    />
                  </label>

                  <label>
                    <span>Country of residence</span>
                    <input
                      type="text"
                      value={guest.country_of_residence}
                      onChange={(event) =>
                        updateGuest("country_of_residence", event.target.value)
                      }
                    />
                  </label>

                  <label className="checkin-checkbox">
                    <input
                      type="checkbox"
                      checked={guest.is_foreign_guest}
                      onChange={(event) => {
                        updateGuest("is_foreign_guest", event.target.checked);
                        updateStayDetail(
                          "form_c_status",
                          event.target.checked ? "pending" : "not_required"
                        );
                      }}
                    />
                    <span>Foreign guest / Form C workflow</span>
                  </label>

                  <label className="checkin-field-wide">
                    <span>Address line 1</span>
                    <input
                      type="text"
                      value={guest.address_line1}
                      onChange={(event) =>
                        updateGuest("address_line1", event.target.value)
                      }
                    />
                  </label>

                  <label className="checkin-field-wide">
                    <span>Address line 2</span>
                    <input
                      type="text"
                      value={guest.address_line2}
                      onChange={(event) =>
                        updateGuest("address_line2", event.target.value)
                      }
                    />
                  </label>

                  <label>
                    <span>City</span>
                    <input
                      type="text"
                      value={guest.city}
                      onChange={(event) => updateGuest("city", event.target.value)}
                    />
                  </label>

                  <label>
                    <span>State / region</span>
                    <input
                      type="text"
                      value={guest.state_region}
                      onChange={(event) =>
                        updateGuest("state_region", event.target.value)
                      }
                    />
                  </label>

                  <label>
                    <span>Postal code</span>
                    <input
                      type="text"
                      value={guest.postal_code}
                      onChange={(event) =>
                        updateGuest("postal_code", event.target.value)
                      }
                    />
                  </label>
                </div>
              )}
            </section>

            <section className="checkin-section">
              <div className="checkin-section-title checkin-section-title--actions">
                <div>
                  <span>3</span>
                  <div>
                    <h2>Companion guests</h2>
                    <p>Every companion is attached to this stay, not to a room label.</p>
                  </div>
                </div>
                <button
                  type="button"
                  className="checkin-button-secondary"
                  onClick={addCompanion}
                >
                  Add companion
                </button>
              </div>

              {!companions.length && (
                <div className="checkin-empty-state">No companions added.</div>
              )}

              <div className="checkin-companion-list">
                {companions.map((item, index) => (
                  <article className="checkin-companion" key={item.client_id}>
                    <div className="checkin-companion-header">
                      <strong>Companion {index + 1}</strong>
                      <button
                        type="button"
                        onClick={() => removeCompanion(item.client_id)}
                      >
                        Remove
                      </button>
                    </div>
                    <div className="checkin-grid checkin-grid--three">
                      <label>
                        <span>Full name *</span>
                        <input
                          type="text"
                          value={item.full_name}
                          onChange={(event) =>
                            updateCompanion(
                              item.client_id,
                              "full_name",
                              event.target.value
                            )
                          }
                        />
                      </label>
                      <label>
                        <span>Category</span>
                        <select
                          value={item.guest_category}
                          onChange={(event) =>
                            updateCompanion(
                              item.client_id,
                              "guest_category",
                              event.target.value
                            )
                          }
                        >
                          <option value="adult">Adult</option>
                          <option value="child">Child</option>
                          <option value="infant">Infant</option>
                        </select>
                      </label>
                      <label>
                        <span>Relationship</span>
                        <input
                          type="text"
                          placeholder="Spouse, child, colleague..."
                          value={item.relationship}
                          onChange={(event) =>
                            updateCompanion(
                              item.client_id,
                              "relationship",
                              event.target.value
                            )
                          }
                        />
                      </label>
                      <label>
                        <span>Phone</span>
                        <input
                          type="tel"
                          value={item.phone}
                          onChange={(event) =>
                            updateCompanion(
                              item.client_id,
                              "phone",
                              event.target.value
                            )
                          }
                        />
                      </label>
                      <label>
                        <span>ID type</span>
                        <select
                          value={item.id_type}
                          onChange={(event) =>
                            updateCompanion(
                              item.client_id,
                              "id_type",
                              event.target.value
                            )
                          }
                        >
                          <option value="">Select ID</option>
                          <option value="aadhaar">Aadhaar</option>
                          <option value="passport">Passport</option>
                          <option value="driving_licence">Driving licence</option>
                          <option value="voter_id">Voter ID</option>
                          <option value="other">Other</option>
                        </select>
                      </label>
                      <label>
                        <span>ID number</span>
                        <input
                          type="text"
                          value={item.id_number}
                          onChange={(event) =>
                            updateCompanion(
                              item.client_id,
                              "id_number",
                              event.target.value
                            )
                          }
                        />
                      </label>
                      <label className="checkin-checkbox">
                        <input
                          type="checkbox"
                          checked={item.form_c_required}
                          onChange={(event) =>
                            updateCompanion(
                              item.client_id,
                              "form_c_required",
                              event.target.checked
                            )
                          }
                        />
                        <span>Form C required</span>
                      </label>
                    </div>
                  </article>
                ))}
              </div>
            </section>

            <section className="checkin-section">
              <div className="checkin-section-title checkin-section-title--actions">
                <div>
                  <span>4</span>
                  <div>
                    <h2>Stay and foreign-guest details</h2>
                    <p>Capture travel, early/late handling and Form C preparation.</p>
                  </div>
                </div>
                <button
                  type="button"
                  className="checkin-button-secondary"
                  onClick={() => setShowStayDetails((current) => !current)}
                >
                  {showStayDetails ? "Hide details" : "Add stay details"}
                </button>
              </div>

              {showStayDetails && (
                <div className="checkin-grid checkin-grid--three checkin-subsection">
                  <label>
                    <span>Purpose of visit</span>
                    <input
                      type="text"
                      value={stayDetails.purpose_of_visit}
                      onChange={(event) =>
                        updateStayDetail("purpose_of_visit", event.target.value)
                      }
                    />
                  </label>
                  <label>
                    <span>Arriving from</span>
                    <input
                      type="text"
                      value={stayDetails.arrival_from}
                      onChange={(event) =>
                        updateStayDetail("arrival_from", event.target.value)
                      }
                    />
                  </label>
                  <label>
                    <span>Next destination</span>
                    <input
                      type="text"
                      value={stayDetails.next_destination}
                      onChange={(event) =>
                        updateStayDetail("next_destination", event.target.value)
                      }
                    />
                  </label>
                  <label>
                    <span>Arrival mode</span>
                    <input
                      type="text"
                      placeholder="Flight, train, road..."
                      value={stayDetails.arrival_mode}
                      onChange={(event) =>
                        updateStayDetail("arrival_mode", event.target.value)
                      }
                    />
                  </label>
                  <label>
                    <span>Arrival transport number</span>
                    <input
                      type="text"
                      value={stayDetails.arrival_transport_number}
                      onChange={(event) =>
                        updateStayDetail(
                          "arrival_transport_number",
                          event.target.value
                        )
                      }
                    />
                  </label>
                  <label>
                    <span>Departure mode</span>
                    <input
                      type="text"
                      value={stayDetails.departure_mode}
                      onChange={(event) =>
                        updateStayDetail("departure_mode", event.target.value)
                      }
                    />
                  </label>
                  <label>
                    <span>Departure transport number</span>
                    <input
                      type="text"
                      value={stayDetails.departure_transport_number}
                      onChange={(event) =>
                        updateStayDetail(
                          "departure_transport_number",
                          event.target.value
                        )
                      }
                    />
                  </label>

                  {guest.is_foreign_guest && (
                    <>
                      <label>
                        <span>Passport number</span>
                        <input
                          type="text"
                          value={stayDetails.passport_number}
                          onChange={(event) =>
                            updateStayDetail("passport_number", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Passport issue country</span>
                        <input
                          type="text"
                          value={stayDetails.passport_issue_country}
                          onChange={(event) =>
                            updateStayDetail(
                              "passport_issue_country",
                              event.target.value
                            )
                          }
                        />
                      </label>
                      <label>
                        <span>Passport issued on</span>
                        <input
                          type="date"
                          value={stayDetails.passport_issued_on}
                          onChange={(event) =>
                            updateStayDetail("passport_issued_on", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Passport expires on</span>
                        <input
                          type="date"
                          value={stayDetails.passport_expires_on}
                          onChange={(event) =>
                            updateStayDetail("passport_expires_on", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Visa number</span>
                        <input
                          type="text"
                          value={stayDetails.visa_number}
                          onChange={(event) =>
                            updateStayDetail("visa_number", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Visa type</span>
                        <input
                          type="text"
                          value={stayDetails.visa_type}
                          onChange={(event) =>
                            updateStayDetail("visa_type", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Visa issue place</span>
                        <input
                          type="text"
                          value={stayDetails.visa_issue_place}
                          onChange={(event) =>
                            updateStayDetail("visa_issue_place", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Visa issued on</span>
                        <input
                          type="date"
                          value={stayDetails.visa_issued_on}
                          onChange={(event) =>
                            updateStayDetail("visa_issued_on", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Visa expires on</span>
                        <input
                          type="date"
                          value={stayDetails.visa_expires_on}
                          onChange={(event) =>
                            updateStayDetail("visa_expires_on", event.target.value)
                          }
                        />
                      </label>
                      <label>
                        <span>Date of arrival in India</span>
                        <input
                          type="date"
                          value={stayDetails.date_of_arrival_in_india}
                          onChange={(event) =>
                            updateStayDetail(
                              "date_of_arrival_in_india",
                              event.target.value
                            )
                          }
                        />
                      </label>
                      <label>
                        <span>Intended stay in India (days)</span>
                        <input
                          type="number"
                          min="1"
                          value={stayDetails.intended_duration_in_india_days}
                          onChange={(event) =>
                            updateStayDetail(
                              "intended_duration_in_india_days",
                              event.target.value
                            )
                          }
                        />
                      </label>
                      <label>
                        <span>Form C status</span>
                        <select
                          value={stayDetails.form_c_status}
                          onChange={(event) =>
                            updateStayDetail("form_c_status", event.target.value)
                          }
                        >
                          <option value="pending">Pending</option>
                          <option value="ready">Ready</option>
                          <option value="submitted">Submitted</option>
                          <option value="not_required">Not required</option>
                        </select>
                      </label>
                    </>
                  )}

                  <label className="checkin-checkbox">
                    <input
                      type="checkbox"
                      checked={stayDetails.early_checkin}
                      onChange={(event) =>
                        updateStayDetail("early_checkin", event.target.checked)
                      }
                    />
                    <span>Early check-in</span>
                  </label>
                  <label className="checkin-checkbox">
                    <input
                      type="checkbox"
                      checked={stayDetails.late_checkout}
                      onChange={(event) =>
                        updateStayDetail("late_checkout", event.target.checked)
                      }
                    />
                    <span>Late checkout planned</span>
                  </label>
                  <label className="checkin-field-wide">
                    <span>Special stay notes</span>
                    <textarea
                      value={stayDetails.special_notes}
                      onChange={(event) =>
                        updateStayDetail("special_notes", event.target.value)
                      }
                    />
                  </label>
                </div>
              )}
            </section>

            <section className="checkin-submit-panel">
              <div>
                <span>Idempotency key</span>
                <code>{requestId}</code>
                <small>
                  Keep this key unchanged while retrying a failed request. The
                  server returns the original result instead of duplicating a stay.
                </small>
              </div>
              <button
                type="button"
                onClick={handleCheckIn}
                disabled={loading || rooms.length === 0}
              >
                {loading ? "Completing atomic check-in..." : "Check in guest"}
              </button>
            </section>
          </>
        )}
      </div>
    </div>
  );
}
