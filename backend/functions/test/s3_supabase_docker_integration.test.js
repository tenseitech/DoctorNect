'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('../../node_modules/pg');
const { _test } = require('../s3_storage');

const {
  confirmS3UploadHandler,
  logStorageAccess,
  setS3ClientForTesting,
} = _test;

const DOCKER_PG_URL = process.env.LOCAL_DOCKER_PG_URL || 'postgres://postgres:postgres@127.0.0.1:54322/postgres';

test('S3 Supabase-mode integration test on local Docker Postgres', async () => {
  const pgClient = new Client({ connectionString: DOCKER_PG_URL });
  await pgClient.connect();

  try {
    // 1. Verify connection and clean prior test rows
    const health = await pgClient.query('SELECT 1 as healthy;');
    assert.equal(health.rows[0].healthy, 1);

    const testUid = `docker_test_user_${Date.now()}`;
    const testObjectKey = `records/docker_patient/${Date.now()}.pdf`;

    // 2. Wrap pgClient as a Supabase-compatible query interface for s3_storage
    const dockerSupabaseAdapter = {
      from(tableName) {
        return {
          async insert(row) {
            const keys = Object.keys(row);
            const values = Object.values(row);
            const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
            const query = `INSERT INTO public.${tableName} (${keys.join(', ')}) VALUES (${placeholders}) RETURNING *;`;
            const res = await pgClient.query(query, values);
            return { data: res.rows, error: null };
          },
          update(updates) {
            return {
              eq(column, value) {
                const keys = Object.keys(updates);
                const values = Object.values(updates);
                const setClause = keys.map((k, i) => `${k} = $${i + 1}`).join(', ');
                values.push(value);
                const query = `UPDATE public.${tableName} SET ${setClause} WHERE ${column} = $${values.length} RETURNING *;`;
                return pgClient.query(query, values).then(res => ({ data: res.rows, error: null }));
              },
            };
          },
          select(columns = '*') {
            return {
              eq(column, value) {
                return {
                  async maybeSingle() {
                    const query = `SELECT ${columns} FROM public.${tableName} WHERE ${column} = $1 LIMIT 1;`;
                    const res = await pgClient.query(query, [value]);
                    return { data: res.rows[0] || null, error: null };
                  },
                };
              },
            };
          },
        };
      },
    };

    // 3. Test logStorageAccess direct write to Docker storage_audit_logs table
    await logStorageAccess(
      null,
      {
        who: testUid,
        role: 'doctor',
        what: testObjectKey,
        action: 'download_presigned',
        status: 'success',
        metadata: { client: 'docker_integration_test' },
      },
      {
        isSupabase: true,
        supabase: dockerSupabaseAdapter,
      }
    );

    // 4. Verify row exists in live Docker Postgres table
    const auditRes = await pgClient.query(
      'SELECT * FROM public.storage_audit_logs WHERE who = $1 AND what = $2;',
      [testUid, testObjectKey]
    );

    assert.equal(auditRes.rows.length, 1, 'Audit log must be written to Docker Postgres storage_audit_logs');
    assert.equal(auditRes.rows[0].who, testUid);
    assert.equal(auditRes.rows[0].action, 'download_presigned');
    assert.equal(auditRes.rows[0].status, 'success');

    // Clean up test audit row
    await pgClient.query('DELETE FROM public.storage_audit_logs WHERE who = $1;', [testUid]);
  } finally {
    await pgClient.end();
  }
});
