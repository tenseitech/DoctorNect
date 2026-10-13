// Supabase Edge Function: sync-to-firestore
// Reverse sync: Propagates Supabase appointment updates (status changes, cancellations)
// back to Firestore so doctor calendars reflect patient actions in real-time.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-webhook-secret, x-supabase-webhook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export interface SyncToFirestoreOptions {
  expectedSecret?: string;
  firestoreWriter?: (appointmentId: string, data: Record<string, any>) => Promise<void>;
}

function getEnvironmentSecret(): string | null {
  const getEnv = (k: string): string | undefined => {
    if (typeof Deno !== "undefined" && Deno.env) {
      return Deno.env.get(k);
    }
    if (typeof process !== "undefined" && process.env) {
      return process.env[k];
    }
    return undefined;
  };

  return (
    getEnv("SYNC_TO_FIRESTORE_SECRET") ||
    getEnv("SYNC_WEBHOOK_SECRET") ||
    getEnv("SUPABASE_WEBHOOK_SECRET") ||
    getEnv("SUPABASE_SERVICE_ROLE_KEY") ||
    null
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

function timingSafeEqualStr(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
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

async function defaultFirestoreWriter(
  appointmentId: string,
  data: Record<string, any>
): Promise<void> {
  const getEnv = (k: string): string | undefined => {
    if (typeof Deno !== "undefined" && Deno.env) return Deno.env.get(k);
    if (typeof process !== "undefined" && process.env) return process.env[k];
    return undefined;
  };

  let initializeApp: any;
  let cert: any;
  let getApps: any;
  let getFirestore: any;

  if (typeof Deno !== "undefined") {
    const appMod = await import("npm:firebase-admin@^12.0.0/app");
    const fsMod = await import("npm:firebase-admin@^12.0.0/firestore");
    initializeApp = appMod.initializeApp;
    cert = appMod.cert;
    getApps = appMod.getApps;
    getFirestore = fsMod.getFirestore;
  } else {
    const appMod = await import("firebase-admin/app");
    const fsMod = await import("firebase-admin/firestore");
    initializeApp = appMod.initializeApp;
    cert = appMod.cert;
    getApps = appMod.getApps;
    getFirestore = fsMod.getFirestore;
  }

  if (getApps().length === 0) {
    const rawServiceAccount = getEnv("FIREBASE_SERVICE_ACCOUNT_KEY");
    if (rawServiceAccount) {
      const serviceAccount = parseFirebaseServiceAccountKey(rawServiceAccount);
      initializeApp({ credential: cert(serviceAccount) });
    } else {
      const projectId = getEnv("FIREBASE_PROJECT_ID") || getEnv("GCLOUD_PROJECT");
      const clientEmail = getEnv("FIREBASE_CLIENT_EMAIL");
      let privateKey = getEnv("FIREBASE_PRIVATE_KEY");

      if (projectId && clientEmail && privateKey) {
        if (privateKey.includes("\\n")) {
          privateKey = privateKey.replace(/\\n/g, "\n");
        }
        initializeApp({
          credential: cert({
            projectId,
            clientEmail,
            privateKey,
          }),
        });
      } else {
        // Fall back to default application credentials
        initializeApp();
      }
    }
  }

  const db = getFirestore();
  await db.collection("appointments").doc(appointmentId).set(data, { merge: true });
}

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

  // 1. AUTHENTICATION & WEBHOOK VALIDATION:
  const expectedSecret = options?.expectedSecret ?? getEnvironmentSecret();
  if (!expectedSecret) {
    console.error("[sync-to-firestore] Webhook secret not configured in environment");
    return new Response(
      JSON.stringify({
        error: "unauthorized",
        message: "Webhook authentication secret is not configured in environment (expected SYNC_TO_FIRESTORE_SECRET, SYNC_WEBHOOK_SECRET, or SUPABASE_SERVICE_ROLE_KEY)",
      }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
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
    const table = payload?.table;
    const record = payload?.record;

    if (table && table !== "appointments") {
      return new Response(
        JSON.stringify({ skipped: true, reason: `Ignored table: ${table}` }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. INFINITE LOOP PREVENTION:
    // If the change originated from Firestore, Reconciler, or Supabase Bridge itself, DROP IT!
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
          skipped: true,
          reason: "Loop prevented: Origin is Firestore, Reconciler, or Supabase Bridge",
          syncOrigin,
          syncedBy,
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

    const appointmentId = String(record.appointment_id || record.appointmentId || record.id || "").trim();
    if (!appointmentId) {
      return new Response(
        JSON.stringify({ error: "bad_request", message: "Missing appointment_id in record" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. BUILD FIRESTORE DOCUMENT PAYLOAD:
    const firestoreUpdate: Record<string, any> = {
      syncedBy: "supabase_bridge",
    };

    if (record.doctor_status !== undefined) {
      firestoreUpdate.doctorStatus = record.doctor_status;
    }
    if (record.patient_status !== undefined) {
      firestoreUpdate.patientStatus = record.patient_status;
    }
    if (record.cancellation_reason !== undefined) {
      firestoreUpdate.cancellationReason = record.cancellation_reason;
    }
    if (record.diagnosis !== undefined) {
      firestoreUpdate.diagnosis = record.diagnosis;
    }
    if (record.clinical_notes !== undefined) {
      firestoreUpdate.clinicalNotes = record.clinical_notes;
    }
    if (record.has_prescription !== undefined) {
      firestoreUpdate.hasPrescription = Boolean(record.has_prescription);
    }
    if (record.has_report !== undefined) {
      firestoreUpdate.hasReport = Boolean(record.has_report);
    }
    if (record.updated_at) {
      firestoreUpdate.updatedAt = new Date(record.updated_at);
    } else {
      firestoreUpdate.updatedAt = new Date();
    }

    // 4. WRITE TO FIRESTORE:
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
