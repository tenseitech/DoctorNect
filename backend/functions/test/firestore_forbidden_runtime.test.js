'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');

describe('FIRESTORE_FORBIDDEN=1 runtime', () => {
  const prev = process.env.FIRESTORE_FORBIDDEN;

  before(() => {
    process.env.FIRESTORE_FORBIDDEN = '1';
  });

  after(() => {
    if (prev === undefined) delete process.env.FIRESTORE_FORBIDDEN;
    else process.env.FIRESTORE_FORBIDDEN = prev;
  });

  it('getLegacyFirestoreDb returns null instead of throwing', () => {
    const { getLegacyFirestoreDb } = require('../legacy_db');
    assert.equal(getLegacyFirestoreDb(), null);
  });

  it('raw getFirestore() remains blocked by guard', () => {
    const { getFirestore } = require('firebase-admin/firestore');
    assert.throws(() => getFirestore(), /FIRESTORE_FORBIDDEN/);
  });
});
