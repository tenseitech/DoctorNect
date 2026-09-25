import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { crypto } from "https://deno.land/std@0.177.0/crypto/mod.ts";
import { corsHeaders } from "../_shared/cors.ts";

/** Pricing Table (Amount in INR) */
const AD_PRICING_TABLE: Record<number, number> = {
  6: 100,
  12: 180,
  24: 300,
  72: 750,
  168: 1500,
};

async function createHmacSha256Hex(secret: string, message: string): Promise<string> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const msgData = encoder.encode(message);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
  const hashArray = Array.from(new Uint8Array(signature));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

  const razorpayKeyId = (Deno.env.get("RAZORPAY_KEY_ID") || "").trim();
  const razorpayKeySecret = (Deno.env.get("RAZORPAY_KEY_SECRET") || "").trim();
  const razorpayWebhookSecret = (Deno.env.get("RAZORPAY_WEBHOOK_SECRET") || "").trim();

  const url = new URL(req.url);
  const isWebhook = url.pathname.endsWith("/webhook") || req.headers.get("x-razorpay-signature");

  try {
    // ------------------------------------------------------------------------
    // WEBHOOK HANDLER
    // ------------------------------------------------------------------------
    if (isWebhook) {
      const signature = req.headers.get("x-razorpay-signature");
      const rawBody = await req.text();

      if (!signature || !razorpayWebhookSecret) {
        return new Response(JSON.stringify({ error: "Missing signature or secret" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const expectedSignature = await createHmacSha256Hex(razorpayWebhookSecret, rawBody);
      if (expectedSignature.toLowerCase() !== signature.toLowerCase()) {
        return new Response(JSON.stringify({ error: "Invalid webhook signature" }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const event = JSON.parse(rawBody);
      if (event.event === "order.paid" || event.event === "payment.captured") {
        const orderId = event.payload?.payment?.entity?.order_id || event.payload?.order?.entity?.id;
        const paymentId = event.payload?.payment?.entity?.id;

        if (orderId) {
          const { data: ad } = await supabaseAdmin
            .from("promoted_ads")
            .select("ad_id, duration_hours, status")
            .eq("razorpay_order_id", orderId)
            .maybeSingle();

          if (ad && ad.status !== "active") {
            const duration = ad.duration_hours || 24;
            const now = new Date();
            const endsAt = new Date(now.getTime() + duration * 3600 * 1000);

            await supabaseAdmin
              .from("promoted_ads")
              .update({
                status: "active",
                payment_status: "verified",
                razorpay_payment_id: paymentId,
                start_time: now.toISOString(),
                end_time: endsAt.toISOString(),
                updated_at: now.toISOString(),
              })
              .eq("ad_id", ad.ad_id);
          }
        }
      }

      return new Response(JSON.stringify({ received: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ------------------------------------------------------------------------
    // API ACTIONS: create-order & verify-payment
    // ------------------------------------------------------------------------
    const { action, adId, durationHours, orderId, paymentId, signature } = await req.json();

    // 1. ACTION: create-order
    if (action === "create-order") {
      if (!razorpayKeyId || !razorpayKeySecret) {
        return new Response(JSON.stringify({ error: "Razorpay credentials not configured" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const hours = parseInt(durationHours, 10);
      const amountINR = AD_PRICING_TABLE[hours];
      if (!amountINR) {
        return new Response(JSON.stringify({ error: "Invalid duration hours" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
      const amountPaise = amountINR * 100;

      const rzResponse = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: {
          Authorization: `Basic ${basicAuth}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          amount: amountPaise,
          currency: "INR",
          receipt: String(adId || "").slice(0, 40),
          notes: {
            adId: String(adId || ""),
            durationHours: String(hours),
          },
        }),
      });

      if (!rzResponse.ok) {
        const errorText = await rzResponse.text();
        console.error("[razorpay-payments] Order creation failed:", errorText);
        return new Response(JSON.stringify({ error: "Failed to create Razorpay order" }), {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const rzOrder = await rzResponse.json();

      // Update promoted_ads record
      if (adId) {
        await supabaseAdmin
          .from("promoted_ads")
          .update({
            razorpay_order_id: rzOrder.id,
            amount_paid: amountINR,
            duration_hours: hours,
            status: "pending_payment",
            payment_status: "pending",
            updated_at: new Date().toISOString(),
          })
          .eq("ad_id", adId);
      }

      return new Response(
        JSON.stringify({
          order_id: rzOrder.id,
          key_id: razorpayKeyId,
          amount: amountINR,
          currency: "INR",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. ACTION: verify-payment
    if (action === "verify-payment") {
      if (!orderId || !paymentId || !signature || !adId) {
        return new Response(JSON.stringify({ error: "Missing verification parameters" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const payload = `${orderId}|${paymentId}`;
      const expectedSignature = await createHmacSha256Hex(razorpayKeySecret, payload);

      if (expectedSignature.toLowerCase() !== signature.toLowerCase()) {
        console.warn(`[razorpay-payments] Signature mismatch for ad ${adId}`);
        await supabaseAdmin
          .from("promoted_ads")
          .update({
            payment_status: "failed",
            status: "rejected",
            razorpay_payment_id: paymentId,
            updated_at: new Date().toISOString(),
          })
          .eq("ad_id", adId);

        return new Response(
          JSON.stringify({ error: "Razorpay payment signature verification failed" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: adData } = await supabaseAdmin
        .from("promoted_ads")
        .select("duration_hours")
        .eq("ad_id", adId)
        .maybeSingle();

      const durationHours = parseInt(adData?.duration_hours || 24, 10);
      const now = new Date();
      const endTime = new Date(now.getTime() + durationHours * 3600 * 1000);

      await supabaseAdmin
        .from("promoted_ads")
        .update({
          payment_status: "verified",
          status: "active",
          razorpay_order_id: orderId,
          razorpay_payment_id: paymentId,
          start_time: now.toISOString(),
          end_time: endTime.toISOString(),
          updated_at: now.toISOString(),
        })
        .eq("ad_id", adId);

      return new Response(
        JSON.stringify({
          success: true,
          message: "Payment verified and banner ad activated successfully!",
          ad_id: adId,
          start_time: now.toISOString(),
          end_time: endTime.toISOString(),
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    console.error("[razorpay-payments] Error:", err);
    return new Response(JSON.stringify({ error: err.message || "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
