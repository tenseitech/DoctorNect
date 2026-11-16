'use strict';

/**
 * FORCE RLS tables block seed INSERTs when connected as doctornect_admin (table owner, not BYPASSRLS).
 * Harness/gateway fixtures may SET LOCAL ROLE service_role only when current_user is already a member.
 */

async function resolveHarnessSeedRole(client) {
  const res = await client.query(`
    SELECT
      current_user AS login,
      COALESCE((SELECT rolsuper FROM pg_roles WHERE rolname = current_user), false) AS super,
      pg_has_role(current_user, 'service_role', 'member') AS member_service_role
  `);
  const row = res.rows[0] || {};
  return {
    login: row.login,
    super: Boolean(row.super),
    memberServiceRole: Boolean(row.member_service_role),
  };
}

async function beginHarnessSeedDml(client) {
  const who = await resolveHarnessSeedRole(client);
  if (!who.super && !who.memberServiceRole) {
    throw new Error(
      `[harness-seed] current_user=${who.login} cannot seed under FORCE RLS: ` +
        'need rolsuper or membership in service_role (GRANT service_role TO doctornect_admin in bootstrap).',
    );
  }
  if (!who.super && who.memberServiceRole) {
    await client.query('SET LOCAL ROLE service_role');
    return { resetAfter: true };
  }
  return { resetAfter: false };
}

async function endHarnessSeedDml(client, { resetAfter } = {}) {
  if (resetAfter) {
    await client.query('RESET ROLE');
  }
}

async function withHarnessSeedDml(client, fn) {
  const ctx = await beginHarnessSeedDml(client);
  try {
    await fn();
  } catch (err) {
    err.message = `[harness-seed] ${err.message}`;
    throw err;
  } finally {
    try {
      await endHarnessSeedDml(client, ctx);
    } catch (resetErr) {
      // Preserve the original seed failure when RESET ROLE runs on an aborted transaction (25P02).
      if (resetErr.code !== '25P02') {
        throw resetErr;
      }
    }
  }
}

module.exports = {
  resolveHarnessSeedRole,
  beginHarnessSeedDml,
  endHarnessSeedDml,
  withHarnessSeedDml,
};