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

function constantTimeCompare(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  if (aBytes.length !== bBytes.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff === 0;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const supabaseServiceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (!supabaseUrl || !supabaseServiceKey) {
    return new Response(JSON.stringify({ error: "Supabase service credentials not configured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
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
        return new Response(JSON.stringify({ error: "Missing signature or webhook secret not configured" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const expectedSignature = await createHmacSha256Hex(razorpayWebhookSecret, rawBody);
      if (!constantTimeCompare(expectedSignature.toLowerCase(), signature.toLowerCase())) {
        return new Response(JSON.stringify({ error: "Invalid webhook signature" }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const event = JSON.parse(rawBody);
      if (event.event === "order.paid" || event.event === "payment.captured") {
        const orderId = event.payload?.payment?.entity?.order_id || event.payload?.order?.entity?.id;
        const paymentId = event.payload?.payment?.entity?.id;

        if (orderId && paymentId) {
          const { data: ad } = await supabaseAdmin
            .from("promoted_ads")
            .select("ad_id, duration_hours, status, razorpay_order_id, razorpay_payment_id")
            .eq("razorpay_order_id", orderId)
            .maybeSingle();

          if (!ad) {
            console.warn(`[razorpay-payments webhook] No ad found for order ${orderId}`);
            return new Response(JSON.stringify({ received: true }), {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          // Idempotency: already active with same payment id
          if (ad.status === "active" && ad.razorpay_payment_id === paymentId) {
            return new Response(JSON.stringify({ received: true, idempotent: true }), {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          // Activate only from pending_payment, never reactivate expired/rejected/active
          if (ad.status !== "pending_payment") {
            console.warn(`[razorpay-payments webhook] Ad ${ad.ad_id} has status '${ad.status}', skipping activation`);
            return new Response(JSON.stringify({ received: true, ignored: true, reason: `Ad status is ${ad.status}` }), {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          // Fail closed: require Razorpay API credentials
          if (!razorpayKeyId || !razorpayKeySecret) {
            console.error("[razorpay-payments webhook] Razorpay API credentials not configured");
            return new Response(JSON.stringify({ error: "Razorpay credentials not configured" }), {
              status: 503,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
          const [pRes, oRes] = await Promise.all([
            fetch(`https://api.razorpay.com/v1/payments/${paymentId}`, {
              headers: { Authorization: `Basic ${basicAuth}` },
            }),
            fetch(`https://api.razorpay.com/v1/orders/${orderId}`, {
              headers: { Authorization: `Basic ${basicAuth}` },
            }),
          ]);

          if (!pRes.ok || !oRes.ok) {
            console.error("[razorpay-payments webhook] Razorpay API response not ok");
            return new Response(JSON.stringify({ error: "Failed to verify with Razorpay API" }), {
              status: 503,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          const rzPayment = await pRes.json();
          const rzOrder = await oRes.json();

          if (rzPayment.status !== "captured" || rzPayment.order_id !== orderId) {
            console.error("[razorpay-payments webhook] Payment not captured or order mismatch");
            return new Response(JSON.stringify({ error: "Payment verification failed" }), {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          if (rzOrder.notes?.adId !== ad.ad_id) {
            console.error("[razorpay-payments webhook] Order notes adId mismatch");
            return new Response(JSON.stringify({ error: "Order notes adId mismatch" }), {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          const durFromNotes = parseInt(rzOrder.notes?.durationHours, 10);
          const priceFromNotes = AD_PRICING_TABLE[durFromNotes];
          if (!priceFromNotes || rzPayment.amount !== priceFromNotes * 100) {
            console.error("[razorpay-payments webhook] Price or duration mismatch");
            return new Response(JSON.stringify({ error: "Price or duration mismatch" }), {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }

          const durationHours = durFromNotes;
          const amountPaid = priceFromNotes;

          const now = new Date();
          const endsAt = new Date(now.getTime() + durationHours * 3600 * 1000);

          await supabaseAdmin
            .from("promoted_ads")
            .update({
              status: "active",
              payment_status: "verified",
              razorpay_payment_id: paymentId,
              amount_paid: amountPaid,
              duration_hours: durationHours,
              start_time: now.toISOString(),
              end_time: endsAt.toISOString(),
              updated_at: now.toISOString(),
            })
            .eq("ad_id", ad.ad_id)
            .eq("status", "pending_payment");
        }
      }

      return new Response(JSON.stringify({ received: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ------------------------------------------------------------------------
    // API ACTIONS: create-order & verify-payment
    // ------------------------------------------------------------------------
    // Explicit non-empty check for razorpayKeySecret and razorpayKeyId
    if (!razorpayKeySecret || !razorpayKeyId) {
      return new Response(JSON.stringify({ error: "Razorpay credentials not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Require Authorization Bearer header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing or invalid authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) {
      return new Response(JSON.stringify({ error: "Empty bearer token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Resolve user via auth.getUser
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Map user.id to public.users.profile_id
    const { data: userProfile, error: profileError } = await supabaseAdmin
      .from("users")
      .select("profile_id")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError || !userProfile || !userProfile.profile_id) {
      return new Response(JSON.stringify({ error: "User profile not found" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const callerProfileId = userProfile.profile_id;

    const { action, adId, durationHours, orderId, paymentId, signature } = await req.json();

    if (!adId || typeof adId !== "string") {
      return new Response(JSON.stringify({ error: "Missing or invalid adId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Load the ad
    const { data: ad, error: adError } = await supabaseAdmin
      .from("promoted_ads")
      .select("*")
      .eq("ad_id", adId)
      .maybeSingle();

    if (adError || !ad) {
      return new Response(JSON.stringify({ error: "Ad not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Require ad.provider_id === profile_id
    if (ad.provider_id !== callerProfileId) {
      return new Response(JSON.stringify({ error: "Forbidden: caller does not own this ad" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. ACTION: create-order
    if (action === "create-order") {
      // Require status in ('draft', 'pending_payment')
      if (ad.status !== "draft" && ad.status !== "pending_payment") {
        return new Response(JSON.stringify({ error: `Cannot create order for ad with status: ${ad.status}` }), {
          status: 400,
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

      // Create Razorpay order with notes { adId, durationHours }
      const rzResponse = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: {
          Authorization: `Basic ${basicAuth}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          amount: amountPaise,
          currency: "INR",
          receipt: String(adId).slice(0, 40),
          notes: {
            adId: String(adId),
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

      // Conditional update checking rows affected
      const { data: updatedRows, error: updateError } = await supabaseAdmin
        .from("promoted_ads")
        .update({
          razorpay_order_id: rzOrder.id,
          amount_paid: amountINR,
          duration_hours: hours,
          status: "pending_payment",
          payment_status: "pending",
          updated_at: new Date().toISOString(),
        })
        .eq("ad_id", adId)
        .in("status", ["draft", "pending_payment"])
        .select();

      if (updateError || !updatedRows || updatedRows.length === 0) {
        return new Response(JSON.stringify({ error: "Failed to update ad order: status changed concurrently" }), {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
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
      if (!orderId || !paymentId || !signature) {
        return new Response(JSON.stringify({ error: "Missing verification parameters (orderId, paymentId, signature)" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Require ad.razorpay_order_id === orderId
      if (ad.razorpay_order_id !== orderId) {
        return new Response(JSON.stringify({ error: "Order ID does not match ad record" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Constant-time signature compare; on mismatch return 400 and write NOTHING
      const payload = `${orderId}|${paymentId}`;
      const expectedSignature = await createHmacSha256Hex(razorpayKeySecret, payload);

      if (!constantTimeCompare(expectedSignature.toLowerCase(), signature.toLowerCase())) {
        console.warn(`[razorpay-payments] Signature mismatch for ad ${adId}`);
        return new Response(
          JSON.stringify({ error: "Razorpay payment signature verification failed" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Idempotency: if already active with same payment id, return 200 success
      if (ad.status === "active" && ad.razorpay_payment_id === paymentId) {
        return new Response(
          JSON.stringify({
            success: true,
            message: "Payment already verified and banner ad is active (idempotent)",
            ad_id: adId,
            idempotent: true,
            start_time: ad.start_time,
            end_time: ad.end_time,
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Otherwise require pending_payment
      if (ad.status !== "pending_payment") {
        return new Response(JSON.stringify({ error: `Ad is not in pending_payment state (status: ${ad.status})` }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Fetch payment and order from Razorpay REST API
      const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
      const [paymentRes, orderRes] = await Promise.all([
        fetch(`https://api.razorpay.com/v1/payments/${paymentId}`, {
          headers: { Authorization: `Basic ${basicAuth}` },
        }),
        fetch(`https://api.razorpay.com/v1/orders/${orderId}`, {
          headers: { Authorization: `Basic ${basicAuth}` },
        }),
      ]);

      if (!paymentRes.ok || !orderRes.ok) {
        console.error("[razorpay-payments] Failed to fetch payment or order from Razorpay");
        return new Response(JSON.stringify({ error: "Failed to verify payment with Razorpay API" }), {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const rzPayment = await paymentRes.json();
      const rzOrder = await orderRes.json();

      // Require payment.status === 'captured'
      if (rzPayment.status !== "captured") {
        return new Response(JSON.stringify({ error: `Payment not captured (status: ${rzPayment.status})` }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Require payment.order_id === orderId
      if (rzPayment.order_id !== orderId) {
        return new Response(JSON.stringify({ error: "Payment order_id does not match orderId" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Require order.notes.adId === adId
      if (rzOrder.notes?.adId !== adId) {
        return new Response(JSON.stringify({ error: "Order notes adId mismatch" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Duration and price validation
      const noteDurationHours = parseInt(rzOrder.notes?.durationHours, 10);
      const expectedPrice = AD_PRICING_TABLE[noteDurationHours];
      if (!expectedPrice) {
        return new Response(JSON.stringify({ error: "Invalid durationHours in order notes" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Require payment.amount === AD_PRICING_TABLE[notes.durationHours] * 100
      const expectedPaise = expectedPrice * 100;
      if (rzPayment.amount !== expectedPaise) {
        return new Response(
          JSON.stringify({
            error: `Payment amount mismatch: expected ${expectedPaise} paise, got ${rzPayment.amount} paise`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Compute end_time from order notes duration, not the row
      const now = new Date();
      const endTime = new Date(now.getTime() + noteDurationHours * 3600 * 1000);

      // Conditional update on status = 'pending_payment'
      const { data: updatedRows, error: updateError } = await supabaseAdmin
        .from("promoted_ads")
        .update({
          payment_status: "verified",
          status: "active",
          razorpay_order_id: orderId,
          razorpay_payment_id: paymentId,
          amount_paid: expectedPrice,
          duration_hours: noteDurationHours,
          start_time: now.toISOString(),
          end_time: endTime.toISOString(),
          updated_at: now.toISOString(),
        })
        .eq("ad_id", adId)
        .eq("status", "pending_payment")
        .select();

      if (updateError || !updatedRows || updatedRows.length === 0) {
        return new Response(JSON.stringify({ error: "Failed to activate ad: status is not pending_payment" }), {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

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
