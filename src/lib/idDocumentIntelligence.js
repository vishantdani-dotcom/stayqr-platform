const AADHAAR_REGEX = /\b(\d{4})[\s.-]{0,3}(\d{4})[\s.-]{0,3}(\d{4})\b/g;
const DATE_REGEX = /\b([0-3]?\d)\s*[/.-]\s*([01]?\d)\s*[/.-]\s*((?:19|20)\d{2})\b/;
const PAN_REGEX = /\b[A-Z]{5}\d{4}[A-Z]\b/i;
const PASSPORT_REGEX = /\b[A-Z][0-9]{7}\b/i;
const VOTER_REGEX = /\b[A-Z]{3}\d{7}\b/i;
const DL_REGEX = /\b[A-Z]{2}[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{7}\b/i;
const MAX_PROVIDER_IMAGE_BYTES = 5 * 1024 * 1024;
const CLIENT_OCR_TIMEOUT_MS = 30000;

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

function filenameDocumentType(fileName) {
  const name = String(fileName || "").toLowerCase();
  if (/\b(?:aadhaar|aadhar|adhar)\b/.test(name)) return "aadhaar";
  if (/\bpan\b/.test(name)) return "pan";
  if (/passport/.test(name)) return "passport";
  if (/(?:driving|licen[cs]e|\bdl\b)/.test(name)) return "driving_licence";
  if (/(?:voter|epic)/.test(name)) return "voter_id";
  return "";
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
  const aadhaarLayoutMarker = /GOVERNMENT OF INDIA/.test(text)
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

const NAME_NOISE_RE = /government|govt\.?|india|bharat|aadhaar|aadhar|uidai|unique identification|income tax|department|date of birth|dob|male|female|address|year of birth|father|mother|signature|passport|republic|driving|licen[cs]e|election|commission|authority|number|no\.|issue|issued|valid|verified|verify|download|document|identity|support|update|updated|enrolment|enrollment|vid\b|help|www\.|http|toll\s*free/i;
const ADDRESS_NOISE_RE = /documents?\s+to\s+support|identity\s+and\s+address|should\s+be\s+updated|update\s+your|downloaded|digitally\s+signed|authentication|verification|government\s+of\s+india|unique\s+identification|aadhaar\s+is|mera\s+aadhaar|www\.|uidai\.gov/i;
const ADDRESS_LABEL_RE = /^(?:address|पता)\s*[:.-]\s*/i;
const ADDRESS_RELATION_RE = /^(?:c\/?o|s\/?o|d\/?o|w\/?o)\b/i;
const ADDRESS_SIGNAL_RE = /\b(?:road|rd\.?|street|st\.?|lane|nagar|colony|sector|ward|village|gaon|taluka|tehsil|district|dist\.?|state|near|opp(?:osite)?|behind|apartment|flat|house|plot|floor|post|po\b|p\.o\.|pin(?:code)?|maharashtra|madhya pradesh|uttar pradesh|delhi|karnataka|tamil nadu|telangana|gujarat|rajasthan|punjab|haryana|bihar|odisha|west bengal|kerala|goa)\b/i;

function looksLikePersonName(value) {
  const line = normalizeSpace(value);
  if (line.length < 3 || line.length > 60) return false;
  if (!/^[A-Za-z][A-Za-z .'-]+$/.test(line)) return false;
  if (NAME_NOISE_RE.test(line)) return false;
  const tokens = line.split(/\s+/).filter(Boolean);
  if (tokens.length >= 2) return true;
  return tokens.length === 1 && tokens[0].length >= 4;
}

function probableName(lines, documentType) {
  if (documentType === "passport") {
    const surname = lineAfterLabel(lines, /^(?:surname|last name)\s*/i);
    const given = lineAfterLabel(lines, /^(?:given names?|given name|first name)\s*/i);
    const combined = normalizeSpace(`${given} ${surname}`);
    if (looksLikePersonName(combined)) return titleCaseWords(combined);
  }
  if (documentType === "pan") {
    const name = lineAfterLabel(lines, /^(?:name)\s*/i);
    if (looksLikePersonName(name)) return titleCaseWords(name);
  }
  if (documentType === "driving_licence" || documentType === "voter_id") {
    const name = lineAfterLabel(lines, /^(?:name|holder'?s? name|elector'?s? name)\s*/i);
    if (looksLikePersonName(name)) return titleCaseWords(name);
  }

  if (documentType === "aadhaar") {
    const dateIndex = lines.findIndex((line) => /\b(?:DOB|YOB|DATE OF BIRTH|YEAR OF BIRTH|जन्म(?:\s+तिथि)?)\b/i.test(line));
    if (dateIndex > 0) {
      const scored = [];
      for (let index = Math.max(0, dateIndex - 6); index < dateIndex; index += 1) {
        const line = normalizeSpace(lines[index]);
        if (!looksLikePersonName(line)) continue;
        const distance = dateIndex - index;
        const tokenCount = line.split(/\s+/).filter(Boolean).length;
        let score = 20 - (distance * 2);
        if (tokenCount >= 2) score += 8;
        if (tokenCount >= 3) score += 2;
        scored.push({ line, score });
      }
      scored.sort((a, b) => b.score - a.score);
      if (scored[0]) return titleCaseWords(scored[0].line);
    }
  }

  const candidate = lines.map(normalizeSpace).find(looksLikePersonName);
  return candidate ? titleCaseWords(candidate) : "";
}

function parseGender(text) {
  if (/\bFEMALE\b/i.test(text)) return "female";
  if (/\bM(?:ALE|ALLE)\b/i.test(text)) return "male";
  if (/\b(?:TRANSGENDER|THIRD GENDER)\b/i.test(text)) return "other";
  return "";
}

function extractAddress(lines) {
  let start = lines.findIndex((line) => ADDRESS_LABEL_RE.test(normalizeSpace(line)));
  let explicitLabel = start >= 0;
  if (start < 0) {
    start = lines.findIndex((line) => ADDRESS_RELATION_RE.test(normalizeSpace(line)));
    explicitLabel = false;
  }
  if (start < 0) return "";

  const addressLines = [];
  for (let index = start; index < Math.min(lines.length, start + 8); index += 1) {
    let cleaned = normalizeSpace(lines[index]);
    if (index === start && explicitLabel) cleaned = cleaned.replace(ADDRESS_LABEL_RE, "");
    if (!cleaned) continue;
    if (ADDRESS_NOISE_RE.test(cleaned)) break;
    if (/\b(?:dob|date of birth|male|female|aadhaar|vid|signature|verified|verify)\b/i.test(cleaned)) break;
    if (/^\d{4}[\s.-]?\d{4}[\s.-]?\d{4}$/.test(cleaned.replace(/X/gi, "0"))) break;
    addressLines.push(cleaned);
  }

  const combined = normalizeSpace(addressLines.join(", ")).slice(0, 240);
  if (combined.length < 10 || ADDRESS_NOISE_RE.test(combined)) return "";
  const hasPostalCode = /\b[1-9]\d{5}\b/.test(combined);
  const hasAddressSignal = ADDRESS_SIGNAL_RE.test(combined) || ADDRESS_RELATION_RE.test(combined);
  if (!hasPostalCode && !hasAddressSignal && addressLines.length < 2) return "";
  return combined;
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

function validIsoDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ""))) return "";
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return "";
  const nowYear = new Date().getUTCFullYear();
  if (year < 1900 || year > nowYear) return "";
  return value;
}

function extractDateOfBirth(lines, text) {
  const labelPattern = /\b(?:DOB|DATE OF BIRTH|BIRTH DATE|D\.O\.B\.?|जन्म(?:\s+तिथि)?)\b/i;
  for (let index = 0; index < lines.length; index += 1) {
    if (!labelPattern.test(lines[index])) continue;
    const sameLine = validIsoDate(isoDateFromMatch(lines[index].match(DATE_REGEX)));
    if (sameLine) return sameLine;
    const nextLine = validIsoDate(isoDateFromMatch(String(lines[index + 1] || "").match(DATE_REGEX)));
    if (nextLine) return nextLine;
  }
  return validIsoDate(isoDateFromMatch(String(text || "").match(DATE_REGEX)));
}

function parseSafeFields(rawText, documentType) {
  const text = String(rawText || "");
  const lines = text.split(/\r?\n/).map(normalizeSpace).filter(Boolean);
  const address = extractAddress(lines);
  const postalCode = address ? extractPostalCode(address) : "";
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

function extractionQuality(documentType, fields, documentNumberMasked) {
  let score = 0;
  const reasons = [];
  if (documentNumberMasked) score += 25; else reasons.push("document number not confidently detected");
  if (fields.full_name) score += 25; else reasons.push("name needs review");
  if (fields.date_of_birth) score += 20; else reasons.push("date of birth needs review");
  if (fields.gender) score += 10;
  if (fields.address_line1) score += 10;
  if (fields.postal_code) score += 10;

  const coreReady = documentType === "aadhaar"
    ? Boolean(documentNumberMasked && fields.full_name && fields.date_of_birth)
    : Boolean(documentNumberMasked || fields.full_name);
  return {
    score: Math.min(100, score),
    reviewRequired: !coreReady || score < 60,
    reasons,
  };
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
  const quality = extractionQuality(documentType, extractedFields, documentNumberMasked);
  return {
    documentType,
    extractedFields,
    documentNumberMasked,
    qualityScore: quality.score,
    reviewRequired: quality.reviewRequired,
    qualityReasons: quality.reasons,
  };
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(offset + chunkSize, bytes.length)));
  }
  return btoa(binary);
}

async function compressImageForProvider(file) {
  if (!file || !String(file.type || "").startsWith("image/")) return file;
  if (file.size <= 900 * 1024) return file;
  if (typeof createImageBitmap !== "function" || typeof document === "undefined") return file;

  const bitmap = await createImageBitmap(file);
  try {
    const longEdge = Math.max(bitmap.width, bitmap.height);
    const scale = longEdge > 1800 ? 1800 / longEdge : 1;
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const context = canvas.getContext("2d");
    if (!context) return file;
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.88));
    if (!blob) return file;
    return new File([blob], `${file.name.replace(/\.[^.]+$/, "") || "guest-id"}.jpg`, { type: "image/jpeg" });
  } finally {
    bitmap.close?.();
  }
}

async function invokeBackendOcr(file, requestedDocumentType, options) {
  if (!options?.hotelId) throw new Error("Hotel context is required before scanning an ID.");
  if (!String(file.type || "").startsWith("image/")) {
    return {
      status: "limited",
      method: "manual",
      documentType: requestedDocumentType === "auto" ? filenameDocumentType(file.name) || "other" : requestedDocumentType,
      extractedFields: {},
      documentNumberMasked: null,
      rawOcrTextStored: false,
      rawQrPayloadStored: false,
      message: "Automatic extraction currently supports JPG/PNG photos. Review this file manually.",
    };
  }

  options.onProgress?.(12);
  const providerFile = await compressImageForProvider(file);
  if (providerFile.size > MAX_PROVIDER_IMAGE_BYTES) {
    throw new Error("This ID photo is too large to read automatically. Use a smaller photo or enter the details manually.");
  }

  options.onProgress?.(28);
  const contentBase64 = arrayBufferToBase64(await providerFile.arrayBuffer());
  options.onProgress?.(42);

  const { supabase } = await import("./supabase");
  const requestPromise = supabase.functions.invoke("id-document-ocr", {
    body: {
      hotel_id: options.hotelId,
      file_name: file.name,
      mime_type: providerFile.type,
      requested_document_type: requestedDocumentType,
      content_base64: contentBase64,
    },
  });

  const timeoutPromise = new Promise((_, reject) => {
    window.setTimeout(() => reject(new Error("ID reading took too long. Please try once more or enter the details manually.")), CLIENT_OCR_TIMEOUT_MS);
  });

  options.onProgress?.(60);
  const { data, error } = await Promise.race([requestPromise, timeoutPromise]);
  if (error) {
    const message = data?.error || error?.message || "Unable to read this ID automatically.";
    throw new Error(message);
  }
  if (!data?.ok) throw new Error(data?.error || "Unable to read this ID automatically.");

  options.onProgress?.(100);
  return data.analysis;
}

export function prewarmIdentityOcrRuntime() {
  return Promise.resolve(true);
}

export async function analyzeIdentityDocument(file, requestedDocumentType = "auto", options = {}) {
  if (!file) throw new Error("Choose or capture a document first.");
  return invokeBackendOcr(file, requestedDocumentType, options);
}
