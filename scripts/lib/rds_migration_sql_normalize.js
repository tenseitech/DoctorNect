'use strict';

/**
 * Rewrite Supabase-oriented SQL for AWS RDS (no login role "postgres").
 * Applied for targets: production, rehearsal, replay when REPLAY_RDS_LIKE=1.
 */

const RDS_SUPERUSER_ROLE = 'rds_superuser';
const DEFAULT_MIGRATOR = 'doctornect_admin';

function shouldNormalizeRdsSql(target) {
  const t = String(target || '').toLowerCase();
  if (t === 'production' || t === 'rehearsal') return true;
  if ((t === 'replay' || t === 'replay_check') && process.env.REPLAY_RDS_LIKE === '1') return true;
  return false;
}

function migratorRoleName() {
  return (
    process.env.PROD_RDS_USER ||
    process.env.REPLAY_USER ||
    process.env.RDS_MIGRATOR_ROLE ||
    DEFAULT_MIGRATOR
  ).trim();
}

const REVOKE_ALL_ROUTINES_RE =
  /REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM [^;]+;?/gi;

function wrapRoutineRevokeForRdsMigrator(sql) {
  return String(sql || '').replace(REVOKE_ALL_ROUTINES_RE, (stmt) => {
    const line = stmt.trim().replace(/;+\s*$/u, '');
    return `DO $doctornect_revoke_routines$
BEGIN
  ${line};
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'RDS migrator: skipped blanket ROUTINE REVOKE (%).', SQLERRM;
END
$doctornect_revoke_routines$;`;
  });
}

function makeIndexAndTriggerStatementsIdempotent(sql) {
  let out = String(sql || '');
  out = out.replace(/\bCREATE UNIQUE INDEX (?!IF NOT EXISTS)/gi, 'CREATE UNIQUE INDEX IF NOT EXISTS ');
  out = out.replace(/\bCREATE INDEX (?!IF NOT EXISTS)/gi, 'CREATE INDEX IF NOT EXISTS ');
  out = out.replace(
    /CREATE TRIGGER\s+([^\s]+)\s+([\s\S]*?)\s+ON\s+([^\s(;]+)/gi,
    (full, name, middle, table) => {
      if (/DROP TRIGGER IF EXISTS\s+[^\s]+\s+ON\s+[^\s]+/i.test(full)) {
        return full;
      }
      const trimmedMiddle = String(middle || '').trim();
      return `DROP TRIGGER IF EXISTS ${name} ON ${table};\nCREATE TRIGGER ${name} ${trimmedMiddle} ON ${table}`;
    },
  );
  return out;
}

function normalizeRdsMigrationSql(sql, target) {
  if (!shouldNormalizeRdsSql(target)) return sql;
  const migrator = migratorRoleName();
  let out = makeIndexAndTriggerStatementsIdempotent(String(sql || ''));
  out = wrapRoutineRevokeForRdsMigrator(out);

  out = out.replace(/\bOWNER\s+TO\s+postgres\b/gi, `OWNER TO ${migrator}`);
  out = out.replace(/\bOWNER\s+postgres\b/gi, `OWNER ${migrator}`);

  out = out.replace(
    /\bALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+postgres\b/gi,
    `ALTER DEFAULT PRIVILEGES FOR ROLE ${migrator}`,
  );

  out = out.replace(/\bFOR\s+ROLE\s+postgres\b/gi, `FOR ROLE ${migrator}`);

  out = out.replace(/,\s*postgres\b/gi, '');
  out = out.replace(/\bpostgres\s*,/gi, '');
  out = out.replace(/\bTO\s+postgres\b/gi, `TO ${migrator}`);

  out = out.replace(
    /current_user\s+IN\s*\(\s*'service_role'\s*,\s*'postgres'\s*\)/gi,
    `current_user IN ('service_role', '${migrator}', 'rds_master', 'app_migrator')`,
  );
  out = out.replace(
    /current_user\s+IN\s*\(\s*'postgres'\s*,\s*'service_role'\s*\)/gi,
    `current_user IN ('service_role', '${migrator}', 'rds_master', 'app_migrator')`,
  );

  return out;
}

module.exports = {
  normalizeRdsMigrationSql,
  makeIndexAndTriggerStatementsIdempotent,
  shouldNormalizeRdsSql,
  migratorRoleName,
  RDS_SUPERUSER_ROLE,
  DEFAULT_MIGRATOR,
};