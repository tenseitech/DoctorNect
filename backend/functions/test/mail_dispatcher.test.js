'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { processMailQueue } = require('../mail_dispatcher');

test.describe('Mail Queue Dispatcher', () => {
  test('dispatches pending emails and marks status sent', async () => {
    const queue = [
      { mail_id: 'mail_1', to_address: 'user@example.com', subject: 'Test', text_body: 'Hello', attempts: 0 },
    ];
    const updates = [];

    const mockSupabase = {
      from: (table) => {
        assert.equal(table, 'mail_queue');
        return {
          select: () => ({
            eq: () => ({
              order: () => ({
                limit: async () => ({ data: queue, error: null }),
              }),
            }),
          }),
          update: (fields) => ({
            eq: async (col, val) => {
              updates.push({ col, val, fields });
              return { error: null };
            },
          }),
        };
      },
    };

    const sentMails = [];
    const mockSendEmail = async (opts) => {
      sentMails.push(opts);
      return { success: true };
    };

    const res = await processMailQueue({
      supabase: mockSupabase,
      sendEmail: mockSendEmail,
    });

    assert.equal(res.success, true);
    assert.equal(res.sent, 1);
    assert.equal(res.failed, 0);
    assert.equal(sentMails.length, 1);
    assert.equal(updates.length, 1);
    assert.equal(updates[0].fields.status, 'sent');
  });

  test('records error and marks failed after 3 attempts', async () => {
    const queue = [
      { mail_id: 'mail_fail', to_address: 'fail@example.com', subject: 'Fail', attempts: 2 },
    ];
    const updates = [];

    const mockSupabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            order: () => ({
              limit: async () => ({ data: queue, error: null }),
            }),
          }),
        }),
        update: (fields) => ({
          eq: async (col, val) => {
            updates.push({ col, val, fields });
            return { error: null };
          },
        }),
      }),
    };

    const mockSendEmail = async () => {
      throw new Error('SMTP connection error');
    };

    const res = await processMailQueue({
      supabase: mockSupabase,
      sendEmail: mockSendEmail,
    });

    assert.equal(res.success, true);
    assert.equal(res.sent, 0);
    assert.equal(res.failed, 1);
    assert.equal(updates[0].fields.status, 'failed');
    assert.equal(updates[0].fields.attempts, 3);
    assert.ok(updates[0].fields.error_message.includes('SMTP connection error'));
  });
});
