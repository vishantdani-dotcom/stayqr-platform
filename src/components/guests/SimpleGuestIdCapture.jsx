import { useMemo, useRef, useState } from "react";
import DocumentScanner from "./DocumentScanner";
import { analyzeIdentityDocument } from "../../lib/idDocumentIntelligence";
import "./SimpleGuestIdCapture.css";

const ACCEPT = ".jpg,.jpeg,.png,.pdf,image/jpeg,image/png,application/pdf";

function labelForType(value) {
  return {
    aadhaar: "Aadhaar Card",
    passport: "Passport",
    pan: "PAN Card",
    driving_licence: "Driving Licence",
    voter_id: "Voter ID",
    other: "Other ID",
  }[value] || "ID document";
}

export default function SimpleGuestIdCapture({
  disabled = false,
  value = null,
  onChange,
  onExtracted,
  compact = false,
}) {
  const inputRef = useRef(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState("");

  const analysis = value?.analysis || null;
  const extracted = analysis?.extractedFields || {};
  const hasFields = Object.keys(extracted).length > 0 || Boolean(analysis?.documentNumberMasked);
  const progressLabel = useMemo(() => {
    if (!busy) return "";
    if (progress > 0) return `Reading ID… ${Math.round(progress)}%`;
    return "Reading ID…";
  }, [busy, progress]);

  async function processFile(file, meta = {}) {
    if (!file) return;
    setBusy(true);
    setProgress(0);
    setError("");
    try {
      const nextAnalysis = await analyzeIdentityDocument(file, "auto", {
        onProgress: (next) => setProgress(Math.max(0, Math.min(100, Number(next) || 0))),
      });
      const nextValue = {
        file,
        analysis: nextAnalysis,
        captureSource: meta.captureSource || "upload",
        qualityStatus: meta.qualityStatus || "not_assessed",
        qualityScore: meta.qualityScore ?? null,
        qualityFlags: meta.qualityFlags || [],
      };
      onChange?.(nextValue);
      onExtracted?.(nextAnalysis, nextValue);
    } catch (scanError) {
      console.error("Simple ID scan error:", scanError);
      setError(scanError.message || "Unable to read this ID. You can still enter the guest details manually.");
      onChange?.({
        file,
        analysis: null,
        captureSource: meta.captureSource || "upload",
        qualityStatus: meta.qualityStatus || "not_assessed",
        qualityScore: meta.qualityScore ?? null,
        qualityFlags: meta.qualityFlags || [],
      });
    } finally {
      setBusy(false);
      setProgress(0);
    }
  }

  function clearDocument() {
    setError("");
    onChange?.(null);
    if (inputRef.current) inputRef.current.value = "";
  }

  return (
    <section className={`simple-id-capture ${compact ? "compact" : ""}`}>
      <div className="simple-id-capture-head">
        <div>
          <span className="simple-id-icon" aria-hidden="true">▣</span>
          <div>
            <h3>Scan or upload ID</h3>
            <p>Take a clear photo or upload the guest&apos;s Aadhaar, passport, PAN, driving licence or voter ID.</p>
          </div>
        </div>
        {value?.file && (
          <button type="button" className="simple-id-clear" onClick={clearDocument} disabled={disabled || busy}>
            Remove
          </button>
        )}
      </div>

      <div className="simple-id-actions">
        <div className="simple-id-action simple-id-action--scan">
          <span aria-hidden="true">📷</span>
          <strong>Scan ID</strong>
          <small>Use camera</small>
          <DocumentScanner
            disabled={disabled || busy}
            onCapture={(capture) => processFile(capture.file, capture)}
          />
        </div>

        <span className="simple-id-or">or</span>

        <button
          type="button"
          className="simple-id-action simple-id-action--upload"
          onClick={() => inputRef.current?.click()}
          disabled={disabled || busy}
        >
          <span aria-hidden="true">⇧</span>
          <strong>Upload ID</strong>
          <small>JPG, PNG or PDF</small>
        </button>
        <input
          ref={inputRef}
          className="simple-id-file-input"
          type="file"
          accept={ACCEPT}
          onChange={(event) => processFile(event.target.files?.[0] || null, { captureSource: "upload" })}
        />
      </div>

      {busy && (
        <div className="simple-id-progress" role="status">
          <div><span style={{ width: `${Math.max(8, progress)}%` }} /></div>
          <strong>{progressLabel}</strong>
          <small>The image is processed in the browser. Raw OCR text is not saved.</small>
        </div>
      )}

      {error && <div className="simple-id-message error">{error}</div>}

      {value?.file && !busy && (
        <div className="simple-id-result">
          <div className="simple-id-result-head">
            <div>
              <strong>{analysis ? labelForType(analysis.documentType) : "ID selected"}</strong>
              <small>{value.file.name}</small>
            </div>
            <span className={hasFields ? "auto" : "review"}>{hasFields ? "Auto-filled" : "Ready to save"}</span>
          </div>

          {hasFields && (
            <div className="simple-id-result-grid">
              {extracted.full_name && <div><span>Full name</span><strong>{extracted.full_name}</strong></div>}
              {extracted.date_of_birth && <div><span>Date of birth</span><strong>{extracted.date_of_birth}</strong></div>}
              {extracted.gender && <div><span>Gender</span><strong>{extracted.gender}</strong></div>}
              {analysis?.documentNumberMasked && <div><span>ID number</span><strong>{analysis.documentNumberMasked}</strong></div>}
              {extracted.nationality && <div><span>Nationality</span><strong>{extracted.nationality}</strong></div>}
              {extracted.address_line1 && <div className="wide"><span>Address</span><strong>{extracted.address_line1}</strong></div>}
            </div>
          )}

          <p className="simple-id-privacy">StayQR uses the scan to pre-fill the guest record. Review the details before saving.</p>
        </div>
      )}
    </section>
  );
}
