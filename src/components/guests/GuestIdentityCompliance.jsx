import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import {
  GUEST_CONSENT_PURPOSES,
  recordUidaiSecureQrVerification,
  setGuestConsent,
  verifyAadhaarOfflineXml,
} from "../../lib/guestCompliance";
import "./GuestIdentityCompliance.css";

const MAX_OFFLINE_XML = 512 * 1024;

export default function GuestIdentityCompliance({
  currentHotel,
  guest,
  sessions = [],
  canManage = false,
  onNotice,
  onChanged,
}) {
  const [loading, setLoading] = useState(true);
  const [consents, setConsents] = useState([]);
  const [verifications, setVerifications] = useState([]);
  const [busy, setBusy] = useState("");
  const [xmlFile, setXmlFile] = useState(null);
  const [confirmEvidence, setConfirmEvidence] = useState(false);
  const [secureQr, setSecureQr] = useState({
    readerVerified: false,
    referenceLast4: "",
    name: "",
    dob: "",
    gender: "",
  });

  const activeSession = useMemo(
    () => sessions.find((session) => session.status === "active") || null,
    [sessions]
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
          .select("id, verification_method, provider, status, reference_id_masked, signature_valid, payload_sha256, verified_fields, source_version, verified_at, metadata")
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
    if (!xmlFile || !hasConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE)) return;
    if (xmlFile.size <= 0 || xmlFile.size > MAX_OFFLINE_XML) {
      onNotice?.("error", "UIDAI offline XML must be between 1 byte and 512 KB.");
      return;
    }
    setBusy("verify_xml");
    try {
      const xml = await xmlFile.text();
      if (!xml.includes("<") || (!xml.includes("OfflinePaperlessKyc") && !xml.includes("<OKY"))) {
        throw new Error("This does not look like a UIDAI Paperless Offline e-KYC XML file.");
      }
      const result = await verifyAadhaarOfflineXml({
        hotelId: currentHotel.id,
        guestId: guest.id,
        guestSessionId: activeSession?.id || null,
        xml,
      });
      setXmlFile(null);
      onNotice?.("success", `UIDAI offline signature verified. Reference ${result.reference_id_masked || "recorded"}.`);
      await load();
      await onChanged?.();
    } catch (error) {
      console.error("Aadhaar offline verification error:", error);
      onNotice?.("error", error.message || "UIDAI offline verification failed.");
    } finally {
      setBusy("");
    }
  }

  async function recordSecureQr(event) {
    event.preventDefault();
    if (!hasConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE)) {
      onNotice?.("error", "Record Aadhaar offline verification consent first.");
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
    if (!window.confirm("Record this Aadhaar Secure QR as verified? Confirm only if the official UIDAI Secure QR Reader displayed a digitally verified result for this guest.")) return;

    setBusy("secure_qr");
    try {
      await recordUidaiSecureQrVerification({
        hotelId: currentHotel.id,
        guestId: guest.id,
        guestSessionId: activeSession?.id || null,
        confirmedUidaiReaderVerified: true,
        referenceLast4: last4 || null,
        verifiedFields: {
          name: secureQr.name.trim() || null,
          dob: secureQr.dob || null,
          gender: secureQr.gender || null,
        },
      });
      setSecureQr({ readerVerified: false, referenceLast4: "", name: "", dob: "", gender: "" });
      onNotice?.("success", "UIDAI Secure QR reader verification evidence recorded.");
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
    return (
      <section className="guest-identity-compliance guest-profile-section">
        <h3>Identity compliance</h3>
        <p className="guest-muted">Private consent and Aadhaar verification evidence requires guest-management permission.</p>
      </section>
    );
  }

  if (loading) {
    return <section className="guest-identity-compliance guest-profile-section"><p className="guest-muted">Loading identity consent evidence…</p></section>;
  }

  const kycConsent = hasConsent(GUEST_CONSENT_PURPOSES.KYC_CAPTURE);
  const aadhaarConsent = hasConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE);

  return (
    <section className="guest-identity-compliance guest-profile-section">
      <div className="guest-kyc-heading">
        <div>
          <p className="guest-directory-kicker">CONSENT • RETENTION • UIDAI OFFLINE</p>
          <h3>Identity compliance</h3>
          <p className="guest-muted">Consent is stored as hotel-scoped evidence. StayQR supports digitally-signed UIDAI Paperless Offline XML and records official UIDAI Secure QR Reader verification evidence without storing raw XML, QR payload, share code, full Aadhaar number or biometric data.</p>
        </div>
        <span className="guest-chip verified">Privacy hardened</span>
      </div>

      <label className="guest-consent-confirm">
        <input type="checkbox" checked={confirmEvidence} onChange={(event) => setConfirmEvidence(event.target.checked)} />
        <span>I confirm the guest has provided consent for the action I am recording.</span>
      </label>

      <div className="guest-consent-grid">
        <ConsentCard
          title="Private KYC capture"
          active={kycConsent}
          busy={busy === GUEST_CONSENT_PURPOSES.KYC_CAPTURE}
          onGrant={() => changeConsent(GUEST_CONSENT_PURPOSES.KYC_CAPTURE, true)}
          onRevoke={() => changeConsent(GUEST_CONSENT_PURPOSES.KYC_CAPTURE, false)}
        />
        <ConsentCard
          title="Aadhaar offline verification"
          active={aadhaarConsent}
          busy={busy === GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE}
          onGrant={() => changeConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE, true)}
          onRevoke={() => changeConsent(GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE, false)}
        />
      </div>

      <form className="guest-aadhaar-offline" onSubmit={verifyXml}>
        <div>
          <strong>UIDAI Paperless Offline e-KYC verification</strong>
          <p>Upload the original digitally-signed XML extracted from the UIDAI offline package. StayQR validates the UIDAI digital signature server-side. A photo/PDF of Aadhaar is never treated as Aadhaar authentication.</p>
        </div>
        <input
          type="file"
          accept=".xml,text/xml,application/xml"
          disabled={!aadhaarConsent || busy === "verify_xml"}
          onChange={(event) => setXmlFile(event.target.files?.[0] || null)}
        />
        <button type="submit" disabled={!aadhaarConsent || !xmlFile || busy === "verify_xml"}>
          {busy === "verify_xml" ? "Verifying UIDAI signature…" : "Verify offline XML"}
        </button>
      </form>

      <form className="guest-secure-qr" onSubmit={recordSecureQr}>
        <div className="guest-secure-qr-copy">
          <strong>UIDAI Secure QR verification</strong>
          <p>UIDAI states that Secure QR must be read with its official reader/app. Use that reader first; record evidence here only after it displays a digitally verified result. StayQR never stores the raw Secure QR payload.</p>
        </div>
        <label className="guest-secure-qr-confirm">
          <input
            type="checkbox"
            checked={secureQr.readerVerified}
            disabled={!aadhaarConsent || busy === "secure_qr"}
            onChange={(event) => setSecureQr((current) => ({ ...current, readerVerified: event.target.checked }))}
          />
          <span>Official UIDAI Secure QR Reader shows <b>verified</b> for this guest.</span>
        </label>
        <div className="guest-secure-qr-grid">
          <label>Reference last 4 (optional)<input inputMode="numeric" maxLength="4" value={secureQr.referenceLast4} onChange={(event) => setSecureQr((current) => ({ ...current, referenceLast4: event.target.value.replace(/\D/g, "").slice(0, 4) }))} placeholder="1234" /></label>
          <label>Name shown by reader (optional)<input value={secureQr.name} onChange={(event) => setSecureQr((current) => ({ ...current, name: event.target.value }))} /></label>
          <label>DOB shown by reader (optional)<input type="date" value={secureQr.dob} onChange={(event) => setSecureQr((current) => ({ ...current, dob: event.target.value }))} /></label>
          <label>Gender shown by reader (optional)<select value={secureQr.gender} onChange={(event) => setSecureQr((current) => ({ ...current, gender: event.target.value }))}><option value="">Not recorded</option><option value="M">Male</option><option value="F">Female</option><option value="T">Transgender / other</option></select></label>
        </div>
        <button type="submit" disabled={!aadhaarConsent || !secureQr.readerVerified || busy === "secure_qr"}>
          {busy === "secure_qr" ? "Recording evidence…" : "Record verified Secure QR"}
        </button>
      </form>

      {verifications.length > 0 && (
        <div className="guest-verification-list">
          {verifications.map((item) => {
            const secureReader = item.verification_method === "aadhaar_secure_qr_uidai_reader";
            return (
              <article key={item.id}>
                <div><strong>{secureReader ? "UIDAI Secure QR Reader" : "UIDAI offline XML"}</strong><span className={`guest-chip ${item.status === "verified" ? "verified" : "neutral"}`}>{item.status}</span></div>
                <p>Reference {item.reference_id_masked || "masked / not retained"} · Signature {item.signature_valid ? (secureReader ? "verified by official UIDAI reader" : "validated by StayQR") : "not validated"}</p>
                <small>{new Date(item.verified_at).toLocaleString()} · SHA-256 evidence {String(item.payload_sha256 || "").slice(0, 12)}…</small>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}

function ConsentCard({ title, active, busy, onGrant, onRevoke }) {
  return (
    <article className="guest-consent-card">
      <div><strong>{title}</strong><span className={`guest-chip ${active ? "verified" : "neutral"}`}>{active ? "Granted" : "Not granted"}</span></div>
      <p>{active ? "Active consent evidence exists for this hotel and guest." : "The protected action remains blocked until consent is recorded."}</p>
      <button type="button" className={active ? "danger" : "secondary"} disabled={busy} onClick={active ? onRevoke : onGrant}>
        {busy ? "Saving…" : active ? "Revoke consent" : "Record consent"}
      </button>
    </article>
  );
}
