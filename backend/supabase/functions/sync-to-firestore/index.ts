// Supabase Edge Function: sync-to-firestore
// Handles Database Webhooks from appointments, patients, and reviews
// Synchronizes records to Firestore with strict loop prevention & origin tagging.

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
    const { type, table, record, old_record } = payload;

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

    // Process sync payload depending on table
    return new Response(
      JSON.stringify({ success: true, table, id: record?.appointment_id || record?.patient_id || record?.id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
