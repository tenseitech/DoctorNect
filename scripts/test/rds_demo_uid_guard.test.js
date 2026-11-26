'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertDemoUidNotOnRds,
  assertServiceRoleRdsQuerySafe,
  collectDemoUidsFromPostgrestQuery,
} = require('../lib/rds_demo_uid_guard');

const prodEnv = {
  APP_ENV: 'production',
  DEMO_REAL_ROUTING_ENABLED: '1',
  DEMO_FIREBASE_UID_ALLOWLIST: 'rev_fb_pat_001,rev_fb_doc_001',
};

describe('rds_demo_uid_guard', () => {
  it('allows null uid on RDS', () => {
    assert.doesNotThrow(() => assertDemoUidNotOnRds(null, prodEnv));
  });

  it('rejects demo firebase uid on RDS', () => {
    assert.throws(
      () => assertDemoUidNotOnRds('rev_fb_pat_001', prodEnv),
      (e) => e.code === 'demo_uid_rds_forbidden',
    );
  });

  it('allows demo uid when APP_ENV is staging', () => {
    assert.doesNotThrow(() =>
      assertDemoUidNotOnRds('rev_fb_pat_001', { ...prodEnv, APP_ENV: 'staging' }),
    );
  });

  it('collects demo uids from PostgREST filters', () => {
    const hits = collectDemoUidsFromPostgrestQuery(
      'select=id&firebase_uid=eq.rev_fb_pat_001&limit=1',
      prodEnv,
    );
    assert.equal(hits.size, 1);
    assert.ok(hits.has('rev_fb_pat_001'));
  });

  it('rejects service_role query targeting demo uid', () => {
    assert.throws(
      () =>
        assertServiceRoleRdsQuerySafe(
          '/rest/v1/users',
          'id=eq.rev_fb_doc_001',
          prodEnv,
        ),
      (e) => e.code === 'demo_uid_rds_forbidden',
    );
  });
});