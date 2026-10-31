'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { getConnectionMeta } = require('./db_connection_guard');

describe('db_connection_guard', () => {
  it('flags Supabase transaction pooler port 6543', () => {
    const meta = getConnectionMeta(
      'postgresql://postgres.ref:secret@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
    );
    assert.equal(meta.isTransactionPooler, true);
    assert.equal(meta.port, 6543);
  });

  it('allows session pooler port 5432', () => {
    const meta = getConnectionMeta(
      'postgresql://postgres.ref:secret@aws-0-ap-south-1.pooler.supabase.com:5432/postgres',
    );
    assert.equal(meta.isTransactionPooler, false);
    assert.equal(meta.port, 5432);
  });
});
