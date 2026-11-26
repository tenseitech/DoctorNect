'use strict';

const { FieldValue } = require('firebase-admin/firestore');
const { getLegacyFirestoreDb } = require('./legacy_db');
const { readSupabaseServiceRoleKey } = require('./secure_config');
const { getPgPool } = require('./src/db/pg_pool');

function getSupabaseConfig() {
  const isProduction = (process.env.APP_ENV || 'staging').toLowerCase() === 'production';
  const url = isProduction
    ? (process.env.PROD_GATEWAY_URL || '')
    : (process.env.STAGING_SUPABASE_URL || process.env.SUPABASE_URL || '');
  const key = isProduction
    ? (process.env.PROD_GATEWAY_SERVICE_KEY || '')
    : (process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY || readSupabaseServiceRoleKey() || '');
  return { url, key };
}

async function executeWithRetry(operationFn, { maxRetries = 3, baseDelayMs = 200, context = {} } = {}) {
  let attempt = 0;
  while (true) {
    try {
      return await operationFn(attempt);
    } catch (err) {
      attempt++;
      if (attempt > maxRetries) {
        console.error(`[RetryExhausted] Failed after ${maxRetries} retries for ${context.entityType || 'entity'} ID: ${context.entityId || 'unknown'}: ${err.message}`);
        const exhaustedErr = new Error(`Exhausted ${maxRetries} retries: ${err.message}`);
        exhaustedErr.originalError = err;
        exhaustedErr.retryCount = maxRetries;
        throw exhaustedErr;
      }
      const delayMs = baseDelayMs * Math.pow(2, attempt - 1);
      console.warn(`[SyncRetry] Attempt ${attempt}/${maxRetries} failed: ${err.message}. Retrying in ${delayMs}ms...`);
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
}

async function recordDlqFailure({ direction, entityType, entityId, payload, errorMessage, errorStack, retryCount }) {
  const { url, key } = getSupabaseConfig();
  const dlqEntry = {
    direction: direction || 'firestore_to_supabase',
    entity_type: entityType,
    entity_id: entityId,
    payload: payload || {},
    error_message: String(errorMessage || 'Unknown sync error'),
    error_stack: errorStack ? String(errorStack).slice(0, 1000) : null,
    retry_count: retryCount || 0,
    status: 'pending',
    created_at: new Date().toISOString(),
  };

  console.error(JSON.stringify({
    securityEvent: true,
    severity: 'CRITICAL',
    event: 'SYNC_BRIDGE_DLQ_FAILURE',
    ...dlqEntry,
  }));

  if (url && key) {
    try {
      const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/sync_dead_letter_queue`, {
        method: 'POST',
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
          'Content-Type': 'application/json',
          Prefer: 'return=minimal',
        },
        body: JSON.stringify(dlqEntry),
      });
      if (resp.ok) return;
    } catch (_) {
      // Supabase may be unreachable; fall through to local Firestore backup
    }
  }

  const pool = getPgPool();
  if (pool) {
    try {
      await pool.query(
        `INSERT INTO sync_dead_letter_queue 
          (direction, entity_type, entity_id, payload, error_message, error_stack, retry_count, status, created_at)
         VALUES 
          ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
        [dlqEntry.direction, dlqEntry.entity_type, dlqEntry.entity_id, JSON.stringify(dlqEntry.payload), dlqEntry.error_message, dlqEntry.error_stack, dlqEntry.retry_count, dlqEntry.status],
      );
      return;
    } catch (_) {}
  }

  try {
    const db = getLegacyFirestoreDb();
    if (!db) return;
    await db.collection('_sync_dlq').doc(`${entityType}_${entityId}_${Date.now()}`).set({
      ...dlqEntry,
      fallbackSavedAt: FieldValue.serverTimestamp(),
    });
  } catch (fsErr) {
    console.error('Fatal: Failed to write DLQ entry to both Supabase and Firestore fallback:', fsErr.message);
  }
}

module.exports = {
  getSupabaseConfig,
  executeWithRetry,
  recordDlqFailure,
};