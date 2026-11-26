'use strict';

/**
 * Promoted ad expiry sweep (Postgres). Replaces the Firestore batch tests: the 400/500 write-batch
 * limits no longer apply (one UPDATE ... WHERE status='active' AND end_time <= now()).
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { expirePromotedAdsHandler } = require('../promoted_ads');
const { createMemoryPostgrest } = require('./helpers/memory_postgrest');

const iso = (msFromNow) => new Date(Date.now() + msFromNow).toISOString();

test('expirePromotedAdsHandler expires every past active ad (>500) and leaves future ones', async () => {
  const past = Array.from({ length: 550 }, (_, i) => ({ ad_id: `past_${i}`, status: 'active', end_time: iso(-3600e3) }));
  const future = Array.from({ length: 5 }, (_, i) => ({ ad_id: `future_${i}`, status: 'active', end_time: iso(3600e3) }));
  const db = createMemoryPostgrest({ promoted_ads: [...past, ...future] });

  const result = await expirePromotedAdsHandler(null, null, db);
  assert.equal(result.totalExpired, 550);
  for (const row of db.rows('promoted_ads')) {
    if (row.ad_id.startsWith('past_')) {
      assert.equal(row.status, 'expired');
      assert.ok(row.updated_at);
    } else {
      assert.equal(row.status, 'active');
    }
  }
  const second = await expirePromotedAdsHandler(null, null, db);
  assert.equal(second.totalExpired, 0, 're-running is idempotent');
});

test('expirePromotedAdsHandler ignores pending_approval ads even if end_time has passed', async () => {
  const db = createMemoryPostgrest({
    promoted_ads: [
      { ad_id: 'pending', status: 'pending_approval', end_time: iso(-3600e3) },
      { ad_id: 'live_old', status: 'active', end_time: iso(-60e3) },
    ],
  });
  const result = await expirePromotedAdsHandler(null, null, db);
  assert.equal(result.totalExpired, 1);
  const byId = Object.fromEntries(db.rows('promoted_ads').map((r) => [r.ad_id, r.status]));
  assert.deepEqual(byId, { pending: 'pending_approval', live_old: 'expired' });
});

test('expirePromotedAdsHandler surfaces database errors (no silent success)', async () => {
  const broken = { from: () => ({ update: () => ({ eq: () => ({ lte: () => ({ select: async () => ({ data: null, error: { message: 'down' } }) }) }) }) }) };
  await assert.rejects(() => expirePromotedAdsHandler(null, null, broken), /promoted ad expiry failed/);
});
