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
  firestoreWriter?: (appointmentId: string, data: Record<string, any>) => Promise<void>;
}

function getEnv(k: string): string | undefined {
  if (typeof Deno !== "undefined" && Deno.env) {
    return Deno.env.get(k);
  }
  if (typeof process !== "undefined" && process.env) {
    return process.env[k];
  }
  return undefined;
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
function timingSafeEqualStr(a: string, b: string): boolean {
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

async function createServiceAccountJwt(
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
    aud: "https://oauth2.googleapis.com/token",
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

async function getGoogleOAuthToken(
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

  const res = await fetch("https://oauth2.googleapis.com/token", {
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
 * Standard Firestore REST Writer using Google OAuth2 token and Web Crypto.
 * Runs in pure Edge Runtime with zero Node-only dependencies.
 */
async function defaultFirestoreWriter(
  appointmentId: string,
  data: Record<string, any>
): Promise<void> {
  const rawServiceAccount = getEnv("FIREBASE_SERVICE_ACCOUNT_KEY");
  let projectId = getEnv("FIREBASE_PROJECT_ID") || getEnv("GCLOUD_PROJECT");
  let clientEmail = getEnv("FIREBASE_CLIENT_EMAIL");
  let privateKey = getEnv("FIREBASE_PRIVATE_KEY");

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

  if (privateKey.includes("\\n")) {
    privateKey = privateKey.replace(/\\n/g, "\n");
  }

  const accessToken = await getGoogleOAuthToken(clientEmail, privateKey);

  // Convert payload into Firestore REST fields format and updateMask
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
    } else if (typeof val === "string") {
      fields[key] = { stringValue: val };
    } else {
      fields[key] = { stringValue: String(val) };
    }
  }

  const maskQuery = fieldPaths.map((p) => `updateMask.fieldPaths=${encodeURIComponent(p)}`).join("&");
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/documents/appointments/${encodeURIComponent(appointmentId)}?${maskQuery}`;

  const resp = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Firestore REST write failed (${resp.status}): ${errText}`);
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

  try {
    const payload = await req.json();
    const eventType = String(payload?.type || "").toUpperCase();
    const table = String(payload?.table || "").toLowerCase();
    const schema = String(payload?.schema || "public").toLowerCase();
    const record = payload?.record;

    // 2. EVENT FILTERING:
    // Only act on type UPDATE for schema public, table appointments; anything else returns 200 {ignored: true}
    if (eventType !== "UPDATE" || table !== "appointments" || schema !== "public") {
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
      syncedBy === "firestore_cloud_function" ||
      syncedBy === "supabase_bridge"
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

    const appointmentId = String(record.appointment_id || record.appointmentId || record.id || "").trim();
    if (!appointmentId) {
      return new Response(
        JSON.stringify({ error: "bad_request", message: "Missing appointment_id in record" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. WRITE ONLY STATUS / CANCELLATION FIELDS, ALWAYS WITH syncedBy: 'supabase_bridge':
    const firestoreUpdate: Record<string, any> = {
      syncedBy: "supabase_bridge",
    };

    if (record.status !== undefined) {
      firestoreUpdate.status = record.status;
    }
    if (record.patient_status !== undefined || record.patientStatus !== undefined) {
      firestoreUpdate.patientStatus = record.patient_status !== undefined ? record.patient_status : record.patientStatus;
    }
    if (record.doctor_status !== undefined || record.doctorStatus !== undefined) {
      firestoreUpdate.doctorStatus = record.doctor_status !== undefined ? record.doctor_status : record.doctorStatus;
    }
    if (record.cancellation_reason !== undefined || record.cancellationReason !== undefined) {
      firestoreUpdate.cancellationReason = record.cancellation_reason !== undefined ? record.cancellation_reason : record.cancellationReason;
    }
    if (record.cancelled_by !== undefined || record.cancelledBy !== undefined) {
      firestoreUpdate.cancelledBy = record.cancelled_by !== undefined ? record.cancelled_by : record.cancelledBy;
    }
    if (record.cancelled_at !== undefined || record.cancelledAt !== undefined) {
      const rawCancelledAt = record.cancelled_at !== undefined ? record.cancelled_at : record.cancelledAt;
      firestoreUpdate.cancelledAt = rawCancelledAt ? new Date(rawCancelledAt) : null;
    }
    if (record.updated_at || record.updatedAt) {
      firestoreUpdate.updatedAt = new Date(record.updated_at || record.updatedAt);
    } else {
      firestoreUpdate.updatedAt = new Date();
    }

    // 5. WRITE TO FIRESTORE:
    const writer = options?.firestoreWriter ?? defaultFirestoreWriter;
    await writer(appointmentId, firestoreUpdate);

    return new Response(
      JSON.stringify({
        success: true,
        appointmentId,
        syncedBy: "supabase_bridge",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
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
