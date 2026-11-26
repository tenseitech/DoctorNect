'use strict';

const { HttpsError } = require('firebase-functions/v2/https');
const { resolveDataPlane } = require('../../lib/demo_routing');
const { evaluateDemoPlaneMarker } = require('../../lib/demo_plane_marker');
const { currentAuth } = require('../auth_context');

/**
 * Data plane for a uid inside the current request. Same as resolveDataPlane (fixed demo uid
 * allowlist; everything else RDS in production), plus: when the uid is the verified caller of
 * this request and its ID token carries the server-set demo-plane marker (demo ambulance on an
 * anonymous session, lib/demo_plane_marker.js), route to the demo (staging) plane. A marker that
 * is present but not valid (expired, copied, wrong session type) is rejected: it never falls
 * back to RDS.
 */
function resolveRequestPlane(uid, { appEnv = (process.env.APP_ENV || 'staging').toLowerCase(), env = process.env, now } = {}) {
  const base = resolveDataPlane({ appEnv, firebaseUid: uid || null, env });
  if (base !== 'rds' || appEnv !== 'production' || !uid) return base;
  const ctx = currentAuth();
  if (!ctx || ctx.uid !== String(uid)) return base;
  const verdict = evaluateDemoPlaneMarker(ctx.token, now);
  if (verdict === 'valid') return 'supabase';
  if (verdict === 'invalid') {
    throw new HttpsError('unauthenticated', 'Your demo session has expired. Please sign in again.');
  }
  return base;
}

function requestObjectStoragePrefix(uid, opts = {}) {
  return resolveRequestPlane(uid, opts) === 'supabase' ? 'demo/' : 'prod/';
}

function requestRedisNamespace(uid, opts = {}) {
  return resolveRequestPlane(uid, opts) === 'supabase' ? 'demo:' : 'real:';
}

module.exports = { resolveRequestPlane, requestObjectStoragePrefix, requestRedisNamespace };
