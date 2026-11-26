/** Deploy bundle copy of scripts/lib/rds_demo_uid_guard.js (Firebase uploads only backend/functions). Keep identical: test/demo_routing_bundle_parity.test.js */
'use strict';

const { isDemoFirebaseUid } = require('./demo_routing');

/**
 * Fail-closed: demo/reviewer Firebase UIDs must not use the RDS PostgREST plane.
 */
function assertDemoUidNotOnRds(firebaseUid, env = process.env) {
  const uid = String(firebaseUid || '').trim();
  if (!uid) return;
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return;
  if (!isDemoFirebaseUid(uid, env)) return;
  const err = new Error(
    `[DataPlane] Demo Firebase UID must not use RDS; configure DEMO_REAL_ROUTING_ENABLED and demo upstream.`,
  );
  err.code = 'demo_uid_rds_forbidden';
  err.httpStatus = 403;
  throw err;
}

function isDemoUidRdsForbidden(firebaseUid, env = process.env) {
  try {
    assertDemoUidNotOnRds(firebaseUid, env);
    return false;
  } catch (e) {
    return e.code === 'demo_uid_rds_forbidden';
  }
}

function collectDemoUidsFromPostgrestQuery(queryString, env = process.env) {
  const hits = new Set();
  const qs = String(queryString || '');
  if (!qs.trim()) return hits;
  const re = /(?:^|[&?])(?:id|firebase_uid)=eq\.([^&]+)/gi;
  let m;
  while ((m = re.exec(qs)) !== null) {
    const raw = decodeURIComponent(String(m[1] || '').trim());
    if (raw && isDemoFirebaseUid(raw, env)) {
      hits.add(raw);
    }
  }
  return hits;
}

function assertServiceRoleRdsQuerySafe(subPath, queryString, env = process.env) {
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return;
  const demoHits = collectDemoUidsFromPostgrestQuery(queryString, env);
  if (demoHits.size === 0) return;
  const err = new Error(
    `[DataPlane] service_role must not query demo Firebase UIDs on RDS: ${[...demoHits].join(', ')}`,
  );
  err.code = 'demo_uid_rds_forbidden';
  err.httpStatus = 403;
  throw err;
}

function assertRdsPathAllowed({ firebaseUid, clientRole, subPath, queryString }, env = process.env) {
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return;
  assertDemoUidNotOnRds(firebaseUid, env);
  if (clientRole === 'service_role') {
    assertServiceRoleRdsQuerySafe(subPath, queryString, env);
  }
}

module.exports = {
  assertDemoUidNotOnRds,
  isDemoUidRdsForbidden,
  collectDemoUidsFromPostgrestQuery,
  assertServiceRoleRdsQuerySafe,
  assertRdsPathAllowed,
};