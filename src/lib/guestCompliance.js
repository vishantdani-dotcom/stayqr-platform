import { supabase } from "./supabase";

export const GUEST_CONSENT_PURPOSES = Object.freeze({
  KYC_CAPTURE: "kyc_capture",
  AADHAAR_OFFLINE: "aadhaar_offline_verification",
  WHATSAPP_TRANSACTIONAL: "whatsapp_transactional",
  WHATSAPP_MARKETING: "whatsapp_marketing",
  DATA_EXPORT: "data_export",
});

async function edgeFunctionErrorMessage(error, fallbackMessage) {
  const fallback = error?.message || fallbackMessage;

  try {
    const response = error?.context;
    if (!response || typeof response !== "object") return fallback;

    if (typeof response.clone === "function") {
      const clone = response.clone();
      const payload = await clone.json();
      if (payload?.error) return String(payload.error);
      if (payload?.message) return String(payload.message);
    }

    if (typeof response.json === "function" && !response.bodyUsed) {
      const payload = await response.json();
      if (payload?.error) return String(payload.error);
      if (payload?.message) return String(payload.message);
    }
  } catch {
    // The generic FunctionsHttpError message is still better than swallowing the failure.
  }

  return fallback;
}

export async function setGuestConsent({
  hotelId,
  guestId,
  guestSessionId = null,
  purpose,
  status = "granted",
  source = "staff_recorded",
  evidence = {},
}) {
  const { data, error } = await supabase.rpc("set_guest_consent", {
    target_hotel_id: hotelId,
    target_guest_id: guestId,
    target_purpose: purpose,
    grant_consent: status === "granted",
    target_source: source,
    target_evidence: { ...evidence, guest_session_id: guestSessionId },
  });
  if (error) throw error;
  return data;
}

export async function setGuestChannelSuppression({
  hotelId,
  guestId,
  active,
  reason,
}) {
  const { data, error } = await supabase.rpc("set_guest_channel_suppression", {
    target_hotel_id: hotelId,
    target_guest_id: guestId,
    target_channel: "whatsapp",
    suppress: Boolean(active),
    target_reason: reason || null,
  });
  if (error) throw error;
  return data;
}

export async function getGuest360Directory(hotelId) {
  const { data, error } = await supabase.rpc("get_guest_360_directory", {
    target_hotel_id: hotelId,
  });
  if (error) throw error;
  return Array.isArray(data) ? data : [];
}

export async function exportGuestDirectory360({
  hotelId,
  guestIds = null,
  reason,
  columns,
  filters = {},
  includeKyc = false,
}) {
  const { data, error } = await supabase.rpc("export_guest_directory_360", {
    target_hotel_id: hotelId,
    target_guest_ids: guestIds,
    target_columns: columns,
    include_kyc_summary: Boolean(includeKyc),
    export_reason: reason,
    export_filters: filters,
  });
  if (error) throw error;
  return data || { rows: [], columns: [] };
}

export async function getGuestCommunicationAudience(hotelId) {
  const { data, error } = await supabase.rpc("get_guest_communication_audience", {
    target_hotel_id: hotelId,
  });
  if (error) throw error;
  return Array.isArray(data) ? data : [];
}

export async function prepareManualWhatsAppContact({ hotelId, guestId, purpose }) {
  const { data, error } = await supabase.rpc("prepare_manual_whatsapp_contact", {
    target_hotel_id: hotelId,
    target_guest_id: guestId,
    target_purpose: purpose,
  });
  if (error) throw error;
  return data;
}

export async function createGuestWhatsAppCampaign({
  hotelId,
  name,
  purpose,
  providerMode,
  templateName,
  templateLanguage,
  guestIds,
}) {
  const { data, error } = await supabase.rpc("create_guest_whatsapp_campaign", {
    target_hotel_id: hotelId,
    target_name: name,
    target_purpose: purpose,
    target_provider_mode: providerMode,
    target_template_name: templateName || null,
    target_template_language: templateLanguage || "en",
    target_guest_ids: guestIds,
  });
  if (error) throw error;
  return data;
}

export async function auditGuestDocumentAccess({
  hotelId,
  documentId,
  action,
  reason,
}) {
  const { data, error } = await supabase.rpc("audit_guest_document_access", {
    target_hotel_id: hotelId,
    target_document_id: documentId,
    target_action: action,
    target_reason: reason || null,
  });
  if (error) throw error;
  return data;
}

export async function verifyAadhaarOfflineXml({
  hotelId,
  guestId,
  guestSessionId = null,
  guestDocumentId = null,
  xml,
}) {
  const { data, error } = await supabase.functions.invoke("verify-aadhaar-offline", {
    body: {
      hotel_id: hotelId,
      guest_id: guestId,
      guest_session_id: guestSessionId,
      guest_document_id: guestDocumentId,
      xml,
    },
  });

  if (error) {
    const message = await edgeFunctionErrorMessage(
      error,
      "Aadhaar offline verification failed."
    );
    throw new Error(message);
  }

  if (!data?.ok) {
    throw new Error(data?.error || "Aadhaar offline verification failed.");
  }

  return data;
}

export async function sendWhatsAppCampaignRecipient({ recipientId }) {
  const { data, error } = await supabase.functions.invoke("whatsapp-send", {
    body: { recipient_id: recipientId },
  });
  if (error) throw error;
  if (!data?.ok) throw new Error(data?.error || "WhatsApp delivery failed.");
  return data;
}

export async function recordUidaiSecureQrVerification({
  hotelId,
  guestId,
  guestSessionId = null,
  guestDocumentId = null,
  confirmedUidaiReaderVerified,
  referenceLast4 = null,
  verifiedFields = {},
}) {
  const { data, error } = await supabase.rpc("record_uidai_secure_qr_reader_verification", {
    target_hotel_id: hotelId,
    target_guest_id: guestId,
    target_guest_session_id: guestSessionId,
    target_guest_document_id: guestDocumentId,
    confirmed_uidai_reader_verified: Boolean(confirmedUidaiReaderVerified),
    reference_last4: referenceLast4 || null,
    verified_fields: verifiedFields || {},
  });
  if (error) throw error;
  return data;
}

export async function getWhatsAppProviderReadiness(hotelId) {
  const [profileResult, templateResult] = await Promise.all([
    supabase
      .from("hotel_whatsapp_provider_profiles")
      .select("hotel_id, provider, business_account_id, phone_number_id, sender_display_name, status, last_verified_at")
      .eq("hotel_id", hotelId)
      .maybeSingle(),
    supabase
      .from("whatsapp_templates")
      .select("id, hotel_id, event_key, locale, template_name, body_template, status, provider_name, provider_status, provider_template_id, provider_language, provider_status_checked_at, updated_at")
      .eq("hotel_id", hotelId)
      .eq("status", "published")
      .order("updated_at", { ascending: false }),
  ]);
  if (profileResult.error) throw profileResult.error;
  if (templateResult.error) throw templateResult.error;
  return {
    profile: profileResult.data || null,
    templates: templateResult.data || [],
  };
}
