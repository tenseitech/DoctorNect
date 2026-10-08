// Supabase Edge Function: sync-to-firestore
// DO NOT register a Database Webhook to this function.
// It does not write Firestore. A webhook here would acknowledge patient
// writes that doctors (who read Firestore) would never see.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const { table, record } = payload;

    // 1. LOOP PREVENTION:
    // If the change originated from the Firestore Doctor trigger or Reconciler, DROP IT!
    if (
      record?.sync_origin === "doctor_firestore" ||
      record?.sync_origin === "reconciler_bot" ||
      record?.synced_by === "firestore_cloud_function"
    ) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Loop prevented: Origin is Firestore/Reconciler" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        error: "not_implemented",
        message: "sync-to-firestore does not write Firestore. Do not register a webhook until it does.",
        table,
      }),
      { status: 501, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
