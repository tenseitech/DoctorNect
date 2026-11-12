'use strict';

const { sendFcmIfTokenExists } = require('./fcm_push');
const { redisKey } = require('./src/config/redis_keys');
const {
  dispatchDatabaseChangeEvent,
  buildDedupeKey,
} = require('./notification_dispatch');

const MAX_ATTEMPTS = 5;
const BATCH_SIZE = 25;

async function markDispatchOnce(dedupeKey) {
  try {
    const { redis } = require('./redis');
    const key = redisKey(`notify:dedupe:${dedupeKey}`);
    const ok = await redis.set(key, '1', 'EX', 86400, 'NX');
    return ok !== 'OK';
  } catch {
    return false;
  }
}

async function processNotificationOutboxBatch(options = {}) {
  const { getDatabaseClient } = require('./src/db/client');
  const client = options.dbClient || getDatabaseClient();
  const sendFcm = options.sendFcm || sendFcmIfTokenExists;

  const { data: rows, error } = await client
    .from('notification_outbox')
    .select('*')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(options.limit || BATCH_SIZE);

  if (error) {
    throw new Error(`notification_outbox fetch failed: ${error.message}`);
  }

  let processed = 0;
  for (const row of rows || []) {
    const payload = row.payload || {};
    const dedupeKey = row.dedupe_key || buildDedupeKey({
      table: row.table_name,
      type: row.event_type,
      record: payload.record,
      payload,
    });

    if (await markDispatchOnce(dedupeKey)) {
      await client
        .from('notification_outbox')
        .update({ status: 'sent', processed_at: new Date().toISOString() })
        .eq('id', row.id);
      processed += 1;
      continue;
    }

    try {
      await client
        .from('notification_outbox')
        .update({ status: 'processing', attempts: (row.attempts || 0) + 1 })
        .eq('id', row.id);

      await dispatchDatabaseChangeEvent({
        type: row.event_type,
        table: row.table_name,
        record: payload.record,
        oldRecord: payload.old_record,
        sendFcm,
        dbStub: null,
      });

      await client
        .from('notification_outbox')
        .update({ status: 'sent', processed_at: new Date().toISOString(), last_error: null })
        .eq('id', row.id);
      processed += 1;
    } catch (err) {
      const attempts = (row.attempts || 0) + 1;
      const status = attempts >= MAX_ATTEMPTS ? 'dead' : 'pending';
      await client
        .from('notification_outbox')
        .update({
          status,
          last_error: String(err?.message || err).slice(0, 500),
          processed_at: status === 'dead' ? new Date().toISOString() : null,
        })
        .eq('id', row.id);
    }
  }

  return { processed, fetched: (rows || []).length };
}

module.exports = {
  processNotificationOutboxBatch,
  MAX_ATTEMPTS,
};
