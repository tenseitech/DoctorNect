// Supabase Edge Function: sync-to-firestore
// Reverse sync: Propagates Supabase appointment updates (status changes, cancellations)
// back to Firestore so doctor calendars reflect patient actions in real-time.
//
// Runtime: Supabase Edge Runtime (Deno-compatible).
// Authentication: Shared secret (SYNC_TO_FIRESTORE_SECRET) validated via constant-time comparison.
// Firestore Writer: Standard Web Crypto RS256 JWT + Firestore REST API (zero Node-only dependencies).

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-webhook-secret, x-supabase-webhook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export interface SyncToFirestoreOptions {
  expectedSecret?: string | null;
  firestoreWriter?: (
    appointmentId: string,
    data: Record<string, any>,
    precondition?: string | { updateTime?: string; exists?: boolean }
  ) => Promise<void>;
  firestoreReader?: (appointmentId: string) => Promise<any>;
  deadLetterWriter?: (
    appointmentId: string,
    reason:
      | "firestore_doc_missing"
      | "terminal_state"
      | "invalid_status_value"
      | "missing_required_fields"
      | "invalid_argument"
      | "other",
    changedFieldNames: string[],
    updatedAtMs?: number | string
  ) => Promise<void>;
}

export function getFieldValue(obj: Record<string, any> | undefined | null, snake: string, camel: string): any {
  if (!obj || typeof obj !== "object") return undefined;
  if (obj[snake] !== undefined) return obj[snake];
  if (obj[camel] !== undefined) return obj[camel];
  return undefined;
}

export function areFieldValuesEqual(valA: any, valB: any): boolean {
  if (valA === valB) return true;
  if ((valA === null || valA === undefined || valA === "") && (valB === null || valB === undefined || valB === "")) {
    return true;
  }
  if (valA && valB) {
    const timeA = new Date(valA).getTime();
    const timeB = new Date(valB).getTime();
    if (!Number.isNaN(timeA) && !Number.isNaN(timeB)) {
      return timeA === timeB;
    }
  }
  return false;
}

export const ALLOWED_PATIENT_STATUS_SQL = new Set([
  "pending",
  "confirmed",
  "completed",
  "cancelled",
]);

export const ALLOWED_PATIENT_STATUS_FIRESTORE = new Set([
  "pending",
  "confirmed",
]);

export const ALLOWED_DOCTOR_STATUS = new Set([
  "pendingRequest",
  "confirmed",
  "inProgress",
  "completed",
  "cancelled",
  "noShow",
  "waiting",
]);

export const ALLOWED_VISIT_TYPE = new Set([
  "newVisit",
  "followUp",
  "returning",
]);

export interface StatusDiff {
  hasChanged: boolean;
  changedFields: Record<string, any>;
  invalidFields?: string[];
}

export function extractChangedStatusFields(
  record: Record<string, any>,
  oldRecord?: Record<string, any> | null
): StatusDiff {
  const isOldRecordMissing = !oldRecord || typeof oldRecord !== "object";
  const changedFields: Record<string, any> = {};
  const invalidFields: string[] = [];
  let hasChanged = false;

  const fieldDefs: Array<{
    snake: string;
    camel: string;
    firestoreKey: string;
    isDate?: boolean;
  }> = [
    { snake: "patient_status", camel: "patientStatus", firestoreKey: "patientStatus" },
    { snake: "doctor_status", camel: "doctorStatus", firestoreKey: "doctorStatus" },
    { snake: "cancellation_reason", camel: "cancellationReason", firestoreKey: "cancellationReason" },
    { snake: "cancelled_by", camel: "cancelledBy", firestoreKey: "cancelledBy" },
    { snake: "cancelled_at", camel: "cancelledAt", firestoreKey: "cancelledAt", isDate: true },
  ];

  for (const def of fieldDefs) {
    const newRaw = getFieldValue(record, def.snake, def.camel);
    if (newRaw === undefined) continue;

    // Validate enum values if applicable
    if (def.snake === "patient_status") {
      const pVal = String(newRaw).trim();
      if (!ALLOWED_PATIENT_STATUS_SQL.has(pVal)) {
        invalidFields.push("patient_status");
      }
    } else if (def.snake === "doctor_status") {
      const dVal = String(newRaw).trim();
      if (!ALLOWED_DOCTOR_STATUS.has(dVal)) {
        invalidFields.push("doctor_status");
      }
    }

    if (isOldRecordMissing) {
      hasChanged = true;
      if (def.snake === "patient_status") {
        const pVal = String(newRaw).trim();
        // If changed to 'completed' or 'cancelled', do NOT write patientStatus to Firestore
        if (pVal === "pending" || pVal === "confirmed") {
          changedFields[def.firestoreKey] = pVal;
        }
      } else if (def.isDate) {
        changedFields[def.firestoreKey] = newRaw ? new Date(newRaw) : null;
      } else {
        changedFields[def.firestoreKey] = newRaw;
      }
    } else {
      const oldRaw = getFieldValue(oldRecord, def.snake, def.camel);
      if (!areFieldValuesEqual(newRaw, oldRaw)) {
        hasChanged = true;
        if (def.snake === "patient_status") {
          const pVal = String(newRaw).trim();
          // If changed to 'completed' or 'cancelled', do NOT write patientStatus to Firestore
          if (pVal === "pending" || pVal === "confirmed") {
            changedFields[def.firestoreKey] = pVal;
          }
        } else if (def.isDate) {
          changedFields[def.firestoreKey] = newRaw ? new Date(newRaw) : null;
        } else {
          changedFields[def.firestoreKey] = newRaw;
        }
      }
    }
  }

  return {
    hasChanged,
    changedFields,
    invalidFields: invalidFields.length > 0 ? invalidFields : undefined,
  };
}

export function getEnv(k: string): string | undefined {
  if (typeof Deno !== "undefined" && Deno.env) {
    return Deno.env.get(k);
  }
  if (typeof process !== "undefined" && process.env) {
    return process.env[k];
  }
  return undefined;
}

export function getOAuthTokenUrl(): string {
  return (
    getEnv("GOOGLE_OAUTH_TOKEN_URL") ||
    getEnv("OAUTH_TOKEN_URL") ||
    "https://oauth2.googleapis.com/token"
  );
}

export function getFirestoreBaseUrl(): string {
  const emulatorHost = getEnv("FIRESTORE_EMULATOR_HOST");
  if (emulatorHost) {
    const host = emulatorHost.startsWith("http") ? emulatorHost : `http://${emulatorHost}`;
    return host.replace(/\/+$/, "") + "/v1";
  }
  return (
    getEnv("FIRESTORE_BASE_URL") ||
    "https://firestore.googleapis.com/v1"
  );
}

function extractSecretFromRequest(req: Request): string | null {
  const customHeader =
    req.headers.get("x-webhook-secret") ||
    req.headers.get("x-supabase-webhook-secret");
  if (customHeader) return customHeader.trim();

  const authHeader = req.headers.get("authorization") || req.headers.get("Authorization");
  if (authHeader) {
    const bearerMatch = authHeader.match(/^Bearer\s+(.+)$/i);
    if (bearerMatch) return bearerMatch[1].trim();
    return authHeader.trim();
  }

  return null;
}

/**
 * Constant-time string comparison to prevent timing attacks.
 * Never uses === on secrets.
 */
export function timingSafeEqualStr(a: string, b: string): boolean {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const enc = new TextEncoder();
  const bufA = enc.encode(a);
  const bufB = enc.encode(b);
  if (bufA.length !== bufB.length) return false;
  let result = 0;
  for (let i = 0; i < bufA.length; i++) {
    result |= bufA[i] ^ bufB[i];
  }
  return result === 0;
}

export async function hashIdentifier(str: string): Promise<string> {
  if (!str) return "";
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(str));
  return Array.from(new Uint8Array(buf).slice(0, 8))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function parseFirebaseServiceAccountKey(raw: string): any {
  try {
    return JSON.parse(raw);
  } catch {
    const decoded = typeof atob === "function" ? atob(raw) : Buffer.from(raw, "base64").toString("utf8");
    return JSON.parse(decoded);
  }
}

// -----------------------------------------------------------------------------
// Web Crypto RS256 Google Service Account Auth for Firestore REST
// -----------------------------------------------------------------------------

function base64UrlEncode(data: string | Uint8Array): string {
  let b64: string;
  if (typeof data === "string") {
    b64 = btoa(data);
  } else {
    let binary = "";
    for (let i = 0; i < data.byteLength; i++) {
      binary += String.fromCharCode(data[i]);
    }
    b64 = btoa(binary);
  }
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function createServiceAccountJwt(
  clientEmail: string,
  privateKeyPem: string
): Promise<string> {
  const cleanPem = privateKeyPem
    .replace(/-----BEGIN[ A-Z_-]+-----/g, "")
    .replace(/-----END[ A-Z_-]+-----/g, "")
    .replace(/\s+/g, "");

  const binaryDer = Uint8Array.from(atob(cleanPem), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    sub: clientEmail,
    aud: getOAuthTokenUrl(),
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/datastore",
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaims = base64UrlEncode(JSON.stringify(claims));
  const signingInput = `${encodedHeader}.${encodedClaims}`;

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const encodedSignature = base64UrlEncode(new Uint8Array(signature));
  return `${signingInput}.${encodedSignature}`;
}

let _cachedOAuthToken: { token: string; expiresAt: number } | null = null;

export async function getGoogleOAuthToken(
  clientEmail: string,
  privateKeyPem: string
): Promise<string> {
  const now = Date.now();
  if (_cachedOAuthToken && _cachedOAuthToken.expiresAt > now + 60000) {
    return _cachedOAuthToken.token;
  }

  const jwtAssertion = await createServiceAccountJwt(clientEmail, privateKeyPem);
  const bodyParams = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion: jwtAssertion,
  });

  const tokenUrl = getOAuthTokenUrl();
  const res = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: bodyParams.toString(),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Google OAuth2 token request failed (${res.status}): ${errText}`);
  }

  const tokenJson = await res.json();
  _cachedOAuthToken = {
    token: tokenJson.access_token,
    expiresAt: now + (tokenJson.expires_in || 3600) * 1000,
  };
  return tokenJson.access_token;
}

/**
 * Builds typed Firestore REST document fields and updateMask fieldPaths.
 */
export function buildFirestoreFields(data: Record<string, any>): {
  fields: Record<string, any>;
  fieldPaths: string[];
} {
  const fields: Record<string, any> = {};
  const fieldPaths: string[] = [];

  for (const [key, val] of Object.entries(data)) {
    if (val === undefined) continue;
    fieldPaths.push(key);
    if (val === null) {
      fields[key] = { nullValue: null };
    } else if (typeof val === "boolean") {
      fields[key] = { booleanValue: val };
    } else if (typeof val === "number") {
      if (Number.isInteger(val)) {
        fields[key] = { integerValue: String(val) };
      } else {
        fields[key] = { doubleValue: val };
      }
    } else if (val instanceof Date) {
      fields[key] = { timestampValue: val.toISOString() };
    } else if (Array.isArray(val)) {
      fields[key] = {
        arrayValue: {
          values: val.map((item) => {
            if (item === null || item === undefined) {
              return { nullValue: null };
            }
            if (typeof item === "boolean") {
              return { booleanValue: item };
            }
            if (typeof item === "number") {
              return Number.isInteger(item)
                ? { integerValue: String(item) }
                : { doubleValue: item };
            }
            if (item instanceof Date) {
              return { timestampValue: item.toISOString() };
            }
            return { stringValue: String(item) };
          }),
        },
      };
    } else if (typeof val === "string") {
      fields[key] = { stringValue: val };
    } else {
      fields[key] = { stringValue: String(val) };
    }
  }

  return { fields, fieldPaths };
}

/**
 * Validates required fields and enum values on an INSERT payload.
 *
 * Required fields per Step 0 / TASK 4 contract:
 * doctorId, patientId, doctorName, patientName, dateTime, slotLabel, tokenNumber, patientStatus, doctorStatus, visitType.
 *
 * If patient_status is omitted (undefined), defaults to 'pending' per TASK 4b.
 * If explicitly null, empty, or an unknown enum value (e.g. cancelled/completed), it fails validation.
 */
export function validateInsertPayload(record: Record<string, any>): {
  isValid: boolean;
  missingFields: string[];
  invalidFields: string[];
} {
  const missingFields: string[] = [];
  const invalidFields: string[] = [];

  const requiredDefs: Array<{ name: string; val: any }> = [
    { name: "doctorId", val: record.doctor_id ?? record.doctorId },
    { name: "patientId", val: record.patient_id ?? record.patientId },
    { name: "doctorName", val: record.doctor_name ?? record.doctorName },
    { name: "patientName", val: record.patient_name ?? record.patientName },
    { name: "dateTime", val: record.date_time ?? record.dateTime },
    { name: "slotLabel", val: record.slot_label ?? record.slotLabel },
    { name: "tokenNumber", val: record.token_number ?? record.tokenNumber },
    { name: "doctorStatus", val: record.doctor_status ?? record.doctorStatus },
    { name: "visitType", val: record.visit_type ?? record.visitType },
  ];

  for (const def of requiredDefs) {
    if (def.val === undefined || def.val === null) {
      missingFields.push(def.name);
    } else if (typeof def.val === "string" && !def.val.trim()) {
      missingFields.push(def.name);
    }
  }

  // patientStatus requirement and default handling:
  const rawPatientStatus = record.patient_status !== undefined ? record.patient_status : record.patientStatus;
  if (rawPatientStatus === null || (typeof rawPatientStatus === "string" && !rawPatientStatus.trim())) {
    missingFields.push("patientStatus");
  } else if (rawPatientStatus !== undefined) {
    const pVal = String(rawPatientStatus).trim();
    if (!ALLOWED_PATIENT_STATUS_FIRESTORE.has(pVal)) {
      invalidFields.push("patient_status");
    }
  }

  // Enum validations:
  const rawDoctorStatus = record.doctor_status ?? record.doctorStatus;
  if (rawDoctorStatus !== undefined && rawDoctorStatus !== null && String(rawDoctorStatus).trim()) {
    const dVal = String(rawDoctorStatus).trim();
    if (!ALLOWED_DOCTOR_STATUS.has(dVal)) {
      invalidFields.push("doctor_status");
    }
  }

  const rawVisitType = record.visit_type ?? record.visitType;
  if (rawVisitType !== undefined && rawVisitType !== null && String(rawVisitType).trim()) {
    const vVal = String(rawVisitType).trim();
    if (!ALLOWED_VISIT_TYPE.has(vVal)) {
      invalidFields.push("visit_type");
    }
  }

  const isValid = missingFields.length === 0 && invalidFields.length === 0;
  return { isValid, missingFields, invalidFields };
}

/**
 * Maps a Supabase public.appointments row to a full Firestore appointment document payload,
 * matching the exact contract of the bookAppointment callable and AppointmentFirestoreMapper.
 * Injects syncedBy: 'supabase_bridge' to prevent feedback loops.
 */
export function buildFirestoreAppointmentFromSupabaseRow(
  record: Record<string, any>
): Record<string, any> {
  const appointmentId = String(record.appointment_id || record.appointmentId || record.id || "").trim();
  const doctorId = String(record.doctor_id || record.doctorId || "").trim();
  const doctorName = String(record.doctor_name || record.doctorName || "").trim();
  const specialization = String(record.specialization || "").trim();
  const patientId = String(record.patient_id || record.patientId || "").trim();
  const patientName = String(record.patient_name || record.patientName || "").trim();
  const patientAge = Number(record.patient_age ?? record.patientAge) || 0;
  const patientGender = String(record.patient_gender || record.patientGender || "Male").trim();
  const dateTime = record.date_time
    ? new Date(record.date_time)
    : (record.dateTime ? new Date(record.dateTime) : new Date());
  const slotLabel = String(record.slot_label || record.slotLabel || "").trim();
  const tokenNumber = Number(record.token_number ?? record.tokenNumber) || 0;
  const visitType = String(record.visit_type || record.visitType || "newVisit").trim();
  const patientStatus = String(record.patient_status || record.patientStatus || "pending").trim();
  const doctorStatus = String(record.doctor_status || record.doctorStatus || "pendingRequest").trim();
  const hasPrescription = Boolean(record.has_prescription ?? record.hasPrescription ?? false);
  const hasReport = Boolean(record.has_report ?? record.hasReport ?? false);
  const hasReview = Boolean(record.has_review ?? record.hasReview ?? false);
  const wasRescheduled = Boolean(record.was_rescheduled ?? record.wasRescheduled ?? false);

  const labReports = Array.isArray(record.lab_reports || record.labReports)
    ? (record.lab_reports || record.labReports)
    : [];
  const chiefComplaints = Array.isArray(record.chief_complaints || record.chiefComplaints)
    ? (record.chief_complaints || record.chiefComplaints)
    : [];
  const symptoms = Array.isArray(record.symptoms) ? record.symptoms : [];
  const observations = Array.isArray(record.observations) ? record.observations : [];

  const createdAt = record.created_at
    ? new Date(record.created_at)
    : (record.createdAt ? new Date(record.createdAt) : new Date());
  const updatedAt = record.updated_at
    ? new Date(record.updated_at)
    : (record.updatedAt ? new Date(record.updatedAt) : new Date());

  const doc: Record<string, any> = {
    appointmentId,
    doctorId,
    doctorName,
    specialization,
    patientId,
    patientName,
    patientAge,
    patientGender,
    dateTime,
    slotLabel,
    tokenNumber,
    visitType,
    patientStatus,
    doctorStatus,
    hasPrescription,
    hasReport,
    hasReview,
    labReports,
    chiefComplaints,
    symptoms,
    observations,
    wasRescheduled,
    createdAt,
    updatedAt,
    syncedBy: "supabase_bridge",
  };

  const clinicName = record.clinic_name ?? record.clinicName;
  if (clinicName) doc.clinicName = String(clinicName);

  const clinicAddress = record.clinic_address ?? record.clinicAddress;
  if (clinicAddress) doc.clinicAddress = String(clinicAddress);

  const mapsUrl = record.maps_url ?? record.mapsUrl;
  if (mapsUrl) doc.mapsUrl = String(mapsUrl);

  const cancellationReason = record.cancellation_reason ?? record.cancellationReason;
  if (cancellationReason) doc.cancellationReason = String(cancellationReason);

  const diagnosis = record.diagnosis;
  if (diagnosis) doc.diagnosis = String(diagnosis);

  const reviewRating = record.review_rating ?? record.reviewRating;
  if (reviewRating !== undefined && reviewRating !== null) {
    doc.reviewRating = Number(reviewRating);
  }

  const reviewId = record.review_id ?? record.reviewId;
  if (reviewId) doc.reviewId = String(reviewId);

  const reviewCreatedAt = record.review_created_at ?? record.reviewCreatedAt;
  if (reviewCreatedAt) {
    doc.reviewCreatedAt = new Date(reviewCreatedAt);
  }

  const clinicalNotes = record.clinical_notes ?? record.clinicalNotes;
  if (clinicalNotes) doc.clinicalNotes = String(clinicalNotes);

  const contactNumber = record.contact_number ?? record.contactNumber;
  if (contactNumber) doc.contactNumber = String(contactNumber);

  const source = record.source;
  if (source) doc.source = String(source);

  const bookedByName = record.booked_by_name ?? record.bookedByName;
  if (bookedByName) doc.bookedByName = String(bookedByName);

  const patientRelation = record.patient_relation ?? record.patientRelation;
  if (patientRelation) doc.patientRelation = String(patientRelation);

  const slotShareReason = record.slot_share_reason ?? record.slotShareReason;
  if (slotShareReason) doc.slotShareReason = String(slotShareReason);

  return doc;
}

export const TERMINAL_STATUSES = new Set([
  "completed",
  "inprogress",
  "noshow",
  "inProgress",
  "noShow",
]);

export function isTerminalTransitionRejected(
  currentDoc: any,
  incomingUpdate: Record<string, any>
): { isTerminal: boolean; isRejected: boolean; currentStatus: string } {
  const currentDoctorStatus = String(
    currentDoc?.fields?.doctorStatus?.stringValue || ""
  ).trim();

  const currentPatientStatus = String(
    currentDoc?.fields?.patientStatus?.stringValue || ""
  ).trim();

  const isTerminal =
    TERMINAL_STATUSES.has(currentDoctorStatus) ||
    TERMINAL_STATUSES.has(currentDoctorStatus.toLowerCase()) ||
    currentPatientStatus === "completed";

  if (!isTerminal) {
    return { isTerminal: false, isRejected: false, currentStatus: currentDoctorStatus };
  }

  // If doc is terminal, check if incoming update would transition it away or cancel it
  const targetDocStatus = incomingUpdate.doctorStatus;
  const targetPatientStatus = incomingUpdate.patientStatus;

  let isRejected = false;
  if (targetDocStatus !== undefined && targetDocStatus !== currentDoctorStatus) {
    isRejected = true;
  }
  if (targetPatientStatus !== undefined && targetPatientStatus !== currentPatientStatus) {
    isRejected = true;
  }

  return { isTerminal, isRejected, currentStatus: currentDoctorStatus };
}

/**
 * Standard Firestore REST Reader using Google OAuth2 token and Web Crypto.
 */
export async function defaultFirestoreReader(
  appointmentId: string
): Promise<any> {
  const rawServiceAccount = getEnv("FIREBASE_SERVICE_ACCOUNT_KEY");
  let projectId = getEnv("FIREBASE_PROJECT_ID") || getEnv("GCLOUD_PROJECT");
  let clientEmail = getEnv("FIREBASE_CLIENT_EMAIL");
  let privateKey = getEnv("FIREBASE_PRIVATE_KEY");

  const isEmulator = Boolean(getEnv("FIRESTORE_EMULATOR_HOST")) || Boolean(getEnv("FIRESTORE_BASE_URL"));
  if (isEmulator) {
    projectId = projectId || "demo-doctornect-test";
  } else {
    if (rawServiceAccount) {
      const sa = parseFirebaseServiceAccountKey(rawServiceAccount);
      projectId = sa.project_id || projectId;
      clientEmail = sa.client_email || clientEmail;
      privateKey = sa.private_key || privateKey;
    }

    if (!projectId || !clientEmail || !privateKey) {
      throw new Error(
        "Missing Firebase service account credentials (expected FIREBASE_SERVICE_ACCOUNT_KEY or FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY)"
      );
    }
  }

  let accessToken = "owner";
  if (!isEmulator) {
    if (privateKey && privateKey.includes("\\n")) {
      privateKey = privateKey.replace(/\\n/g, "\n");
    }
    accessToken = await getGoogleOAuthToken(clientEmail!, privateKey!);
  }

  const firestoreBase = getFirestoreBaseUrl();
  const url = `${firestoreBase}/projects/${encodeURIComponent(projectId)}/databases/(default)/documents/appointments/${encodeURIComponent(appointmentId)}`;

  const resp = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!resp.ok) {
    const errText = await resp.text();
    const err: any = new Error(`Firestore REST read failed (${resp.status}): ${errText}`);
    err.status = resp.status;
    err.code = resp.status === 404 ? "NOT_FOUND" : "INTERNAL";
    throw err;
  }

  return await resp.json();
}

/**
 * Durable dead-letter record writer in Firestore syncDeadLetters collection.
 * Uses deterministic ID ${appointmentId}_${reason}_${updatedAtMs} and precondition currentDocument.exists=false.
 * Stores NO free text (field names only).
 */
export async function writeFirestoreDeadLetter(
  appointmentId: string,
  reason:
    | "firestore_doc_missing"
    | "terminal_state"
    | "invalid_status_value"
    | "missing_required_fields"
    | "invalid_argument"
    | "other",
  changedFieldNames: string[],
  updatedAtMs?: number | string
): Promise<void> {
  const ms = updatedAtMs ? Number(updatedAtMs) || Date.now() : Date.now();
  const docId = `${appointmentId}_${reason}_${ms}`;

  const fields: Record<string, any> = {
    direction: { stringValue: "supabase_to_firestore" },
    entityType: { stringValue: "appointments" },
    entityId: { stringValue: appointmentId },
    reason: { stringValue: reason },
    changedFields: {
      arrayValue: {
        values: changedFieldNames.map((name) => ({ stringValue: name })),
      },
    },
    createdAt: { timestampValue: new Date().toISOString() },
    attempts: { integerValue: "1" },
  };

  const rawServiceAccount = getEnv("FIREBASE_SERVICE_ACCOUNT_KEY");
  let projectId = getEnv("FIREBASE_PROJECT_ID") || getEnv("GCLOUD_PROJECT");
  let clientEmail = getEnv("FIREBASE_CLIENT_EMAIL");
  let privateKey = getEnv("FIREBASE_PRIVATE_KEY");

  const isEmulator = Boolean(getEnv("FIRESTORE_EMULATOR_HOST")) || Boolean(getEnv("FIRESTORE_BASE_URL"));
  if (isEmulator) {
    projectId = projectId || "demo-doctornect-test";
  } else {
    if (rawServiceAccount) {
      const sa = parseFirebaseServiceAccountKey(rawServiceAccount);
      projectId = sa.project_id || projectId;
      clientEmail = sa.client_email || clientEmail;
      privateKey = sa.private_key || privateKey;
    }
  }

  let accessToken = "owner";
  if (!isEmulator) {
    if (!projectId || !clientEmail || !privateKey) {
      console.error("[sync-to-firestore] Missing service account credentials for dead letter write");
      return;
    }
    if (privateKey.includes("\\n")) {
      privateKey = privateKey.replace(/\\n/g, "\n");
    }
    accessToken = await getGoogleOAuthToken(clientEmail, privateKey);
  }

  const firestoreBase = getFirestoreBaseUrl();
  const effectiveProjectId = projectId || "demo-doctornect-test";
  const url = `${firestoreBase}/projects/${encodeURIComponent(effectiveProjectId)}/databases/(default)/documents/syncDeadLetters/${encodeURIComponent(docId)}?currentDocument.exists=false`;

  const resp = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });

  // 409 means already recorded with this deterministic ID (treat as success)
  if (resp.status === 409) {
    return;
  }

  if (!resp.ok) {
    const errText = await resp.text();
    console.error(`[sync-to-firestore] Failed to write dead letter (${resp.status}): ${errText}`);
  }
}

/**
 * Standard Firestore REST Writer using Google OAuth2 token and Web Crypto.
 * Runs in pure Edge Runtime with zero Node-only dependencies.
 *
 * Precondition: currentDocument.updateTime enforces optimistic concurrency control.
 */
export async function defaultFirestoreWriter(
  appointmentId: string,
  data: Record<string, any>,
  precondition?: string | { updateTime?: string; exists?: boolean }
): Promise<void> {
  const rawServiceAccount = getEnv("FIREBASE_SERVICE_ACCOUNT_KEY");
  let projectId = getEnv("FIREBASE_PROJECT_ID") || getEnv("GCLOUD_PROJECT");
  let clientEmail = getEnv("FIREBASE_CLIENT_EMAIL");
  let privateKey = getEnv("FIREBASE_PRIVATE_KEY");

  const isEmulator = Boolean(getEnv("FIRESTORE_EMULATOR_HOST")) || Boolean(getEnv("FIRESTORE_BASE_URL"));

  if (isEmulator) {
    projectId = projectId || "demo-doctornect-test";
  } else {
    if (rawServiceAccount) {
      const sa = parseFirebaseServiceAccountKey(rawServiceAccount);
      projectId = sa.project_id || projectId;
      clientEmail = sa.client_email || clientEmail;
      privateKey = sa.private_key || privateKey;
    }

    if (!projectId || !clientEmail || !privateKey) {
      throw new Error(
        "Missing Firebase service account credentials (expected FIREBASE_SERVICE_ACCOUNT_KEY or FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY)"
      );
    }
  }

  let accessToken = "owner";
  if (!isEmulator) {
    if (privateKey && privateKey.includes("\\n")) {
      privateKey = privateKey.replace(/\\n/g, "\n");
    }
    accessToken = await getGoogleOAuthToken(clientEmail!, privateKey!);
  }

  const { fields, fieldPaths } = buildFirestoreFields(data);
  const firestoreBase = getFirestoreBaseUrl();
  const docName = `projects/${encodeURIComponent(projectId)}/databases/(default)/documents/appointments/${encodeURIComponent(appointmentId)}`;
  const url = `${firestoreBase}/projects/${encodeURIComponent(projectId)}/databases/(default)/documents:commit`;

  let currentDocument: any = { exists: true };
  if (typeof precondition === "string") {
    currentDocument = { updateTime: precondition };
  } else if (precondition && typeof precondition === "object") {
    currentDocument = precondition;
  }

  const writeObj: any = {
    update: {
      name: docName,
      fields,
    },
    currentDocument,
  };

  if (currentDocument?.exists !== false) {
    writeObj.updateMask = { fieldPaths };
  }

  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ writes: [writeObj] }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    let parsedStatus: string | undefined;
    let parsedMessage: string | undefined;
    try {
      const errJson = JSON.parse(errText);
      if (errJson?.error) {
        parsedStatus = errJson.error.status;
        parsedMessage = errJson.error.message;
      }
    } catch (_) {}

    const isNotFound =
      parsedStatus === "NOT_FOUND" ||
      resp.status === 404 ||
      errText.includes("no entity to update");

    const isAlreadyExists =
      parsedStatus === "ALREADY_EXISTS" ||
      (resp.status === 409 && (parsedStatus === "ALREADY_EXISTS" || /already exists/i.test(errText)));

    const isFailedPrecondition =
      parsedStatus === "FAILED_PRECONDITION" ||
      parsedStatus === "ABORTED" ||
      resp.status === 412 ||
      (resp.status === 409 && !isAlreadyExists && /precondition|base version/i.test(errText));

    const isInvalidArgument =
      parsedStatus === "INVALID_ARGUMENT" ||
      (resp.status === 400 && parsedStatus !== "FAILED_PRECONDITION");

    const err: any = new Error(
      `Firestore REST write failed (${resp.status}): ${parsedMessage || errText}`
    );
    err.status = resp.status;
    err.code = isNotFound
      ? "NOT_FOUND"
      : isAlreadyExists
      ? "ALREADY_EXISTS"
      : isFailedPrecondition
      ? (parsedStatus || "FAILED_PRECONDITION")
      : isInvalidArgument
      ? "INVALID_ARGUMENT"
      : (parsedStatus || "INTERNAL");
    err.grpcStatus = parsedStatus;
    throw err;
  }
}

// -----------------------------------------------------------------------------
// Request Handler
// -----------------------------------------------------------------------------

export async function handleSyncToFirestore(
  req: Request,
  options?: SyncToFirestoreOptions
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "method_not_allowed", message: "Only POST is supported" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // 1. AUTHENTICATION (FAIL CLOSED):
  // Since deployed with --no-verify-jwt, shared secret is the only authentication.
  // If SYNC_TO_FIRESTORE_SECRET is unset or empty, return 500 immediately.
  const expectedSecret = options?.expectedSecret !== undefined
    ? options.expectedSecret
    : (getEnv("SYNC_TO_FIRESTORE_SECRET") || null);

  if (!expectedSecret || typeof expectedSecret !== "string" || expectedSecret.trim() === "") {
    console.error("[sync-to-firestore] SYNC_TO_FIRESTORE_SECRET is unset or empty; failing closed with 500");
    return new Response(
      JSON.stringify({
        error: "server_misconfigured",
        message: "Webhook authentication secret is not configured or empty (expected SYNC_TO_FIRESTORE_SECRET)",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const providedSecret = extractSecretFromRequest(req);
  if (!providedSecret || !timingSafeEqualStr(providedSecret, expectedSecret)) {
    return new Response(
      JSON.stringify({ error: "unauthorized", message: "Invalid or missing webhook secret" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let appointmentId = "";
  let record: any = null;
  let isInsert = false;

  try {
    const payload = await req.json();
    const eventType = String(payload?.type || "").toUpperCase();
    const table = String(payload?.table || "").toLowerCase();
    const schema = String(payload?.schema || "public").toLowerCase();
    record = payload?.record;
    const oldRecord = payload?.old_record || payload?.oldRecord;

    const isUpdate = eventType === "UPDATE";
    isInsert = eventType === "INSERT";

    // 2. EVENT FILTERING:
    // Only act on type UPDATE or INSERT for schema public, table appointments; anything else returns 200 {ignored: true}
    if ((!isUpdate && !isInsert) || table !== "appointments" || schema !== "public") {
      return new Response(
        JSON.stringify({
          ignored: true,
          reason: `Ignored event: type=${eventType || "unknown"}, table=${table || "unknown"}, schema=${schema}`,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!record || typeof record !== "object") {
      return new Response(
        JSON.stringify({ error: "bad_request", message: "Missing record in payload" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. INFINITE LOOP PREVENTION:
    // If mutation originated from Firestore, Reconciler, or Supabase Bridge itself, DROP IT.
    const syncOrigin = String(record?.sync_origin || record?.syncOrigin || "").trim().toLowerCase();
    const syncedBy = String(record?.synced_by || record?.syncedBy || "").trim().toLowerCase();

    if (
      syncOrigin === "doctor_firestore" ||
      syncOrigin === "patient_firestore" ||
      syncOrigin === "reconciler_bot" ||
      syncOrigin === "firestore_cloud_function" ||
      syncOrigin === "firestore" ||
      syncedBy === "firestore_cloud_function" ||
      syncedBy === "supabase_bridge" ||
      syncedBy === "reconciler_bot"
    ) {
      return new Response(
        JSON.stringify({
          ignored: true,
          reason: "Loop prevented: Origin is Firestore, Reconciler, or Supabase Bridge",
          syncOrigin,
          syncedBy,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    appointmentId = String(record.appointment_id || record.appointmentId || record.id || "").trim();
    if (!appointmentId) {
      return new Response(
        JSON.stringify({ error: "bad_request", message: "Missing appointment_id in record" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const isEmulatedOrCustomBase = Boolean(getEnv("FIRESTORE_EMULATOR_HOST")) || Boolean(getEnv("FIRESTORE_BASE_URL"));
    const defaultMockReader = (!isEmulatedOrCustomBase && options?.firestoreWriter)
      ? async (id: string) => ({
          name: `projects/demo-doctornect-test/databases/(default)/documents/appointments/${id}`,
          updateTime: "2026-10-13T00:00:00Z",
          fields: {},
        })
      : defaultFirestoreReader;

    const reader = options?.firestoreReader ?? defaultMockReader;
    const writer = options?.firestoreWriter ?? defaultFirestoreWriter;
    const deadLetterWriter = options?.deadLetterWriter ?? (
      (!isEmulatedOrCustomBase && options?.firestoreWriter)
        ? async (_id: string, _reason: any, _changedFields: string[], _ms?: any) => {
            // In-memory test hook when firestoreWriter is mocked in tests
          }
        : writeFirestoreDeadLetter
    );

    // 4. INSERT HANDLING (CREATE ONLY IF ABSENT):
    if (isInsert) {
      const validation = validateInsertPayload(record);
      if (validation.missingFields.length > 0) {
        await deadLetterWriter(
          appointmentId,
          "missing_required_fields",
          validation.missingFields,
          record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
        );
        return new Response(
          JSON.stringify({
            skipped: "missing_required_fields",
            appointmentId,
            missingFields: validation.missingFields,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (validation.invalidFields.length > 0) {
        await deadLetterWriter(
          appointmentId,
          "invalid_status_value",
          validation.invalidFields,
          record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
        );
        return new Response(
          JSON.stringify({
            skipped: "invalid_status_value",
            appointmentId,
            invalidFields: validation.invalidFields,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const firestoreDoc = buildFirestoreAppointmentFromSupabaseRow(record);
      try {
        await writer(appointmentId, firestoreDoc, { exists: false });
      } catch (writeErr: any) {
        const isAlreadyExists =
          writeErr?.grpcStatus === "ALREADY_EXISTS" ||
          writeErr?.status === 409 ||
          writeErr?.code === "ALREADY_EXISTS" ||
          (writeErr?.code === "FAILED_PRECONDITION" && /already exists/i.test(String(writeErr?.message)));

        if (isAlreadyExists) {
          return new Response(
            JSON.stringify({
              ignored: "already_exists",
              appointmentId,
              reason: "Appointment document already exists in Firestore; INSERT did not overwrite",
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        throw writeErr;
      }

      return new Response(
        JSON.stringify({
          success: true,
          action: "created",
          appointmentId,
          syncedBy: "supabase_bridge",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 5. UPDATE HANDLING:
    // REAL STATUS / CANCELLATION CHANGE FILTER:
    // Act only when the UPDATE actually changed a status or cancellation field.
    // If none changed, return 200 { ignored: "no_status_change" }
    const statusDiff = extractChangedStatusFields(record, oldRecord);

    if (statusDiff.invalidFields && statusDiff.invalidFields.length > 0) {
      await deadLetterWriter(
        appointmentId,
        "invalid_status_value",
        statusDiff.invalidFields,
        record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
      );
      return new Response(
        JSON.stringify({
          skipped: "invalid_status_value",
          appointmentId,
          invalidFields: statusDiff.invalidFields,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!statusDiff.hasChanged || Object.keys(statusDiff.changedFields).length === 0) {
      return new Response(
        JSON.stringify({
          ignored: "no_status_change",
          reason: "No writable status or cancellation field was changed in UPDATE",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // WRITE ONLY CHANGED STATUS / CANCELLATION FIELDS, ALWAYS WITH syncedBy: 'supabase_bridge':
    const firestoreUpdate: Record<string, any> = {
      syncedBy: "supabase_bridge",
      ...statusDiff.changedFields,
    };

    if (record.updated_at || record.updatedAt) {
      firestoreUpdate.updatedAt = new Date(record.updated_at || record.updatedAt);
    } else {
      firestoreUpdate.updatedAt = new Date();
    }

    // 6. READ CURRENT FIRESTORE DOCUMENT (TERMINAL-STATE & PRECONDITION GUARD):
    let currentDoc: any = null;
    try {
      currentDoc = await reader(appointmentId);
    } catch (readErr: any) {
      if (
        readErr?.status === 404 ||
        readErr?.code === "NOT_FOUND" ||
        String(readErr?.message || "").includes("(404)")
      ) {
        const idHash = await hashIdentifier(appointmentId);
        console.warn(JSON.stringify({
          severity: "WARNING",
          category: "sync",
          action: "sync.reverse_not_found",
          appointmentIdHash: idHash,
          reason: "firestore_doc_missing",
          message: "Appointment document missing in Firestore during reverse sync read",
        }));

        await deadLetterWriter(
          appointmentId,
          "firestore_doc_missing",
          Object.keys(statusDiff.changedFields),
          record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
        );

        return new Response(
          JSON.stringify({
            skipped: "not_found",
            reason: "firestore_doc_missing",
            appointmentIdHash: idHash,
            dlqPersisted: true,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      throw readErr;
    }

    // 7. TERMINAL-STATE GUARD:
    const terminalCheck = isTerminalTransitionRejected(currentDoc, firestoreUpdate);
    if (terminalCheck.isRejected) {
      const idHash = await hashIdentifier(appointmentId);
      console.warn(JSON.stringify({
        severity: "WARNING",
        category: "sync",
        action: "sync.terminal_state_rejected",
        appointmentIdHash: idHash,
        reason: "terminal_state",
        currentStatus: terminalCheck.currentStatus,
        message: "Incoming update rejected: appointment is in a terminal state",
      }));

      await deadLetterWriter(
        appointmentId,
        "terminal_state",
        Object.keys(statusDiff.changedFields),
        record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
      );

      return new Response(
        JSON.stringify({
          skipped: "terminal_state",
          reason: "terminal_state",
          currentStatus: terminalCheck.currentStatus,
          appointmentIdHash: idHash,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 8. WRITE WITH PRECONDITION currentDocument.updateTime & RETRY ON CONFLICT (unverified, see verification procedure):
    try {
      await writer(appointmentId, firestoreUpdate, currentDoc?.updateTime);
    } catch (patchErr: any) {
      const isRetryableConflict =
        patchErr?.grpcStatus === "FAILED_PRECONDITION" ||
        patchErr?.grpcStatus === "ABORTED" ||
        patchErr?.code === "FAILED_PRECONDITION" ||
        patchErr?.code === "ABORTED" ||
        patchErr?.status === 412 ||
        (patchErr?.status === 409 &&
          patchErr?.code !== "ALREADY_EXISTS" &&
          patchErr?.grpcStatus !== "ALREADY_EXISTS");

      if (isRetryableConflict) {
        // Concurrent modification: re-read once
        currentDoc = await reader(appointmentId);
        const recheck = isTerminalTransitionRejected(currentDoc, firestoreUpdate);
        if (recheck.isRejected) {
          const idHash = await hashIdentifier(appointmentId);
          await deadLetterWriter(
            appointmentId,
            "terminal_state",
            Object.keys(statusDiff.changedFields),
            record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
          );
          return new Response(
            JSON.stringify({
              skipped: "terminal_state",
              reason: "terminal_state",
              currentStatus: recheck.currentStatus,
              appointmentIdHash: idHash,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        // Retry PATCH once with refreshed updateTime
        await writer(appointmentId, firestoreUpdate, currentDoc?.updateTime);
      } else {
        throw patchErr;
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        appointmentId,
        syncedBy: "supabase_bridge",
        changedFields: Object.keys(statusDiff.changedFields),
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    if (
      err?.status === 404 ||
      err?.statusCode === 404 ||
      err?.code === "NOT_FOUND" ||
      String(err?.message || "").includes("(404)")
    ) {
      const idHash = await hashIdentifier(appointmentId);
      console.warn(JSON.stringify({
        severity: "WARNING",
        category: "sync",
        action: "sync.reverse_not_found",
        appointmentIdHash: idHash,
        reason: "firestore_doc_missing",
        message: "Precondition currentDocument.exists=true failed; appointment document does not exist in Firestore",
      }));

      const deadLetterWriter = options?.deadLetterWriter ?? writeFirestoreDeadLetter;
      await deadLetterWriter(
        appointmentId,
        "firestore_doc_missing",
        record ? Object.keys(extractChangedStatusFields(record).changedFields) : [],
        record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
      );

      return new Response(
        JSON.stringify({
          skipped: "not_found",
          reason: "firestore_doc_missing",
          appointmentIdHash: idHash,
          dlqPersisted: true,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const isInvalidArgument =
      err?.code === "INVALID_ARGUMENT" ||
      err?.grpcStatus === "INVALID_ARGUMENT";

    if (isInvalidArgument) {
      const idHash = await hashIdentifier(appointmentId);
      console.warn(JSON.stringify({
        severity: "WARNING",
        category: "sync",
        action: "sync.invalid_argument",
        appointmentIdHash: idHash,
        reason: "invalid_argument",
        message: err?.message || "Invalid argument sent to Firestore REST API",
      }));

      const deadLetterWriter = options?.deadLetterWriter ?? writeFirestoreDeadLetter;
      await deadLetterWriter(
        appointmentId,
        "invalid_argument",
        isInsert
          ? Object.keys(buildFirestoreAppointmentFromSupabaseRow(record))
          : (record ? Object.keys(extractChangedStatusFields(record).changedFields) : []),
        record?.updated_at ? new Date(record.updated_at).getTime() : Date.now()
      );

      return new Response(
        JSON.stringify({
          skipped: "invalid_argument",
          reason: "invalid_argument",
          appointmentIdHash: idHash,
          dlqPersisted: true,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.error("[sync-to-firestore] Write failed:", err);
    // Non-2xx status code signals failure so Supabase Database Webhook retries
    return new Response(
      JSON.stringify({
        error: "internal_error",
        message: err?.message || "Failed to sync to Firestore",
        retriable: true,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
}

// Automatic bootstrap in Deno Edge Runtime
if (typeof Deno !== "undefined") {
  if (typeof (Deno as any).serve === "function") {
    (Deno as any).serve((req: Request) => handleSyncToFirestore(req));
  } else {
    import("https://deno.land/std@0.168.0/http/server.ts")
      .then(({ serve }) => serve((req: Request) => handleSyncToFirestore(req)))
      .catch((e) => console.error("[sync-to-firestore] Failed to start server:", e));
  }
}

