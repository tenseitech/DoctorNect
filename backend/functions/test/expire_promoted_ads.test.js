'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { expirePromotedAdsHandler, EXPIRE_BATCH_LIMIT } = require('../promoted_ads');

function createMockFirestoreForAds() {
  const docs = new Map();
  const batchCommitSizes = [];

  function getQueryRef(filters = [], limitCount = null) {
    return {
      where(field, op, val) {
        return getQueryRef([...filters, { field, op, val }], limitCount);
      },
      limit(n) {
        return getQueryRef(filters, n);
      },
      async get() {
        const matches = [];
        for (const [id, data] of docs.entries()) {
          let pass = true;
          for (const f of filters) {
            if (f.op === '==' && data[f.field] !== f.val) {
              pass = false;
              break;
            }
            if (f.op === '<=') {
              const dTime = data[f.field]?.toDate ? data[f.field].toDate().getTime() : new Date(data[f.field]).getTime();
              const vTime = f.val?.toDate ? f.val.toDate().getTime() : new Date(f.val).getTime();
              if (dTime > vTime) {
                pass = false;
                break;
              }
            }
          }
          if (pass) {
            matches.push({
              id,
              ref: { id },
              data: () => ({ ...data }),
            });
          }
        }
        const limited = limitCount != null ? matches.slice(0, limitCount) : matches;
        return {
          empty: limited.length === 0,
          size: limited.length,
          docs: limited,
        };
      },
    };
  }

  return {
    docs,
    batchCommitSizes,
    collection(name) {
      if (name !== 'promotedAds') throw new Error(`Unexpected collection ${name}`);
      return getQueryRef();
    },
    batch() {
      const updates = [];
      return {
        update(ref, data) {
          updates.push({ ref, data });
        },
        async commit() {
          if (updates.length > 500) {
            throw new Error(`Firestore batch operation limit exceeded: ${updates.length} > 500`);
          }
          batchCommitSizes.push(updates.length);
          for (const u of updates) {
            const current = docs.get(u.ref.id) || {};
            docs.set(u.ref.id, { ...current, ...u.data });
          }
          updates.length = 0;
        },
      };
    },
  };
}

test('expirePromotedAdsHandler processes >500 expired ads in chunks <= 400 per batch', async () => {
  const db = createMockFirestoreForAds();
  const pastTime = Timestamp.fromDate(new Date(Date.now() - 3600000));
  const futureTime = Timestamp.fromDate(new Date(Date.now() + 3600000));
  const TOTAL_EXPIRED = 550;

  // 1. Seed 550 expired ads
  for (let i = 1; i <= TOTAL_EXPIRED; i++) {
    db.docs.set(`ad_expired_${i}`, {
      status: 'active',
      endTime: pastTime,
      title: `Expired Ad ${i}`,
    });
  }

  // 2. Seed 20 active ads whose endTime has not passed
  for (let i = 1; i <= 20; i++) {
    db.docs.set(`ad_future_${i}`, {
      status: 'active',
      endTime: futureTime,
      title: `Future Ad ${i}`,
    });
  }

  assert.equal(EXPIRE_BATCH_LIMIT, 400);

  // 3. Run expiration handler
  const result = await expirePromotedAdsHandler(db);

  assert.equal(result.totalExpired, TOTAL_EXPIRED);
  assert.equal(result.batchCount, 2, '550 items must be processed in 2 batches (400 and 150)');

  // Verify batch commit sizes
  assert.deepEqual(db.batchCommitSizes, [400, 150]);
  for (const size of db.batchCommitSizes) {
    assert.ok(size <= EXPIRE_BATCH_LIMIT, `Batch size ${size} must be <= ${EXPIRE_BATCH_LIMIT}`);
    assert.ok(size <= 500, `Batch size ${size} must never exceed Firestore limit 500`);
  }

  // Verify all 550 expired ads now have status = 'expired'
  for (let i = 1; i <= TOTAL_EXPIRED; i++) {
    const ad = db.docs.get(`ad_expired_${i}`);
    assert.equal(ad.status, 'expired');
    assert.ok(ad.updatedAt);
  }

  // Verify future ads remain active
  for (let i = 1; i <= 20; i++) {
    const ad = db.docs.get(`ad_future_${i}`);
    assert.equal(ad.status, 'active');
  }

  // 4. Running a second time finds 0 expired ads
  const secondRun = await expirePromotedAdsHandler(db);
  assert.equal(secondRun.totalExpired, 0);
  assert.equal(secondRun.batchCount, 0);
});

test('expirePromotedAdsHandler ignores pending_approval ads even if endTime has passed', async () => {
  const db = createMockFirestoreForAds();
  const pastTime = Timestamp.fromDate(new Date(Date.now() - 3600000));
  db.docs.set('ad_pending_review', {
    status: 'pending_approval',
    endTime: pastTime,
  });
  db.docs.set('ad_rejected', {
    status: 'rejected',
    endTime: pastTime,
  });
  db.docs.set('ad_active_expired', {
    status: 'active',
    endTime: pastTime,
  });

  const result = await expirePromotedAdsHandler(db);
  assert.equal(result.totalExpired, 1);
  assert.equal(db.docs.get('ad_pending_review').status, 'pending_approval');
  assert.equal(db.docs.get('ad_rejected').status, 'rejected');
  assert.equal(db.docs.get('ad_active_expired').status, 'expired');
});
