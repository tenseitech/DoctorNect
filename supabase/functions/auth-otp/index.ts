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

      if (error) throw error;

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

      const isDemo = DEMO_ACCOUNTS[role]?.includes(digits) ?? false;
      const rateLimitBucket = `otp_rate_${digits}`;

      // Rate limit check (max 5 requests per hour)
      if (!isDemo) {
        const { data: bucketData } = await supabaseAdmin
          .from("abuse_rate_limits")
          .select("count, window_start")
          .eq("bucket", rateLimitBucket)
          .maybeSingle();

        const now = new Date();
        if (bucketData) {
          const windowStart = new Date(bucketData.window_start);
          const diffMinutes = (now.getTime() - windowStart.getTime()) / 60000;
          if (diffMinutes < 60 && bucketData.count >= 5) {
            return new Response(
              JSON.stringify({ error: "Too many OTP requests. Please wait a few minutes." }),
              { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
          await supabaseAdmin
            .from("abuse_rate_limits")
            .update({
              count: diffMinutes < 60 ? bucketData.count + 1 : 1,
              window_start: diffMinutes < 60 ? bucketData.window_start : now.toISOString(),
              updated_at: now.toISOString(),
            })
            .eq("bucket", rateLimitBucket);
        } else {
          await supabaseAdmin.from("abuse_rate_limits").insert({
            bucket: rateLimitBucket,
            count: 1,
            category: "otp",
            window_start: now.toISOString(),
            updated_at: now.toISOString(),
          });
        }
      }

      // Generate OTP code
      const generatedCode = isDemo
        ? "000000"
        : Math.floor(100000 + Math.random() * 900000).toString();

      const challengeId = await sha256Hex(`${digits}_${role}_${Date.now()}_${Math.random()}`);
      const otpHash = await sha256Hex(generatedCode);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

      await supabaseAdmin.from("otp_challenges").insert({
        challenge_id: challengeId,
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

      const isDemo = DEMO_ACCOUNTS[role]?.includes(digits) && submittedOtp === "000000";

      if (!isDemo) {
        if (!challengeId) {
          return new Response(JSON.stringify({ error: "Missing challenge ID" }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

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

        if (new Date(challenge.expires_at).getTime() < Date.now()) {
          return new Response(JSON.stringify({ error: "OTP expired" }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        if (challenge.attempts >= 5) {
          return new Response(JSON.stringify({ error: "Maximum attempts exceeded" }), {
            status: 429,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        const submittedHash = await sha256Hex(submittedOtp);
        if (submittedHash !== challenge.otp_hash) {
          await supabaseAdmin
            .from("otp_challenges")
            .update({ attempts: challenge.attempts + 1 })
            .eq("challenge_id", challengeId);

          return new Response(JSON.stringify({ error: "Incorrect OTP code" }), {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        // Consume challenge
        await supabaseAdmin.from("otp_challenges").delete().eq("challenge_id", challengeId);
      }

      // Check or create Supabase Auth User
      const fallbackEmail = `${role}_${digits}@doctornect.com`;
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

      let targetUserId: string;
      let targetAuthEmail: string;

      if (existingUser) {
        targetUserId = existingUser.id;
        const { data: authUserData, error: authUserErr } = await supabaseAdmin.auth.admin.getUserById(targetUserId);
        if (authUserErr || !authUserData?.user?.email) {
          throw (authUserErr || new Error(`Auth user email could not be found for user ID ${targetUserId}`));
        }
        targetAuthEmail = authUserData.user.email;
      } else {
        // Register new user via Supabase Auth Admin (pass role in app_metadata for DB trigger)
        const { data: authCreated, error: createErr } = await supabaseAdmin.auth.admin.createUser({
          email: fallbackEmail,
          phone: `+91${digits}`,
          email_confirm: true,
          phone_confirm: true,
          app_metadata: { role },
          user_metadata: { role, mobile: digits },
        });

        const isAlreadyRegistered =
          createErr &&
          (createErr.status === 422 ||
            createErr.code === "email_exists" ||
            createErr.code === "phone_exists" ||
            createErr.message?.toLowerCase().includes("already registered"));

        if (createErr && !isAlreadyRegistered) {
          throw createErr;
        }

        if (authCreated?.user?.id) {
          targetUserId = authCreated.user.id;
          targetAuthEmail = authCreated.user.email || fallbackEmail;
        } else {
          // Resolve existing auth user ID and email via listUsers without calling generateLink
          const { data: listRes, error: listErr } = await supabaseAdmin.auth.admin.listUsers({
            page: 1,
            perPage: 50,
          });
          const matchedUser = listRes?.users?.find(
            (u) => u.email?.toLowerCase() === fallbackEmail.toLowerCase() || u.phone === `+91${digits}`
          );
          if (!matchedUser?.id || !matchedUser?.email) {
            throw (listErr || new Error(`Existing auth user could not be resolved for phone +91${digits}`));
          }
          targetUserId = matchedUser.id;
          targetAuthEmail = matchedUser.email;
        }

        // Self-heal check: if user was already registered or trigger was skipped/failed, ensure public.users row exists
        const { data: userProfile } = await supabaseAdmin
          .from("users")
          .select("id, role, profile_id, deactivated")
          .eq("id", targetUserId)
          .maybeSingle();

        if (userProfile?.deactivated) {
          return new Response(
            JSON.stringify({ error: "Your account has been deactivated. Please contact support." }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }

        if (!userProfile) {
          const validRole = ["patient", "doctor", "medicalStore", "lab", "ambulance"].includes(role) ? role : "patient";
          const prefix = {
            doctor: "d_",
            patient: "p_",
            medicalStore: "m_",
            lab: "l_",
            ambulance: "a_",
          }[validRole] || "p_";
          const randomSuffix = crypto.randomUUID().replace(/-/g, "");
          const profileId = `${prefix}${randomSuffix}`;
          const initialStatus = validRole === "patient" ? "approved" : "pending_review";

          const { error: insertErr } = await supabaseAdmin.from("users").upsert(
            {
              id: targetUserId,
              role: validRole,
              profile_id: profileId,
              display_name: "",
              email: targetAuthEmail,
              mobile: digits,
              profile_completed: false,
              verified: false,
              deactivated: false,
              status: initialStatus,
            },
            { onConflict: "id", ignoreDuplicates: true }
          );

          if (insertErr) {
            console.error("[auth-otp] Failed to self-heal public.users row:", insertErr);
          }
        }
      }

      // Generate native Supabase magiclink token hash using the real auth email
      const { data: linkData, error: linkErr } = await supabaseAdmin.auth.admin.generateLink({
        type: "magiclink",
        email: targetAuthEmail,
      });

      if (linkErr) throw linkErr;

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
