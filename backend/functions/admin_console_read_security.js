'use strict';

const { getAuth } = require('firebase-admin/auth');
const { HttpsError } = require('firebase-functions/v2/https');
const { resolveCallerIdentity } = require('./caller_identity');

const SYSTEM_ADMIN_EMAIL = 'admin@doctornect.com';
const FIREBASE_PROJECT_ID = String(process.env.FIREBASE_PROJECT_ID || 'medibond-45fad').trim();
const MAX_PAGE_SIZE = 200;
const DEFAULT_PAGE_SIZE = 100;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_PER_UID = 120;
const RATE_LIMIT_MAX_PER_IP = 300;

const uidBuckets = new Map();
const ipBuckets = new Map();

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function isSystemAdminRecord(userRow) {
  if (!userRow) return false;
  if (userRow.is_system_admin === true) return true;
  return normalizeEmail(userRow.email) === SYSTEM_ADMIN_EMAIL;
}

function isDirectoryExcludedRow(row) {
  if (!row) return true;
  if (isSystemAdminRecord(row)) return true;
  const role = String(row.role || '').toLowerCase();
  return role === 'super_admin' || role === 'superadmin';
}

function assertSuperAdminDbRecord(decoded, callerRow) {
  if (!callerRow?.id) {
    throw new HttpsError('permission-denied', 'Super admin database record required.');
  }
  const dbRole = String(callerRow.role || '').toLowerCase();
  const isSuperRole = dbRole === 'super_admin' || dbRole === 'superadmin';
  if (!isSuperRole) {
    throw new HttpsError('permission-denied', 'Super admin role required in database.');
  }
  const tokenEmail = normalizeEmail(decoded.email);
  const dbEmail = normalizeEmail(callerRow.email);
  if (tokenEmail && dbEmail && tokenEmail !== dbEmail) {
    throw new HttpsError('permission-denied', 'Token email does not match database user.');
  }
  if (isSystemAdminRecord(callerRow)) {
    if (!decoded.email_verified) {
      throw new HttpsError('permission-denied', 'Verified email required for platform admin.');
    }
    if (tokenEmail !== SYSTEM_ADMIN_EMAIL) {
      throw new HttpsError('permission-denied', 'Platform system admin email mismatch.');
    }
  }
}

function parseLimit(raw) {
  const n = parseInt(String(raw || DEFAULT_PAGE_SIZE), 10);
  if (!Number.isFinite(n) || n < 1) return DEFAULT_PAGE_SIZE;
  return Math.min(n, MAX_PAGE_SIZE);
}

function assertUserId(id) {
  const s = String(id || '').trim();
  if (!/^[a-zA-Z0-9_-]{1,128}$/.test(s)) {
    throw new HttpsError('invalid-argument', 'Invalid user id.');
  }
  return s;
}

function clientIp(req) {
  const xff = req.headers['x-forwarded-for'];
  if (typeof xff === 'string' && xff.trim()) {
    const hops = xff.split(',').map((h) => h.trim()).filter(Boolean);
    if (hops.length) return hops[hops.length - 1];
  }
  return req.socket?.remoteAddress || 'unknown';
}

function hitRateLimit(map, key, max) {
  const now = Date.now();
  const bucket = map.get(key) || { count: 0, reset: now + RATE_LIMIT_WINDOW_MS };
  if (now > bucket.reset) {
    bucket.count = 0;
    bucket.reset = now + RATE_LIMIT_WINDOW_MS;
  }
  bucket.count += 1;
  map.set(key, bucket);
  return bucket.count > max;
}

function assertRateLimits(req, uid) {
  const ip = clientIp(req);
  if (hitRateLimit(ipBuckets, ip, RATE_LIMIT_MAX_PER_IP)) {
    throw new HttpsError('resource-exhausted', 'Too many requests.');
  }
  if (uid && hitRateLimit(uidBuckets, uid, RATE_LIMIT_MAX_PER_UID)) {
    throw new HttpsError('resource-exhausted', 'Too many requests.');
  }
}

function allowedCorsOrigins() {
  const env = String(process.env.APP_ENV || 'staging').toLowerCase();
  const staging = String(process.env.ADMIN_CONSOLE_CORS_ORIGINS_STAGING || '').trim();
  const production = String(process.env.ADMIN_CONSOLE_CORS_ORIGINS_PRODUCTION || '').trim();
  const legacy = String(process.env.ADMIN_CONSOLE_CORS_ORIGINS || '').trim();
  const raw = env === 'production' ? production || legacy : staging || legacy;
  const list = raw
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .filter((o) => o !== '*');
  if (!list.length) {
    return ['http://localhost:8081', 'http://localhost:8090', 'http://127.0.0.1:8081'];
  }
  return list;
}

function applyCors(req, res) {
  const origin = String(req.headers.origin || '').trim();
  const allowed = allowedCorsOrigins();
  if (origin && allowed.includes(origin)) {
    res.set('Access-Control-Allow-Origin', origin);
    res.set('Vary', 'Origin');
  }
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Max-Age', '600');
}

function assertCorsOrigin(req) {
  if (req.method === 'OPTIONS') return;
  const origin = String(req.headers.origin || '').trim();
  if (!origin) return;
  const allowed = allowedCorsOrigins();
  if (!allowed.includes(origin)) {
    throw new HttpsError('permission-denied', 'Origin not allowed.');
  }
}

async function verifyFirebaseAdminToken(token) {
  if (!token) {
    throw new HttpsError('unauthenticated', 'Missing Authorization Bearer token.');
  }
  let decoded;
  try {
    decoded = await getAuth().verifyIdToken(token, true);
  } catch (e) {
    const code = e?.code || '';
    if (code === 'auth/id-token-revoked') {
      throw new HttpsError('unauthenticated', 'Token revoked.');
    }
    if (code === 'auth/id-token-expired') {
      throw new HttpsError('unauthenticated', 'Token expired.');
    }
    throw new HttpsError('unauthenticated', 'Invalid token.');
  }
  const aud = String(decoded.aud || '');
  if (aud !== FIREBASE_PROJECT_ID) {
    throw new HttpsError('unauthenticated', 'Invalid token audience.');
  }
  const iss = String(decoded.iss || '');
  const expectedIss = `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`;
  if (iss !== expectedIss) {
    throw new HttpsError('unauthenticated', 'Invalid token issuer.');
  }
  return decoded;
}

async function assertSuperAdminHttp(req, supabase) {
  assertCorsOrigin(req);
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = String(header).replace(/^Bearer\s+/i, '').trim();
  const decoded = await verifyFirebaseAdminToken(token);
  assertRateLimits(req, decoded.uid);
  const caller = await resolveCallerIdentity({
    uid: decoded.uid,
    supabaseClient: supabase,
    forceSupabase: true,
  });
  assertSuperAdminDbRecord(decoded, caller);
  return { supabase, caller, decoded };
}

function publicError(e) {
  if (e instanceof HttpsError) {
    return { code: e.code, message: e.message };
  }
  return { code: 'internal', message: 'Request failed.' };
}

function resetRateLimitsForTests() {
  uidBuckets.clear();
  ipBuckets.clear();
}

module.exports = {
  SYSTEM_ADMIN_EMAIL,
  MAX_PAGE_SIZE,
  DEFAULT_PAGE_SIZE,
  normalizeEmail,
  isSystemAdminRecord,
  isDirectoryExcludedRow,
  assertSuperAdminDbRecord,
  parseLimit,
  assertUserId,
  allowedCorsOrigins,
  applyCors,
  assertCorsOrigin,
  verifyFirebaseAdminToken,
  assertSuperAdminHttp,
  publicError,
  resetRateLimitsForTests,
};
