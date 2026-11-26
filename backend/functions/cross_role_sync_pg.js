'use strict';

async function pgMergeUpsert(pool, table, payload, conflictColumn) {
  const entries = Object.entries(payload).filter(([, value]) => value !== undefined);
  if (entries.length === 0) return;
  const cols = entries.map(([key]) => key);
  const values = entries.map(([, value]) => value);
  const placeholders = cols.map((_, index) => `$${index + 1}`).join(', ');
  const updates = cols
    .filter((col) => col !== conflictColumn && col !== 'created_at')
    .map((col) => `${col} = EXCLUDED.${col}`);
  const action = updates.length > 0 ? `DO UPDATE SET ${updates.join(', ')}` : 'DO NOTHING';
  await pool.query(
    `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${placeholders}) ON CONFLICT (${conflictColumn}) ${action}`,
    values,
  );
}

async function readRemoteUpdatedAtMs({ url, key, pool, table, idColumn, id }) {
  if (!/^[a-z_]+$/.test(table) || !/^[a-z_]+$/.test(idColumn)) {
    throw new Error('Unsupported compare-and-skip target');
  }
  if (url && key) {
    const base = url.replace(/\/+$/, '');
    let endpoint;
    if (table === 'appointments' && idColumn === 'appointment_id') {
      endpoint = `${base}/rest/v1/appointments?appointment_id=eq.${encodeURIComponent(id)}&select=updated_at&limit=1`;
    } else if (table === 'users' && idColumn === 'firebase_uid') {
      endpoint = `${base}/rest/v1/users?firebase_uid=eq.${encodeURIComponent(id)}&select=updated_at&limit=1`;
    } else {
      throw new Error('Unsupported compare-and-skip REST target');
    }
    const resp = await fetch(endpoint, {
      method: 'GET',
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
    });
    if (!resp.ok) {
      throw new Error(`compare-and-skip read failed (${resp.status})`);
    }
    const rows = await resp.json();
    if (!Array.isArray(rows) || rows.length === 0 || rows[0].updated_at == null) return null;
    const ms = Date.parse(rows[0].updated_at);
    return Number.isNaN(ms) ? null : ms;
  }
  if (pool) {
    const result = await pool.query(
      `SELECT updated_at FROM ${table} WHERE ${idColumn} = $1 LIMIT 1`,
      [id],
    );
    if (!result.rows || result.rows.length === 0 || result.rows[0].updated_at == null) return null;
    const ms = new Date(result.rows[0].updated_at).getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

async function upsertMergeRow(pool, table, conflictColumn, payload) {
  if (!/^[a-z_]+$/.test(table) || !/^[a-z_]+$/.test(conflictColumn)) {
    throw new Error('Unsupported upsert target');
  }
  const cols = Object.keys(payload).filter((col) => /^[a-z_]+$/.test(col));
  if (!cols.includes(conflictColumn)) throw new Error('Upsert payload missing conflict column');
  const assignments = cols
    .filter((col) => col !== conflictColumn && col !== 'id' && col !== 'created_at')
    .map((col) => `${col} = EXCLUDED.${col}`);
  const action = assignments.length > 0 ? `DO UPDATE SET ${assignments.join(', ')}` : 'DO NOTHING';
  const sql = `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')}) ON CONFLICT (${conflictColumn}) ${action}`;
  await pool.query(sql, cols.map((col) => payload[col]));
}

module.exports = {
  pgMergeUpsert,
  readRemoteUpdatedAtMs,
  upsertMergeRow,
};