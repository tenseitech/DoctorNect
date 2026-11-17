'use strict';

const APP_SCHEMAS = ['public', 'auth', 'private'];

/**
 * Count application-schema objects (tables, views, indexes, sequences, matviews).
 */
async function countAppSchemaObjects(client) {
  const res = await client.query(
    `
    SELECT count(*)::int AS n
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = ANY ($1::text[])
      AND c.relkind IN ('r', 'v', 'i', 'S', 'm')
    `,
    [APP_SCHEMAS],
  );
  return res.rows[0].n;
}

function assertTripwireUnchanged(before, after, context) {
  if (before !== after) {
    throw new Error(
      `[PROD TRIPWIRE] Application object count changed during ${context}: before=${before} after=${after}. ` +
        'Aborting — production catalog must not be mutated by dry-run tooling.',
    );
  }
}

module.exports = {
  APP_SCHEMAS,
  countAppSchemaObjects,
  assertTripwireUnchanged,
};