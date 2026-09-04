const AADHAAR_REGEX = /\b(\d{4})[\s-]?(\d{4})[\s-]?(\d{4})\b/g;
const DATE_REGEX = /\b([0-3]?\d)[/.-]([01]?\d)[/.-]((?:19|20)\d{2})\b/;

function normalizeSpace(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function titleCaseWords(value) {
  return normalizeSpace(value)
    .toLowerCase()
    .replace(/\b([a-z])/g, (match) => match.toUpperCase());
}

function isoDateFromMatch(match) {
  if (!match) return "";
  const day = String(match[1]).padStart(2, "0");
  const month = String(match[2]).padStart(2, "0");
  return `${match[3]}-${month}-${day}`;
}

function maskAadhaar(value) {
  const digits = String(value || "").replace(/\D/g, "");
  return digits.length === 12 ? `XXXX XXXX ${digits.slice(-4)}` : "";
}

function maskPan(value) {
  const normalized = String(value || "").toUpperCase().replace(/\s+/g, "");
  return /^[A-Z]{5}\d{4}[A-Z]$/.test(normalized)
    ? `${normalized.slice(0, 5)}••••${normalized.slice(-1)}`
    : "";
}

function maskGeneric(value) {
  const normalized = normalizeSpace(value).replace(/\s+/g, "");
  if (normalized.length < 4) return normalized;
  return `${"•".repeat(Math.min(8, Math.max(4, normalized.length - 4)))}${normalized.slice(-4)}`;
}

export function maskSensitiveNumbers(text) {
  return String(text || "").replace(AADHAAR_REGEX, (_match, _a, _b, c) => `XXXX XXXX ${c}`);
}

async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(String(value || ""));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function imageBitmapFromFile(file) {
  if (!file || !String(file.type || "").startsWith("image/")) return null;
  if (typeof createImageBitmap === "function") return createImageBitmap(file);

  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.decoding = "async";
    await new Promise((resolve, reject) => {
      image.onload = resolve;
      image.onerror = () => reject(new Error("Unable to decode this document image."));
      image.src = url;
    });
    return image;
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function detectText(bitmap) {
  if (!bitmap || typeof window === "undefined" || typeof window.TextDetector !== "function") {
    return { engine: "manual_fallback", text: "", supported: false };
  }

  const detector = new window.TextDetector();
  const blocks = await detector.detect(bitmap);
  const text = (blocks || [])
    .map((block) => block.rawValue || block.text || "")
    .filter(Boolean)
    .join("\n");
  return { engine: "browser_text_detector", text, supported: true };
}

async function detectQr(bitmap) {
  if (!bitmap || typeof window === "undefined" || typeof window.BarcodeDetector !== "function") {
    return { detected: false, supported: false, secureQrPayloadSha256: null };
  }

  try {
    const formats = await window.BarcodeDetector.getSupportedFormats?.();
    if (Array.isArray(formats) && !formats.includes("qr_code")) {
      return { detected: false, supported: false, secureQrPayloadSha256: null };
    }
    const detector = new window.BarcodeDetector({ formats: ["qr_code"] });
    const codes = await detector.detect(bitmap);
    const rawValue = codes?.find((code) => String(code.rawValue || "").trim())?.rawValue || "";
    return {
      detected: Boolean(rawValue),
      supported: true,
      secureQrPayloadSha256: rawValue ? await sha256Hex(rawValue) : null,
    };
  } catch {
    return { detected: false, supported: true, secureQrPayloadSha256: null };
  }
}

function probableName(lines) {
  const rejected = /government|india|aadhaar|uidai|income tax|department|date of birth|dob|male|female|address|year of birth|father|signature|passport|republic|driving|licen[cs]e|election|commission/i;
  const candidates = lines
    .map(normalizeSpace)
    .filter((line) => line.length >= 3 && line.length <= 60)
    .filter((line) => /^[A-Za-z][A-Za-z .'-]+$/.test(line))
    .filter((line) => !rejected.test(line));
  return candidates.length ? titleCaseWords(candidates[0]) : "";
}

function parseGender(text) {
  if (/\b(female|f)\b/i.test(text)) return "female";
  if (/\b(male|m)\b/i.test(text)) return "male";
  if (/\b(transgender|third gender)\b/i.test(text)) return "other";
  return "";
}

function extractAddress(lines) {
  const start = lines.findIndex((line) => /\baddress\b\s*[:-]?/i.test(line));
  if (start < 0) return "";
  const addressLines = [];
  for (let index = start; index < Math.min(lines.length, start + 5); index += 1) {
    const cleaned = normalizeSpace(lines[index]).replace(/^address\s*[:-]?\s*/i, "");
    if (!cleaned) continue;
    if (/\b(?:dob|date of birth|male|female|aadhaar|vid)\b/i.test(cleaned)) break;
    addressLines.push(cleaned);
  }
  return normalizeSpace(addressLines.join(", ")).slice(0, 240);
}

function extractPostalCode(text) {
  const match = String(text || "").match(/\b[1-9]\d{5}\b/);
  return match?.[0] || "";
}

function extractMaskedDocumentNumber(text, documentType) {
  const raw = String(text || "");
  if (documentType === "aadhaar") {
    const match = [...raw.matchAll(AADHAAR_REGEX)][0];
    return match ? maskAadhaar(match[0]) : "";
  }
  if (documentType === "pan") {
    const match = raw.toUpperCase().match(/\b[A-Z]{5}\d{4}[A-Z]\b/);
    return match ? maskPan(match[0]) : "";
  }
  if (documentType === "passport") {
    const match = raw.toUpperCase().match(/\b[A-Z][0-9]{7}\b/);
    return match ? maskGeneric(match[0]) : "";
  }
  if (documentType === "driving_licence") {
    const match = raw.toUpperCase().match(/\b[A-Z]{2}[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{7}\b/);
    return match ? maskGeneric(match[0]) : "";
  }
  if (documentType === "voter_id") {
    const match = raw.toUpperCase().match(/\b[A-Z]{3}\d{7}\b/);
    return match ? maskGeneric(match[0]) : "";
  }
  return "";
}

function parseSafeFields(rawText, documentType) {
  const text = String(rawText || "");
  const lines = text.split(/\r?\n/).map(normalizeSpace).filter(Boolean);
  const dateMatch = text.match(DATE_REGEX);
  const fields = {
    name: probableName(lines),
    dob: isoDateFromMatch(dateMatch),
    gender: parseGender(text),
    address_line1: extractAddress(lines),
    postal_code: extractPostalCode(text),
    nationality: documentType === "aadhaar" || documentType === "pan" || documentType === "voter_id" || documentType === "driving_licence" ? "India" : "",
    issue_country: documentType === "aadhaar" || documentType === "pan" || documentType === "voter_id" || documentType === "driving_licence" ? "India" : "",
  };

  return Object.fromEntries(
    Object.entries(fields).filter(([, value]) => value !== "" && value !== null && value !== undefined)
  );
}

export async function analyzeIdentityDocument(file, documentType) {
  if (!file) throw new Error("Choose or capture a document first.");
  if (!String(file.type || "").startsWith("image/")) {
    return {
      status: "limited", method: "manual", extractedFields: {}, documentNumberMasked: null,
      secureQrDetected: false, secureQrSupported: false, secureQrPayloadSha256: null,
      rawOcrTextStored: false, rawQrPayloadStored: false,
      message: "Automatic extraction currently runs on JPEG/PNG captures. Review this file securely and manually.",
    };
  }

  const bitmap = await imageBitmapFromFile(file);
  try {
    const [textResult, qrResult] = await Promise.all([detectText(bitmap), detectQr(bitmap)]);
    const rawText = textResult.text || "";
    const maskedText = maskSensitiveNumbers(rawText);
    const extractedFields = parseSafeFields(maskedText, documentType);
    const documentNumberMasked = extractMaskedDocumentNumber(rawText, documentType) || null;
    const hasText = Boolean(textResult.supported && rawText.trim());
    const method = hasText && qrResult.detected ? "combined" : hasText ? "browser_text_detector" : qrResult.detected ? "barcode_detector" : "manual";
    const status = hasText || qrResult.detected ? "extracted" : "limited";
    const warnings = [];
    if (!textResult.supported) warnings.push("This browser does not expose local OCR. The file can still be stored and reviewed manually.");
    if (textResult.supported && !rawText.trim()) warnings.push("No readable text was detected. Retake the photo with better focus and lighting.");
    if (documentType === "aadhaar" && !qrResult.detected) warnings.push("Aadhaar Secure QR was not detected automatically. OCR alone must not be treated as Aadhaar verification.");
    if (documentType === "aadhaar" && qrResult.detected) warnings.push("Secure QR detected. Authenticity still requires UIDAI digital-signature verification; QR presence alone is not proof.");

    return {
      status, method, extractedFields, documentNumberMasked,
      secureQrDetected: qrResult.detected, secureQrSupported: qrResult.supported,
      secureQrPayloadSha256: qrResult.secureQrPayloadSha256,
      rawOcrTextStored: false, rawQrPayloadStored: false,
      warnings,
      message: warnings.join(" ") || "Safe identity fields extracted locally. Review before saving.",
    };
  } finally {
    bitmap?.close?.();
  }
}
