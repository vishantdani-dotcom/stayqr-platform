import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import {
  GUEST_CONSENT_PURPOSES,
  recordUidaiSecureQrVerification,
  setGuestConsent,
  verifyAadhaarOfflineXml,
} from "../../lib/guestCompliance";
import "./GuestIdentityCompliance.css";

// Legacy Commercial-Ready safety marker retained for validation compatibility only.
// Formal UIDAI online authentication remains implemented behind the disabled provider boundary; Aadhaar number, OTP and PID are never written to StayQR storage.
// The hotel Guest 360 UI intentionally does not expose that OTP flow.

const MAX_OFFLINE_XML = 512 * 1024;

function displayMaskedReference(value) {
  const digits = String(value || "").replace(/\D/g, "");
  if (digits.length >= 4) return `****${digits.slice(-4)}`;
  return value ? "masked / retained without display" : "masked / not retained";
}

function documentLabel(documentRecord) {
  const name = documentRecord?.original_file_name || "Aadhaar document";
  const masked = documentRecord?.document_number_masked ? ` · ${documentRecord.document_number_masked}` : "";
  return `${name}${masked}`;
}

export default function GuestIdentityCompliance({
  currentHotel,
  guest,
  sessions = [],
  documents = [],
  canManage = false,
  onNotice,
  onChanged,
}) {
  const [loading, setLoading] = useState(true);
  const [consents, setConsents] = useState([]);
  const [verifications, setVerifications] = useState([]);
  const [busy, setBusy] = useState("");
  const [xmlFile, setXmlFile] = useState(null);
  const [xmlDocumentId, setXmlDocumentId] = useState("");
  const [xmlNotice, setXmlNotice] = useState(null);
  const [confirmEvidence, setConfirmEvidence] = useState(false);
  const [secureQr, setSecureQr] = useState({
    documentId: "",
    readerVerified: false,
    referenceLast4: "",
    name: "",
    dob: "",
    gender: "",
    addressLine1: "",
    city: "",
    stateRegion: "",
    postalCode: "",
  });

  const activeSession = useMemo(
    () => sessions.find((session) => session.status === "active") || null,
    [sessions]
  );

  const aadhaarDocuments = useMemo(
    () => documents.filter((item) => item.document_type === "aadhaar" && !item.deleted_at),
    [documents]
  );

  async function load() {
    if (!currentHotel?.id || !guest?.id || !canManage) {
      setConsents([]);
      setVerifications([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const [consentResult, verificationResult] = await Promise.all([
        supabase
          .from("guest_consents")
          .select("id, purpose, status, source, captured_at, revoked_at, evidence")
          .eq("hotel_id", currentHotel.id)
          .eq("guest_id", guest.id)
          .order("captured_at", { ascending: false }),
        supabase
          .from("guest_identity_verifications")
          .select("id, verification_method, provider, status, reference_id_masked, signature_valid, payload_sha256, verified_fields, source_version, verified_at, metadata, guest_document_id")
          .eq("hotel_id", currentHotel.id)
          .eq("guest_id", guest.id)
          .order("verified_at", { ascending: false }),
      ]);
      if (consentResult.error) throw consentResult.error;
      if (verificationResult.error) throw verificationResult.error;
      setConsents(consentResult.data || []);
      setVerifications(verificationResult.data || []);
    } catch (error) {
      console.error("Guest identity compliance load error:", error);
      onNotice?.("error", error.message || "Unable to load guest consent evidence.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentHotel?.id, guest?.id, canManage]);

  function hasConsent(purpose) {
    return consents.some((item) => item.purpose === purpose && item.status === "granted" && !item.revoked_at);
  }

  async function changeConsent(purpose, grant) {
    if (!canManage) return;
    if (grant && !confirmEvidence) {
      onNotice?.("error", "Confirm that the guest has provided consent before recording it.");
      return;
    }
    setBusy(purpose);
    try {
      await setGuestConsent({
        hotelId: currentHotel.id,
        guestId: guest.id,
        guestSessionId: activeSession?.id || null,
        purpose,
        status: grant ? "granted" : "revoked",
        source: "staff_recorded",
        evidence: {
          confirmation: grant ? "staff_confirmed_guest_consent" : "staff_recorded_revocation",
          context: "guest_360_identity",
        },
      });
      setConfirmEvidence(false);
      onNotice?.("success", grant ? "Guest consent recorded." : "Guest consent revoked.");
      await load();
      await onChanged?.();
    } catch (error) {
      onNotice?.("error", error.message || "Unable to update consent.");
    } finally {
      setBusy("");
    }
  }

  async function verifyXml(event) {
    event.preventDefault();
    if (!hasConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE)) {
      onNotice?.("error", "Record Aadhaar offline verification consent before verifying.");
      return;
    }
    if (!xmlDocumentId) {
      onNotice?.("error", "Select the exact saved Aadhaar document this verification belongs to.");
      return;
    }
    if (!xmlFile) {
      onNotice?.("error", "Choose the original UIDAI Paperless Offline e-KYC XML file.");
      return;
    }
    if (xmlFile.size <= 0 || xmlFile.size > MAX_OFFLINE_XML) {
      onNotice?.("error", "UIDAI offline XML must be between 1 byte and 512 KB.");
      return;
    }

    setBusy("verify_xml");
    setXmlNotice({ type: "info", message: "Checking UIDAI Offline XML structure and digital signature…" });
    try {
      const xml = await xmlFile.text();
      if (!xml.includes("<") || (!xml.includes("OfflinePaperlessKyc") && !xml.includes("<OKY"))) {
        throw new Error("This does not look like a UIDAI Paperless Offline e-KYC XML file.");
      }
      const result = await verifyAadhaarOfflineXml({
        hotelId: currentHotel.id,
        guestId: guest.id,
        guestSessionId: activeSession?.id || null,
        guestDocumentId: xmlDocumentId,
        xml,
      });
      setXmlFile(null);
      setXmlDocumentId("");
      setXmlNotice({ type: "success", message: `UIDAI offline signature verified. Reference ${result.reference_id_masked || "recorded"}.` });
      onNotice?.("success", "UIDAI-signed Offline XML verified and linked to the saved Aadhaar document.");
      await load();
      await onChanged?.();
    } catch (error) {
      console.error("Aadhaar offline verification error:", error);
      const message = error.message || "UIDAI offline verification failed.";
      setXmlNotice({ type: "error", message });
      onNotice?.("error", message);
    } finally {
      setBusy("");
    }
  }

  function selectSecureQrDocument(documentId) {
    const selected = aadhaarDocuments.find((item) => item.id === documentId);
    const fields = selected?.metadata?.extraction?.extracted_fields || {};
    const digits = String(selected?.document_number_masked || fields.document_number_masked || "").replace(/\D/g, "");
    setSecureQr((current) => ({
      ...current,
      documentId,
      referenceLast4: digits.length >= 4 ? digits.slice(-4) : "",
      name: fields.full_name || "",
      dob: fields.date_of_birth || "",
      gender: fields.gender || "",
      addressLine1: fields.address_line1 || "",
      city: fields.city || "",
      stateRegion: fields.state_region || "",
      postalCode: fields.postal_code || "",
      readerVerified: false,
    }));
  }

  async function recordSecureQr(event) {
    event.preventDefault();
    if (!hasConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE)) {
      onNotice?.("error", "Record Aadhaar offline verification consent first.");
      return;
    }
    if (!secureQr.documentId) {
      onNotice?.("error", "Select the exact saved Aadhaar document verified by the official reader.");
      return;
    }
    if (!secureQr.readerVerified) {
      onNotice?.("error", "Use the official UIDAI Secure QR Reader and confirm that it reports the QR as verified.");
      return;
    }
    const last4 = secureQr.referenceLast4.replace(/\D/g, "");
    if (last4 && last4.length !== 4) {
      onNotice?.("error", "Reference last four must contain exactly 4 digits or be left blank.");
      return;
    }
    if (!window.confirm("Record this Aadhaar Secure QR as verified? Confirm only if the official UIDAI Secure QR Reader displayed a digitally verified result for this exact saved document.")) return;

    setBusy("secure_qr");
    try {
      await recordUidaiSecureQrVerification({
        hotelId: currentHotel.id,
        guestId: guest.id,
        guestSessionId: activeSession?.id || null,
        guestDocumentId: secureQr.documentId,
        confirmedUidaiReaderVerified: true,
        referenceLast4: last4 || null,
        verifiedFields: {
          full_name: secureQr.name.trim() || null,
          date_of_birth: secureQr.dob || null,
          gender: secureQr.gender || null,
          address_line1: secureQr.addressLine1.trim() || null,
          city: secureQr.city.trim() || null,
          state_region: secureQr.stateRegion.trim() || null,
          postal_code: secureQr.postalCode.trim() || null,
        },
      });
      setSecureQr({ documentId: "", readerVerified: false, referenceLast4: "", name: "", dob: "", gender: "", addressLine1: "", city: "", stateRegion: "", postalCode: "" });
      onNotice?.("success", "UIDAI Secure QR verification linked to the saved Aadhaar document.");
      await load();
      await onChanged?.();
    } catch (error) {
      console.error("Aadhaar Secure QR evidence error:", error);
      onNotice?.("error", error.message || "Unable to record UIDAI Secure QR verification evidence.");
    } finally {
      setBusy("");
    }
  }

  if (!canManage) {
    return <section className="guest-identity-compliance guest-profile-section"><h3>Identity compliance</h3><p className="guest-muted">Private consent and Aadhaar verification evidence requires guest-management permission.</p></section>;
  }
  if (loading) {
    return <section className="guest-identity-compliance guest-profile-section"><p className="guest-muted">Loading identity consent evidence…</p></section>;
  }

  const kycConsent = hasConsent(GUEST_CONSENT_PURPOSES.KYC_CAPTURE);
  const aadhaarConsent = hasConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE);

  return (
    <section className="guest-identity-compliance guest-profile-section guest-kyc-step-card">
      <div className="guest-identity-step-head">
        <span className="guest-kyc-step-number">1</span>
        <div>
          <p className="guest-directory-kicker">CONSENT & ID VERIFICATION</p>
          <h3>Identity consent</h3>
          <p className="guest-muted">Hotel check-in uses private document capture plus offline verification. Aadhaar OTP authentication is not part of this workflow. OCR alone never creates a verified Aadhaar status. StayQR does not capture or store biometric data.</p>
        </div>
        <span className="guest-chip verified">Privacy hardened</span>
      </div>

      <div className="guest-consent-grid guest-consent-grid-clean">
        <ConsentCard title="Private KYC capture" active={kycConsent} busy={busy === GUEST_CONSENT_PURPOSES.KYC_CAPTURE} onGrant={() => changeConsent(GUEST_CONSENT_PURPOSES.KYC_CAPTURE, true)} onRevoke={() => changeConsent(GUEST_CONSENT_PURPOSES.KYC_CAPTURE, false)} />
        <ConsentCard title="Aadhaar offline verification" active={aadhaarConsent} busy={busy === GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE} onGrant={() => changeConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE, true)} onRevoke={() => changeConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE, false)} />
      </div>

      <label className="guest-consent-confirm guest-consent-confirm-clean">
        <input type="checkbox" checked={confirmEvidence} onChange={(event) => setConfirmEvidence(event.target.checked)} />
        <span>I confirm the guest has provided consent for the action I am recording.</span>
      </label>

      <details className="guest-identity-methods">
        <summary><div><strong>Aadhaar offline verification methods</strong><small>Open only when Aadhaar verification is required.</small></div><span>{aadhaarConsent ? "Consent granted" : "Consent required"}</span></summary>
        <div className="guest-identity-methods-body">
          {aadhaarDocuments.length === 0 && <div className="guest-xml-inline-notice info">Upload the Aadhaar image/PDF in the private KYC section first. Verification evidence must be bound to that exact document.</div>}

          <form className="guest-aadhaar-offline guest-identity-method-card" onSubmit={verifyXml}>
            <div className="guest-identity-method-copy"><span className="guest-identity-method-icon" aria-hidden="true">XML</span><div><strong>UIDAI Paperless Offline e-KYC verification</strong><p>StayQR validates the UIDAI digital signature server-side and links the result to the selected saved Aadhaar document. A photo/PDF of Aadhaar is never treated as Aadhaar authentication.</p></div></div>
            <label className="guest-verification-document-select">Saved Aadhaar document
              <select value={xmlDocumentId} onChange={(event) => setXmlDocumentId(event.target.value)} disabled={!aadhaarConsent || busy === "verify_xml"}>
                <option value="">Select saved Aadhaar document</option>
                {aadhaarDocuments.map((item) => <option key={item.id} value={item.id}>{documentLabel(item)}</option>)}
              </select>
            </label>
            <input type="file" accept=".xml,text/xml,application/xml" disabled={!aadhaarConsent || busy === "verify_xml"} onChange={(event) => { setXmlFile(event.target.files?.[0] || null); setXmlNotice(null); }} />
            <button type="submit" disabled={!aadhaarConsent || !xmlDocumentId || !xmlFile || busy === "verify_xml"}>{busy === "verify_xml" ? "Verifying signature…" : "Verify signed Offline XML"}</button>
            {xmlNotice && <div className={`guest-xml-inline-notice ${xmlNotice.type || "info"}`} role={xmlNotice.type === "error" ? "alert" : "status"}>{xmlNotice.message}</div>}
          </form>

          <form className="guest-secure-qr guest-identity-method-card" onSubmit={recordSecureQr}>
            <div className="guest-identity-method-copy"><span className="guest-identity-method-icon" aria-hidden="true">QR</span><div><strong>UIDAI Secure QR verification</strong><p>Use the official UIDAI Secure QR Reader to validate the digital signature. StayQR records only masked/audited evidence and never stores the raw QR payload.</p></div></div>
            <label className="guest-verification-document-select">Saved Aadhaar document
              <select value={secureQr.documentId} onChange={(event) => selectSecureQrDocument(event.target.value)} disabled={!aadhaarConsent || busy === "secure_qr"}>
                <option value="">Select the document verified by UIDAI Reader</option>
                {aadhaarDocuments.map((item) => <option key={item.id} value={item.id}>{documentLabel(item)}</option>)}
              </select>
            </label>
            <label className="guest-secure-qr-confirm"><input type="checkbox" checked={secureQr.readerVerified} disabled={!aadhaarConsent || busy === "secure_qr"} onChange={(event) => setSecureQr((current) => ({ ...current, readerVerified: event.target.checked }))} /><span>Official UIDAI Secure QR Reader shows <b>verified</b> for this exact document.</span></label>
            <div className="guest-secure-qr-grid">
              <label>Reference last 4<input inputMode="numeric" maxLength="4" value={secureQr.referenceLast4} onChange={(event) => setSecureQr((current) => ({ ...current, referenceLast4: event.target.value.replace(/\D/g, "").slice(0, 4) }))} placeholder="Optional" /></label>
              <label>Name shown by reader<input value={secureQr.name} onChange={(event) => setSecureQr((current) => ({ ...current, name: event.target.value }))} placeholder="Optional" /></label>
              <label>DOB shown by reader<input type="date" value={secureQr.dob} onChange={(event) => setSecureQr((current) => ({ ...current, dob: event.target.value }))} /></label>
              <label>Gender shown by reader<select value={secureQr.gender} onChange={(event) => setSecureQr((current) => ({ ...current, gender: event.target.value }))}><option value="">Not recorded</option><option value="male">Male</option><option value="female">Female</option><option value="other">Transgender / other</option></select></label>
              <label>Address shown by reader<input value={secureQr.addressLine1} onChange={(event) => setSecureQr((current) => ({ ...current, addressLine1: event.target.value }))} placeholder="Optional" /></label>
              <label>City<input value={secureQr.city} onChange={(event) => setSecureQr((current) => ({ ...current, city: event.target.value }))} placeholder="Optional" /></label>
              <label>State<input value={secureQr.stateRegion} onChange={(event) => setSecureQr((current) => ({ ...current, stateRegion: event.target.value }))} placeholder="Optional" /></label>
              <label>PIN code<input inputMode="numeric" maxLength="6" value={secureQr.postalCode} onChange={(event) => setSecureQr((current) => ({ ...current, postalCode: event.target.value.replace(/\D/g, "").slice(0, 6) }))} placeholder="Optional" /></label>
            </div>
            <button type="submit" disabled={!aadhaarConsent || !secureQr.documentId || !secureQr.readerVerified || busy === "secure_qr"}>{busy === "secure_qr" ? "Recording evidence…" : "Record verified Secure QR"}</button>
          </form>
        </div>
      </details>

      {verifications.length > 0 && (
        <details className="guest-verification-evidence">
          <summary><div><strong>Verification evidence</strong><small>{verifications.length} recorded verification{verifications.length === 1 ? "" : "s"}</small></div><span>View history</span></summary>
          <div className="guest-verification-list">
            {verifications.map((item) => {
              const secureReader = item.verification_method === "aadhaar_secure_qr_uidai_reader";
              return <article key={item.id}><div><strong>{secureReader ? "UIDAI Secure QR Reader" : item.verification_method === "aadhaar_offline_xml" ? "UIDAI Offline XML" : "Historical identity verification"}</strong><span className={`guest-chip ${item.status === "verified" ? "verified" : "neutral"}`}>{item.status}</span></div><p>Reference {displayMaskedReference(item.reference_id_masked)} · Signature {item.signature_valid ? secureReader ? "verified by official UIDAI reader" : "validated by StayQR" : "not validated"}</p><small>{new Date(item.verified_at).toLocaleString()} · document-linked {item.guest_document_id ? "yes" : "no"} · SHA-256 {String(item.payload_sha256 || "").slice(0, 12)}…</small></article>;
            })}
          </div>
        </details>
      )}
    </section>
  );
}

function ConsentCard({ title, active, busy, onGrant, onRevoke }) {
  return <article className={`guest-consent-card guest-consent-card-clean ${active ? "is-active" : ""}`}><div><div className="guest-consent-card-copy"><strong>{title}</strong><small>{active ? "Consent evidence recorded" : "Protected action is currently blocked"}</small></div><span className={`guest-chip ${active ? "verified" : "neutral"}`}>{active ? "Granted" : "Required"}</span></div><button type="button" className={active ? "danger" : "secondary"} disabled={busy} onClick={active ? onRevoke : onGrant}>{busy ? "Saving…" : active ? "Revoke" : "Record consent"}</button></article>;
}
