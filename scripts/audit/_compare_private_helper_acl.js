#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv, maskConnectionString } = require('../lib/env_loader');

loadRootEnv();

const FN_QUERY = `
SELECT
  n.nspname AS schema,
  p.proname AS name,
  pg_get_function_identity_arguments(p.oid) AS args,
  r.rolname AS owner,
  p.prosecdef AS security_definer,
  COALESCE(array_to_string(p.proconfig, ', '), '') AS proconfig,
  pg_catalog.array_to_string(p.proacl, E'\\n') AS acl,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
  has_function_privilege('service_role', p.oid, 'EXECUTE') AS svc_exec,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles r ON r.oid = p.proowner
WHERE n.nspname IN ('private', 'public')
  AND (
    p.proname LIKE 'is_%'
    OR p.proname LIKE 'trg_%'
    OR p.proname IN (
      'deactivate_provider_profile',
      'reactivate_provider_profile',
      'current_profile_id',
      'doctor_can_access_patient',
      'enqueue_notification_outbox'
    )
  )
ORDER BY 1, 2, 3;
`;

async function fetchTarget(label, connectionString) {
  const c = new Client({ connectionString: connectionString.replace(/^postgres:/i, 'postgresql:') });
  await c.connect();
  try {
    const { rows } = await c.query(FN_QUERY);
    return { label, url: maskConnectionString(connectionString), rows };
  } finally {
    await c.end();
  }
}

function key(row) {
  return `${row.schema}.${row.name}(${row.args})`;
}

async function main() {
  const stagingUrl = getEnv('STAGING_SUPABASE_DB_URL');
  const replayUrl =
    getEnv('REPLAY_DB_URL') ||
    `postgresql://doctornect_admin:test@127.0.0.1:${getEnv('RDSLIKE_PG_PORT') || '5442'}/doctornect`;

  const [staging, replay] = await Promise.all([
    fetchTarget('staging', stagingUrl),
    fetchTarget('replay', replayUrl),
  ]);

  const replayByKey = new Map(replay.rows.map((r) => [key(r), r]));
  const stagingByKey = new Map(staging.rows.map((r) => [key(r), r]));

  const gaps = [];
  for (const [k, s] of stagingByKey) {
    const r = replayByKey.get(k);
    if (!r) continue;
    if (s.auth_exec !== r.auth_exec || s.svc_exec !== r.svc_exec || s.security_definer !== r.security_definer) {
      gaps.push({
        fn: k,
        staging: {
          auth_exec: s.auth_exec,
          svc_exec: s.svc_exec,
          owner: s.owner,
          secdef: s.security_definer,
          acl: s.acl,
        },
        replay: {
          auth_exec: r.auth_exec,
          svc_exec: r.svc_exec,
          owner: r.owner,
          secdef: r.security_definer,
          acl: r.acl,
        },
      });
    }
  }

  const stagingOnlyMissingAuth = staging.rows.filter(
    (s) => s.schema === 'private' && !s.auth_exec && replayByKey.get(key(s))?.auth_exec,
  );

  console.log(
    JSON.stringify(
      {
        staging: { url: staging.url, count: staging.rows.length },
        replay: { url: replay.url, count: replay.rows.length },
        diffs: gaps,
        staging_missing_auth_replay_has: stagingOnlyMissingAuth.map((s) => key(s)),
        focus: {
          staging: staging.rows.find((r) => r.name === 'is_system_admin_user'),
          replay: replay.rows.find((r) => r.name === 'is_system_admin_user'),
        },
      },
      null,
      2,
    ),
  );
}

main().catch((e) => {
  console.error('FAIL', e.message);
  process.exit(1);
});