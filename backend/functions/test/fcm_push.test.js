'use strict';

const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { sendFcmIfTokenExists, setMessagingForTesting } = require('../fcm_push');

describe('fcm_push service (Postgres user_devices path)', () => {
  afterEach(() => {
    setMessagingForTesting(null);
  });

  it('resolves user_id and sends FCM to tokens from user_devices table', async () => {
    const sentTokens = [];
    setMessagingForTesting({
      send: async (msg) => {
        sentTokens.push(msg.token);
        return 'msg_id_' + sentTokens.length;
      },
    });

    const mockSupabase = {
      from: (table) => {
        if (table === 'users') {
          return {
            select: () => ({
              or: () => ({
                maybeSingle: async () => ({
                  data: { id: 'firebase_uid_123' },
                  error: null,
                }),
              }),
            }),
          };
        }
        if (table === 'user_devices') {
          return {
            select: () => ({
              eq: (col, val) => {
                assert.equal(col, 'user_id');
                assert.equal(val, 'firebase_uid_123');
                return {
                  data: [
                    { id: 'dev_1', fcm_token: 'device_token_android' },
                    { id: 'dev_2', fcm_token: 'device_token_ios' },
                  ],
                  error: null,
                };
              },
            }),
          };
        }
        throw new Error('Unexpected table ' + table);
      },
    };

    const result = await sendFcmIfTokenExists(null, {
      collection: 'patients',
      docId: 'pat_1',
      title: 'New Notification',
      body: 'Hello patient',
      androidChannelId: 'updates',
      supabaseClient: mockSupabase,
    });

    assert.equal(result, true);
    assert.deepEqual(sentTokens, ['device_token_android', 'device_token_ios']);
  });

  it('deletes invalid device token on registration-token-not-registered error', async () => {
    let deletedId = null;
    setMessagingForTesting({
      send: async () => {
        const err = new Error('Not registered');
        err.code = 'messaging/registration-token-not-registered';
        throw err;
      },
    });

    const mockSupabase = {
      from: (table) => {
        if (table === 'user_devices') {
          return {
            select: () => ({
              eq: () => ({
                data: [{ id: 'dead_dev_id', fcm_token: 'dead_token_456' }],
                error: null,
              }),
            }),
            delete: () => ({
              eq: (col, val) => {
                assert.equal(col, 'id');
                deletedId = val;
                return Promise.resolve({ error: null });
              },
            }),
          };
        }
        throw new Error('Unexpected table ' + table);
      },
    };

    const result = await sendFcmIfTokenExists(null, {
      collection: 'users',
      docId: 'uid_abc',
      title: 'Test',
      body: 'Test',
      androidChannelId: 'updates',
      supabaseClient: mockSupabase,
    });

    assert.equal(result, false);
    assert.equal(deletedId, 'dead_dev_id');
  });
});
