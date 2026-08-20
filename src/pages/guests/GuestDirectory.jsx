import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { loadTenantContext } from "../../lib/tenantContext";
import DocumentScanner from "../../components/guests/DocumentScanner";
import GuestIdentityCompliance from "../../components/guests/GuestIdentityCompliance";
import {
  auditGuestDocumentAccess,
  exportGuestDirectory360,
  getGuest360Directory,
  prepareManualWhatsAppContact,
} from "../../lib/guestCompliance";
import "./GuestDirectory.css";

const EMPTY_PROFILE = {
  sessions: [],
  notes: [],
  preferences: [],
  documents: [],
  companions: [],
  stayDetails: [],
  roomHistory: [],
  payments: [],
};

const KYC_BUCKET = "guest-documents";
const MAX_KYC_FILE_SIZE = 15 * 1024 * 1024;
const KYC_MIME_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "application/pdf",
]);

const EXPORT_COLUMN_OPTIONS = [
  { key: "guest_name", label: "Guest name" },
  { key: "phone", label: "Phone" },
  { key: "email", label: "Email" },
  { key: "preferred_language", label: "Preferred language" },
  { key: "nationality", label: "Nationality" },
  { key: "country_of_residence", label: "Country of residence" },
  { key: "current_status", label: "Current status" },
  { key: "current_room", label: "Current room" },
  { key: "check_in", label: "Check-in" },
  { key: "check_out", label: "Check-out" },
  { key: "total_stays", label: "Total stays" },
  { key: "last_stay", label: "Last stay" },
  { key: "created_at", label: "Profile created" },
  { key: "kyc_status", label: "KYC status" },
  { key: "kyc_document_count", label: "KYC document count" },
  { key: "whatsapp_transactional_consent", label: "Transactional WhatsApp consent" },
  { key: "whatsapp_marketing_consent", label: "Marketing WhatsApp consent" },
  { key: "whatsapp_suppressed", label: "WhatsApp suppressed" },
];

function createEmptyKycForm() {
  return {
    documentType: "aadhaar",
    documentNumberMasked: "",
    issueCountry: "",
    issuedOn: "",
    expiresOn: "",
    documentSide: "single",
    captureSource: "upload",
    qualityStatus: "not_assessed",
    qualityScore: null,
    qualityFlags: [],
    retentionDays: "365",
    retentionBasis: "hotel_policy",
    file: null,
  };
}

export default function GuestDirectory({ currentHotel, onNotice }) {
  const [loading, setLoading] = useState(true);
  const [guests, setGuests] = useState([]);
  const [sessions, setSessions] = useState([]);
  const [guest360Rows, setGuest360Rows] = useState([]);
  const [searchTerm, setSearchTerm] = useState("");
  const [directoryFilters, setDirectoryFilters] = useState({
    stay: "all", nationality: "all", room: "all", repeat: "all", kyc: "all", whatsapp: "all",
    dateFrom: "", dateTo: "",
  });
  const [exportPanelOpen, setExportPanelOpen] = useState(false);
  const [exportReason, setExportReason] = useState("");
  const [exportIncludeKyc, setExportIncludeKyc] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [exportColumns, setExportColumns] = useState([
    "guest_name", "phone", "email", "nationality", "current_status", "current_room", "total_stays", "last_stay",
  ]);
  const [selectedGuest, setSelectedGuest] = useState(null);
  const [profile, setProfile] = useState(EMPTY_PROFILE);
  const [profileLoading, setProfileLoading] = useState(false);
  const [noteType, setNoteType] = useState("general");
  const [noteText, setNoteText] = useState("");
  const [preferenceKey, setPreferenceKey] = useState("");
  const [preferenceValue, setPreferenceValue] = useState("");
  const [savingNote, setSavingNote] = useState(false);
  const [savingPreference, setSavingPreference] = useState(false);
  const [kycForm, setKycForm] = useState(createEmptyKycForm);
  const [kycDocumentId, setKycDocumentId] = useState(createUuid);
  const [kycRequestId, setKycRequestId] = useState(createUuid);
  const [kycDocumentGroupId, setKycDocumentGroupId] = useState(createUuid);
  const [kycFileInputKey, setKycFileInputKey] = useState(0);
  const [kycUploading, setKycUploading] = useState(false);
  const [openingDocumentId, setOpeningDocumentId] = useState(null);
  const [reviewingDocumentId, setReviewingDocumentId] = useState(null);
  const [deletingDocumentId, setDeletingDocumentId] = useState(null);
  const [kycPermissions, setKycPermissions] = useState({
    canView: false,
    canUpload: false,
    canReview: false,
    canDelete: false,
  });

  useEffect(() => {
    if (!currentHotel?.id) return;
    loadDirectory();
    loadKycPermissions();
    // The directory reloads only when the canonical tenant hotel changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentHotel?.id]);

  async function loadKycPermissions() {
    try {
      const context = await loadTenantContext();
      const permissions = context?.permissions || [];
      setKycPermissions({
        canView: permissions.some((permission) =>
          ["guests.manage", "checkin.manage", "checkout.manage"].includes(permission)
        ),
        canUpload: permissions.some((permission) =>
          ["guests.manage", "checkin.manage"].includes(permission)
        ),
        canReview: permissions.includes("guests.manage"),
        canDelete: permissions.includes("guests.manage"),
      });
    } catch (error) {
      console.error("KYC permission load error:", error);
      setKycPermissions({
        canView: false,
        canUpload: false,
        canReview: false,
        canDelete: false,
      });
    }
  }

  async function loadDirectory() {
    if (!currentHotel?.id) return;

    setLoading(true);

    try {
      const [guestResult, sessionResult, documentResult] = await Promise.all([
        supabase
          .from("guests")
          .select(`
            id,
            hotel_id,
            full_name,
            phone,
            email,
            id_type,
            id_number,
            preferred_language,
            date_of_birth,
            gender,
            nationality,
            country_of_residence,
            address_line1,
            address_line2,
            city,
            state_region,
            postal_code,
            purpose_of_visit,
            is_foreign_guest,
            normalized_phone,
            normalized_email,
            normalized_id_type,
            normalized_id_number,
            identity_verification_status,
            created_at,
            updated_at
          `)
          .eq("hotel_id", currentHotel.id)
          .order("updated_at", { ascending: false }),
        supabase
          .from("guest_sessions")
          .select(`
            id,
            hotel_id,
            guest_id,
            room_id,
            status,
            checkin_time,
            checkout_time,
            extended_until,
            created_at,
            rooms (
              id,
              room_number,
              room_type
            )
          `)
          .eq("hotel_id", currentHotel.id)
          .order("checkin_time", { ascending: false }),
        getGuest360Directory(currentHotel.id),
      ]);

      if (guestResult.error) throw guestResult.error;
      if (sessionResult.error) throw sessionResult.error;
      setGuests(guestResult.data || []);
      setSessions(sessionResult.data || []);
      setGuest360Rows(Array.isArray(documentResult) ? documentResult : []);
    } catch (error) {
      console.error("Guest directory load error:", error);
      onNotice?.("error", error.message || "Unable to load guest directory.");
    } finally {
      setLoading(false);
    }
  }

  const directoryRows = useMemo(() => {
    const sessionsByGuest = new Map();
    const summaryByGuest = new Map(guest360Rows.map((row) => [row.guest_id, row]));

    for (const session of sessions) {
      const current = sessionsByGuest.get(session.guest_id) || [];
      current.push(session);
      sessionsByGuest.set(session.guest_id, current);
    }

    return guests.map((guest) => {
      const guestSessions = sessionsByGuest.get(guest.id) || [];
      const summary = summaryByGuest.get(guest.id) || {};
      const activeStay = guestSessions.find((session) => session.status === "active") || null;
      const totalStays = Number(summary.total_stays ?? guestSessions.length ?? 0);
      const completedStays = Number(
        summary.completed_stays ?? guestSessions.filter((session) => session.status !== "active").length
      );

      return {
        guest,
        stays: guestSessions,
        totalStays,
        completedStays,
        activeStay,
        lastStay: guestSessions[0] || null,
        lastStayAt: summary.last_stay_at || guestSessions[0]?.checkin_time || null,
        repeatGuest: totalStays > 1,
        documentCount: Number(summary.document_count || 0),
        verifiedDocument: Boolean(summary.verified_document),
        kycCaptureConsent: Boolean(summary.kyc_capture_consent),
        aadhaarOfflineConsent: Boolean(summary.aadhaar_offline_consent),
        whatsappTransactionalConsent: Boolean(summary.whatsapp_transactional_consent),
        whatsappMarketingConsent: Boolean(summary.whatsapp_marketing_consent),
        whatsappSuppressed: Boolean(summary.whatsapp_suppressed),
      };
    });
  }, [guests, sessions, guest360Rows]);

  const filterOptions = useMemo(() => ({
    nationalities: [...new Set(directoryRows.map((row) => row.guest.nationality).filter(Boolean))].sort(),
    rooms: [...new Set(directoryRows.map((row) => row.activeStay?.rooms?.room_number).filter(Boolean))].sort(),
  }), [directoryRows]);

  const visibleRows = useMemo(() => {
    const term = searchTerm.trim().toLowerCase();
    const fromTime = directoryFilters.dateFrom ? new Date(`${directoryFilters.dateFrom}T00:00:00`).getTime() : null;
    const toTime = directoryFilters.dateTo ? new Date(`${directoryFilters.dateTo}T23:59:59`).getTime() : null;

    return directoryRows.filter((row) => {
      const { guest, activeStay } = row;
      const searchable = [
        guest.full_name,
        guest.phone,
        guest.normalized_phone,
        guest.email,
        guest.normalized_email,
        guest.id_type,
        guest.id_number,
        guest.normalized_id_number,
        activeStay?.rooms?.room_number,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      if (term && !searchable.includes(term)) return false;
      if (directoryFilters.stay === "in_house" && !activeStay) return false;
      if (directoryFilters.stay === "past" && activeStay) return false;
      if (directoryFilters.nationality !== "all" && guest.nationality !== directoryFilters.nationality) return false;
      if (directoryFilters.room !== "all" && activeStay?.rooms?.room_number !== directoryFilters.room) return false;
      if (directoryFilters.repeat === "repeat" && !row.repeatGuest) return false;
      if (directoryFilters.repeat === "first" && row.repeatGuest) return false;
      const effectiveKyc = row.verifiedDocument || guest.identity_verification_status === "verified"
        ? "verified"
        : row.documentCount > 0 || guest.identity_verification_status === "pending"
          ? "pending"
          : "unverified";
      if (directoryFilters.kyc !== "all" && effectiveKyc !== directoryFilters.kyc) return false;
      if (directoryFilters.whatsapp === "transactional" && (!row.whatsappTransactionalConsent || row.whatsappSuppressed)) return false;
      if (directoryFilters.whatsapp === "marketing" && (!row.whatsappMarketingConsent || row.whatsappSuppressed)) return false;
      if (directoryFilters.whatsapp === "suppressed" && !row.whatsappSuppressed) return false;
      if (directoryFilters.whatsapp === "none" && (row.whatsappTransactionalConsent || row.whatsappMarketingConsent)) return false;
      const stayTime = row.lastStayAt ? new Date(row.lastStayAt).getTime() : null;
      if (fromTime && (!stayTime || stayTime < fromTime)) return false;
      if (toTime && (!stayTime || stayTime > toTime)) return false;
      return true;
    });
  }, [directoryRows, searchTerm, directoryFilters]);

  const metrics = useMemo(() => {
    return {
      total: directoryRows.length,
      active: directoryRows.filter((row) => row.activeStay).length,
      repeat: directoryRows.filter((row) => row.repeatGuest).length,
      verified: directoryRows.filter(
        (row) => row.verifiedDocument || row.guest.identity_verification_status === "verified"
      ).length,
    };
  }, [directoryRows]);

  function toggleExportColumn(column) {
    setExportColumns((current) => current.includes(column)
      ? current.filter((item) => item !== column)
      : [...current, column]);
  }

  async function exportGuestDirectory() {
    if (visibleRows.length === 0) {
      onNotice?.("error", "There are no guest records to export.");
      return;
    }
    if (exportReason.trim().length < 3) {
      onNotice?.("error", "Enter an export reason of at least 3 characters.");
      return;
    }
    if (exportColumns.length === 0) {
      onNotice?.("error", "Select at least one export column.");
      return;
    }

    setExporting(true);
    try {
      const result = await exportGuestDirectory360({
        hotelId: currentHotel.id,
        guestIds: visibleRows.map((row) => row.guest.id),
        reason: exportReason.trim(),
        columns: exportColumns,
        filters: directoryFilters,
        includeKyc: exportIncludeKyc,
      });
      const columns = Array.isArray(result?.columns) ? result.columns : exportColumns;
      const records = Array.isArray(result?.rows) ? result.rows : [];
      const csv = [
        columns,
        ...records.map((record) => columns.map((column) => record?.[column] ?? "")),
      ].map((row) => row.map(escapeCsvValue).join(",")).join("\r\n");
      const blob = new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      const hotelName = sanitizeDownloadFileName(currentHotel?.hotel_name || currentHotel?.name || "hotel");
      anchor.href = url;
      anchor.download = `${hotelName}-guest-360-${new Date().toISOString().slice(0, 10)}.csv`;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);
      setExportPanelOpen(false);
      setExportReason("");
      onNotice?.("success", `Controlled export created for ${Number(result?.guest_count || records.length)} guest record(s).`);
    } catch (error) {
      console.error("Guest directory export error:", error);
      onNotice?.("error", error.message || "Unable to create the controlled guest export.");
    } finally {
      setExporting(false);
    }
  }

  async function openWhatsApp(row) {
    const confirmed = window.confirm(
      "Confirm the guest has consented to receive this transactional message on WhatsApp. StayQR will also re-check stored consent and suppression before opening WhatsApp."
    );
    if (!confirmed) return;

    try {
      const prepared = await prepareManualWhatsAppContact({
        hotelId: currentHotel.id,
        guestId: row.guest.id,
        purpose: "transactional",
      });
      const hotelName = currentHotel?.hotel_name || currentHotel?.name || "the hotel";
      const message = `Hello ${prepared.guest_name || row.guest.full_name || "Guest"}, this is ${hotelName}. We would like to share an update regarding your stay.`;
      const destination = String(prepared.phone_e164 || "").replace(/\D/g, "");
      window.open(`https://wa.me/${destination}?text=${encodeURIComponent(message)}`, "_blank", "noopener,noreferrer");
    } catch (error) {
      onNotice?.("error", error.message || "Stored WhatsApp consent is required before contacting this guest.");
    }
  }

  async function openProfile(guest) {
    setSelectedGuest(guest);
    setProfileLoading(true);
    setProfile(EMPTY_PROFILE);
    setNoteText("");
    setPreferenceKey("");
    setPreferenceValue("");
    resetKycDraft(guest);

    try {
      const { data: guestSessions, error: sessionError } = await supabase
        .from("guest_sessions")
        .select(`
          id,
          hotel_id,
          guest_id,
          room_id,
          reservation_id,
          status,
          checkin_time,
          checkout_time,
          extended_until,
          created_at,
          rooms (
            id,
            room_number,
            room_type
          )
        `)
        .eq("hotel_id", currentHotel.id)
        .eq("guest_id", guest.id)
        .order("checkin_time", { ascending: false });

      if (sessionError) throw sessionError;

      const sessionIds = (guestSessions || []).map((session) => session.id);

      const [noteResult, preferenceResult, documentResult] = await Promise.all([
        supabase
          .from("guest_notes")
          .select("*")
          .eq("hotel_id", currentHotel.id)
          .eq("guest_id", guest.id)
          .order("created_at", { ascending: false }),
        supabase
          .from("guest_preferences")
          .select("*")
          .eq("hotel_id", currentHotel.id)
          .eq("guest_id", guest.id)
          .eq("is_active", true)
          .order("updated_at", { ascending: false }),
        supabase
          .from("guest_documents")
          .select("*")
          .eq("hotel_id", currentHotel.id)
          .eq("guest_id", guest.id)
          .is("deleted_at", null)
          .order("created_at", { ascending: false }),
      ]);

      if (noteResult.error) throw noteResult.error;
      if (preferenceResult.error) throw preferenceResult.error;
      if (documentResult.error) throw documentResult.error;

      let payments = [];
      let companions = [];
      let stayDetails = [];
      let roomHistory = [];

      if (sessionIds.length > 0) {
        const [paymentResult, companionResult, stayResult, historyResult] = await Promise.all([
          supabase
            .from("payments")
            .select("id, guest_session_id, amount, payment_type, payment_status, created_at")
            .eq("hotel_id", currentHotel.id)
            .in("guest_session_id", sessionIds)
            .order("created_at", { ascending: false }),
          supabase
            .from("guest_companions")
            .select("*")
            .eq("hotel_id", currentHotel.id)
            .in("guest_session_id", sessionIds)
            .order("created_at", { ascending: true }),
          supabase
            .from("guest_stay_details")
            .select("*")
            .eq("hotel_id", currentHotel.id)
            .in("guest_session_id", sessionIds),
          supabase
            .from("stay_room_history")
            .select(`
              *,
              rooms (
                id,
                room_number,
                room_type
              )
            `)
            .eq("hotel_id", currentHotel.id)
            .in("guest_session_id", sessionIds)
            .order("segment_start", { ascending: false }),
        ]);

        if (paymentResult.error) throw paymentResult.error;
        if (companionResult.error) throw companionResult.error;
        if (stayResult.error) throw stayResult.error;
        if (historyResult.error) throw historyResult.error;

        payments = paymentResult.data || [];
        companions = companionResult.data || [];
        stayDetails = stayResult.data || [];
        roomHistory = historyResult.data || [];

        const companionGuestIds = [...new Set(companions.map((item) => item.guest_id))];

        if (companionGuestIds.length > 0) {
          const { data: companionGuests, error: companionGuestError } = await supabase
            .from("guests")
            .select("id, full_name, phone, id_type, id_number, is_foreign_guest")
            .eq("hotel_id", currentHotel.id)
            .in("id", companionGuestIds);

          if (companionGuestError) throw companionGuestError;

          const guestMap = new Map((companionGuests || []).map((item) => [item.id, item]));
          companions = companions.map((item) => ({
            ...item,
            guest: guestMap.get(item.guest_id) || null,
          }));
        }
      }

      setProfile({
        sessions: guestSessions || [],
        notes: noteResult.data || [],
        preferences: preferenceResult.data || [],
        documents: documentResult.data || [],
        companions,
        stayDetails,
        roomHistory,
        payments,
      });
    } catch (error) {
      console.error("Guest profile load error:", error);
      onNotice?.("error", error.message || "Unable to load guest profile.");
    } finally {
      setProfileLoading(false);
    }
  }

  function exportFormCChecklist(session, details, companions) {
    if (!selectedGuest || !session) return;

    const checklist = buildFormCChecklist({
      guest: selectedGuest,
      session,
      details,
      companions,
      documents: profile.documents,
    });

    const csvRows = [
      ["Category", "Requirement", "Required", "Status", "Value"],
      ...checklist.items.map((item) => [
        item.category,
        item.label,
        item.required ? "Yes" : "No",
        item.complete ? "Complete" : "Pending",
        item.value || "",
      ]),
    ];

    const csv = csvRows
      .map((row) => row.map(escapeCsvValue).join(","))
      .join("\r\n");
    const blob = new Blob(["\uFEFF", csv], {
      type: "text/csv;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    const roomNumber = session.rooms?.room_number || "unassigned";
    const safeGuestName = sanitizeDownloadFileName(selectedGuest.full_name);

    link.href = url;
    link.download = `StayQR-Form-C-Checklist-${safeGuestName}-Room-${roomNumber}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);

    onNotice?.(
      checklist.ready ? "success" : "warning",
      checklist.ready
        ? "Form C readiness checklist exported."
        : `Form C checklist exported with ${checklist.pendingRequired} required item(s) pending.`
    );
  }

  function closeProfile() {
    setSelectedGuest(null);
    setProfile(EMPTY_PROFILE);
  }

  async function addNote() {
    if (!selectedGuest || !noteText.trim()) return;

    setSavingNote(true);

    try {
      const { data: userData } = await supabase.auth.getUser();
      const { error } = await supabase.from("guest_notes").insert({
        hotel_id: currentHotel.id,
        guest_id: selectedGuest.id,
        note_type: noteType,
        note: noteText.trim(),
        is_private: true,
        created_by: userData?.user?.id || null,
      });

      if (error) throw error;

      setNoteText("");
      onNotice?.("success", "Guest note saved.");
      await openProfile(selectedGuest);
    } catch (error) {
      console.error("Guest note error:", error);
      onNotice?.("error", error.message || "Unable to save guest note.");
    } finally {
      setSavingNote(false);
    }
  }

  function resetKycDraft(guest = selectedGuest, { preserveGroup = false, nextSide = "single" } = {}) {
    setKycForm({
      ...createEmptyKycForm(),
      issueCountry: guest?.country_of_residence || guest?.nationality || "",
      documentSide: nextSide,
    });
    setKycDocumentId(createUuid());
    setKycRequestId(createUuid());
    if (!preserveGroup) setKycDocumentGroupId(createUuid());
    setKycFileInputKey((value) => value + 1);
  }

  async function savePreference() {
    if (!selectedGuest || !preferenceKey.trim() || !preferenceValue.trim()) return;

    setSavingPreference(true);

    try {
      const normalizedKey = preferenceKey.trim();
      const { data: existing, error: existingError } = await supabase
        .from("guest_preferences")
        .select("id")
        .eq("hotel_id", currentHotel.id)
        .eq("guest_id", selectedGuest.id)
        .eq("is_active", true)
        .ilike("preference_key", normalizedKey)
        .maybeSingle();

      if (existingError) throw existingError;

      const { data: userData } = await supabase.auth.getUser();
      const payload = {
        preference_key: normalizedKey,
        preference_value: { value: preferenceValue.trim() },
        source: "manual",
        is_active: true,
        updated_by: userData?.user?.id || null,
      };

      const result = existing?.id
        ? await supabase
            .from("guest_preferences")
            .update(payload)
            .eq("hotel_id", currentHotel.id)
            .eq("id", existing.id)
        : await supabase.from("guest_preferences").insert({
            hotel_id: currentHotel.id,
            guest_id: selectedGuest.id,
            ...payload,
            created_by: userData?.user?.id || null,
          });

      if (result.error) throw result.error;

      setPreferenceKey("");
      setPreferenceValue("");
      onNotice?.("success", "Guest preference saved.");
      await openProfile(selectedGuest);
    } catch (error) {
      console.error("Guest preference error:", error);
      onNotice?.("error", error.message || "Unable to save guest preference.");
    } finally {
      setSavingPreference(false);
    }
  }

  async function uploadGuestDocument(event) {
    event.preventDefault();

    if (!selectedGuest || !currentHotel?.id || !kycPermissions.canUpload) return;

    const file = kycForm.file;
    const mimeType = resolveFileMimeType(file);

    if (!file) {
      onNotice?.("error", "Choose a synthetic JPEG, PNG or PDF document.");
      return;
    }

    if (!KYC_MIME_TYPES.has(mimeType)) {
      onNotice?.("error", "Only JPEG, PNG and PDF files are allowed.");
      return;
    }

    if (file.size <= 0 || file.size > MAX_KYC_FILE_SIZE) {
      onNotice?.("error", "The document must be between 1 byte and 15 MB.");
      return;
    }

    if (
      kycForm.issuedOn &&
      kycForm.expiresOn &&
      new Date(`${kycForm.expiresOn}T00:00:00`) <
        new Date(`${kycForm.issuedOn}T00:00:00`)
    ) {
      onNotice?.("error", "Document expiry cannot be before its issue date.");
      return;
    }

    const activeSession =
      profile.sessions.find((session) => session.status === "active") || null;
    const retentionDays = Number.parseInt(kycForm.retentionDays, 10);
    if (!Number.isFinite(retentionDays) || retentionDays < 1 || retentionDays > 3650) {
      onNotice?.("error", "Retention must be between 1 and 3650 days.");
      return;
    }
    const retentionUntil = new Date();
    retentionUntil.setUTCDate(retentionUntil.getUTCDate() + retentionDays);
    const storageFileName = sanitizeStorageFileName(file.name);
    const storagePath = `${currentHotel.id}/${selectedGuest.id}/${kycDocumentId}/${storageFileName}`;

    setKycUploading(true);

    try {
      const uploadResult = await supabase.storage
        .from(KYC_BUCKET)
        .upload(storagePath, file, {
          cacheControl: "3600",
          contentType: mimeType,
          upsert: false,
        });

      if (uploadResult.error && !isExistingStorageObjectError(uploadResult.error)) {
        throw uploadResult.error;
      }

      const { data, error } = await supabase.rpc("register_guest_document", {
        target_hotel_id: currentHotel.id,
        payload: {
          document_id: kycDocumentId,
          request_id: kycRequestId,
          guest_id: selectedGuest.id,
          guest_session_id: activeSession?.id || null,
          reservation_id: activeSession?.reservation_id || null,
          document_type: kycForm.documentType,
          storage_bucket: KYC_BUCKET,
          storage_path: storagePath,
          original_file_name: file.name,
          mime_type: mimeType,
          file_size_bytes: file.size,
          document_number_masked:
            kycForm.documentNumberMasked.trim() || null,
          issue_country: kycForm.issueCountry.trim() || null,
          issued_on: kycForm.issuedOn || null,
          expires_on: kycForm.expiresOn || null,
          document_group_id: kycDocumentGroupId,
          capture_source: kycForm.captureSource,
          document_side: kycForm.documentSide,
          quality_status: kycForm.qualityStatus,
          quality_score: kycForm.qualityScore,
          quality_flags: kycForm.qualityFlags,
          retention_until: retentionUntil.toISOString(),
          retention_basis: kycForm.retentionBasis || "hotel_policy",
          metadata: {
            source: "guest_directory",
            workflow: "postlaunch_batch3_private_kyc",
            raw_document_number_stored: false,
          },
        },
      });

      if (error) throw error;

      onNotice?.(
        "success",
        data?.idempotent
          ? "KYC upload retry resolved without creating a duplicate."
          : "Private KYC document uploaded for review."
      );

      const keepGroupForBack = kycForm.documentSide === "front";
      resetKycDraft(selectedGuest, {
        preserveGroup: keepGroupForBack,
        nextSide: keepGroupForBack ? "back" : "single",
      });
      await Promise.all([openProfile(selectedGuest), loadDirectory()]);
    } catch (error) {
      console.error("Guest KYC upload error:", error);
      onNotice?.(
        "error",
        `${error.message || "Unable to upload the KYC document."} The same draft can be retried safely.`
      );
    } finally {
      setKycUploading(false);
    }
  }

  async function openPrivateDocument(documentRecord) {
    if (!kycPermissions.canView) return;

    setOpeningDocumentId(documentRecord.id);

    try {
      await auditGuestDocumentAccess({
        hotelId: currentHotel.id,
        documentId: documentRecord.id,
        action: "view",
        reason: "authorized_guest_profile_view",
      });
      const { data, error } = await supabase.storage
        .from(KYC_BUCKET)
        .createSignedUrl(documentRecord.storage_path, 60);

      if (error) throw error;
      if (!data?.signedUrl) throw new Error("A temporary document link was not returned.");

      const anchor = window.document.createElement("a");
      anchor.href = data.signedUrl;
      anchor.target = "_blank";
      anchor.rel = "noopener noreferrer";
      window.document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
    } catch (error) {
      console.error("Private KYC view error:", error);
      onNotice?.("error", error.message || "Unable to open the private document.");
    } finally {
      setOpeningDocumentId(null);
    }
  }

  async function reviewGuestDocument(documentRecord, action) {
    if (!kycPermissions.canReview) return;

    let rejectionReason = null;

    if (action === "reject") {
      rejectionReason = window.prompt(
        "Enter the KYC rejection reason. This will be stored in the audit trail."
      );

      if (!rejectionReason?.trim()) return;
    }

    if (
      ["expire", "reset_pending"].includes(action) &&
      !window.confirm(
        action === "expire"
          ? "Mark this KYC document as expired?"
          : "Reset this document to pending review?"
      )
    ) {
      return;
    }

    setReviewingDocumentId(documentRecord.id);

    try {
      const { data, error } = await supabase.rpc("review_guest_document", {
        target_hotel_id: currentHotel.id,
        target_document_id: documentRecord.id,
        target_action: action,
        target_rejection_reason: rejectionReason?.trim() || null,
      });

      if (error) throw error;

      const updatedGuest = {
        ...selectedGuest,
        identity_verification_status:
          data?.guest_identity_status ||
          selectedGuest.identity_verification_status,
      };

      setSelectedGuest(updatedGuest);
      onNotice?.(
        "success",
        `KYC document ${formatReviewAction(action)}.`
      );

      await Promise.all([openProfile(updatedGuest), loadDirectory()]);
    } catch (error) {
      console.error("Guest KYC review error:", error);
      onNotice?.("error", error.message || "Unable to review the KYC document.");
    } finally {
      setReviewingDocumentId(null);
    }
  }

  async function deleteGuestDocument(documentRecord) {
    if (
      !kycPermissions.canDelete ||
      !currentHotel?.id ||
      !selectedGuest?.id ||
      !documentRecord?.id
    ) {
      return;
    }

    const confirmed = window.confirm(
      "Permanently delete this KYC file? The private storage object will be removed and the document record will be soft-deleted."
    );

    if (!confirmed) return;

    setDeletingDocumentId(documentRecord.id);

    try {
      const { data: deletionResult, error: metadataError } = await supabase.rpc(
        "soft_delete_guest_document",
        {
          target_hotel_id: currentHotel.id,
          target_document_id: documentRecord.id,
        }
      );

      if (metadataError) throw metadataError;

      const storageBucket = deletionResult?.storage_bucket || documentRecord.storage_bucket || KYC_BUCKET;
      const storagePath = deletionResult?.storage_path || documentRecord.storage_path;

      if (storagePath) {
        const { error: storageError } = await supabase.storage
          .from(storageBucket)
          .remove([storagePath]);

        if (storageError) throw storageError;
      }

      onNotice?.("success", "KYC document permanently removed.");

      await Promise.all([openProfile(selectedGuest), loadDirectory()]);
    } catch (error) {
      console.error("Guest KYC delete error:", error);
      onNotice?.(
        "error",
        error.message || "Unable to permanently remove the KYC document."
      );
    } finally {
      setDeletingDocumentId(null);
    }
  }

  const profileSummary = useMemo(() => {
    const roomCharges = profile.payments
      .filter((payment) => payment.payment_type === "room_charge")
      .reduce((sum, payment) => sum + Number(payment.amount || 0), 0);

    return {
      totalStays: profile.sessions.length,
      activeStays: profile.sessions.filter((session) => session.status === "active").length,
      completedStays: profile.sessions.filter((session) => session.status !== "active").length,
      roomCharges,
    };
  }, [profile]);

  const paymentsBySession = useMemo(() => {
    const map = new Map();
    for (const payment of profile.payments) {
      const current = map.get(payment.guest_session_id) || [];
      current.push(payment);
      map.set(payment.guest_session_id, current);
    }
    return map;
  }, [profile.payments]);

  const stayDetailsBySession = useMemo(
    () => new Map(profile.stayDetails.map((item) => [item.guest_session_id, item])),
    [profile.stayDetails]
  );

  const companionsBySession = useMemo(() => {
    const map = new Map();
    for (const companion of profile.companions) {
      const current = map.get(companion.guest_session_id) || [];
      current.push(companion);
      map.set(companion.guest_session_id, current);
    }
    return map;
  }, [profile.companions]);

  if (loading) {
    return <div className="guest-directory-empty">Loading guest directory...</div>;
  }

  return (
    <div className="guest-directory-shell">
      <div className="guest-directory-toolbar">
        <div>
          <p className="guest-directory-kicker">CANONICAL GUEST DIRECTORY</p>
          <h2>Guest profiles and stay history</h2>
          <p>Search every guest profile, review repeat stays, KYC status, notes and preferences.</p>
        </div>

        <div className="guest-directory-actions">
          <input
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
            placeholder="Search name, phone, email, ID or room..."
          />
          <button
            type="button"
            className="secondary guest-directory-export-btn"
            onClick={() => setExportPanelOpen((value) => !value)}
          >
            Controlled export
          </button>
          <button
            type="button"
            className="guest-directory-refresh-btn"
            onClick={loadDirectory}
          >
            Refresh directory
          </button>
        </div>
      </div>

      <p className="guest-directory-policy-note">
        Guest 360 exports are server-authorized, reason-audited and CSV-injection protected. CSV exports exclude identity documents and full document numbers. WhatsApp requires stored consent and suppression checks.
      </p>

      <div className="guest-directory-filters" aria-label="Guest 360 filters">
        <select value={directoryFilters.stay} onChange={(event) => setDirectoryFilters((current) => ({ ...current, stay: event.target.value }))}>
          <option value="all">All stay states</option><option value="in_house">Currently in-house</option><option value="past">Past guests</option>
        </select>
        <select value={directoryFilters.nationality} onChange={(event) => setDirectoryFilters((current) => ({ ...current, nationality: event.target.value }))}>
          <option value="all">All nationalities</option>
          {filterOptions.nationalities.map((value) => <option key={value} value={value}>{value}</option>)}
        </select>
        <select value={directoryFilters.room} onChange={(event) => setDirectoryFilters((current) => ({ ...current, room: event.target.value }))}>
          <option value="all">All active rooms</option>
          {filterOptions.rooms.map((value) => <option key={value} value={value}>{value}</option>)}
        </select>
        <select value={directoryFilters.repeat} onChange={(event) => setDirectoryFilters((current) => ({ ...current, repeat: event.target.value }))}>
          <option value="all">All guest types</option><option value="repeat">Repeat guests</option><option value="first">First-time guests</option>
        </select>
        <select value={directoryFilters.kyc} onChange={(event) => setDirectoryFilters((current) => ({ ...current, kyc: event.target.value }))}>
          <option value="all">All KYC states</option><option value="verified">Verified</option><option value="pending">Pending</option><option value="unverified">Unverified</option>
        </select>
        <select value={directoryFilters.whatsapp} onChange={(event) => setDirectoryFilters((current) => ({ ...current, whatsapp: event.target.value }))}>
          <option value="all">All WhatsApp states</option><option value="transactional">Transactional consent</option><option value="marketing">Marketing consent</option><option value="suppressed">Suppressed</option><option value="none">No consent</option>
        </select>
        <label><span>Last stay from</span><input type="date" value={directoryFilters.dateFrom} onChange={(event) => setDirectoryFilters((current) => ({ ...current, dateFrom: event.target.value }))} /></label>
        <label><span>Last stay to</span><input type="date" value={directoryFilters.dateTo} onChange={(event) => setDirectoryFilters((current) => ({ ...current, dateTo: event.target.value }))} /></label>
        <button type="button" className="secondary" onClick={() => setDirectoryFilters({ stay: "all", nationality: "all", room: "all", repeat: "all", kyc: "all", whatsapp: "all", dateFrom: "", dateTo: "" })}>Reset filters</button>
      </div>

      {exportPanelOpen && (
        <section className="guest-export-panel">
          <div>
            <p className="guest-directory-kicker">AUDITED EXPORT</p>
            <h3>Controlled Guest 360 CSV</h3>
            <p>{visibleRows.length} filtered guest(s) will be included. Every export records actor, reason, columns, filters and row count.</p>
          </div>
          <label className="guest-export-reason"><span>Export reason</span><input value={exportReason} onChange={(event) => setExportReason(event.target.value)} maxLength={500} placeholder="Example: monthly front-office reconciliation" /></label>
          <div className="guest-export-columns">
            {EXPORT_COLUMN_OPTIONS.map((item) => (
              <label key={item.key}>
                <input type="checkbox" checked={exportColumns.includes(item.key)} onChange={() => toggleExportColumn(item.key)} />
                <span>{item.label}</span>
              </label>
            ))}
          </div>
          <label className="guest-export-kyc">
            <input type="checkbox" checked={exportIncludeKyc} onChange={(event) => setExportIncludeKyc(event.target.checked)} />
            <span>Include KYC status/count summary (requires guest-management permission; never includes files or full ID numbers)</span>
          </label>
          <div className="guest-export-actions">
            <button type="button" className="secondary" onClick={() => setExportPanelOpen(false)}>Cancel</button>
            <button type="button" disabled={exporting || exportReason.trim().length < 3 || exportColumns.length === 0} onClick={exportGuestDirectory}>{exporting ? "Preparing audited export…" : "Export CSV"}</button>
          </div>
        </section>
      )}

      <div className="guest-directory-metrics">
        <Metric label="Guest profiles" value={metrics.total} />
        <Metric label="Currently in-house" value={metrics.active} />
        <Metric label="Repeat guests" value={metrics.repeat} />
        <Metric label="KYC verified" value={metrics.verified} />
      </div>

      {visibleRows.length === 0 ? (
        <div className="guest-directory-empty">No guest profile matches this search.</div>
      ) : (
        <div className="guest-directory-table-wrap">
          <table className="guest-directory-table">
            <thead>
              <tr>
                <th>Guest</th>
                <th>Contact</th>
                <th>Identity</th>
                <th>Stay history</th>
                <th>Current status</th>
                <th>KYC</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {visibleRows.map((row) => (
                <tr key={row.guest.id}>
                  <td>
                    <strong>{row.guest.full_name}</strong>
                    <div className="guest-directory-badges">
                      {row.repeatGuest && <span className="guest-chip repeat">Repeat guest</span>}
                      {row.guest.is_foreign_guest && <span className="guest-chip foreign">Foreign guest</span>}
                    </div>
                  </td>
                  <td>
                    <span>{row.guest.phone || "—"}</span>
                    <small>{row.guest.email || "No email"}</small>
                  </td>
                  <td>
                    <span>{formatIdentity(row.guest)}</span>
                    <small>{formatVerification(row.guest.identity_verification_status)}</small>
                  </td>
                  <td>
                    <strong>{row.totalStays}</strong> stay{row.totalStays === 1 ? "" : "s"}
                    <small>
                      {row.lastStay?.checkin_time
                        ? `Last: ${formatDate(row.lastStay.checkin_time)}`
                        : "No stay recorded"}
                    </small>
                  </td>
                  <td>
                    {row.activeStay ? (
                      <span className="guest-chip active">
                        In Room {row.activeStay.rooms?.room_number || "—"}
                      </span>
                    ) : (
                      <span className="guest-chip neutral">Not in-house</span>
                    )}
                  </td>
                  <td>
                    <span className={`guest-chip ${row.verifiedDocument ? "verified" : "neutral"}`}>
                      {row.verifiedDocument ? "Verified" : `${row.documentCount} document(s)`}
                    </span>
                  </td>
                  <td>
                    <div className="guest-directory-row-actions">
                      <button type="button" className="secondary" onClick={() => openWhatsApp(row)}>
                        WhatsApp
                      </button>
                      <button type="button" onClick={() => openProfile(row.guest)}>
                        View profile
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {selectedGuest && (
        <div className="guest-profile-overlay" onMouseDown={closeProfile}>
          <section className="guest-profile-panel" onMouseDown={(event) => event.stopPropagation()}>
            <header className="guest-profile-header">
              <div>
                <p className="guest-directory-kicker">GUEST PROFILE</p>
                <h2>{selectedGuest.full_name}</h2>
                <p>
                  {selectedGuest.phone || "No phone"}
                  {selectedGuest.email ? ` · ${selectedGuest.email}` : ""}
                </p>
              </div>
              <button type="button" className="guest-profile-close" onClick={closeProfile}>×</button>
            </header>

            {profileLoading ? (
              <div className="guest-directory-empty">Loading complete guest history...</div>
            ) : (
              <div className="guest-profile-content">
                <div className="guest-directory-metrics compact">
                  <Metric label="Total stays" value={profileSummary.totalStays} />
                  <Metric label="Active stays" value={profileSummary.activeStays} />
                  <Metric label="Completed" value={profileSummary.completedStays} />
                  <Metric label="Room charges" value={`₹${formatMoney(profileSummary.roomCharges)}`} />
                </div>

                <section className="guest-profile-section">
                  <h3>Identity and address</h3>
                  <div className="guest-detail-grid">
                    <Detail label="Phone" value={selectedGuest.phone} />
                    <Detail label="Email" value={selectedGuest.email} />
                    <Detail label="Identity" value={formatIdentity(selectedGuest)} />
                    <Detail label="Verification" value={formatVerification(selectedGuest.identity_verification_status)} />
                    <Detail label="Date of birth" value={formatDateOnly(selectedGuest.date_of_birth)} />
                    <Detail label="Gender" value={titleCase(selectedGuest.gender)} />
                    <Detail label="Nationality" value={selectedGuest.nationality} />
                    <Detail label="Country of residence" value={selectedGuest.country_of_residence} />
                    <Detail
                      label="Address"
                      value={[
                        selectedGuest.address_line1,
                        selectedGuest.address_line2,
                        selectedGuest.city,
                        selectedGuest.state_region,
                        selectedGuest.postal_code,
                      ].filter(Boolean).join(", ")}
                      wide
                    />
                  </div>
                </section>

                <section className="guest-profile-section">
                  <h3>Stay history</h3>
                  {profile.sessions.length === 0 ? (
                    <p className="guest-muted">No stay history recorded.</p>
                  ) : (
                    <div className="guest-history-list">
                      {profile.sessions.map((session) => {
                        const roomCharges = (paymentsBySession.get(session.id) || [])
                          .filter((payment) => payment.payment_type === "room_charge")
                          .reduce((sum, payment) => sum + Number(payment.amount || 0), 0);
                        const details = stayDetailsBySession.get(session.id);
                        const companions = companionsBySession.get(session.id) || [];

                        return (
                          <article className="guest-history-card" key={session.id}>
                            <div className="guest-history-head">
                              <div>
                                <strong>Room {session.rooms?.room_number || "—"}</strong>
                                <small>{session.rooms?.room_type || "Room"}</small>
                              </div>
                              <span className={`guest-chip ${session.status === "active" ? "active" : "neutral"}`}>
                                {titleCase(session.status)}
                              </span>
                            </div>
                            <div className="guest-history-grid">
                              <Detail label="Check-in" value={formatDateTime(session.checkin_time)} />
                              <Detail label="Checkout" value={formatDateTime(session.extended_until || session.checkout_time)} />
                              <Detail label="Room charge" value={`₹${formatMoney(roomCharges)}`} />
                              <Detail label="Companions" value={String(companions.length)} />
                              <Detail label="Purpose" value={details?.purpose_of_visit} />
                              <Detail label="Route" value={formatRoute(details)} />
                            </div>
                            {companions.length > 0 && (
                              <div className="guest-companion-line">
                                <strong>Companions:</strong>{" "}
                                {companions.map((item) => item.guest?.full_name || "Guest").join(", ")}
                              </div>
                            )}

                            {selectedGuest.is_foreign_guest && (() => {
                              const formCChecklist = buildFormCChecklist({
                                guest: selectedGuest,
                                session,
                                details,
                                companions,
                                documents: profile.documents,
                              });

                              return (
                                <div className="guest-formc-panel">
                                  <div className="guest-formc-summary">
                                    <div>
                                      <span className="guest-directory-kicker">FORM C READINESS</span>
                                      <strong>
                                        {formCChecklist.completeRequired}/{formCChecklist.requiredCount} required items complete
                                      </strong>
                                      <small>
                                        Status: {titleCase(details?.form_c_status || "pending")}
                                      </small>
                                    </div>
                                    <span
                                      className={`guest-chip ${formCChecklist.ready ? "verified" : "pending"}`}
                                    >
                                      {formCChecklist.ready ? "Ready to export" : `${formCChecklist.pendingRequired} pending`}
                                    </span>
                                  </div>

                                  <div className="guest-formc-actions">
                                    <button
                                      type="button"
                                      onClick={() =>
                                        exportFormCChecklist(session, details, companions)
                                      }
                                    >
                                      Export Form C checklist
                                    </button>
                                  </div>

                                  <details className="guest-formc-checklist">
                                    <summary>View readiness checklist</summary>
                                    <div>
                                      {formCChecklist.items.map((item) => (
                                        <article
                                          className={item.complete ? "complete" : "pending"}
                                          key={`${item.category}-${item.label}`}
                                        >
                                          <span>{item.complete ? "✓" : "!"}</span>
                                          <div>
                                            <strong>{item.label}</strong>
                                            <small>
                                              {item.category}
                                              {item.required ? " · Required" : " · Review"}
                                            </small>
                                          </div>
                                          <em>{item.value || "Pending"}</em>
                                        </article>
                                      ))}
                                    </div>
                                  </details>
                                </div>
                              );
                            })()}
                          </article>
                        );
                      })}
                    </div>
                  )}
                </section>

                <section className="guest-profile-section two-column">
                  <div>
                    <h3>Private guest notes</h3>
                    <div className="guest-inline-form">
                      <select value={noteType} onChange={(event) => setNoteType(event.target.value)}>
                        <option value="general">General</option>
                        <option value="preference">Preference</option>
                        <option value="warning">Warning</option>
                        <option value="service">Service</option>
                        <option value="recovery">Recovery</option>
                        <option value="kyc">KYC</option>
                      </select>
                      <textarea
                        value={noteText}
                        onChange={(event) => setNoteText(event.target.value)}
                        placeholder="Add a private operational note..."
                      />
                      <button type="button" disabled={savingNote || !noteText.trim()} onClick={addNote}>
                        {savingNote ? "Saving..." : "Save note"}
                      </button>
                    </div>
                    <div className="guest-record-list">
                      {profile.notes.length === 0 ? (
                        <p className="guest-muted">No notes recorded.</p>
                      ) : profile.notes.map((note) => (
                        <article key={note.id}>
                          <span className="guest-chip neutral">{titleCase(note.note_type)}</span>
                          <p>{note.note}</p>
                          <small>{formatDateTime(note.created_at)}</small>
                        </article>
                      ))}
                    </div>
                  </div>

                  <div>
                    <h3>Guest preferences</h3>
                    <div className="guest-inline-form">
                      <input
                        value={preferenceKey}
                        onChange={(event) => setPreferenceKey(event.target.value)}
                        placeholder="Preference key, e.g. pillow"
                      />
                      <input
                        value={preferenceValue}
                        onChange={(event) => setPreferenceValue(event.target.value)}
                        placeholder="Preference value, e.g. soft"
                      />
                      <button
                        type="button"
                        disabled={savingPreference || !preferenceKey.trim() || !preferenceValue.trim()}
                        onClick={savePreference}
                      >
                        {savingPreference ? "Saving..." : "Save preference"}
                      </button>
                    </div>
                    <div className="guest-record-list">
                      {profile.preferences.length === 0 ? (
                        <p className="guest-muted">No preferences recorded.</p>
                      ) : profile.preferences.map((preference) => (
                        <article key={preference.id}>
                          <strong>{preference.preference_key}</strong>
                          <p>{formatPreference(preference.preference_value)}</p>
                          <small>{titleCase(preference.source)} · {formatDateTime(preference.updated_at)}</small>
                        </article>
                      ))}
                    </div>
                  </div>
                </section>

                <GuestIdentityCompliance
                  currentHotel={currentHotel}
                  guest={selectedGuest}
                  sessions={profile.sessions}
                  canManage={kycPermissions.canUpload}
                  onNotice={onNotice}
                  onChanged={async () => {
                    await loadDirectory();
                    await openProfile(selectedGuest);
                  }}
                />

                <section className="guest-profile-section">
                  <div className="guest-kyc-heading">
                    <div>
                      <h3>Private KYC documents</h3>
                      <p className="guest-muted">
                        Files stay private in the guest-documents bucket. Viewing uses a 60-second signed link.
                      </p>
                    </div>
                    <span className="guest-chip neutral">
                      {profile.documents.length} document(s)
                    </span>
                  </div>

                  {kycPermissions.canUpload ? (
                    <form className="guest-kyc-upload-form" onSubmit={uploadGuestDocument}>
                      <div className="guest-kyc-guidance">
                        <strong>Use synthetic files during acceptance.</strong>
                        <span>Never upload a real Aadhaar, passport, PAN card or personal document for testing.</span>
                      </div>

                      <label>
                        <span>Document type</span>
                        <select
                          value={kycForm.documentType}
                          onChange={(event) =>
                            setKycForm((current) => ({
                              ...current,
                              documentType: event.target.value,
                            }))
                          }
                        >
                          <option value="aadhaar">Aadhaar</option>
                          <option value="passport">Passport</option>
                          <option value="driving_licence">Driving licence</option>
                          <option value="voter_id">Voter ID</option>
                          <option value="pan">PAN</option>
                          <option value="visa">Visa</option>
                          <option value="form_c">Form C</option>
                          <option value="other">Other</option>
                        </select>
                      </label>

                      <label>
                        <span>Masked document number</span>
                        <input
                          value={kycForm.documentNumberMasked}
                          onChange={(event) =>
                            setKycForm((current) => ({
                              ...current,
                              documentNumberMasked: event.target.value,
                            }))
                          }
                          maxLength={64}
                          placeholder="Example: TEST••••9999"
                        />
                      </label>

                      <label>
                        <span>Issue country</span>
                        <input
                          value={kycForm.issueCountry}
                          onChange={(event) =>
                            setKycForm((current) => ({
                              ...current,
                              issueCountry: event.target.value,
                            }))
                          }
                          placeholder="India"
                        />
                      </label>

                      <label>
                        <span>Issued on</span>
                        <input
                          type="date"
                          value={kycForm.issuedOn}
                          onChange={(event) =>
                            setKycForm((current) => ({
                              ...current,
                              issuedOn: event.target.value,
                            }))
                          }
                        />
                      </label>

                      <label>
                        <span>Expires on</span>
                        <input
                          type="date"
                          value={kycForm.expiresOn}
                          onChange={(event) =>
                            setKycForm((current) => ({
                              ...current,
                              expiresOn: event.target.value,
                            }))
                          }
                        />
                      </label>

                      <label>
                        <span>Document side</span>
                        <select
                          value={kycForm.documentSide}
                          onChange={(event) => setKycForm((current) => ({ ...current, documentSide: event.target.value }))}
                        >
                          <option value="single">Single / full document</option>
                          <option value="front">Front</option>
                          <option value="back">Back</option>
                        </select>
                        <small>Front and back captures can share one document group.</small>
                      </label>

                      <label>
                        <span>Retention period (days)</span>
                        <input
                          type="number" min="1" max="3650"
                          value={kycForm.retentionDays}
                          onChange={(event) => setKycForm((current) => ({ ...current, retentionDays: event.target.value }))}
                        />
                        <small>Default 365 days. Expired records enter the protected purge queue unless legal hold applies.</small>
                      </label>

                      <label>
                        <span>Retention basis</span>
                        <select
                          value={kycForm.retentionBasis}
                          onChange={(event) => setKycForm((current) => ({ ...current, retentionBasis: event.target.value }))}
                        >
                          <option value="hotel_policy">Hotel retention policy</option>
                          <option value="legal_requirement">Legal / regulatory requirement</option>
                          <option value="guest_request">Guest-requested retention</option>
                        </select>
                      </label>

                      <div className="guest-kyc-scanner-field">
                        <span>Camera scanner</span>
                        <DocumentScanner
                          disabled={kycUploading}
                          onCapture={(capture) => {
                            setKycForm((current) => ({
                              ...current,
                              file: capture.file,
                              captureSource: capture.captureSource,
                              qualityStatus: capture.qualityStatus,
                              qualityScore: capture.qualityScore,
                              qualityFlags: [
                                ...capture.qualityFlags,
                                ...(capture.cropApplied ? ["manual_crop_applied"] : []),
                              ],
                            }));
                            setKycDocumentId(createUuid());
                            setKycRequestId(createUuid());
                            setKycFileInputKey((value) => value + 1);
                          }}
                        />
                        <small>Uses the device camera with edge framing, manual crop/rotate controls, JPEG compression and glare/blur/lighting warnings. No biometric matching or OCR is performed.</small>
                      </div>

                      <label className="guest-kyc-file-field">
                        <span>Private file</span>
                        <input
                          key={kycFileInputKey}
                          type="file"
                          accept=".jpg,.jpeg,.png,.pdf,image/jpeg,image/png,application/pdf"
                          onChange={(event) => {
                            const nextFile = event.target.files?.[0] || null;
                            setKycForm((current) => ({
                              ...current,
                              file: nextFile,
                              captureSource: "upload",
                              qualityStatus: "not_assessed",
                              qualityScore: null,
                              qualityFlags: [],
                            }));
                            setKycDocumentId(createUuid());
                            setKycRequestId(createUuid());
                          }}
                        />
                        <small>JPEG, PNG or PDF · maximum 15 MB</small>
                      </label>

                      <div className="guest-kyc-request">
                        <span>Document group / request</span>
                        <code>{kycDocumentGroupId}</code>
                        <code>{kycRequestId}</code>
                        <small>{kycForm.captureSource === "camera" ? `Camera quality: ${kycForm.qualityStatus} ${kycForm.qualityScore ?? ""}/100 ${kycForm.qualityFlags.join(" · ")}` : "Uploaded file: manual visual review required."}</small>
                      </div>

                      <button
                        type="submit"
                        disabled={kycUploading || !kycForm.file}
                      >
                        {kycUploading ? "Uploading securely..." : "Upload for review"}
                      </button>
                    </form>
                  ) : (
                    <div className="guest-directory-empty compact">
                      Your role can view KYC metadata but cannot upload documents.
                    </div>
                  )}

                  {profile.documents.length === 0 ? (
                    <div className="guest-directory-empty compact">
                      No KYC document uploaded for this guest yet.
                    </div>
                  ) : (
                    <div className="guest-document-grid">
                      {profile.documents.map((documentRecord) => {
                        const statusClass = getDocumentStatusClass(
                          documentRecord.verification_status
                        );
                        const busy =
                          openingDocumentId === documentRecord.id ||
                          reviewingDocumentId === documentRecord.id ||
                          deletingDocumentId === documentRecord.id;

                        return (
                          <article key={documentRecord.id}>
                            <div className="guest-document-head">
                              <strong>{titleCase(documentRecord.document_type)}</strong>
                              <span className={`guest-chip ${statusClass}`}>
                                {titleCase(documentRecord.verification_status)}
                              </span>
                            </div>

                            <div className="guest-document-meta">
                              <KycDetail
                                label="Masked number"
                                value={documentRecord.document_number_masked}
                              />
                              <KycDetail
                                label="Issue country"
                                value={documentRecord.issue_country}
                              />
                              <KycDetail
                                label="Issued"
                                value={formatDateOnly(documentRecord.issued_on)}
                              />
                              <KycDetail
                                label="Expires"
                                value={formatDateOnly(documentRecord.expires_on)}
                              />
                              <KycDetail
                                label="File"
                                value={documentRecord.original_file_name}
                              />
                              <KycDetail
                                label="Size"
                                value={formatFileSize(documentRecord.file_size_bytes)}
                              />
                              <KycDetail label="Capture" value={`${titleCase(documentRecord.capture_source || "upload")} · ${titleCase(documentRecord.document_side || "single")}`} />
                              <KycDetail label="Quality" value={documentRecord.quality_status === "not_assessed" ? "Manual review" : `${titleCase(documentRecord.quality_status)}${documentRecord.quality_score !== null && documentRecord.quality_score !== undefined ? ` · ${documentRecord.quality_score}/100` : ""}`} />
                              <KycDetail label="Retention until" value={formatDateTime(documentRecord.retention_until)} />
                              <KycDetail label="Retention basis" value={titleCase(documentRecord.retention_basis || "hotel_policy")} />
                            </div>

                            {documentRecord.rejection_reason && (
                              <div className="guest-document-rejection">
                                <strong>Rejection reason</strong>
                                <span>{documentRecord.rejection_reason}</span>
                              </div>
                            )}

                            <small>
                              Uploaded {formatDateTime(documentRecord.created_at)}
                            </small>
                            {documentRecord.reviewed_at && (
                              <small>
                                Reviewed {formatDateTime(documentRecord.reviewed_at)}
                              </small>
                            )}

                            <div className="guest-document-actions">
                              {kycPermissions.canView && (
                                <button
                                  type="button"
                                  className="secondary"
                                  disabled={busy}
                                  onClick={() => openPrivateDocument(documentRecord)}
                                >
                                  {openingDocumentId === documentRecord.id
                                    ? "Opening..."
                                    : "View private file"}
                                </button>
                              )}

                              {kycPermissions.canReview && (
                                <>
                                  {documentRecord.verification_status !== "verified" && (
                                    <button
                                      type="button"
                                      disabled={busy}
                                      onClick={() =>
                                        reviewGuestDocument(documentRecord, "verify")
                                      }
                                    >
                                      Verify
                                    </button>
                                  )}

                                  {documentRecord.verification_status !== "rejected" && (
                                    <button
                                      type="button"
                                      className="danger"
                                      disabled={busy}
                                      onClick={() =>
                                        reviewGuestDocument(documentRecord, "reject")
                                      }
                                    >
                                      Reject
                                    </button>
                                  )}

                                  {documentRecord.verification_status !== "expired" && (
                                    <button
                                      type="button"
                                      className="secondary"
                                      disabled={busy}
                                      onClick={() =>
                                        reviewGuestDocument(documentRecord, "expire")
                                      }
                                    >
                                      Mark expired
                                    </button>
                                  )}

                                  {documentRecord.verification_status !== "pending" && (
                                    <button
                                      type="button"
                                      className="secondary"
                                      disabled={busy}
                                      onClick={() =>
                                        reviewGuestDocument(
                                          documentRecord,
                                          "reset_pending"
                                        )
                                      }
                                    >
                                      Reset pending
                                    </button>
                                  )}
                                </>
                              )}

                              {kycPermissions.canDelete && (
                                <button
                                  type="button"
                                  className="danger"
                                  disabled={busy}
                                  onClick={() => deleteGuestDocument(documentRecord)}
                                >
                                  {deletingDocumentId === documentRecord.id
                                    ? "Deleting..."
                                    : "Delete KYC"}
                                </button>
                              )}
                            </div>
                          </article>
                        );
                      })}
                    </div>
                  )}
                </section>
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
}

function buildFormCChecklist({ guest, session, details, companions, documents }) {
  const verifiedTypes = new Set(
    (documents || [])
      .filter((documentRecord) =>
        documentRecord.verification_status === "verified" &&
        (!documentRecord.guest_session_id || documentRecord.guest_session_id === session?.id)
      )
      .map((documentRecord) => documentRecord.document_type)
  );

  const requiredItems = [
    checklistItem("Guest", "Foreign guest workflow enabled", guest?.is_foreign_guest, "Yes"),
    checklistItem("Guest", "Full legal name", guest?.full_name, guest?.full_name),
    checklistItem("Guest", "Nationality", guest?.nationality, guest?.nationality),
    checklistItem("Guest", "Country of residence", guest?.country_of_residence, guest?.country_of_residence),
    checklistItem("Passport", "Passport number", details?.passport_number, maskDocumentValue(details?.passport_number)),
    checklistItem("Passport", "Passport issue country", details?.passport_issue_country, details?.passport_issue_country),
    checklistItem("Passport", "Passport issue date", details?.passport_issued_on, formatDateOnly(details?.passport_issued_on)),
    checklistItem("Passport", "Passport expiry date", details?.passport_expires_on, formatDateOnly(details?.passport_expires_on)),
    checklistItem("Visa", "Visa number", details?.visa_number, maskDocumentValue(details?.visa_number)),
    checklistItem("Visa", "Visa type", details?.visa_type, details?.visa_type),
    checklistItem("Visa", "Visa issue place", details?.visa_issue_place, details?.visa_issue_place),
    checklistItem("Visa", "Visa issue date", details?.visa_issued_on, formatDateOnly(details?.visa_issued_on)),
    checklistItem("Visa", "Visa expiry date", details?.visa_expires_on, formatDateOnly(details?.visa_expires_on)),
    checklistItem("India stay", "Date of arrival in India", details?.date_of_arrival_in_india, formatDateOnly(details?.date_of_arrival_in_india)),
    checklistItem("India stay", "Intended duration in India", Number(details?.intended_duration_in_india_days) > 0, details?.intended_duration_in_india_days ? `${details.intended_duration_in_india_days} day(s)` : ""),
    checklistItem("Hotel stay", "Hotel address line", guest?.address_line1, guest?.address_line1),
    checklistItem("Hotel stay", "City", guest?.city, guest?.city),
    checklistItem("Hotel stay", "State / region", guest?.state_region, guest?.state_region),
    checklistItem("Hotel stay", "Postal code", guest?.postal_code, guest?.postal_code),
    checklistItem("Travel", "Arriving from", details?.arrival_from, details?.arrival_from),
    checklistItem("Travel", "Next destination", details?.next_destination, details?.next_destination),
    checklistItem("Travel", "Arrival mode", details?.arrival_mode, details?.arrival_mode),
    checklistItem("Travel", "Arrival transport number", details?.arrival_transport_number, details?.arrival_transport_number),
    checklistItem("Form C", "Form C marked ready or submitted", ["ready", "submitted"].includes(details?.form_c_status), titleCase(details?.form_c_status || "pending")),
  ];

  const reviewItems = [
    checklistItem("Private KYC", "Verified passport file", verifiedTypes.has("passport"), verifiedTypes.has("passport") ? "Verified" : "Not verified", false),
    checklistItem("Private KYC", "Verified visa file", verifiedTypes.has("visa"), verifiedTypes.has("visa") ? "Verified" : "Not verified", false),
    checklistItem("Travel", "Departure mode", details?.departure_mode, details?.departure_mode, false),
    checklistItem("Travel", "Departure transport number", details?.departure_transport_number, details?.departure_transport_number, false),
    checklistItem(
      "Companions",
      "Companion Form C review",
      !(companions || []).some((item) => item.form_c_required),
      (companions || []).some((item) => item.form_c_required)
        ? `${companions.filter((item) => item.form_c_required).length} companion(s) require separate review`
        : "No companion Form C review pending",
      false
    ),
  ];

  const items = [...requiredItems, ...reviewItems];
  const requiredCount = requiredItems.length;
  const completeRequired = requiredItems.filter((item) => item.complete).length;

  return {
    items,
    requiredCount,
    completeRequired,
    pendingRequired: requiredCount - completeRequired,
    ready: completeRequired === requiredCount,
  };
}

function checklistItem(category, label, completeValue, displayValue, required = true) {
  return {
    category,
    label,
    required,
    complete: Boolean(completeValue),
    value: displayValue ? String(displayValue) : "",
  };
}

function maskDocumentValue(value) {
  const normalized = String(value || "").trim();
  if (!normalized) return "";
  if (normalized.length <= 4) return normalized;
  return `${"•".repeat(Math.min(8, normalized.length - 4))}${normalized.slice(-4)}`;
}

function escapeCsvValue(value) {
  const normalized = String(value ?? "");
  const safeValue = /^[=+\-@]/.test(normalized.trimStart()) ? `'${normalized}` : normalized;
  return `"${safeValue.replace(/"/g, '""')}"`;
}

function sanitizeDownloadFileName(value) {
  return String(value || "guest")
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9_-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 80) || "guest";
}

function Metric({ label, value }) {
  return (
    <div className="guest-directory-metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function Detail({ label, value, wide = false }) {
  return (
    <div className={`guest-detail ${wide ? "wide" : ""}`}>
      <span>{label}</span>
      <strong>{value || "—"}</strong>
    </div>
  );
}

function KycDetail({ label, value }) {
  return (
    <div>
      <span>{label}</span>
      <strong>{value || "—"}</strong>
    </div>
  );
}

function formatIdentity(guest) {
  if (!guest?.id_type && !guest?.id_number) return "No identity recorded";
  const number = guest?.id_number || guest?.normalized_id_number || "";
  const masked = number.length > 4 ? `${"•".repeat(Math.min(8, number.length - 4))}${number.slice(-4)}` : number;
  return `${titleCase(guest.id_type || guest.normalized_id_type)} ${masked}`.trim();
}

function formatVerification(status) {
  return titleCase(status || "unverified");
}

function formatPreference(value) {
  if (value && typeof value === "object" && "value" in value) return String(value.value);
  if (typeof value === "string") return value;
  return JSON.stringify(value || {});
}

function formatRoute(details) {
  if (!details) return "—";
  return [details.arrival_from, details.next_destination].filter(Boolean).join(" → ") || "—";
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleDateString("en-IN");
}

function formatDateOnly(value) {
  if (!value) return "—";
  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleDateString("en-IN");
}

function formatDateTime(value) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("en-IN");
}

function formatMoney(value) {
  return Number(value || 0).toLocaleString("en-IN", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function createUuid() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }

  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

function resolveFileMimeType(file) {
  if (!file) return "";
  if (KYC_MIME_TYPES.has(file.type)) return file.type;

  const extension = file.name.split(".").pop()?.toLowerCase();

  if (["jpg", "jpeg"].includes(extension)) return "image/jpeg";
  if (extension === "png") return "image/png";
  if (extension === "pdf") return "application/pdf";
  return "";
}

function sanitizeStorageFileName(fileName) {
  const normalized = String(fileName || "document")
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^[.-]+|[.-]+$/g, "")
    .slice(0, 180);

  return normalized || "document";
}

function isExistingStorageObjectError(error) {
  const status = Number(error?.statusCode || error?.status || 0);
  return (
    status === 409 ||
    /already exists|duplicate|resource exists/i.test(error?.message || "")
  );
}

function getDocumentStatusClass(status) {
  if (status === "verified") return "verified";
  if (status === "rejected") return "rejected";
  if (status === "expired") return "expired";
  if (status === "pending") return "pending";
  return "neutral";
}

function formatReviewAction(action) {
  const labels = {
    verify: "verified",
    reject: "rejected",
    expire: "marked expired",
    reset_pending: "reset to pending",
  };

  return labels[action] || "updated";
}

function formatFileSize(bytes) {
  const size = Number(bytes || 0);
  if (!size) return "—";
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / (1024 * 1024)).toFixed(2)} MB`;
}

function titleCase(value) {
  return String(value || "")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (character) => character.toUpperCase());
}
