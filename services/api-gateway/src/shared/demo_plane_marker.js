/** Deploy bundle copy of scripts/lib/demo_plane_marker.js (the gateway image ships only src/). Keep identical: test/shared_module_parity.test.js */
'use strict';

/**
 * Demo-plane marker for ANONYMOUS ambulance driver sessions (PROJECT_ANALYSIS.md H3 / D1 = a).
 *
 * The ambulance module signs drivers in anonymously, so the demo ambulance's Firebase uid is a
 * random anonymous uid that is not on the fixed demo uid allowlist. When the server verifies the
 * demo ambulance's OTP (completeAmbulanceMobileOtpLogin, demo number from the FIXED allowlist in
 * demo_accounts.js), it sets these Firebase custom claims on that anonymous user with the Admin
 * SDK. Custom claims are written only server-side and are carried in the Google-signed ID token,
 * so a client can neither create nor edit them.
 *
 *   dn_plane      'demo'
 *   dn_plane_sub  the uid the marker was issued for (must equal the token subject)
 *   dn_plane_exp  unix seconds; at most MARKER_TTL_SECONDS after issue
 *
 * A marker is honoured only on an anonymous session, for its own uid, before it expires. Any
 * token that carries a dn_plane* claim that is not valid (expired, copied to another uid, edited
 * value, non-anonymous session) is REJECTED, never routed to RDS. Logging in again (OTP) issues a
 * fresh marker; a real ambulance login replaces all claims, so a stale marker cannot survive it.
 * This module is shared: Functions (backend/functions/lib copy) and gateway (src/shared copy).
 */

const DEMO_PLANE_CLAIM = 'dn_plane';
const DEMO_PLANE_SUB_CLAIM = 'dn_plane_sub';
const DEMO_PLANE_EXP_CLAIM = 'dn_plane_exp';
const MARKER_TTL_SECONDS = 12 * 60 * 60;
const CLOCK_SKEW_SECONDS = 60;

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

/** Claims to merge into the anonymous user's custom claims (server only). */
function buildDemoPlaneClaims(uid, now = nowSeconds()) {
  const sub = String(uid || '').trim();
  if (!sub) throw new Error('buildDemoPlaneClaims: uid required');
  return {
    [DEMO_PLANE_CLAIM]: 'demo',
    [DEMO_PLANE_SUB_CLAIM]: sub,
    [DEMO_PLANE_EXP_CLAIM]: now + MARKER_TTL_SECONDS,
  };
}

function tokenSubject(token) {
  return String((token && (token.sub || token.uid || token.user_id)) || '').trim();
}

function signInProvider(token) {
  return String((token && token.firebase && token.firebase.sign_in_provider) || '').trim();
}

/**
 * @param {object|null|undefined} token verified ID token payload (Functions request.auth.token,
 *   gateway rawPayload). Never pass unverified data.
 * @returns {'none'|'valid'|'invalid'}
 */
function evaluateDemoPlaneMarker(token, now = nowSeconds()) {
  if (!token || typeof token !== 'object') return 'none';
  const has = [DEMO_PLANE_CLAIM, DEMO_PLANE_SUB_CLAIM, DEMO_PLANE_EXP_CLAIM]
    .some((k) => Object.prototype.hasOwnProperty.call(token, k));
  if (!has) return 'none';
  const exp = token[DEMO_PLANE_EXP_CLAIM];
  const sub = tokenSubject(token);
  const ok =
    token[DEMO_PLANE_CLAIM] === 'demo' &&
    sub !== '' &&
    token[DEMO_PLANE_SUB_CLAIM] === sub &&
    signInProvider(token) === 'anonymous' &&
    Number.isInteger(exp) &&
    exp > now &&
    exp <= now + MARKER_TTL_SECONDS + CLOCK_SKEW_SECONDS;
  return ok ? 'valid' : 'invalid';
}

module.exports = {
  DEMO_PLANE_CLAIM,
  DEMO_PLANE_SUB_CLAIM,
  DEMO_PLANE_EXP_CLAIM,
  MARKER_TTL_SECONDS,
  buildDemoPlaneClaims,
  evaluateDemoPlaneMarker,
};
