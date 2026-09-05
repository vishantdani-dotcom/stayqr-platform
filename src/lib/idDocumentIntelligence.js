const AADHAAR_REGEX = /\b(\d{4})[\s.-]{0,3}(\d{4})[\s.-]{0,3}(\d{4})\b/g;
const DATE_REGEX = /\b([0-3]?\d)\s*[/.-]\s*([01]?\d)\s*[/.-]\s*((?:19|20)\d{2})\b/;
const PAN_REGEX = /\b[A-Z]{5}\d{4}[A-Z]\b/i;
const PASSPORT_REGEX = /\b[A-Z][0-9]{7}\b/i;
const VOTER_REGEX = /\b[A-Z]{3}\d{7}\b/i;
const DL_REGEX = /\b[A-Z]{2}[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{7}\b/i;
const MAX_PROVIDER_IMAGE_BYTES = 5 * 1024 * 1024;
const CLIENT_OCR_TIMEOUT_MS = 15000;

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
      for (let index = dateIndex - 1; index >= Math.max(0, dateIndex - 4); index -= 1) {
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
  return isoDateFromMatch(String(text || "").match(DATE_REGEX));
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

export function extractIdentityFromText(rawText, requestedDocumentType = "auto", hints = {}) {
  const raw = String(rawText || "");
  const detectedDocumentType = inferDocumentType(raw, hints.fileName || "");
  const documentType = requestedDocumentType && requestedDocumentType !== "auto"
    ? requestedDocumentType
    : detectedDocumentType;
  const maskedText = maskSensitiveNumbers(raw);
  return {
    documentType,
    extractedFields: parseSafeFields(maskedText, documentType),
    documentNumberMasked: extractMaskedDocumentNumber(raw, documentType) || null,
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
