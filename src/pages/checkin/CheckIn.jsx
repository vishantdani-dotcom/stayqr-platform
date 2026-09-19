import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { getCurrentStaff } from "../../lib/currentStaff";
import { navigateToSection } from "../../lib/bookingCalendar";
import {
  GUEST_CONSENT_PURPOSES,
  recordGuestDocumentExtraction,
  setGuestConsent,
} from "../../lib/guestCompliance";
import { printCheckInPack, printRegistrationCard } from "../../lib/checkInPrintPack";
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
  date_of_birth: "",
  gender: "",
  nationality: "Indian",
  country_of_residence: "India",
  address_line1: "",
  city: "",
  state_region: "",
  postal_code: "",
  relationship: "",
  guest_category: "adult",
  form_c_required: false,
  id_capture: null,
  id_document_id: createUuid(),
  id_request_id: createUuid(),
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

function fillBlankField(currentValue, extractedValue) {
  const currentText = String(currentValue ?? "").trim();
  if (currentText) return currentValue;
  return extractedValue || currentValue;
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
  const [currentStaff, setCurrentStaff] = useState(null);
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
  const [savedPrintDocuments, setSavedPrintDocuments] = useState([]);
  const [printingPack, setPrintingPack] = useState(false);
  const [printError, setPrintError] = useState("");
  const [kycCaptureConsentConfirmed, setKycCaptureConsentConfirmed] = useState(false);

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

  const hasCapturedIdentityDocuments = Boolean(
    idCapture?.file || companions.some((item) => item.id_capture?.file)
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
        const [hotel, staff] = await Promise.all([
          getCurrentHotel(),
          getCurrentStaff(),
        ]);

        if (!hotel) {
          throw new Error("No active hotel is assigned to this account.");
        }

        if (cancelled) return;

        setCurrentHotel(hotel);
        setCurrentStaff(staff);
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

  const updateCompanionCapture = (clientId, capture) => {
    setCompanions((current) =>
      current.map((item) =>
        item.client_id === clientId ? { ...item, id_capture: capture } : item
      )
    );
  };

  const handleCompanionIdExtracted = (clientId, analysis) => {
    if (!analysis) return;
    const fields = analysis.extractedFields || {};
    if (analysis.autoFillAllowed === false) return;

    setCompanions((current) =>
      current.map((item) => {
        if (item.client_id !== clientId) return item;

        return {
          ...item,
          full_name: fillBlankField(item.full_name, fields.full_name),
          id_type: fillBlankField(
            item.id_type,
            analysis.documentType && analysis.documentType !== "other"
              ? analysis.documentType
              : ""
          ),
          id_number: fillBlankField(item.id_number, analysis.documentNumberMasked),
          date_of_birth: fillBlankField(item.date_of_birth, fields.date_of_birth),
          gender: fillBlankField(item.gender, fields.gender),
          nationality: fillBlankField(item.nationality, fields.nationality),
          country_of_residence: fillBlankField(
            item.country_of_residence,
            fields.country_of_residence
          ),
          address_line1: fillBlankField(item.address_line1, fields.address_line1),
          city: fillBlankField(item.city, fields.city),
          state_region: fillBlankField(item.state_region, fields.state_region),
          postal_code: fillBlankField(item.postal_code, fields.postal_code),
        };
      })
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

    if (hasCapturedIdentityDocuments && !kycCaptureConsentConfirmed) {
      return "Confirm KYC / identity-document storage consent before completing check-in.";
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
    setSavedPrintDocuments([]);
    setPrintingPack(false);
    setPrintError("");
    setKycCaptureConsentConfirmed(false);
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
    if (analysis.autoFillAllowed === false) {
      setSelectedGuest(null);
      setGuestMatches([]);
      setMessage("StayQR read the ID but did not auto-fill uncertain identity details. Review the scan result and enter the correct values manually.");
      setError("");
      return;
    }
    setGuest((current) => ({
      ...current,
      full_name: fillBlankField(current.full_name, fields.full_name),
      id_type: fillBlankField(current.id_type, analysis.documentType && analysis.documentType !== "other" ? analysis.documentType : ""),
      id_number: fillBlankField(current.id_number, analysis.documentNumberMasked),
      date_of_birth: fillBlankField(current.date_of_birth, fields.date_of_birth),
      gender: fillBlankField(current.gender, fields.gender),
      nationality: fillBlankField(current.nationality, fields.nationality),
      country_of_residence: fillBlankField(current.country_of_residence, fields.country_of_residence),
      address_line1: fillBlankField(current.address_line1, fields.address_line1),
      city: fillBlankField(current.city, fields.city),
      state_region: fillBlankField(current.state_region, fields.state_region),
      postal_code: fillBlankField(current.postal_code, fields.postal_code),
    }));
    const extractedCount = Object.keys(fields).filter((key) => fields[key]).length + (analysis.documentNumberMasked ? 1 : 0);
    setSelectedGuest(null);
    setGuestMatches([]);
    if (extractedCount > 0) {
      setMessage(analysis.status === "extracted"
        ? "ID details extracted. Review the auto-filled fields before completing check-in."
        : "Some ID details were extracted, but review is required. Complete any missing or incorrect fields before check-in.");
      setError("");
    } else {
      setMessage("");
      setError(analysis.message || "StayQR could not read enough details from this ID. Retake a clearer photo or enter the fields manually.");
    }
  };

  const saveCapturedIdForGuest = async ({
    capture,
    guestId,
    guestSessionId,
    documentId,
    documentRequestId,
    fallbackGuest,
  }) => {
    const file = capture?.file;
    if (!file || !currentHotel?.id || !guestId) return null;
    if (!ALLOWED_ID_MIME_TYPES.has(file.type)) {
      throw new Error("Only JPG, PNG and PDF ID files are supported in quick check-in.");
    }
    if (file.size <= 0 || file.size > MAX_ID_FILE_SIZE) {
      throw new Error("ID image must be between 1 byte and 15 MB.");
    }

    const safeName = sanitizeStorageFileName(file.name);
    const storagePath = `${currentHotel.id}/${guestId}/${documentId}/${safeName}`;
    const { error: storageError } = await supabase.storage
      .from(GUEST_DOCUMENT_BUCKET)
      .upload(storagePath, file, { contentType: file.type, upsert: false });
    if (storageError && !isExistingStorageObjectError(storageError)) {
      throw storageError;
    }

    const analysis = capture.analysis || null;
    const documentType =
      analysis?.documentType && analysis.documentType !== "other"
        ? analysis.documentType
        : fallbackGuest?.id_type || "other";

    const { data: registration, error: registrationError } = await supabase.rpc(
      "register_guest_document",
      {
        target_hotel_id: currentHotel.id,
        payload: {
          document_id: documentId,
          request_id: documentRequestId,
          guest_id: guestId,
          guest_session_id: guestSessionId || null,
          document_type: documentType,
          storage_bucket: GUEST_DOCUMENT_BUCKET,
          storage_path: storagePath,
          original_file_name: file.name,
          mime_type: file.type,
          file_size_bytes: file.size,
          document_number_masked:
            analysis?.documentNumberMasked || fallbackGuest?.id_number || null,
          issue_country: "India",
          capture_source:
            capture.captureSource === "camera" ? "camera" : "upload",
          document_side: "single",
          quality_status: capture.qualityStatus || "not_assessed",
          quality_score: capture.qualityScore ?? null,
          quality_flags: capture.qualityFlags || [],
          retention_until: addDaysIso(365),
          retention_basis: "hotel_policy",
          metadata: {
            workflow: "simple_front_desk_multi_occupant_rev6",
            raw_ocr_text_stored: false,
            raw_qr_payload_stored: false,
            government_verification_claimed: false,
          },
        },
      }
    );
    if (registrationError) throw registrationError;

    const savedDocument = registration?.document || registration;
    const savedDocumentId = savedDocument?.id || documentId;
    if (analysis) {
      await recordGuestDocumentExtraction({
        hotelId: currentHotel.id,
        documentId: savedDocumentId,
        analysis,
      });
    }
    return savedDocumentId;
  };

  const saveCapturedIdsAfterCheckin = async (checkinResult, consentFailedKeys = new Set()) => {
    const warnings = [];
    const documents = [];

    if (idCapture?.file && !consentFailedKeys.has("primary")) {
      try {
        const savedDocumentId = await saveCapturedIdForGuest({
          capture: idCapture,
          guestId: checkinResult?.guest_id,
          guestSessionId: checkinResult?.guest_session_id,
          documentId: idDocumentId,
          documentRequestId: idRequestId,
          fallbackGuest: guest,
        });
        if (savedDocumentId) {
          documents.push({
            documentId: savedDocumentId,
            guestName: guest.full_name || "Primary guest",
            idType: guest.id_type,
            idNumber: guest.id_number,
            capture: idCapture,
          });
        }
      } catch (documentError) {
        console.error("Primary guest ID save error:", documentError);
        warnings.push(
          documentError.message ||
            "Primary guest checked in, but the ID image could not be saved."
        );
      }
    }

    const resultCompanions = Array.isArray(checkinResult?.companions)
      ? checkinResult.companions
      : [];

    for (const companion of companions) {
      if (!companion.id_capture?.file) continue;
      if (consentFailedKeys.has(companion.client_id)) continue;

      const resultCompanion = resultCompanions.find(
        (item) => item?.client_id === companion.client_id
      );

      if (!resultCompanion?.guest_id) {
        warnings.push(
          `${companion.full_name || "Companion"} was checked in, but StayQR could not link the captured ID to the companion profile.`
        );
        continue;
      }

      try {
        const savedDocumentId = await saveCapturedIdForGuest({
          capture: companion.id_capture,
          guestId: resultCompanion.guest_id,
          guestSessionId: checkinResult?.guest_session_id,
          documentId: companion.id_document_id,
          documentRequestId: companion.id_request_id,
          fallbackGuest: companion,
        });
        if (savedDocumentId) {
          documents.push({
            documentId: savedDocumentId,
            guestName: companion.full_name || "Companion",
            idType: companion.id_type,
            idNumber: companion.id_number,
            capture: companion.id_capture,
          });
        }
      } catch (documentError) {
        console.error("Companion ID save error:", documentError);
        warnings.push(
          `${companion.full_name || "Companion"} was checked in, but the ID image could not be saved.`
        );
      }
    }

    return { warnings, documents };
  };

  const recordKycCaptureConsents = async (checkinResult) => {
    const warnings = [];
    const failedKeys = new Set();
    const resultCompanions = Array.isArray(checkinResult?.companions)
      ? checkinResult.companions
      : [];

    const recordConsent = async ({ key, guestId, guestName }) => {
      if (!guestId) return;
      try {
        await setGuestConsent({
          hotelId: currentHotel.id,
          guestId,
          guestSessionId: null,
          purpose: GUEST_CONSENT_PURPOSES.KYC_CAPTURE,
          status: "granted",
          source: "staff_recorded",
          evidence: {
            workflow: "front_desk_checkin_identity_capture_rev4",
            checkin_request_id: requestId,
            checkin_guest_session_id: checkinResult?.guest_session_id || null,
            confirmed_before_checkin: true,
            captured_for_guest: guestName || null,
          },
        });
      } catch (consentError) {
        console.error("KYC capture consent save error:", consentError);
        failedKeys.add(key);
        warnings.push(
          `${guestName || "Guest"} was checked in, but KYC consent evidence could not be recorded. The captured ID was not stored.`
        );
      }
    };

    if (idCapture?.file) {
      await recordConsent({
        key: "primary",
        guestId: checkinResult?.guest_id,
        guestName: guest.full_name || "Primary guest",
      });
    }

    for (const companion of companions) {
      if (!companion.id_capture?.file) continue;
      const mappedCompanion = resultCompanions.find(
        (item) => item?.client_id === companion.client_id
      );
      if (!mappedCompanion?.guest_id) continue;
      await recordConsent({
        key: companion.client_id,
        guestId: mappedCompanion.guest_id,
        guestName: companion.full_name || "Companion",
      });
    }

    return { warnings, failedKeys };
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
          client_id: item.client_id,
          full_name: item.full_name.trim(),
          phone: item.phone.trim(),
          email: item.email.trim(),
          id_type: item.id_type.trim(),
          id_number: item.id_number.trim(),
          date_of_birth: item.date_of_birth,
          gender: item.gender,
          nationality: item.nationality,
          country_of_residence: item.country_of_residence,
          address_line1: item.address_line1,
          city: item.city,
          state_region: item.state_region,
          postal_code: item.postal_code,
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

      const { warnings: consentWarnings, failedKeys: consentFailedKeys } =
        hasCapturedIdentityDocuments
          ? await recordKycCaptureConsents(data)
          : { warnings: [], failedKeys: new Set() };

      const { warnings: documentWarnings, documents: printDocuments } =
        await saveCapturedIdsAfterCheckin(data, consentFailedKeys);
      const documentWarning = [...consentWarnings, ...documentWarnings].join(" ");
      setIdSaveWarning(documentWarning);
      setSavedPrintDocuments(printDocuments);
      setPrintError("");

      setResult(data);
      setMessage(
        data?.idempotent
          ? "This request was already completed earlier. The existing result was returned safely."
          : `${occupancy.total} guest${occupancy.total === 1 ? "" : "s"} checked in to Room ${data?.room_number || selectedRoom?.room_number || ""}.${documentWarning ? " Check the ID save warning below." : ""}`
      );

      await fetchAvailableRooms(currentHotel.id);
    } catch (checkInError) {
      console.error("Atomic walk-in check-in error:", checkInError);
      setError(checkInError.message || "Unable to complete walk-in check-in.");
    } finally {
      setLoading(false);
    }
  };

  const printSnapshot = () => ({
    hotel: currentHotel,
    staff: currentStaff,
    guest,
    companions,
    stayDetails,
    result,
    roomCharge,
    checkinTime,
    checkoutTime,
    notes,
    documentEntries: savedPrintDocuments,
  });

  const capturedIdCount =
    (idCapture?.file ? 1 : 0) +
    companions.filter((item) => item.id_capture?.file).length;
  const printDocumentsReady = capturedIdCount === savedPrintDocuments.length;

  const handlePrintPack = async () => {
    if (!result || printingPack) return;
    if (!printDocumentsReady) {
      setPrintError(
        "One or more captured ID documents were not saved securely. Print the registration card only until the ID save issue is resolved."
      );
      return;
    }
    setPrintingPack(true);
    setPrintError("");
    try {
      await printCheckInPack(printSnapshot());
    } catch (printPackError) {
      console.error("Check-in pack print error:", printPackError);
      setPrintError(
        printPackError.message || "Unable to prepare the check-in pack for printing."
      );
    } finally {
      setPrintingPack(false);
    }
  };

  const handlePrintRegistrationCard = () => {
    if (!result) return;
    setPrintError("");
    try {
      printRegistrationCard(printSnapshot());
    } catch (registrationPrintError) {
      console.error("Registration card print error:", registrationPrintError);
      setPrintError(
        registrationPrintError.message || "Unable to prepare the registration card for printing."
      );
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
              <span>
                {occupancy.total} guest{occupancy.total === 1 ? "" : "s"} linked to the same room stay.
              </span>
              <small className="simple-checkin-guide-active">
                Guest Guide activated automatically. The permanent Room {result.room_number} QR is ready now and stays valid until {formatStayAccessTime(checkoutTime)}.
              </small>
              {(idCapture?.file || companions.some((item) => item.id_capture?.file)) && !idSaveWarning && (
                <small>Captured ID documents were saved privately to the correct guest profiles.</small>
              )}
              {idSaveWarning && <div className="checkin-alert checkin-alert--warning">{idSaveWarning}</div>}
              {printError && <div className="checkin-alert checkin-alert--error">{printError}</div>}
              <div className="simple-checkin-print-note">
                <strong>Front-desk paperwork ready</strong>
                <span>Print a guest registration card, or include securely captured ID copies. The browser print dialog also supports Save as PDF.</span>
              </div>
            </div>
            <div className="simple-checkin-success-actions">
              <button
                type="button"
                className="simple-print-pack-action"
                onClick={handlePrintPack}
                disabled={printingPack || !printDocumentsReady}
              >
                {printingPack
                  ? "Preparing pack…"
                  : !printDocumentsReady
                    ? "ID save issue — pack unavailable"
                    : "Print check-in pack"}
              </button>
              <button
                type="button"
                className="simple-registration-action"
                onClick={handlePrintRegistrationCard}
              >
                Registration card only
              </button>
              <button type="button" className="simple-next-checkin-action" onClick={resetForm}>
                Check in another guest
              </button>
            </div>
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

            <section className="simple-checkin-card simple-occupants-card">
              <div className="simple-section-title">
                <span>4</span>
                <div>
                  <h2>Guests staying in this room</h2>
                  <p>Add every person staying in the room. Adults can scan an ID; children can be added with basic details.</p>
                </div>
                <div className="simple-occupancy-summary">
                  <strong>{occupancy.adults} adult{occupancy.adults === 1 ? "" : "s"}</strong>
                  <span>{occupancy.children} child{occupancy.children === 1 ? "" : "ren"}</span>
                  <em>{occupancy.total} total</em>
                </div>
              </div>

              <div className="simple-primary-occupant">
                <div className="simple-occupant-number">1</div>
                <div>
                  <span>Primary guest</span>
                  <strong>{guest.full_name || "Enter primary guest name above"}</strong>
                  <small>{idCapture?.file ? "ID captured" : "ID optional / not captured yet"}</small>
                </div>
                <span className="simple-occupant-chip">Adult</span>
              </div>

              <div className="simple-occupant-list">
                {companions.map((companion, index) => (
                  <article className="simple-occupant-card" key={companion.client_id}>
                    <header className="simple-occupant-head">
                      <div>
                        <span className="simple-occupant-number">{index + 2}</span>
                        <div>
                          <strong>Guest {index + 2}</strong>
                          <small>{companion.guest_category === "adult" ? "Accompanying adult" : companion.guest_category === "infant" ? "Infant" : "Child"}</small>
                        </div>
                      </div>
                      <button type="button" onClick={() => removeCompanion(companion.client_id)}>Remove</button>
                    </header>

                    <div className="simple-occupant-fields">
                      <label>
                        <span>Full name *</span>
                        <input
                          value={companion.full_name}
                          onChange={(event) => updateCompanion(companion.client_id, "full_name", event.target.value)}
                          placeholder="Guest full name"
                        />
                      </label>
                      <label>
                        <span>Category</span>
                        <select
                          value={companion.guest_category}
                          onChange={(event) => updateCompanion(companion.client_id, "guest_category", event.target.value)}
                        >
                          <option value="adult">Adult</option>
                          <option value="child">Child</option>
                          <option value="infant">Infant</option>
                        </select>
                      </label>
                      <label>
                        <span>Relationship</span>
                        <input
                          value={companion.relationship}
                          onChange={(event) => updateCompanion(companion.client_id, "relationship", event.target.value)}
                          placeholder="Spouse, child, parent…"
                        />
                      </label>
                      <label>
                        <span>Date of birth</span>
                        <input
                          type="date"
                          value={companion.date_of_birth}
                          onChange={(event) => updateCompanion(companion.client_id, "date_of_birth", event.target.value)}
                        />
                      </label>
                    </div>

                    <SimpleGuestIdCapture
                      compact
                      hotelId={currentHotel?.id || null}
                      value={companion.id_capture}
                      onChange={(capture) => updateCompanionCapture(companion.client_id, capture)}
                      onExtracted={(analysis) => handleCompanionIdExtracted(companion.client_id, analysis)}
                      disabled={loading}
                    />

                    <details className="simple-companion-review">
                      <summary>Contact & extracted details</summary>
                      <div className="simple-occupant-fields review">
                        <label><span>Phone</span><input value={companion.phone} onChange={(event) => updateCompanion(companion.client_id, "phone", event.target.value)} /></label>
                        <label><span>Email</span><input type="email" value={companion.email} onChange={(event) => updateCompanion(companion.client_id, "email", event.target.value)} /></label>
                        <label><span>ID type</span><select value={companion.id_type} onChange={(event) => updateCompanion(companion.client_id, "id_type", event.target.value)}><option value="">Select ID</option><option value="aadhaar">Aadhaar</option><option value="passport">Passport</option><option value="pan">PAN</option><option value="driving_licence">Driving licence</option><option value="voter_id">Voter ID</option><option value="other">Other</option></select></label>
                        <label><span>ID number</span><input value={companion.id_number} onChange={(event) => updateCompanion(companion.client_id, "id_number", event.target.value)} placeholder="Masked / extracted ID" /></label>
                        <label><span>Gender</span><select value={companion.gender} onChange={(event) => updateCompanion(companion.client_id, "gender", event.target.value)}><option value="">Not specified</option><option value="male">Male</option><option value="female">Female</option><option value="non_binary">Non-binary</option><option value="other">Other</option><option value="prefer_not_to_say">Prefer not to say</option></select></label>
                        <label><span>Nationality</span><input value={companion.nationality} onChange={(event) => updateCompanion(companion.client_id, "nationality", event.target.value)} /></label>
                        <label className="wide simple-inline-check">
                          <input
                            type="checkbox"
                            checked={companion.form_c_required}
                            onChange={(event) => updateCompanion(companion.client_id, "form_c_required", event.target.checked)}
                          />
                          <span>Form C required for this companion</span>
                        </label>
                        <label className="wide"><span>Address</span><input value={companion.address_line1} onChange={(event) => updateCompanion(companion.client_id, "address_line1", event.target.value)} /></label>
                      </div>
                    </details>
                  </article>
                ))}
              </div>

              <button type="button" className="simple-add-occupant" onClick={addCompanion}>
                + Add another guest
              </button>
            </section>

            {hasCapturedIdentityDocuments && (
              <section className="simple-checkin-card simple-kyc-consent-card">
                <label className="simple-kyc-consent-control">
                  <input
                    type="checkbox"
                    checked={kycCaptureConsentConfirmed}
                    onChange={(event) => setKycCaptureConsentConfirmed(event.target.checked)}
                    disabled={loading}
                  />
                  <span>
                    <strong>KYC / identity-document storage consent</strong>
                    <small>
                      I confirm that each guest whose ID is captured has consented to this hotel securely storing the identity-document copy for check-in/compliance according to hotel policy.
                    </small>
                  </span>
                </label>
                <p>Required only when a captured ID image or PDF will be stored. StayQR keeps the visible ID reference masked.</p>
              </section>
            )}

            <section className="simple-more-wrap">
              <button type="button" className="simple-more-toggle" onClick={() => setShowMoreOptions((current) => !current)}>
                <span>{showMoreOptions ? "−" : "+"}</span>
                {showMoreOptions ? "Hide extra check-in options" : "More check-in options"}
                <small>Charge, language, travel and foreign guest details</small>
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


function formatStayAccessTime(value) {
  if (!value) return "checkout";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? "checkout" : parsed.toLocaleString("en-IN");
}
