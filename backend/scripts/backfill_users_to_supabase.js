/**
 * DoctorNect: Existing Users Backfill to Supabase
 * File: backend/scripts/backfill_users_to_supabase.js
 *
 * Purpose:
 * Backfills Firestore users to Supabase public.users (C-1 gap).
 *
 * Safety & Guarantees:
 * - Dry-run by default; real writes only when --apply is supplied.
 * - Refuses to run with --apply unless an explicit --project <id> argument
 *   is given and matches the initialized Firebase Admin SDK project ID.
 * - Paginates Firestore users in batches via orderBy(documentId) and startAfter.
 * - Resumable from any UID via --start-after <uid>.
 * - Uses shared toUserUuid (RFC 4122 v5 deterministic UUID) and buildUserSupabasePayload.
 * - Idempotent: Handles conflict if a row already exists with the same deterministic id
 *   (e.g., created by earlier migration script) by updating that row rather than failing.
 * - Privacy: Logs counts only (scanned, created, updated, skipped, failed). No PII or UIDs in logs.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

// Safe environment loading
const loadEnvPath = path.join(__dirname, 'load_env.js');
if (fs.existsSync(loadEnvPath)) {
  try {
    require('./load_env').loadEnv();
  } catch (_) {}
}

// Load shared helpers from backend/functions
const { toUserUuid, executeUserSyncWithEmailFallback } = require('../functions/user_id_bridge');
const { buildUserSupabasePayload, normalizeRole } = require('../functions/cross_role_sync');

// Graceful Firebase Admin loader
let admin;
try {
  admin = require('firebase-admin');
} catch (_) {
  try {
    const fnReq = createRequire(path.resolve(__dirname, '..', 'functions', 'package.json'));
    admin = fnReq('firebase-admin');
  } catch (_) {
    admin = null;
  }
}

function parseCliArgs(argv = process.argv.slice(2)) {
  const args = {
    apply: false,
    project: null,
    startAfter: null,
    limit: null,
    batchSize: 50,
  };

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--apply') {
      args.apply = true;
    } else if (a === '--project' && argv[i + 1] && !argv[i + 1].startsWith('--')) {
      args.project = argv[++i].trim();
    } else if (a.startsWith('--project=')) {
      args.project = a.split('=')[1]?.trim() || null;
    } else if (a === '--start-after' && argv[i + 1] && !argv[i + 1].startsWith('--')) {
      args.startAfter = argv[++i].trim();
    } else if (a.startsWith('--start-after=')) {
      args.startAfter = a.split('=')[1]?.trim() || null;
    } else if (a === '--limit' && argv[i + 1] && !argv[i + 1].startsWith('--')) {
      args.limit = parseInt(argv[++i], 10);
    } else if (a.startsWith('--limit=')) {
      args.limit = parseInt(a.split('=')[1], 10);
    } else if (a === '--batch-size' && argv[i + 1] && !argv[i + 1].startsWith('--')) {
      args.batchSize = parseInt(argv[++i], 10);
    } else if (a.startsWith('--batch-size=')) {
      args.batchSize = parseInt(a.split('=')[1], 10);
    }
  }

  if (isNaN(args.limit) || args.limit <= 0) args.limit = null;
  if (isNaN(args.batchSize) || args.batchSize <= 0) args.batchSize = 50;

  return args;
}

function resolveAdminProjectId(adminApp) {
  if (adminApp && adminApp.options && adminApp.options.projectId) {
    return adminApp.options.projectId;
  }
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  if (process.env.FIREBASE_PROJECT_ID) return process.env.FIREBASE_PROJECT_ID;
  if (process.env.GOOGLE_CLOUD_PROJECT) return process.env.GOOGLE_CLOUD_PROJECT;
  return null;
}

function resolveSupabaseConfig() {
  const url = process.env.SUPABASE_URL || process.env.STAGING_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY;
  if (!url || !key) return null;
  return {
    url: url.replace(/\/+$/, ''),
    key,
  };
}

/**
 * Execute backfill with dependency injection for testing.
 */
async function runBackfill(options = {}) {
  const cliArgs = parseCliArgs(options.argv || process.argv.slice(2));
  const apply = options.apply !== undefined ? options.apply : cliArgs.apply;
  const projectArg = options.project !== undefined ? options.project : cliArgs.project;
  const startAfterUid = options.startAfter !== undefined ? options.startAfter : cliArgs.startAfter;
  const maxLimit = options.limit !== undefined ? options.limit : cliArgs.limit;
  const batchSize = options.batchSize !== undefined ? options.batchSize : cliArgs.batchSize;
  const logger = options.logger || console.log;

  // Resolve Firebase app and database
  let firestoreDb = options.firestoreDb;
  let adminApp = options.adminApp;
  if (!firestoreDb && admin) {
    if (!admin.apps.length) {
      admin.initializeApp();
    }
    adminApp = admin.app();
    firestoreDb = admin.firestore();
  }

  // Safety Guard: Require explicit --project matching Admin SDK projectId when applying
  if (apply) {
    if (!projectArg || typeof projectArg !== 'string' || projectArg.trim().length === 0) {
      throw new Error(
        'Refusing to run --apply: An explicit --project <id> argument is strictly required.'
      );
    }
    const sdkProjectId = resolveAdminProjectId(adminApp);
    if (!sdkProjectId || sdkProjectId !== projectArg.trim()) {
      throw new Error(
        `Refusing to run --apply: --project argument ("${projectArg}") does not match initialized Admin SDK projectId ("${sdkProjectId || 'unknown'}").`
      );
    }
  }

  // Resolve Supabase client or HTTP helper
  const supabaseConfig = options.supabaseConfig || resolveSupabaseConfig();
  const customFetch = options.fetch || global.fetch;

  if (apply && !supabaseConfig && !options.supabaseWriter) {
    throw new Error('Supabase configuration (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY) missing for --apply run.');
  }

  const counts = {
    scanned: 0,
    created: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    emailCollisions: 0,
    emailFallbackSynthetic: 0,
    emailKeptOnUpdate: 0,
  };

  if (!firestoreDb) {
    throw new Error('Firestore database instance could not be resolved.');
  }

  let currentStartAfter = startAfterUid;
  let hasMore = true;
  let totalProcessed = 0;
  const seenEmails = new Set();

  while (hasMore) {
    const currentBatchLimit = maxLimit ? Math.min(batchSize, maxLimit - totalProcessed) : batchSize;
    if (currentBatchLimit <= 0) break;

    // Build paginated query
    let query = firestoreDb.collection('users');
    if (admin && admin.firestore && admin.firestore.FieldPath) {
      query = query.orderBy(admin.firestore.FieldPath.documentId());
    } else {
      query = query.orderBy('__name__');
    }

    if (currentStartAfter) {
      query = query.startAfter(currentStartAfter);
    }
    query = query.limit(currentBatchLimit);

    const snapshot = await query.get();
    if (!snapshot || snapshot.empty || snapshot.docs.length === 0) {
      hasMore = false;
      break;
    }

    for (const doc of snapshot.docs) {
      counts.scanned++;
      totalProcessed++;
      currentStartAfter = doc.id;

      const uid = doc.id;
      const data = typeof doc.data === 'function' ? doc.data() : (doc.data || {});

      // Validate role can be normalized to a schema-supported role
      const rawRole = data.role;
      const normalizedRole = normalizeRole(rawRole);
      const isRoleSupported = [
        'patient',
        'doctor',
        'medicalStore',
        'lab',
        'ambulance',
        'superAdmin',
        'admin',
        'nurse',
        'receptionist',
        'billing_staff',
        'hospital_admin',
      ].includes(normalizedRole);

      if (!rawRole || !isRoleSupported) {
        counts.skipped++;
        if (maxLimit && totalProcessed >= maxLimit) {
          hasMore = false;
          break;
        }
        continue;
      }

      // Build payload using shared helper
      const built = buildUserSupabasePayload(uid, data);
      if (built.skip) {
        counts.skipped++;
        if (maxLimit && totalProcessed >= maxLimit) {
          hasMore = false;
          break;
        }
        continue;
      }

      const { row, createdAt } = built;
      const candidateEmail = String(row?.email || '').trim().toLowerCase();
      if (!apply && candidateEmail) {
        if (seenEmails.has(candidateEmail)) {
          counts.emailCollisions++;
        } else {
          seenEmails.add(candidateEmail);
        }
      }
      const deterministicId = toUserUuid(uid);

      if (!apply) {
        // Dry-run mode: do not write to database
        if (options.dryRunChecker) {
          const sim = await options.dryRunChecker(uid, deterministicId);
          if (sim === 'updated') counts.updated++;
          else counts.created++;
        } else {
          counts.created++;
        }
      } else {
        try {
          if (options.supabaseWriter) {
            const result = await options.supabaseWriter({
              uid,
              deterministicId,
              row,
              createdAt,
            });
            if (result === 'created') counts.created++;
            else if (result === 'updated') counts.updated++;
            else if (result === 'skipped') counts.skipped++;
          } else {
            // Live PostgREST write handler
            const { url, key } = supabaseConfig;
            const headers = {
              apikey: key,
              Authorization: `Bearer ${key}`,
              'Content-Type': 'application/json',
            };

            // 1. Check if row exists by firebase_uid
            const checkByUidResp = await customFetch(
              `${url}/rest/v1/users?firebase_uid=eq.${encodeURIComponent(uid)}&select=id,firebase_uid,email`,
              { method: 'GET', headers }
            );
            const byUidRows = checkByUidResp.ok ? await checkByUidResp.json() : [];
            let existingUser = (Array.isArray(byUidRows) && byUidRows.length > 0) ? byUidRows[0] : null;

            if (!existingUser) {
              // 2. Check if a row already exists with the deterministic ID
              const checkByIdResp = await customFetch(
                `${url}/rest/v1/users?id=eq.${encodeURIComponent(deterministicId)}&select=id,firebase_uid,email`,
                { method: 'GET', headers }
              );
              const byIdRows = checkByIdResp.ok ? await checkByIdResp.json() : [];
              if (Array.isArray(byIdRows) && byIdRows.length > 0) {
                existingUser = byIdRows[0];
              }
            }

            const patchFn = async (patchPayload) => {
              const targetUrl = existingUser?.firebase_uid
                ? `${url}/rest/v1/users?firebase_uid=eq.${encodeURIComponent(uid)}`
                : `${url}/rest/v1/users?id=eq.${encodeURIComponent(deterministicId)}`;
              const patchResp = await customFetch(
                targetUrl,
                {
                  method: 'PATCH',
                  headers: { ...headers, Prefer: 'return=minimal' },
                  body: JSON.stringify(patchPayload),
                }
              );
              if (!patchResp.ok) {
                const errText = await patchResp.text();
                const err = new Error(`Update failed (${patchResp.status}): ${errText}`);
                err.status = patchResp.status;
                err.body = errText;
                throw err;
              }
            };

            const postFn = async (insertPayload) => {
              const postResp = await customFetch(
                `${url}/rest/v1/users?on_conflict=firebase_uid`,
                {
                  method: 'POST',
                  headers: {
                    ...headers,
                    Prefer: 'resolution=merge-duplicates,return=minimal',
                  },
                  body: JSON.stringify(insertPayload),
                }
              );
              if (!postResp.ok) {
                const errText = await postResp.text();
                const err = new Error(`Insert failed (${postResp.status}): ${errText}`);
                err.status = postResp.status;
                err.body = errText;
                throw err;
              }
            };

            const syncResult = await executeUserSyncWithEmailFallback({
              uid,
              row,
              createdAt,
              deterministicId,
              existingUser,
              patchFn,
              postFn,
              logger: (msg) => {
                // Structured warnings contain uidHash and reason only; safe to log
                logger(msg);
              },
              counts,
            });

            if (syncResult.action === 'created' || syncResult.action === 'inserted') {
              counts.created++;
            } else if (syncResult.action === 'updated') {
              counts.updated++;
            }
          }
        } catch (_) {
          counts.failed++;
        }
      }

      if (maxLimit && totalProcessed >= maxLimit) {
        hasMore = false;
        break;
      }
    }

    if (snapshot.docs.length < currentBatchLimit) {
      hasMore = false;
    }
  }

  // Print counts ONLY. Strictly no PII, emails, phones, names or uids.
  logger('========================================');
  logger(`[Backfill Users] Mode: ${apply ? 'APPLY' : 'DRY-RUN'}`);
  logger(`[Backfill Users] Scanned: ${counts.scanned}`);
  logger(`[Backfill Users] Created: ${counts.created}`);
  logger(`[Backfill Users] Updated: ${counts.updated}`);
  logger(`[Backfill Users] Skipped: ${counts.skipped}`);
  logger(`[Backfill Users] Failed: ${counts.failed}`);
  logger(`[Backfill Users] Email Collisions: ${counts.emailCollisions}`);
  logger(`[Backfill Users] Email Fallback Synthetic: ${counts.emailFallbackSynthetic}`);
  logger(`[Backfill Users] Email Kept On Update: ${counts.emailKeptOnUpdate}`);
  logger('========================================');

  return counts;
}

if (require.main === module) {
  runBackfill()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(`[Backfill Users] Fatal error: ${err.message}`);
      process.exit(1);
    });
}

module.exports = {
  runBackfill,
  parseCliArgs,
  resolveAdminProjectId,
};
