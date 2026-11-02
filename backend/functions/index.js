const { resolveCallerIdentity } = require('./caller_identity');
// Deploy: disable OTP App Check until reCAPTCHA is configured.
require('./firestore_forbidden_guard');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
initializeApp();

const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { sendFcmIfTokenExists, resolveAmbulanceDriverToken } = require('./fcm_push');
const crypto = require('crypto');
const {
  supabaseDatabaseWebhookHandler,
  supabaseWebhookSecret,
} = require('./supabase_database_webhook');

/**
 * Constant-time string comparison preventing timing attacks on webhook secrets.
 */
function safeCompareSecrets(provided, expected) {
  if (typeof provided !== 'string' || typeof expected !== 'string') return false;
  const cleanP = provided.trim();
  const cleanE = expected.trim();
  if (cleanP.length === 0 || cleanE.length === 0) return false;
  const pHash = crypto.createHash('sha256').update(cleanP).digest();
  const eHash = crypto.createHash('sha256').update(cleanE).digest();
  return crypto.timingSafeEqual(pHash, eHash);
}

const {
  isDoctorPatientSupabasePrimary,
  _resetRemoteConfigCache,
  _setMockRemoteConfigTemplate,
} = require('./sync_flags');

const {
  RULES,
  VITAL_THRESHOLDS,
  runRule,
  runVitalAdvisory,
  validateFields,
} = require('./validation_rules');
const {
  sendUserRegistrationOtp,
  verifyUserRegistrationOtp,
  finalizePatientOtpVerification,
  approveUserAccount,
  approvePatientAccount,
  resetAmbulanceDriverPin,
  completeAmbulanceMobileOtpLogin,
  resetUserPasswordWithOtp,
  completeMobileOtpLogin,
  assertLoginAllowed,
  recordFailedLogin,
  clearFailedLogins,
  hashAmbulancePin,
  ambulancePinMatches,
  lookupMobileRegistration,
  cleanupPendingRegistration,
} = require('./registration_otp');
const {
  createRazorpayOrder,
  verifyRazorpayPayment,
  expirePromotedAds,
  razorpayWebhook,
  reviewPromotedAd,
} = require('./promoted_ads');
const {
  bookAppointment,
  rescheduleAppointment,
} = require('./appointment_slots');

const {
  sanitizeRuleParams,
  requireKnownRule,
  requireDocId,
  requireUsername,
  requirePin,
  requireAmbulancePassword,
  requireStars,
  sanitizeReview,
  sanitizePlainText,
  requireEmail,
  requireString,
  requireHexLikeToken,
  requireInviteToken,
} = require('./input_sanitize');
const {
  logAuthAttempt,
  logUnusualTraffic,
  withSecurityLogging,
} = require('./security_logger');
const { assertProductionSecrets } = require('./secure_config');
const { assertProductionOtpSafety } = require('./production_otp_guard');
const {
  enforceAbuseLimit,
  assertAppCheck,
  withAbuseProtection,
} = require('./abuse_rate_limit');
const {
  resolveAmbulanceHttpAllowedOrigins,
  handleAmbulanceHttpPreflight,
  isAmbulanceHttpOriginAllowed,
  applyAmbulanceHttpCorsHeaders,
  assertAmbulanceHttpAppCheck,
  isAmbulanceHttpAppCheckEnforced,
} = require('./http_endpoint_security');
const {
  GENERIC_AMBULANCE_LOGIN_FAILED,
  clientFacingHttpsMessage,
} = require('./public_error_messages');
const { deleteMyAccountHandler, supabaseServiceRoleKey } = require('./delete_my_account');
const {
  awsAccessKeyId,
  awsSecretAccessKey,
} = require('./s3_storage');

assertProductionSecrets();
assertProductionOtpSafety();

/** Firestore triggers must run in the Firestore database location (live: asia-south2); callables in asia-south1. */
const FIRESTORE_TRIGGER_REGION = String(process.env.FIRESTORE_TRIGGER_REGION || 'asia-south2').trim();
const CALLABLE_REGION = 'asia-south1';

/** Redis secrets are bound to OTP callables only when the OTP Redis mirror is enabled. */
const OTP_REDIS_MIRROR_ON = String(process.env.OTP_REDIS_MIRROR || '').trim().toLowerCase() === 'on';
const OTP_REDIS_SECRET_OPTIONS = OTP_REDIS_MIRROR_ON
  ? { secrets: require('./redis').REDIS_SECRETS }
  : {};

/** MSG91 callable options (asia-south1) — region + optional VPC connector for static IP egress. */
const MSG91_VPC_OPTIONS = {
  region: 'asia-south1',
  ...(process.env.VPC_CONNECTOR ? {
    vpcConnector: process.env.VPC_CONNECTOR,
    vpcConnectorEgressSettings: 'ALL_TRAFFIC',
  } : {}),
};

/** Set ENFORCE_OTP_APP_CHECK=false in functions/.env only while App Check is being configured. */
const ENFORCE_OTP_APP_CHECK = String(process.env.ENFORCE_OTP_APP_CHECK || 'true')
  .trim()
  .toLowerCase() !== 'false';

/** Broader App Check for abuse-sensitive callables (defaults to same as OTP). */
const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
)
  .trim()
  .toLowerCase() !== 'false';

/** App Check for the public ambulance login HTTP fallback (defaults OFF for staged rollout). */
const ENFORCE_AMBULANCE_HTTP_APP_CHECK = isAmbulanceHttpAppCheckEnforced();
const AMBULANCE_HTTP_ALLOWED_ORIGINS = resolveAmbulanceHttpAllowedOrigins();

function db() {
  return getFirestore();
}

/** Compose security logging + abuse limits for callables. */
function protectCallable(name, options, handler) {
  const opts = typeof options === 'function'
    ? { category: 'api', handler: options }
    : { ...options, handler };
  const {
    category = 'api',
    enforceAppCheck = ENFORCE_ABUSE_APP_CHECK,
    identifierFromRequest,
    message,
    handler: h,
  } = opts;

  return withSecurityLogging(
    name,
    withAbuseProtection(
      db,
      { category, enforceAppCheck, identifierFromRequest, message },
      h,
    ),
  );
}

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
}

function getCallableClientIp(request) {
  const raw = request.rawRequest;
  if (!raw) return 'unknown';

  const forwarded = raw.headers?.['x-forwarded-for'];
  if (forwarded) {
    return String(forwarded).split(',')[0].trim();
  }

  return raw.ip || raw.socket?.remoteAddress || 'unknown';
}

function isAmbulancePinHash(storedPin) {
  const stored = String(storedPin || '').trim();
  if (stored.startsWith('pbkdf2$')) return true;
  return stored.length === 64 && /^[a-f0-9]{64}$/i.test(stored);
}

function pinMatches(storedPin, enteredPin) {
  return ambulancePinMatches(storedPin, enteredPin);
}

async function readAmbulancePinHash(db, driverId) {
  const privateSnap = await db
    .collection('ambulances')
    .doc(driverId)
    .collection('private')
    .doc('settings')
    .get();
  if (privateSnap.exists) {
    return privateSnap.data()?.pin || '';
  }
  const legacySnap = await db.collection('ambulances').doc(driverId).get();
  return legacySnap.data()?.pin || '';
}

async function findAmbulanceByUsername(db, username) {
  const normalized = String(username || '').trim().toLowerCase();
  if (normalized.length < 3) return null;

  const snapshot = await db
    .collection('ambulances')
    .where('username', '==', normalized)
    .limit(1)
    .get();

  if (snapshot.empty) return null;

  const doc = snapshot.docs[0];
  return { id: doc.id, data: doc.data(), username: normalized };
}

async function verifyAmbulanceCredentials(db, username, pin) {
  const pinNorm = String(pin || '').trim();
  if (pinNorm.length < 6) {
    return { ok: false, invalidCredentials: true };
  }

  const { isDoctorPatientSupabasePrimary } = require('./sync_flags');
  const isCutover = (await isDoctorPatientSupabasePrimary()) || process.env.FIRESTORE_FORBIDDEN === '1';

  const useFirestoreDb = db && typeof db.collection === 'function';
  if (isCutover && !useFirestoreDb) {
    const { getSupabaseAdminClient } = require('./caller_identity');
    const sb = getSupabaseAdminClient();
    if (!sb) return { ok: false, invalidCredentials: true };

    const { data: amb } = await sb
      .from('ambulances')
      .select('*')
      .ilike('username', username.trim().toLowerCase())
      .maybeSingle();

    if (!amb) {
      return { ok: false, invalidCredentials: true };
    }

    const { data: priv } = await sb
      .from('ambulance_private_settings')
      .select('pin_hash')
      .eq('ambulance_id', amb.ambulance_id)
      .maybeSingle();

    const storedPin = priv?.pin_hash;
    if (!isAmbulancePinHash(storedPin)) {
      return { ok: false, invalidCredentials: true, pinUpgradeRequired: !!storedPin };
    }
    if (!pinMatches(storedPin, pinNorm)) {
      return { ok: false, invalidCredentials: true };
    }

    return {
      ok: true,
      driverId: amb.ambulance_id,
      data: amb,
      username: amb.username,
    };
  }

  const found = await findAmbulanceByUsername(db, username);
  if (!found) {
    return { ok: false, invalidCredentials: true };
  }

  const storedPin = await readAmbulancePinHash(db, found.id);
  if (!isAmbulancePinHash(storedPin)) {
    if (storedPin) {
      console.warn(`Ambulance ${found.id} has a non-hashed PIN on file; login denied until PIN reset.`);
    }
    return { ok: false, invalidCredentials: true, pinUpgradeRequired: !!storedPin };
  }
  if (!pinMatches(storedPin, pinNorm)) {
    return { ok: false, invalidCredentials: true };
  }

  // Upgrade legacy unsalted SHA-256 hashes to PBKDF2 after successful verify.
  if (/^[a-f0-9]{64}$/i.test(String(storedPin || '').trim())) {
    try {
      await db
        .collection('ambulances')
        .doc(found.id)
        .collection('private')
        .doc('settings')
        .set({
          pin: hashAmbulancePin(pinNorm),
          pinUpdatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
    } catch (e) {
      console.warn(`Ambulance ${found.id} PIN upgrade failed:`, e.message);
    }
  }

  return {
    ok: true,
    driverId: found.id,
    data: found.data,
    username: found.username,
  };
}

function ambulanceBookerMatches(profile, broadcast) {
  if (!profile || !broadcast) return false;

  const bookerPatientId = String(broadcast.patientId || '');
  const profileId = String(profile.profileId || '');
  const role = String(profile.role || '');

  return (
    (role === 'patient' && bookerPatientId === profileId)
    || (role === 'doctor' && bookerPatientId === profileId)
  );
}

function broadcastAlreadyRated(broadcast) {
  const rating = broadcast.rating;
  if (rating == null) return false;
  const numericRating = Number(rating);
  if (Number.isNaN(numericRating)) return false;
  if (numericRating === -1) {
    throw new HttpsError('failed-precondition', 'Rating was skipped for this trip.');
  }
  if (numericRating > 0) {
    throw new HttpsError('already-exists', 'Already rated.');
  }
  return false;
}

/**
 * When a patient/doctor books an ambulance, one ambulance_requests doc is
 * created per online driver. Send a high-priority FCM push to that driver.
 */

/** Returns declarative validation rules for the client engine (pre-login; rules are not secret). */
exports.getValidationRules = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, invoker: 'public' },
  protectCallable('getValidationRules', { category: 'api' }, async () => {
    return { rules: RULES, vitalThresholds: VITAL_THRESHOLDS, version: 1 };
  }),
);

/**
 * Same-origin web entry for validation rules (Firebase Hosting rewrite).
 * Avoids browser CORS preflight to cloudfunctions.net when Cloud Run is not public.
 */
exports.getValidationRulesHttp = onRequest(
  { region: CALLABLE_REGION },
  (req, res) => {
    if (req.method !== 'GET') {
      res.status(405).json({ error: { message: 'GET required.' } });
      return;
    }
    res.set('Cache-Control', 'public, max-age=300');
    res.json({ rules: RULES, vitalThresholds: VITAL_THRESHOLDS, version: 1 });
  },
);

/** Validates a single field server-side. */
exports.validateField = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('validateField', { category: 'api' }, async (request) => {
    requireAuth(request);
    const { rule, value, params } = request.data || {};
    const safeRule = requireKnownRule(rule, RULES);
    const safeParams = sanitizeRuleParams(params);
    const safeValue =
      value == null || typeof value === 'number' || typeof value === 'boolean'
        ? value
        : sanitizePlainText(String(value), { maxLength: 500 });
    const result = runRule(safeRule, safeValue, safeParams);
    return { error: result.error ?? null };
  }),
);

/** Validates multiple fields server-side. */
exports.validateFormFields = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('validateFormFields', { category: 'api' }, async (request) => {
    requireAuth(request);
    const { checks } = request.data || {};
    if (!Array.isArray(checks)) {
      throw new HttpsError('invalid-argument', 'checks must be an array');
    }
    if (checks.length > 40) {
      throw new HttpsError('invalid-argument', 'Too many validation checks.');
    }
    const sanitized = checks.map((c, i) => {
      if (!c || typeof c !== 'object') {
        throw new HttpsError('invalid-argument', `Invalid check at index ${i}.`);
      }
      return {
        rule: requireKnownRule(c.rule, RULES),
        value:
          c.value == null || typeof c.value === 'number' || typeof c.value === 'boolean'
            ? c.value
            : sanitizePlainText(String(c.value), { maxLength: 500 }),
        params: sanitizeRuleParams(c.params),
      };
    });
    return validateFields(sanitized);
  }),
);

async function enforceSendUserRegistrationOtpRateLimit(firestore, request) {
  const otpType = String(request.data?.otpType || 'registration').trim();
  const mobile = request.data?.mobile || request.data?.email || request.data?.identifier;
  const role = String(request.data?.role || 'patient').trim();
    const digits10 = String(mobile || '').replace(/\D/g, '').slice(-10);
    const identifier = digits10 || mobile;
    if (otpType === 'registration') {
      await enforceAbuseLimit(firestore, request, 'signup', {
        identifier,
        message: 'Too many account creation attempts. Please try again later.',
      });
    } else if (otpType === 'login' || otpType === 'forgot_password') {
      await enforceAbuseLimit(firestore, request, 'otp_send', {
        identifier,
        message: 'Too many OTP requests. Please try again in a few minutes.',
      });
    } else {
      await enforceAbuseLimit(firestore, request, 'api');
    }
}

/** Sends registration OTP (server-side storage; SMS optional). */
exports.sendUserRegistrationOtp = onCall(
  {
    ...MSG91_VPC_OPTIONS,
    ...OTP_REDIS_SECRET_OPTIONS,
    enforceAppCheck: ENFORCE_OTP_APP_CHECK,
    secrets: [...(OTP_REDIS_SECRET_OPTIONS.secrets || []), supabaseServiceRoleKey],
  },
  withSecurityLogging('sendUserRegistrationOtp', async (request) => {
  try {
    console.info('[sendUserRegistrationOtp] request', {
      hasAppCheck: Boolean(request.app),
      appId: request.app?.appId || null,
      otpType: request.data?.otpType || 'registration',
      mobileLast4: String(request.data?.mobile || '').replace(/\D/g, '').slice(-4),
      platform: request.rawRequest?.headers?.['x-client-platform'] || 'unknown',
    });
    if (ENFORCE_OTP_APP_CHECK && !request.app) {
      logUnusualTraffic(request, { pattern: 'app_check_missing', detail: 'sendUserRegistrationOtp' });
    }
    const firestore = getFirestore();
    await enforceSendUserRegistrationOtpRateLimit(firestore, request);
    return await sendUserRegistrationOtp(firestore, request.data || {}, {
      clientIp: getCallableClientIp(request),
    });
  } catch (err) {
    console.error('sendUserRegistrationOtp failed', err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', 'Could not send OTP. Please try again.');
  }
}),
);
exports.enforceSendUserRegistrationOtpRateLimit = enforceSendUserRegistrationOtpRateLimit;

/** Returns whether a mobile number conflicts with login/registration intent (no role disclosure). */
exports.lookupMobileRegistration = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  withSecurityLogging('lookupMobileRegistration', async (request) => {
    try {
      assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
      const firestore = getFirestore();
      await enforceAbuseLimit(firestore, request, 'api', {
        message: 'Too many requests. Please try again later.',
      });
      return await lookupMobileRegistration(firestore, request.data || {});
    } catch (err) {
      console.error('lookupMobileRegistration failed', err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not look up mobile number.');
    }
  }),
);

/** Verifies registration OTP. */
exports.verifyUserRegistrationOtp = onCall(
  {
    ...MSG91_VPC_OPTIONS,
    ...OTP_REDIS_SECRET_OPTIONS,
    enforceAppCheck: ENFORCE_OTP_APP_CHECK,
    secrets: [...(OTP_REDIS_SECRET_OPTIONS.secrets || []), supabaseServiceRoleKey],
  },
  withSecurityLogging('verifyUserRegistrationOtp', async (request) => {
    const mobileLast4 = String(request.data?.mobile || request.data?.identifier || '')
      .replace(/\D/g, '')
      .slice(-4);
    console.info('[verifyUserRegistrationOtp] Callable request received', {
      hasAppCheck: Boolean(request.app),
      appId: request.app?.appId || null,
      otpType: request.data?.otpType || 'registration',
      role: request.data?.role || 'patient',
      mobileLast4: mobileLast4 || 'unknown',
      otpLength: String(request.data?.otp || '').trim().length,
      platform: request.rawRequest?.headers?.['x-client-platform'] || 'unknown',
    });
    try {
      const firestore = getFirestore();
      await enforceAbuseLimit(firestore, request, 'api', {
        message: 'Too many OTP verification attempts. Please try again later.',
      });
      const result = await verifyUserRegistrationOtp(
        firestore,
        request.data || {},
        request.auth,
        { clientIp: getCallableClientIp(request) },
      );
      console.info('[verifyUserRegistrationOtp] Callable request succeeded', {
        mobileLast4: mobileLast4 || 'unknown',
        ok: result?.ok,
        hasSessionId: Boolean(result?.sessionId),
        hasCustomToken: Boolean(result?.customToken),
      });
      return result;
    } catch (err) {
      console.error('[verifyUserRegistrationOtp] Callable request failed', {
        mobileLast4: mobileLast4 || 'unknown',
        errorCode: err.code || 'unknown',
        errorMessage: err.message,
        details: err.details || null,
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not verify OTP. Please try again.');
    }
  }),
);
/** Applies a pre-registration OTP session to the signed-in patient account. */
exports.finalizePatientOtpVerification = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  protectCallable('finalizePatientOtpVerification', { category: 'api' }, async (request) => {
    requireAuth(request);
    const firestore = getFirestore();
    return finalizePatientOtpVerification(firestore, request.data || {}, request.auth);
  }),
);

/** Removes caller-owned fresh orphan registration rows + Auth user (service role). */
exports.cleanupPendingRegistration = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  withSecurityLogging('cleanupPendingRegistration', async (request) => {
    requireAuth(request);
    if (ENFORCE_OTP_APP_CHECK && !request.app) {
      throw new HttpsError('failed-precondition', 'App Check verification required.');
    }
    const firestore = getFirestore();
    await enforceAbuseLimit(firestore, request, 'api', {
      message: 'Too many registration cleanup attempts. Please try again later.',
    });
    return cleanupPendingRegistration(firestore, request.auth);
  }),
);

/** Resets ambulance driver PIN after OTP verification (Admin SDK write to private/settings). */
exports.resetAmbulanceDriverPin = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  protectCallable('resetAmbulanceDriverPin', { category: 'login' }, async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Anonymous sign-in required.');
      }
      const firestore = getFirestore();
      return await resetAmbulanceDriverPin(firestore, request.data || {}, request.auth, {
        clientIp: getCallableClientIp(request),
      });
    } catch (err) {
      console.error('resetAmbulanceDriverPin failed', err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not reset PIN. Please try again.');
    }
  }),
);

/** Resets user password after OTP verification using Admin SDK. */
exports.resetUserPasswordWithOtp = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  withSecurityLogging('resetUserPasswordWithOtp', async (request) => {
    try {
      const firestore = getFirestore();
      await enforceAbuseLimit(firestore, request, 'login', {
        identifier: request.data?.identifier || request.data?.mobile || request.data?.email,
        message: 'Too many password reset attempts. Please try again later.',
      });
      const result = await resetUserPasswordWithOtp(firestore, request.data || {}, {
        clientIp: getCallableClientIp(request),
      });
      logAuthAttempt(request, {
        outcome: 'success',
        method: 'password_reset',
        identifier: request.data?.identifier || request.data?.mobile || request.data?.email,
      });
      return result;
    } catch (err) {
      console.error('resetUserPasswordWithOtp failed', err);
      logAuthAttempt(request, {
        outcome: 'failure',
        method: 'password_reset',
        identifier: request.data?.identifier || request.data?.mobile || request.data?.email,
        reason: err?.code || 'error',
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not reset password. Please try again.');
    }
  }),
);

/** Exchanges a verified mobile OTP session for a Firebase custom auth token. */
exports.completeMobileOtpLogin = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  withSecurityLogging('completeMobileOtpLogin', async (request) => {
    try {
      const firestore = getFirestore();
      await enforceAbuseLimit(firestore, request, 'login', {
        identifier: request.data?.mobile || request.data?.identifier,
        message: 'Too many login attempts. Please try again later.',
      });
      const result = await completeMobileOtpLogin(firestore, request.data || {}, {
        clientIp: getCallableClientIp(request),
      });
      logAuthAttempt(request, {
        outcome: 'success',
        method: 'mobile_otp',
        identifier: request.data?.mobile || request.data?.identifier,
      });
      return result;
    } catch (err) {
      console.error('completeMobileOtpLogin failed', err);
      logAuthAttempt(request, {
        outcome: 'failure',
        method: 'mobile_otp',
        identifier: request.data?.mobile || request.data?.identifier,
        reason: err?.code || 'error',
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not complete OTP login. Please try again.');
    }
  }),
);

/** Pre-login rate-limit gate for email/password and admin sign-in. */
exports.assertLoginAllowed = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  withSecurityLogging('assertLoginAllowed', async (request) => {
  const firestore = getFirestore();
  await enforceAbuseLimit(firestore, request, 'login', {
    identifier: request.data?.identifier || request.data?.email,
    message: 'Too many login attempts. Please try again later.',
  });
  try {
    return await assertLoginAllowed(firestore, request.data || {}, {
      clientIp: getCallableClientIp(request),
    });
  } catch (err) {
    if (err?.code === 'resource-exhausted') {
      logAuthAttempt(request, {
        outcome: 'blocked',
        method: 'email_password',
        identifier: request.data?.identifier || request.data?.email,
        reason: 'rate_limited',
      });
    }
    throw err;
  }
}),
);

/** Records a failed email/password login for rate limiting. */
exports.recordFailedLogin = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  protectCallable('recordFailedLogin', { category: 'api' }, async (request) => {
  const firestore = getFirestore();
  logAuthAttempt(request, {
    outcome: 'failure',
    method: 'email_password',
    identifier: request.data?.identifier || request.data?.email,
    reason: 'invalid_credentials',
  });
  return recordFailedLogin(firestore, request.data || {}, {
    clientIp: getCallableClientIp(request),
  });
}),
);

/** Clears failed-login counters after a successful sign-in. */
exports.clearFailedLogins = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('clearFailedLogins', { category: 'api' }, async (request) => {
  const firestore = getFirestore();
  logAuthAttempt(request, {
    outcome: 'success',
    method: 'email_password',
    identifier: request.data?.identifier || request.data?.email,
  });
  return clearFailedLogins(firestore, request.data || {});
}),
);

/**
 * Returns a pending ambulance invite only when inviteId + token both match.
 * Replaces anonymous Firestore get-by-id (IDOR on timestamp invite IDs).
 */
exports.getAmbulanceInvite = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  withSecurityLogging('getAmbulanceInvite', async (request) => {
  assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
  await enforceAbuseLimit(getFirestore(), request, 'api');
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign-in required to open an invite.');
  }
  const inviteId = requireDocId(request.data?.inviteId, 'inviteId');
  const token = requireInviteToken(request.data?.token, 'token');

  const { isDoctorPatientSupabasePrimary } = require('./sync_flags');
  const isCutover = (await isDoctorPatientSupabasePrimary()) || process.env.FIRESTORE_FORBIDDEN === '1';

  if (isCutover) {
    const { getSupabaseAdminClient } = require('./caller_identity');
    const sb = getSupabaseAdminClient();
    if (!sb) throw new HttpsError('internal', 'Supabase admin client not configured.');

    const { data: inv, error } = await sb
      .from('ambulance_invites')
      .select('*')
      .eq('invite_id', inviteId)
      .maybeSingle();

    if (error || !inv) {
      throw new HttpsError('not-found', 'Invite not found.');
    }
    if (String(inv.token || '') !== token) {
      logUnusualTraffic(request, {
        pattern: 'forbidden_resource',
        detail: 'ambulance_invite_token_mismatch',
        identifier: inviteId,
      });
      throw new HttpsError('permission-denied', 'Invalid invite link.');
    }
    if (String(inv.status || '') !== 'pending') {
      throw new HttpsError('failed-precondition', 'This invite has already been used.');
    }
    return { ok: true, inviteId: inv.invite_id, invite: inv };
  }

  const firestore = getFirestore();
  const snap = await firestore.collection('ambulance_invites').doc(inviteId).get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Invite not found.');
  }
  const data = snap.data() || {};
  if (String(data.token || '') !== token) {
    logUnusualTraffic(request, {
      pattern: 'forbidden_resource',
      detail: 'ambulance_invite_token_mismatch',
      identifier: inviteId,
    });
    throw new HttpsError('permission-denied', 'Invalid invite link.');
  }
  if (String(data.status || '') !== 'pending') {
    throw new HttpsError('failed-precondition', 'This invite has already been used.');
  }
  const expiresAt = data.expiresAt?.toDate?.();
  if (expiresAt && Date.now() > expiresAt.getTime()) {
    throw new HttpsError('deadline-exceeded', 'This invite link has expired.');
  }

  return { ok: true, inviteId: snap.id, invite: data };
}),
);

/** Developer/admin approval: sets role profile verified = true for any account role. */
exports.approveUserAccount = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  protectCallable('approveUserAccount', { category: 'api' }, async (request) => {
    requireAuth(request);
    const firestore = getFirestore();
    return approveUserAccount(firestore, request.data || {}, request.auth);
  }),
);

/** Backward-compatible alias for patient approval. */
exports.approvePatientAccount = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  protectCallable('approvePatientAccount', { category: 'api' }, async (request) => {
    requireAuth(request);
    const firestore = getFirestore();
    return approvePatientAccount(firestore, request.data || {}, request.auth);
  }),
);

/** Returns vitals advisory for prescription fields (treated as AI/advisory generation). */
exports.validateVitalAdvisory = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('validateVitalAdvisory', {
    category: 'ai',
    message: 'Too many AI advisory requests. Please wait and try again.',
  }, async (request) => {
    requireAuth(request);
    const { rule, value } = request.data || {};
    if (!rule || typeof rule !== 'string') {
      throw new HttpsError('invalid-argument', 'rule is required');
    }
    return runVitalAdvisory(rule, value);
  }),
);

/**
 * Explicit AI generation quota gate for future / existing generative features.
 * Client should call before any LLM / generative request.
 */
exports.consumeAiGenerationQuota = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('consumeAiGenerationQuota', {
    category: 'ai',
    message: 'AI generation rate limit exceeded. Please try again later.',
  }, async (request) => {
    requireAuth(request);
    return {
      ok: true,
      limits: {
        perHourPerUser: 40,
        perHourPerIp: 60,
      },
    };
  }),
);

/**
 * Account creation gate — call before Firebase createUserWithEmailAndPassword.
 */
exports.assertAccountCreationAllowed = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('assertAccountCreationAllowed', {
    category: 'signup',
    identifierFromRequest: (request) =>
      request.data?.email || request.data?.mobile || request.data?.identifier,
    message: 'Too many account creation attempts from this device or identity.',
  }, async (request) => {
    const emailRaw = String(request.data?.email || '').trim();
    const mobileRaw = String(request.data?.mobile || '').trim();
    if (!emailRaw && !mobileRaw) {
      throw new HttpsError('invalid-argument', 'email or mobile is required.');
    }
    if (emailRaw) requireEmail(emailRaw, 'email');
    if (mobileRaw) {
      const digits = mobileRaw.replace(/\D/g, '');
      let normalized = digits;
      if (normalized.length === 12 && normalized.startsWith('91')) normalized = normalized.slice(2);
      else if (normalized.length === 11 && normalized.startsWith('0')) normalized = normalized.slice(1);
      if (normalized.length !== 10 || !/^[6-9]\d{9}$/.test(normalized)) {
        throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile.');
      }
    }
    return { ok: true };
  }),
);

/**
 * Shared username/password verification for ambulance driver login.
 */
async function runVerifyAmbulanceDriverLogin(firestore, payload, { clientIp, requestForLimits }) {
  const username = requireUsername(payload?.username);
  const pin = requireAmbulancePassword(payload?.pin, 'password');

  await enforceAbuseLimit(firestore, requestForLimits, 'login', {
    identifier: `ambulance:${username}`,
    message: 'Too many login attempts. Please try again later.',
  });

  try {
    await assertLoginAllowed(firestore, { identifier: `ambulance:${username}` }, { clientIp });
  } catch (err) {
    logAuthAttempt(requestForLimits, {
      outcome: 'blocked',
      method: 'ambulance',
      identifier: username,
      reason: 'rate_limited',
    });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('resource-exhausted', 'Too many login attempts. Please try again later.');
  }

  const verified = await verifyAmbulanceCredentials(firestore, username, pin);
  if (!verified.ok) {
    try {
      await recordFailedLogin(firestore, { identifier: `ambulance:${username}` }, { clientIp });
    } catch (err) {
      console.error('[verifyAmbulanceDriverLoginHttp] Failed to record login failure', {
        username,
        clientIp,
        error: err,
      });
    }
    logAuthAttempt(requestForLimits, {
      outcome: 'failure',
      method: 'ambulance',
      identifier: username,
      reason: 'invalid_credentials',
    });
    return { ok: false, pinUpgradeRequired: verified.pinUpgradeRequired === true };
  }

  try {
    await clearFailedLogins(firestore, { identifier: `ambulance:${username}` });
  } catch (err) {
    console.error('[verifyAmbulanceDriverLoginHttp] Failed to clear login attempts', {
      username,
      clientIp,
      error: err,
    });
  }
  logAuthAttempt(requestForLimits, {
    outcome: 'success',
    method: 'ambulance',
    identifier: username,
  });

  const data = verified.data || {};
  return {
    ok: true,
    driverId: verified.driverId,
    serviceName: data.serviceName || '',
    driverName: data.driverName || '',
    username: data.username || verified.username,
    city: data.city || '',
    isAvailable: data.isAvailable !== false,
  };
}

/**
 * Verifies ambulance driver username/PIN server-side so PIN hashes are never
 * exposed to clients. Auth is optional here (PIN is verified server-side); the
 * client links an anonymous Firebase session after success for Firestore access.
 */
exports.verifyAmbulanceDriverLogin = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, invoker: 'public', secrets: [supabaseServiceRoleKey] },
  withSecurityLogging('verifyAmbulanceDriverLogin', async (request) => {
  try {
  const firestore = getFirestore();
  const clientIp = getCallableClientIp(request);
  return await runVerifyAmbulanceDriverLogin(
    firestore,
    request.data || {},
    { clientIp, requestForLimits: request },
  );
  } catch (err) {
    console.error('verifyAmbulanceDriverLogin failed', err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError(
      'internal',
      'Could not verify ambulance login. Please try again.',
    );
  }
}),
);

/**
 * Web-friendly HTTP entry for ambulance username/PIN login.
 * CORS is restricted to hosted app origins. App Check is required only when
 * ENFORCE_AMBULANCE_HTTP_APP_CHECK=true. The flag defaults to false, and the
 * PIN check still runs in that default path.
 */
exports.verifyAmbulanceDriverLoginHttp = onRequest(
  { region: CALLABLE_REGION, cors: false, invoker: 'public', secrets: [supabaseServiceRoleKey] },
  async (req, res) => {
    const allowedOrigins = AMBULANCE_HTTP_ALLOWED_ORIGINS;
    if (handleAmbulanceHttpPreflight(req, res, allowedOrigins)) return;

    applyAmbulanceHttpCorsHeaders(req, res, allowedOrigins);

    if (!isAmbulanceHttpOriginAllowed(req.headers.origin, allowedOrigins)) {
      res.status(403).json({
        error: { status: 'PERMISSION_DENIED', message: 'Origin not allowed.' },
      });
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ error: { status: 'INVALID_ARGUMENT', message: 'POST required.' } });
      return;
    }

    const clientIp = String(req.headers['x-forwarded-for'] || req.ip || 'unknown')
      .split(',')[0]
      .trim();
    const requestForLimits = { auth: null, rawRequest: req, app: null };

    try {
      await assertAmbulanceHttpAppCheck(req, { enforce: ENFORCE_AMBULANCE_HTTP_APP_CHECK });
      const firestore = getFirestore();
      const payload = req.body?.data ?? req.body ?? {};
      const result = await runVerifyAmbulanceDriverLogin(
        firestore,
        payload,
        { clientIp, requestForLimits },
      );
      res.status(200).json({ result });
    } catch (err) {
      console.error('verifyAmbulanceDriverLoginHttp failed', err);
      if (err instanceof HttpsError) {
        const status = err.code === 'resource-exhausted' ? 429 : 400;
        res.status(status).json({
          error: {
            status: String(err.code || 'internal').toUpperCase(),
            message: clientFacingHttpsMessage(err, GENERIC_AMBULANCE_LOGIN_FAILED),
          },
        });
        return;
      }
      res.status(500).json({
        error: {
          status: 'INTERNAL',
          message: 'Could not verify ambulance login. Please try again.',
        },
      });
    }
  },
);

/** Ambulance driver login via verified mobile OTP session (anonymous auth required). */
exports.completeAmbulanceMobileOtpLogin = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, invoker: 'public' },
  withSecurityLogging('completeAmbulanceMobileOtpLogin', async (request) => {
    try {
      const firestore = getFirestore();
      return await completeAmbulanceMobileOtpLogin(
        firestore,
        request.data || {},
        request.auth,
        { clientIp: getCallableClientIp(request) },
      );
    } catch (err) {
      console.error('completeAmbulanceMobileOtpLogin failed', err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not complete mobile login.');
    }
  }),
);

/**
 * Server-side ambulance trip rating. Validates booker + completed trip, prevents
 * duplicate ratings, and atomically updates ambulance rating aggregates.
 */
exports.submitAmbulanceRating = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: [supabaseServiceRoleKey] },
  protectCallable('submitAmbulanceRating', { category: 'api' }, async (request) => {
  requireAuth(request);

  const broadcastId = requireDocId(request.data?.broadcastId, 'broadcastId');
  const ambulanceId = requireDocId(request.data?.ambulanceId, 'ambulanceId');
  const stars = requireStars(request.data?.stars);
  const review = sanitizeReview(request.data?.review || '');

  const db = getFirestore();
  const uid = request.auth.uid;

  const profile = await resolveCallerIdentity({ db, uid });

  const broadcastRef = db.collection('ambulance_broadcasts').doc(broadcastId);
  const ambRef = db.collection('ambulances').doc(ambulanceId);

  const broadcastSnap = await broadcastRef.get();
  if (!broadcastSnap.exists) {
    throw new HttpsError('not-found', 'Trip not found.');
  }

  const broadcast = broadcastSnap.data() || {};
  if (broadcast.status !== 'completed') {
    throw new HttpsError('failed-precondition', 'Trip not completed.');
  }
  if (String(broadcast.acceptedDriverId || '') !== ambulanceId) {
    throw new HttpsError('invalid-argument', 'Ambulance does not match this trip.');
  }
  if (!ambulanceBookerMatches(profile, broadcast)) {
    throw new HttpsError('permission-denied', 'Unauthorized.');
  }
  broadcastAlreadyRated(broadcast);

  const ratingFields = {
    rating: stars,
    ratedAt: FieldValue.serverTimestamp(),
  };
  if (review) {
    ratingFields.review = review;
  }

  await db.runTransaction(async (tx) => {
    const liveBroadcastSnap = await tx.get(broadcastRef);
    if (!liveBroadcastSnap.exists) {
      throw new HttpsError('not-found', 'Trip not found.');
    }

    const liveBroadcast = liveBroadcastSnap.data() || {};
    if (liveBroadcast.status !== 'completed') {
      throw new HttpsError('failed-precondition', 'Trip not completed.');
    }
    if (String(liveBroadcast.acceptedDriverId || '') !== ambulanceId) {
      throw new HttpsError('invalid-argument', 'Ambulance does not match this trip.');
    }
    if (!ambulanceBookerMatches(profile, liveBroadcast)) {
      throw new HttpsError('permission-denied', 'Unauthorized.');
    }
    broadcastAlreadyRated(liveBroadcast);

    const ambSnap = await tx.get(ambRef);
    if (!ambSnap.exists) {
      throw new HttpsError('not-found', 'Ambulance not found.');
    }

    const ambData = ambSnap.data() || {};
    const oldCount = Number(ambData.ratingCount) || 0;
    const oldTotal = Number(ambData.totalRating) || 0;

    tx.update(ambRef, {
      ratingCount: oldCount + 1,
      totalRating: oldTotal + stars,
    });
    tx.update(broadcastRef, ratingFields);
  });

  const requestsSnap = await db
    .collection('ambulance_requests')
    .where('broadcastId', '==', broadcastId)
    .get();

  if (!requestsSnap.empty) {
    const batch = db.batch();
    for (const doc of requestsSnap.docs) {
      batch.update(doc.ref, ratingFields);
    }
    await batch.commit();
  }

  return { ok: true };
}),
);

/**
 * Re-links a driver's authUid after reinstall/device change. Requires username+PIN
 * verification so stale authUid values can be reclaimed without opening hijack.
 */
exports.resyncAmbulanceAuthUid = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, invoker: 'public', secrets: [supabaseServiceRoleKey] },
  protectCallable('resyncAmbulanceAuthUid', {
    category: 'login',
    identifierFromRequest: (request) =>
      `ambulance:${String(request.data?.username || '').trim().toLowerCase()}`,
  }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Anonymous sign-in required.');
  }

  const username = requireUsername(request.data?.username);
  const pin = requireAmbulancePassword(request.data?.pin, 'password');

  const firestore = getFirestore();
  const verified = await verifyAmbulanceCredentials(firestore, username, pin);
  if (!verified.ok) {
    throw new HttpsError('permission-denied', 'Incorrect username or PIN.');
  }

  await firestore.collection('ambulances').doc(verified.driverId).set({
    authUid: request.auth.uid,
  }, { merge: true });

  const data = verified.data;
  return {
    ok: true,
    driverId: verified.driverId,
    serviceName: data.serviceName || '',
    driverName: data.driverName || '',
    username: data.username || verified.username,
    city: data.city || '',
    isAvailable: data.isAvailable !== false,
  };
}),
);

/** Recompute doctor rating aggregates when a review is created or updated. */

/**
 * One-time migration: grant careTeamDoctorIds from historical appointments.
 * Set BACKFILL_ADMIN_EMAILS env (comma-separated) on the function before calling.
 */
exports.backfillPatientCareTeams = onCall(
  { timeoutSeconds: 540, region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('backfillPatientCareTeams', { category: 'api' }, async (request) => {
  requireAuth(request);

  const allowedEmails = (process.env.BACKFILL_ADMIN_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const callerEmail = String(request.auth.token.email || '').trim().toLowerCase();
  const emailVerified = request.auth.token.email_verified === true;
  // Fail closed: empty allow-list must not grant access to every authenticated user.
  if (allowedEmails.length === 0 || !emailVerified || !allowedEmails.includes(callerEmail)) {
    throw new HttpsError('permission-denied', 'Not authorized to run migration.');
  }
  if (request.data?.confirm !== true) {
    throw new HttpsError('invalid-argument', 'Pass { confirm: true } to run migration.');
  }

  const db = getFirestore();
  let lastDoc = null;
  let scanned = 0;
  let updated = 0;
  const pending = new Map();

  while (true) {
    let query = db.collection('appointments').orderBy('__name__').limit(200);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      scanned += 1;
      const data = doc.data();
      const patientId = String(data.patientId || '').trim();
      const doctorId = String(data.doctorId || '').trim();
      if (!patientId || !doctorId) continue;
      if (!/^p\d+$|^wi/i.test(patientId)) continue;

      if (!pending.has(patientId)) pending.set(patientId, new Set());
      pending.get(patientId).add(doctorId);
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < 200) break;
  }

  for (const [patientId, doctorIds] of pending.entries()) {
    const patientRef = db.collection('patients').doc(patientId);
    const patientSnap = await patientRef.get();
    if (!patientSnap.exists) continue;

    await patientRef.set(
      {
        careTeamDoctorIds: FieldValue.arrayUnion(...doctorIds),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    updated += 1;
  }

  return { scanned, patientsUpdated: updated };
}),
);

exports.createRazorpayOrder = createRazorpayOrder;
exports.verifyRazorpayPayment = verifyRazorpayPayment;
exports.reviewPromotedAd = reviewPromotedAd;
exports.expirePromotedAds = expirePromotedAds;
exports.razorpayWebhook = razorpayWebhook;
exports.bookAppointment = bookAppointment;
exports.rescheduleAppointment = rescheduleAppointment;
// Slot reconciliation: Postgres book_appointment_atomic / triggers (no Firestore onDocumentWritten export).

const { sendMsg91Email } = require('./msg91_email');

/**
 * Triggered whenever an email is queued into the `mail` collection in Firestore.
 * Automatically dispatches the email via MSG91 Email API v5.
 */

/** Permanently deletes the caller's Firestore, Storage, and Auth data. */
exports.deleteMyAccount = onCall(
  {
    region: CALLABLE_REGION,
    enforceAppCheck: ENFORCE_ABUSE_APP_CHECK,
    secrets: [awsAccessKeyId, awsSecretAccessKey, supabaseServiceRoleKey],
  },
  protectCallable('deleteMyAccount', { category: 'api' }, async (request) => {
    requireAuth(request);
    return deleteMyAccountHandler(request.auth.uid);
  }),
);

exports.sendMsg91EmailCallable = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('sendMsg91EmailCallable', { category: 'api' }, async (request) => {
  requireAuth(request);
  const allowedEmails = (
    process.env.ACCOUNT_APPROVAL_ADMIN_EMAILS
    || process.env.BACKFILL_ADMIN_EMAILS
    || ''
  )
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const callerEmail = String(request.auth.token.email || '').trim().toLowerCase();
  const emailVerified = request.auth.token.email_verified === true;
  if (allowedEmails.length === 0 || !emailVerified || !allowedEmails.includes(callerEmail)) {
    throw new HttpsError('permission-denied', 'Not authorized to send email.');
  }

  const toEmail = requireEmail(request.data?.toEmail, 'toEmail');
  const recipientName = sanitizePlainText(request.data?.recipientName || 'User', {
    maxLength: 80,
  });
  const templateId = request.data?.templateId
    ? requireString(request.data.templateId, 'templateId', {
        min: 2,
        max: 80,
        pattern: /^[A-Za-z0-9_\-]+$/,
      })
    : undefined;
  const subject = sanitizePlainText(request.data?.subject || 'DoctorNect', {
    maxLength: 120,
  });
  // Never accept raw HTML from clients — plain text only.
  const body = sanitizePlainText(request.data?.body || request.data?.html || '', {
    maxLength: 5000,
  });
  return await sendMsg91Email({
    toEmail,
    recipientName,
    templateId,
    subject,
    html: undefined,
    body,
    variables: undefined,
    fromEmail: process.env.MSG91_FROM_EMAIL || 'no-reply@mail.doctornect.com',
    domain: process.env.MSG91_EMAIL_DOMAIN || 'mail.doctornect.com',
  });
}),
);

const { processMailQueue } = require('./mail_dispatcher');
const { getDatabaseClient } = require('./src/db/client');

/** Drain public.mail_queue (Postgres-only; replaces Firestore mail/{id} trigger). */
exports.processMailQueueScheduled = onSchedule(
  {
    schedule: 'every 5 minutes',
    region: CALLABLE_REGION,
    secrets: [supabaseServiceRoleKey],
  },
  async () => {
    const supabase = getDatabaseClient();
    await processMailQueue({ supabase });
  },
);

const { processNotificationOutboxBatch } = require('./notification_outbox_worker');

/** Poll notification_outbox → FCM (RDS + staging; same path as SQL triggers). */
exports.processNotificationOutboxScheduled = onSchedule(
  {
    schedule: 'every 1 minutes',
    region: CALLABLE_REGION,
    secrets: [supabaseServiceRoleKey, ...(OTP_REDIS_MIRROR_ON ? require('./redis').REDIS_SECRETS : [])],
  },
  async () => {
    await processNotificationOutboxBatch();
  },
);

/** HTTPS webhook: Postgres change events → FCM (see supabase_database_webhook.js). */
exports.supabaseDatabaseWebhook = onRequest(
  {
    region: CALLABLE_REGION,
    secrets: [supabaseWebhookSecret, supabaseServiceRoleKey],
  },
  supabaseDatabaseWebhookHandler,
);

// Helpers exported for unit testing
exports._safeCompareSecrets = safeCompareSecrets;
exports._isDoctorPatientSupabasePrimary = isDoctorPatientSupabasePrimary;
exports._resetRemoteConfigCache = _resetRemoteConfigCache;
exports._setMockRemoteConfigTemplate = _setMockRemoteConfigTemplate;
exports._supabaseDatabaseWebhookHandler = supabaseDatabaseWebhookHandler;


