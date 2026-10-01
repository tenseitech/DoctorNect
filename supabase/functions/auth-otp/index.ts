import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { crypto } from "https://deno.land/std@0.177.0/crypto/mod.ts";
import { corsHeaders } from "../_shared/cors.ts";

// Play Store review demo accounts config
const DEMO_ACCOUNTS: Record<string, string[]> = {
  patient: ["7058809803"],
  doctor: ["7666892394"],
  medicalStore: ["9359503874"],
  lab: ["9409858233"],
  ambulance: ["9307583929"],
};

function normalizeMobile(raw: string): string {
  const digits = String(raw || "").replace(/\D/g, "");
  return digits.length > 10 ? digits.slice(-10) : digits;
}

// Generate unbiased 6-digit OTP code using crypto.getRandomValues and rejection sampling
function generateSecureOtp(): string {
  const buf = new Uint32Array(1);
  const limit = 4294000000; // largest multiple of 1,000,000 <= 2^32
  let val: number;
  do {
    crypto.getRandomValues(buf);
    val = buf[0];
  } while (val >= limit);
  return (val % 1000000).toString().padStart(6, "0");
}

async function sha256Hex(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function resolveMsg91TemplateId(otpType: string): string {
  let envKey = "MSG91_TEMPLATE_ID_REGISTRATION";
  if (otpType === "login") envKey = "MSG91_TEMPLATE_ID_LOGIN";
  if (otpType === "password_reset" || otpType === "forgot_password") {
    envKey = "MSG91_TEMPLATE_ID_PASSWORD_RESET";
  }
  return Deno.env.get(envKey) || Deno.env.get("MSG91_TEMPLATE_ID") || "6a82fb0c248c482651029d14";
}

function resolveMsg91SenderId(): string {
  return Deno.env.get("MSG91_SENDER_ID") || "DRNECT";
}

async function dispatchMsg91Otp(mobileDigits: string, code: string, templateId: string): Promise<boolean> {
  const proxyUrl = Deno.env.get("MSG91_PROXY_URL");
  const proxySecret = Deno.env.get("PROXY_SECRET");
  const senderId = resolveMsg91SenderId();

  // Route through GCP static IP proxy (Option B) if configured
  if (proxyUrl && proxySecret) {
    try {
      const res = await fetch(proxyUrl, {
        method: "POST",
        headers: {
          "x-proxy-key": proxySecret,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          mobile: `91${mobileDigits}`,
          otp: code,
          template_id: templateId,
          sender: senderId,
        }),
      });

      const resBody = await res.text();
      if (!res.ok) {
        console.error("[auth-otp] MSG91 proxy dispatch failed HTTP", res.status, resBody);
        return false;
      }
      console.info("[auth-otp] MSG91 proxy dispatch successful for 91" + mobileDigits);
      return true;
    } catch (err: any) {
      console.error("[auth-otp] Network error contacting MSG91 proxy:", err.message);
      return false;
    }
  }

  // Fallback direct call if no proxy configured
  const authKey = Deno.env.get("MSG91_AUTH_KEY") || Deno.env.get("MSG91_AUTHKEY") || "";
  if (!authKey) {
    console.error("[auth-otp] Neither MSG91_PROXY_URL nor MSG91_AUTH_KEY is configured!");
    return false;
  }

  const url = new URL("https://control.msg91.com/api/v5/otp");
  url.searchParams.set("template_id", templateId);
  url.searchParams.set("mobile", `91${mobileDigits}`);
  url.searchParams.set("otp", code);
  url.searchParams.set("sender", senderId);

  try {
    const res = await fetch(url.toString(), {
      method: "POST",
      headers: {
        authkey: authKey,
        "content-type": "application/json",
        accept: "application/json",
      },
    });

    const resBody = await res.text();
    if (!res.ok) {
      console.error("[auth-otp] Direct MSG91 dispatch failed HTTP", res.status, resBody);
      return false;
    }
    console.info("[auth-otp] Direct MSG91 dispatch successful for 91" + mobileDigits);
    return true;
  } catch (err: any) {
    console.error("[auth-otp] Network error contacting MSG91:", err.message);
    return false;
  }
}


serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const rawIp = req.headers.get("cf-connecting-ip") ||
    req.headers.get("x-real-ip") ||
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    null;
  const clientIp = rawIp && rawIp.length > 0 ? rawIp : null;
  const enableDemoAccounts = Deno.env.get("ENABLE_DEMO_ACCOUNTS") === "true";

  try {
    const { action, mobile, role, otp, intent, sessionId } = await req.json();
    const digits = normalizeMobile(mobile);

    // ------------------------------------------------------------------------
    // 1. ACTION: resolve-path (Login vs Register vs Wrong Role Conflict)
    // ------------------------------------------------------------------------
    if (action === "resolve-path") {
      if (!digits || digits.length !== 10) {
        return new Response(JSON.stringify({ error: "Invalid mobile number" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: userRows, error } = await supabaseAdmin
        .from("users")
        .select("role, deactivated")
        .eq("mobile", digits)
        .order("deactivated", { ascending: true })
        .limit(1);

      if (error) throw new Error(error.message || "Failed to query user by mobile");

      const user = userRows && userRows.length > 0 ? userRows[0] : null;

      if (!user) {
        return new Response(JSON.stringify({ path: "register" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      if (user.deactivated) {
        return new Response(
          JSON.stringify({
            error: "Your account has been deactivated. Please contact support.",
          }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (user.role !== role) {
        return new Response(
          JSON.stringify({
            path: "blocked_wrong_role",
            message:
              "This mobile number is registered under a different account type. Please select the correct role or contact support.",
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(JSON.stringify({ path: "login" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ------------------------------------------------------------------------
    // 2. ACTION: send-otp
    // ------------------------------------------------------------------------
    if (action === "send-otp") {
      if (!digits || digits.length !== 10) {
        return new Response(JSON.stringify({ error: "Invalid mobile number" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const isDemo = enableDemoAccounts && (DEMO_ACCOUNTS[role]?.includes(digits) ?? false);

      // Rate limit check via atomic SQL function (max 5 per mobile / 20 per IP per hour)
      if (!isDemo) {
        const mobileBucket = `otp_rate_mobile_${digits}`;

        // Check mobile rate limit (max 5 requests per 3600 seconds)
        const { data: mobileAllowed, error: rateErr1 } = await supabaseAdmin.rpc(
          "check_and_increment_rate_limit",
          {
            p_bucket: mobileBucket,
            p_max_count: 5,
            p_window_seconds: 3600,
            p_category: "otp_mobile",
          }
        );

        if (rateErr1 || mobileAllowed === false) {
          return new Response(
            JSON.stringify({ error: "Too many OTP requests for this mobile. Please wait a few minutes." }),
            { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        // Check IP rate limit if client IP header is present (max 20 requests per 3600 seconds)
        // If no trusted client IP header is present, skip the IP bucket (never share an "unknown_ip" bucket)
        if (clientIp) {
          const ipBucket = `otp_rate_ip_${clientIp}`;
          const { data: ipAllowed, error: rateErr2 } = await supabaseAdmin.rpc(
            "check_and_increment_rate_limit",
            {
              p_bucket: ipBucket,
              p_max_count: 20,
              p_window_seconds: 3600,
              p_category: "otp_ip",
            }
          );

          if (rateErr2 || ipAllowed === false) {
            return new Response(
              JSON.stringify({ error: "Too many OTP requests from this IP. Please wait a few minutes." }),
              { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
        }
      }

      // Generate unbiased 6-digit OTP code and UUID challengeId
      const generatedCode = isDemo ? "000000" : generateSecureOtp();
      const challengeId = crypto.randomUUID();
      const otpHash = await sha256Hex(`${challengeId}:${digits}:${generatedCode}`);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

      await supabaseAdmin.from("otp_challenges").insert({
        challenge_id: challengeId,
        mobile: digits,
        role: role,
        otp_hash: otpHash,
        attempts: 0,
        is_demo: isDemo,
        expires_at: expiresAt,
      });

      // Dispatch SMS via MSG91
      if (!isDemo) {
        const templateId = resolveMsg91TemplateId(intent || "login");
        const dispatched = await dispatchMsg91Otp(digits, generatedCode, templateId);
        if (!dispatched) {
          return new Response(
            JSON.stringify({ error: "Failed to dispatch SMS OTP. Please try again." }),
            { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      return new Response(
        JSON.stringify({
          success: true,
          challenge_id: challengeId,
          is_demo: isDemo,
          expires_at: expiresAt,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // 3. ACTION: verify-otp
    // ------------------------------------------------------------------------
    if (action === "verify-otp") {
      const challengeId = sessionId || req.headers.get("x-challenge-id");
      const submittedOtp = String(otp || "").trim();

      if (!digits || !submittedOtp) {
        return new Response(JSON.stringify({ error: "Missing mobile or OTP" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const isDemo = enableDemoAccounts && (DEMO_ACCOUNTS[role]?.includes(digits) ?? false) && submittedOtp === "000000";

      if (!isDemo) {
        if (!challengeId) {
          return new Response(JSON.stringify({ error: "Missing challenge ID" }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        // 1. Consume attempt atomically BEFORE comparing hash
        const { data: attemptRows, error: attemptErr } = await supabaseAdmin.rpc("consume_otp_attempt", {
          p_challenge_id: challengeId,
        });

        const attemptCount = Array.isArray(attemptRows) && attemptRows.length > 0 ? attemptRows[0]?.attempts : null;
        if (attemptErr || attemptCount === null) {
          return new Response(JSON.stringify({ error: "Maximum attempts exceeded or invalid session" }), {
            status: 429,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        // 2. Fetch challenge row
        const { data: challenge, error: chalErr } = await supabaseAdmin
          .from("otp_challenges")
          .select("*")
          .eq("challenge_id", challengeId)
          .maybeSingle();

        if (chalErr || !challenge) {
          return new Response(JSON.stringify({ error: "Invalid or expired OTP session" }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        // Tightly bind challenge to mobile and role; reject mismatch with generic session error
        if (challenge.mobile !== digits || challenge.role !== role) {
          return new Response(JSON.stringify({ error: "Invalid or expired OTP session" }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        if (new Date(challenge.expires_at).getTime() < Date.now()) {
          return new Response(JSON.stringify({ error: "OTP expired" }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        // 3. Compare hash
        const submittedHash = await sha256Hex(`${challengeId}:${digits}:${submittedOtp}`);
        if (submittedHash !== challenge.otp_hash) {
          return new Response(JSON.stringify({ error: "Incorrect OTP code" }), {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        // Consume challenge
        await supabaseAdmin.from("otp_challenges").delete().eq("challenge_id", challengeId);
      }

      // Check or create Supabase Auth User
      const { data: userRows, error: lookupErr } = await supabaseAdmin
        .from("users")
        .select("id, role, profile_id, display_name, deactivated")
        .eq("mobile", digits)
        .order("deactivated", { ascending: true })
        .limit(1);

      if (lookupErr) {
        console.error("[auth-otp] Database error querying user by mobile:", lookupErr);
        return new Response(JSON.stringify({ error: "Failed to verify account status" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const existingUser = userRows && userRows.length > 0 ? userRows[0] : null;

      if (existingUser?.deactivated) {
        return new Response(
          JSON.stringify({ error: "Your account has been deactivated. Please contact support." }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (existingUser && existingUser.role !== role) {
        return new Response(
          JSON.stringify({
            error:
              "This mobile number is registered under a different account type. Please select the correct role or contact support.",
          }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      let targetUserId: string;
      let targetAuthEmail: string;

      if (existingUser) {
        targetUserId = existingUser.id;
        const { data: authUserData, error: authUserErr } = await supabaseAdmin.auth.admin.getUserById(targetUserId);
        if (authUserErr || !authUserData?.user?.email) {
          throw new Error(authUserErr?.message || `Auth user email could not be found for user ID ${targetUserId}`);
        }
        targetAuthEmail = authUserData.user.email;
      } else {
        // --- Step 1: match auth user by phone only (right 10 digits) ---
        const { data: existingAuthUsers, error: preLookupErr } = await supabaseAdmin.rpc("find_auth_user", {
          p_phone: `+91${digits}`,
        });
        const preMatch = Array.isArray(existingAuthUsers) && existingAuthUsers.length > 0
          ? existingAuthUsers[0]
          : null;

        if (preLookupErr) {
          console.warn("[auth-otp] pre-check find_auth_user failed, attempting createUser:", preLookupErr);
        }

        const preDigits = normalizeMobile(preMatch?.phone || "");

        if (preMatch?.id && preMatch?.email && preDigits === digits) {
          // Auth user already exists matching this exact phone — use directly
          targetUserId = preMatch.id;
          targetAuthEmail = preMatch.email;
        } else {
          // --- Step 2: no existing auth user matching phone — try to create one ---
          const syntheticEmail = `${crypto.randomUUID()}@users.doctornect.invalid`;
          const { data: authCreated, error: createErr } = await supabaseAdmin.auth.admin.createUser({
            email: syntheticEmail,
            phone: `+91${digits}`,
            email_confirm: true,
            phone_confirm: true,
            app_metadata: { role, mobile: digits },
            user_metadata: { role, mobile: digits },
          });

          if (authCreated?.user?.id) {
            targetUserId = authCreated.user.id;
            targetAuthEmail = authCreated.user.email || syntheticEmail;
          } else {
            // If createUser fails (e.g. email exists with different phone), retry find_auth_user by phone only
            console.warn("[auth-otp] createUser failed, retrying find_auth_user by phone. Error:",
              createErr?.message || createErr);
            const { data: retryUsers, error: retryErr } = await supabaseAdmin.rpc("find_auth_user", {
              p_phone: `+91${digits}`,
            });
            const retryMatch = Array.isArray(retryUsers) && retryUsers.length > 0 ? retryUsers[0] : null;
            const retryDigits = normalizeMobile(retryMatch?.phone || "");

            if (!retryErr && retryMatch?.id && retryMatch?.email && retryDigits === digits) {
              targetUserId = retryMatch.id;
              targetAuthEmail = retryMatch.email;
            } else {
              // If email exists with a different phone or no phone match: throw immediately (no fallback to that user)
              console.error("[auth-otp] retry find_auth_user by phone failed:", retryErr);
              const errMsg = createErr?.message || "User creation failed: email collision with different phone number";
              throw new Error(errMsg);
            }
          }
        }

        // Require a public.users row with id=targetUserId and role===role; otherwise fail closed
        const { data: userProfile, error: profileErr } = await supabaseAdmin
          .from("users")
          .select("id, role, profile_id, deactivated")
          .eq("id", targetUserId)
          .maybeSingle();

        if (profileErr || !userProfile || userProfile.role !== role) {
          console.error("[auth-otp] Fail-closed: missing public.users row or role mismatch:", {
            targetUserId,
            expectedRole: role,
            foundRole: userProfile?.role,
            error: profileErr,
          });
          return new Response(
            JSON.stringify({ error: "User profile provisioning failed or role mismatch" }),
            {
              status: 500,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }

        if (userProfile.deactivated) {
          return new Response(
            JSON.stringify({ error: "Your account has been deactivated. Please contact support." }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }
      }

      // Generate native Supabase magiclink token hash using the real auth email
      const { data: linkData, error: linkErr } = await supabaseAdmin.auth.admin.generateLink({
        type: "magiclink",
        email: targetAuthEmail,
      });

      if (linkErr || !linkData?.properties?.hashed_token) {
        throw new Error(linkErr?.message || "Failed to generate authentication link token");
      }

      return new Response(
        JSON.stringify({
          success: true,
          token_hash: linkData.properties.hashed_token,
          user_id: targetUserId,
          is_new_user: !existingUser,
          role,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    console.error("[auth-otp] Error:", err);
    return new Response(JSON.stringify({ error: err.message || "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
