'use strict';

const { defineSecret } = require('firebase-functions/params');
const crypto = require('crypto');

/** Bind via Cloud Functions secrets (name must match Secret Manager). */
const supabaseWebhookSecret = defineSecret('SUPABASE_WEBHOOK_SECRET');
const { sendFcmIfTokenExists } = require('./fcm_push');
const { redisKey } = require('./src/config/redis_keys');
const {
  dispatchDatabaseChangeEvent,
  buildDedupeKey,
  notificationDispatchMode,
} = require('./notification_dispatch');

function safeCompareSecrets(provided, expected) {
  if (typeof provided !== 'string' || typeof expected !== 'string') return false;
  const cleanP = provided.trim();
  const cleanE = expected.trim();
  if (cleanP.length === 0 || cleanE.length === 0) return false;
  const pHash = crypto.createHash('sha256').update(cleanP).digest();
  const eHash = crypto.createHash('sha256').update(cleanE).digest();
  return crypto.timingSafeEqual(pHash, eHash);
}

async function markWebhookEventOnce(dedupeKey, options = {}) {
  if (options.dedupeStore instanceof Map) {
    if (options.dedupeStore.has(dedupeKey)) return true;
    options.dedupeStore.set(dedupeKey, true);
    return false;
  }

  const db = options.db;
  if (db && typeof db.runTransaction === 'function' && typeof db.collection === 'function') {
    const ref = db.collection('_webhook_processed_events').doc(dedupeKey);
    let duplicate = false;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) {
        duplicate = true;
        return;
      }
      tx.set(ref, { processedAt: new Date().toISOString() });
    });
    return duplicate;
  }

  try {
    const { redis } = require('./redis');
    const key = redisKey(`webhook:dedupe:${dedupeKey}`);
    const ok = await redis.set(key, '1', 'EX', 86400, 'NX');
    return ok !== 'OK';
  } catch {
    return false;
  }
}

function isLegacyDatabaseWebhookEnabled(options = {}) {
  if (options.forceEnableLegacyWebhook === true) return true;
  if (String(process.env.ENABLE_SUPABASE_DATABASE_WEBHOOK || '').trim() === '1') return true;
  const appEnv = String(process.env.APP_ENV || '').trim().toLowerCase();
  if (appEnv !== 'production') return true;
  return false;
}

async function supabaseDatabaseWebhookHandler(req, res, options = {}) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (!isLegacyDatabaseWebhookEnabled(options)) {
    console.warn(
      '[supabaseDatabaseWebhook] Rejected: APP_ENV=production and ENABLE_SUPABASE_DATABASE_WEBHOOK≠1 (use notification_outbox worker).',
    );
    return res.status(503).json({
      error: 'Disabled',
      message:
        'Legacy Supabase database webhook handler is disabled in production. Use notification_outbox + processNotificationOutboxScheduled.',
    });
  }

  const providedSecret = req.headers['x-supabase-webhook-secret'] || req.headers['x-webhook-secret'];
  const expectedSecret =
    options.expectedSecret !== undefined ? options.expectedSecret : process.env.SUPABASE_WEBHOOK_SECRET;

  if (!safeCompareSecrets(providedSecret, expectedSecret)) {
    console.warn('[supabaseDatabaseWebhook] Unauthorized webhook request: missing or invalid secret');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const payload = req.body;
  if (!payload || typeof payload !== 'object') {
    return res.status(400).json({ error: 'Invalid payload' });
  }

  const { type, table, record, old_record: oldRecord } = payload;
  const fcmSender = options.sendFcm || sendFcmIfTokenExists;
  const dbStub = options.db || null;

  try {
    const dedupeKey = buildDedupeKey({ table, type, record, payload });

    if (await markWebhookEventOnce(dedupeKey, options)) {
      return res.status(200).json({ success: true, duplicate: true });
    }

    const dispatchMode = options.dispatchMode || notificationDispatchMode();
    if (dispatchMode === 'outbox') {
      try {
        const { getDatabaseClient } = require('./src/db/client');
        const sb = options.dbClient || getDatabaseClient();
        await sb.from('notification_outbox').upsert(
          {
            dedupe_key: dedupeKey,
            table_name: String(table),
            event_type: String(type),
            payload: { type, table, record, old_record: oldRecord },
            status: 'pending',
          },
          { onConflict: 'dedupe_key', ignoreDuplicates: true },
        );
      } catch (err) {
        console.error('[supabaseDatabaseWebhook] outbox enqueue failed:', err?.message || err);
        return res.status(500).json({ error: 'Outbox enqueue failed' });
      }
      return res.status(200).json({ success: true, queued: true });
    }

    await dispatchDatabaseChangeEvent({
      type,
      table,
      record,
      oldRecord,
      sendFcm: fcmSender,
      dbStub,
    });

    return res.status(200).json({ success: true });
  } catch (err) {
    console.error('[supabaseDatabaseWebhook] Error processing webhook event:', err?.message || err);
    return res.status(500).json({ error: 'Internal processing error' });
  }
}

module.exports = {
  supabaseDatabaseWebhookHandler,
  safeCompareSecrets,
  supabaseWebhookSecret,
  isLegacyDatabaseWebhookEnabled,
};
