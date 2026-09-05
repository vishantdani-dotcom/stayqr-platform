const AADHAAR_REGEX = /\b(\d{4})[\s.-]{0,3}(\d{4})[\s.-]{0,3}(\d{4})\b/g;
const DATE_REGEX = /\b([0-3]?\d)\s*[/.-]\s*([01]?\d)\s*[/.-]\s*((?:19|20)\d{2})\b/;
const PAN_REGEX = /\b[A-Z]{5}\d{4}[A-Z]\b/i;
const PASSPORT_REGEX = /\b[A-Z][0-9]{7}\b/i;
const VOTER_REGEX = /\b[A-Z]{3}\d{7}\b/i;
const DL_REGEX = /\b[A-Z]{2}[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{7}\b/i;

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

function identityTextScore(value) {
  const text = String(value || "");
  if (!text.trim()) return 0;

  let score = Math.min(3, Math.floor(text.trim().length / 80));
  if (/\b(?:AADHAAR|AADHAR|GOVERNMENT OF INDIA|UNIQUE IDENTIFICATION)\b/i.test(text)) score += 4;
  if (/\b(?:DOB|DATE OF BIRTH|YOB)\b/i.test(text)) score += 2;
  if (DATE_REGEX.test(text)) score += 2;
  if (/\b(?:MALE|FEMALE)\b/i.test(text)) score += 1;
  if ([...text.matchAll(AADHAAR_REGEX)].length) score += 4;
  if (PAN_REGEX.test(text) || PASSPORT_REGEX.test(text) || VOTER_REGEX.test(text) || DL_REGEX.test(text)) score += 4;
  if (text.split(/\r?\n/).some((line) => /^[A-Za-z][A-Za-z .'-]{3,55}$/.test(normalizeSpace(line)))) score += 1;
  return score;
}

function filenameDocumentType(fileName) {
  const name = String(fileName || "").toLowerCase();
  if (/\b(?:aadhaar|aadhar|adhar)\b/.test(name)) return "aadhaar";
  if (/\bpan\b/.test(name)) return "pan";
  if (/passport/.test(name)) return "passport";
  if (/(?:driving|licen[cs]e|\bdl\b)/.test(name)) return "driving_licence";
  if (/(?:voter|epic)/.test(name)) return "voter_id";
  return "";
}

function prepareOcrCanvas(bitmap) {
  if (!bitmap || typeof document === "undefined") return bitmap;

  const sourceWidth = Number(bitmap.width || bitmap.naturalWidth || 0);
  const sourceHeight = Number(bitmap.height || bitmap.naturalHeight || 0);
  if (!sourceWidth || !sourceHeight) return bitmap;

  const minLongEdge = 1600;
  const maxLongEdge = 2200;
  const longEdge = Math.max(sourceWidth, sourceHeight);
  const scale = longEdge < minLongEdge
    ? Math.min(3, minLongEdge / longEdge)
    : longEdge > maxLongEdge
      ? maxLongEdge / longEdge
      : 1;

  const width = Math.max(1, Math.round(sourceWidth * scale));
  const height = Math.max(1, Math.round(sourceHeight * scale));
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) return bitmap;

  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = "high";
  context.drawImage(bitmap, 0, 0, width, height);

  try {
    const image = context.getImageData(0, 0, width, height);
    const data = image.data;
    const contrast = 1.18;
    for (let index = 0; index < data.length; index += 4) {
      const gray = (data[index] * 0.299) + (data[index + 1] * 0.587) + (data[index + 2] * 0.114);
      const adjusted = Math.max(0, Math.min(255, ((gray - 128) * contrast) + 128));
      data[index] = adjusted;
      data[index + 1] = adjusted;
      data[index + 2] = adjusted;
    }
    context.putImageData(image, 0, 0);
  } catch {
    // Keep the scaled image if pixel access is unavailable.
  }
  return canvas;
}

async function detectTextWithBrowser(bitmap) {
  if (!bitmap || typeof window === "undefined" || typeof window.TextDetector !== "function") {
    return { engine: "browser_text_detector", text: "", supported: false };
  }
  try {
    const detector = new window.TextDetector();
    const blocks = await detector.detect(bitmap);
    const text = (blocks || [])
      .map((block) => block.rawValue || block.text || "")
      .filter(Boolean)
      .join("\n");
    return { engine: "browser_text_detector", text, supported: true };
  } catch {
    return { engine: "browser_text_detector", text: "", supported: false };
  }
}

async function detectTextWithTesseract(file, bitmap, onProgress) {
  if (!file || !String(file.type || "").startsWith("image/")) {
    return { engine: "tesseract_browser", text: "", supported: false, errorMessage: "Image OCR is unavailable for this file type." };
  }

  let worker;
  let workerError = "";
  try {
    const { createWorker } = await import("tesseract.js");
    worker = await createWorker("eng", 1, {
      workerPath: "/ocr/worker.min.js",
      corePath: "/ocr/core",
      langPath: "/ocr/lang",
      workerBlobURL: false,
      logger: (event) => {
        if (event?.status === "recognizing text" && Number.isFinite(event.progress)) {
          onProgress?.(Math.round(event.progress * 100));
        }
      },
      errorHandler: (error) => {
        workerError = error instanceof Error ? error.message : String(error || "OCR worker error");
        console.error("StayQR OCR worker error:", error);
      },
    });

    const source = prepareOcrCanvas(bitmap) || file;
    await worker.setParameters?.({
      tessedit_pageseg_mode: "6",
      preserve_interword_spaces: "1",
    });

    const first = await worker.recognize(source);
    let bestText = String(first?.data?.text || "");
    let bestConfidence = Number.isFinite(first?.data?.confidence) ? Number(first.data.confidence) : null;
    let bestScore = identityTextScore(bestText);

    if (bestScore < 6) {
      await worker.setParameters?.({ tessedit_pageseg_mode: "11" });
      const second = await worker.recognize(source);
      const secondText = String(second?.data?.text || "");
      const secondScore = identityTextScore(secondText);
      if (secondScore > bestScore) {
        bestText = secondText;
        bestScore = secondScore;
        bestConfidence = Number.isFinite(second?.data?.confidence) ? Number(second.data.confidence) : bestConfidence;
      }
    }

    return {
      engine: "tesseract_browser",
      text: bestText,
      supported: true,
      confidence: bestConfidence,
      score: bestScore,
    };
  } catch (error) {
    const errorMessage = workerError || (error instanceof Error ? error.message : String(error || "OCR runtime unavailable"));
    console.error("StayQR browser OCR unavailable:", error);
    return { engine: "tesseract_browser", text: "", supported: false, error, errorMessage };
  } finally {
    try { await worker?.terminate?.(); } catch { /* best effort */ }
  }
}

async function detectText(bitmap, file, onProgress) {
  const nativeResult = await detectTextWithBrowser(bitmap);
  const nativeScore = identityTextScore(nativeResult.text);

  if (nativeResult.supported && nativeScore >= 7) {
    onProgress?.(100);
    return { ...nativeResult, score: nativeScore };
  }

  const tesseractResult = await detectTextWithTesseract(file, bitmap, onProgress);
  const tesseractScore = identityTextScore(tesseractResult.text);

  if (tesseractResult.supported && tesseractScore >= nativeScore) {
    return { ...tesseractResult, score: tesseractScore };
  }

  if (nativeResult.supported && String(nativeResult.text || "").trim()) {
    onProgress?.(100);
    return { ...nativeResult, score: nativeScore };
  }

  return tesseractResult;
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

function inferDocumentType(rawText, fileName = "") {
  const text = String(rawText || "").toUpperCase();
  const byFileName = filenameDocumentType(fileName);

  if (/PASSPORT|REPUBLIC OF INDIA|P<IND/.test(text) || PASSPORT_REGEX.test(text)) return "passport";
  if (/INCOME TAX|PERMANENT ACCOUNT NUMBER|\bPAN\b/.test(text) || PAN_REGEX.test(text)) return "pan";
  if (/DRIVING LICEN[CS]E|TRANSPORT DEPARTMENT|\bDL\s*NO/.test(text) || DL_REGEX.test(text)) return "driving_licence";
  if (/ELECTION COMMISSION|ELECTOR PHOTO IDENTITY|EPIC/.test(text) || VOTER_REGEX.test(text)) return "voter_id";

  const aadhaarNumberFound = [...text.matchAll(AADHAAR_REGEX)].length > 0;
  const aadhaarTextMarker = /AADHAAR|AADHAR|UNIQUE IDENTIFICATION|GOVERNMENT OF INDIA/.test(text);
  const aadhaarLayoutMarker =
    /GOVERNMENT OF INDIA/.test(text)
    && /\b(?:DOB|DATE OF BIRTH|YOB)\b/.test(text)
    && /\b(?:MALE|FEMALE)\b/.test(text);

  if ((aadhaarTextMarker && aadhaarNumberFound) || aadhaarLayoutMarker || byFileName === "aadhaar") return "aadhaar";
  return byFileName || "other";
}

function lineAfterLabel(lines, pattern) {
  for (let index = 0; index < lines.length; index += 1) {
    if (!pattern.test(lines[index])) continue;
    const inline = normalizeSpace(lines[index].replace(pattern, "").replace(/^\s*[:.-]\s*/, ""));
    if (inline && !/^[:.-]+$/.test(inline)) return inline;
    const next = normalizeSpace(lines[index + 1] || "");
    if (next) return next;
  }
  return "";
}

function probableName(lines, documentType) {
  if (documentType === "passport") {
    const surname = lineAfterLabel(lines, /^(?:surname|last name)\s*/i);
    const given = lineAfterLabel(lines, /^(?:given names?|given name|first name)\s*/i);
    if (surname || given) return titleCaseWords(`${given} ${surname}`);
  }
  if (documentType === "pan") {
    const name = lineAfterLabel(lines, /^(?:name)\s*/i);
    if (name) return titleCaseWords(name);
  }
  if (documentType === "driving_licence" || documentType === "voter_id") {
    const name = lineAfterLabel(lines, /^(?:name|holder'?s? name|elector'?s? name)\s*/i);
    if (name) return titleCaseWords(name);
  }

  const rejected = /government|india|aadhaar|uidai|income tax|department|date of birth|dob|male|female|address|year of birth|father|signature|passport|republic|driving|licen[cs]e|election|commission|authority|number|no\.|issue|valid/i;
  const candidates = lines
    .map(normalizeSpace)
    .filter((line) => line.length >= 3 && line.length <= 60)
    .filter((line) => /^[A-Za-z][A-Za-z .'-]+$/.test(line))
    .filter((line) => !rejected.test(line));

  if (documentType === "aadhaar") {
    const dateIndex = lines.findIndex((line) => /\b(?:DOB|YOB|DATE OF BIRTH|YEAR OF BIRTH)\b/i.test(line));
    if (dateIndex > 0) {
      for (let index = dateIndex - 1; index >= Math.max(0, dateIndex - 3); index -= 1) {
        const line = normalizeSpace(lines[index]);
        if (/^[A-Za-z][A-Za-z .'-]{2,59}$/.test(line) && !rejected.test(line)) return titleCaseWords(line);
      }
    }
  }

  return candidates.length ? titleCaseWords(candidates[0]) : "";
}

function parseGender(text) {
  if (/\bFEMALE\b/i.test(text)) return "female";
  if (/\bM(?:ALE|ALLE)\b/i.test(text)) return "male";
  if (/\b(?:TRANSGENDER|THIRD GENDER)\b/i.test(text)) return "other";
  return "";
}

function extractAddress(lines) {
  const start = lines.findIndex((line) => /\baddress\b\s*[:-]?/i.test(line));
  if (start < 0) return "";
  const addressLines = [];
  for (let index = start; index < Math.min(lines.length, start + 7); index += 1) {
    const cleaned = normalizeSpace(lines[index]).replace(/^address\s*[:-]?\s*/i, "");
    if (!cleaned) continue;
    if (/\b(?:dob|date of birth|male|female|aadhaar|vid|signature)\b/i.test(cleaned)) break;
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
    const match = raw.toUpperCase().match(PAN_REGEX);
    return match ? maskPan(match[0]) : "";
  }
  if (documentType === "passport") {
    const match = raw.toUpperCase().match(PASSPORT_REGEX);
    return match ? maskGeneric(match[0]) : "";
  }
  if (documentType === "driving_licence") {
    const match = raw.toUpperCase().match(DL_REGEX);
    return match ? maskGeneric(match[0]) : "";
  }
  if (documentType === "voter_id") {
    const match = raw.toUpperCase().match(VOTER_REGEX);
    return match ? maskGeneric(match[0]) : "";
  }
  return "";
}

function extractDateOfBirth(lines, text) {
  const labelPattern = /\b(?:DOB|DATE OF BIRTH|BIRTH DATE|D\.O\.B\.?|जन्म(?:\s+तिथि)?)\b/i;
  for (let index = 0; index < lines.length; index += 1) {
    if (!labelPattern.test(lines[index])) continue;
    const sameLine = lines[index].match(DATE_REGEX);
    if (sameLine) return isoDateFromMatch(sameLine);
    const nextLine = String(lines[index + 1] || "").match(DATE_REGEX);
    if (nextLine) return isoDateFromMatch(nextLine);
  }
  const generic = String(text || "").match(DATE_REGEX);
  return isoDateFromMatch(generic);
}

export function extractIdentityFromText(rawText, requestedDocumentType = "auto", hints = {}) {
  const raw = String(rawText || "");
  const detectedDocumentType = inferDocumentType(raw, hints.fileName || "");
  const documentType = requestedDocumentType && requestedDocumentType !== "auto"
    ? requestedDocumentType
    : detectedDocumentType;
  const maskedText = maskSensitiveNumbers(raw);
  const extractedFields = parseSafeFields(maskedText, documentType);
  const documentNumberMasked = extractMaskedDocumentNumber(raw, documentType) || null;
  return {
    documentType,
    extractedFields,
    documentNumberMasked,
  };
}

function parseSafeFields(rawText, documentType) {
  const text = String(rawText || "");
  const lines = text.split(/\r?\n/).map(normalizeSpace).filter(Boolean);
  const address = extractAddress(lines);
  const postalCode = extractPostalCode(text);
  const indianDocument = ["aadhaar", "pan", "voter_id", "driving_licence"].includes(documentType);
  const fields = {
    full_name: probableName(lines, documentType),
    date_of_birth: extractDateOfBirth(lines, text),
    gender: parseGender(text),
    address_line1: address,
    postal_code: postalCode,
    nationality: indianDocument ? "India" : documentType === "passport" && /\bIND\b/.test(text) ? "India" : "",
    country_of_residence: indianDocument ? "India" : "",
  };
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== "" && value !== null && value !== undefined));
}

export async function analyzeIdentityDocument(file, requestedDocumentType = "auto", options = {}) {
  if (!file) throw new Error("Choose or capture a document first.");
  if (!String(file.type || "").startsWith("image/")) {
    return {
      status: "limited",
      method: "manual",
      documentType: requestedDocumentType === "auto" ? "other" : requestedDocumentType,
      extractedFields: {},
      documentNumberMasked: null,
      secureQrDetected: false,
      secureQrSupported: false,
      secureQrPayloadSha256: null,
      rawOcrTextStored: false,
      rawQrPayloadStored: false,
      message: "Automatic extraction currently runs on JPG/PNG captures. Review this file manually.",
    };
  }

  const bitmap = await imageBitmapFromFile(file);
  try {
    const [textResult, qrResult] = await Promise.all([
      detectText(bitmap, file, options.onProgress),
      detectQr(bitmap),
    ]);
    const rawText = textResult.text || "";
    const { documentType, extractedFields, documentNumberMasked } = extractIdentityFromText(
      rawText,
      requestedDocumentType,
      { fileName: file.name }
    );
    const hasText = Boolean(rawText.trim());
    const meaningfulFieldKeys = ["full_name", "date_of_birth", "gender", "address_line1", "postal_code"];
    const meaningfulFieldCount = meaningfulFieldKeys.filter((key) => Boolean(extractedFields[key])).length;
    const hasExtractedIdentity = meaningfulFieldCount > 0 || Boolean(documentNumberMasked);
    const status = hasExtractedIdentity ? "extracted" : "limited";
    const warnings = [];
    if (!hasText && textResult.errorMessage) warnings.push(`OCR engine could not start: ${textResult.errorMessage}. Hard-refresh the page and try again.`);
    else if (!hasText) warnings.push("No readable text was detected. Retake the photo with better focus and lighting, or enter the fields manually.");
    else if (!hasExtractedIdentity) warnings.push("Text was detected, but StayQR could not confidently map the ID fields. Retake a straighter, sharper photo or enter the fields manually.");
    if (documentType === "aadhaar" && qrResult.detected) warnings.push("Aadhaar QR detected. This simplified check-in uses it only as a scan signal and does not claim UIDAI verification.");

    return {
      status,
      method: hasText ? textResult.engine : qrResult.detected ? "barcode_detector" : "manual",
      confidence: textResult.confidence ?? null,
      ocrRuntimeReady: Boolean(textResult.supported),
      documentType,
      extractedFields,
      documentNumberMasked,
      secureQrDetected: qrResult.detected,
      secureQrSupported: qrResult.supported,
      secureQrPayloadSha256: qrResult.secureQrPayloadSha256,
      rawOcrTextStored: false,
      rawQrPayloadStored: false,
      warnings,
      message: warnings.join(" ") || (hasExtractedIdentity ? "ID details extracted. Review them before completing check-in." : "ID selected. Review and enter any missing details."),
    };
  } finally {
    bitmap?.close?.();
  }
}
