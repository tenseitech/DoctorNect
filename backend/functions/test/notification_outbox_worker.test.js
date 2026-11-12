'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { processNotificationOutboxBatch } = require('../notification_outbox_worker');
const { setRedisClientForTesting } = require('../redis');

test('processNotificationOutboxBatch sends FCM and marks row sent', async () => {
  const sent = [];
  const updates = [];

  const mockDb = {
    from(table) {
      if (table !== 'notification_outbox') throw new Error('unexpected table');
      return {
        select() {
          return this;
        },
        eq(_col, _val) {
          return this;
        },
        order() {
          return this;
        },
        limit() {
          return Promise.resolve({
            data: [
              {
                id: 'row-1',
                dedupe_key: 'dedupe-abc',
                table_name: 'referrals',
                event_type: 'INSERT',
                attempts: 0,
                payload: {
                  record: {
                    to_doctor_id: 'doc_1',
                    from_doctor_name: 'Dr. A',
                    referral_id: 'ref_1',
                  },
                },
              },
            ],
            error: null,
          });
        },
        update(patch) {
          updates.push(patch);
          return {
            eq: () => Promise.resolve({ error: null }),
          };
        },
      };
    },
  };

  setRedisClientForTesting({
    set: async () => 'OK',
  });

  const result = await processNotificationOutboxBatch({
    dbClient: mockDb,
    sendFcm: async (_db, payload) => {
      sent.push(payload);
      return true;
    },
  });

  assert.equal(result.processed, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].data.type, 'referral_received');
  assert.ok(updates.some((u) => u.status === 'sent'));
  setRedisClientForTesting(null);
});
