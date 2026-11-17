'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  resolveHarnessSeedRole,
  beginHarnessSeedDml,
  endHarnessSeedDml,
} = require('../lib/harness_seed_role');

describe('harness_seed_role', () => {
  it('refuses seed when not super and not service_role member', async () => {
    const client = {
      queries: [],
      async query(sql) {
        this.queries.push(sql);
        if (sql.includes('pg_has_role')) {
          return { rows: [{ login: 'app_only', super: false, member_service_role: false }] };
        }
        throw new Error('unexpected query');
      },
    };
    await assert.rejects(() => beginHarnessSeedDml(client), /service_role/);
  });

  it('sets local role for doctornect_admin member', async () => {
    const client = {
      async query(sql) {
        if (sql.includes('pg_has_role')) {
          return { rows: [{ login: 'doctornect_admin', super: false, member_service_role: true }] };
        }
        if (sql.includes('SET LOCAL ROLE service_role')) return { rows: [] };
        if (sql.includes('RESET ROLE')) return { rows: [] };
        throw new Error(`unexpected: ${sql}`);
      },
    };
    const who = await resolveHarnessSeedRole(client);
    assert.equal(who.memberServiceRole, true);
    const ctx = await beginHarnessSeedDml(client);
    assert.equal(ctx.resetAfter, true);
    await endHarnessSeedDml(client, ctx);
  });
});