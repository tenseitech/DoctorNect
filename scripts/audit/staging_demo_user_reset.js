'use strict';

/**
 * Staging Supabase demo user reset — investigate | backup | dry-run | execute (execute gated).
 * Never targets prod RDS.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

const PHASE = (() => {
  const a = process.argv.find((x) => x.startsWith('--phase='));
  return a ? a.split('=')[1] : 'investigate';
})();

/** Matches Firebase Auth reviewer accounts (medibond-45fad); create-only — do not re-point phones. */
const FIREBASE_DEMO_UID_BY_DIGITS = {
  '9999900001': 'rev_fb_pat_001',
  '9999900002': 'rev_fb_doc_001',
  '9999900003': 'rev_fb_store_001',
  '9999900004': 'rev_fb_lab_001',
  '9999900005': 'rev_fb_amb_001',
};

const DEMO_PHONES = [
  { digits: '9999900001', role: 'patient', name: 'Demo Patient', email: 'demo.patient@doctornect.demo' },
  { digits: '9999900002', role: 'doctor', name: 'Demo Doctor', email: 'demo.doctor@doctornect.demo' },
  { digits: '9999900003', role: 'medicalStore', name: 'Demo Pharmacy', email: 'demo.pharmacy@doctornect.demo' },
  { digits: '9999900004', role: 'lab', name: 'Demo Lab', email: 'demo.lab@doctornect.demo' },
  { digits: '9999900005', role: 'ambulance', name: 'Demo Ambulance', email: 'demo.ambulance@doctornect.demo' },
];

const LEGACY_DEMO_PHONES = ['7058809803', '7666892394', '9359503874', '9409858233', '9307583929'];

const STAGING_ADMIN = {
  id: 'wfT7vh7pakYR64scZkXrFcOefDZ2',
  email: 'admin@doctornect.com',
  mobileDigits: '9359503874',
};

const KEY_TABLES = [
  'users',
  'patients',
  'doctors',
  'medical_stores',
  'labs',
  'ambulances',
  'appointments',
  'prescriptions',
  'notification_outbox',
  'system_config',
];

const ADMIN_TABLES = [
  { schema: 'public', table: 'users', cols: ['id', 'email', 'mobile', 'firebase_uid', 'profile_id'] },
  { schema: 'private', table: 'admin_users', cols: ['user_id', 'granted_by'] },
  { schema: 'public', table: 'admin_audit_logs', cols: ['admin_uid'] },
  { schema: 'public', table: 'security_events', cols: ['uid'] },
  { schema: 'public', table: 'support_tickets', cols: ['user_id'] },
  { schema: 'public', table: 'in_app_notifications', cols: ['recipient_uid'] },
  { schema: 'auth', table: 'users', cols: ['id', 'email', 'phone'] },
];

function extractSupabaseRef(dbUrl, supabaseUrl) {
  try {
    const u = new URL(supabaseUrl || '');
    const m = u.hostname.match(/^([a-z0-9]+)\.supabase\.co$/i);
    if (m) return m[1];
  } catch (_) {
    /* ignore */
  }
  try {
    const p = new URL(dbUrl);
    const host = p.hostname.toLowerCase();
    const m = host.match(/db\.([a-z0-9]+)\.supabase\.co/);
    if (m) return m[1];
    const pool = host.match(/^aws-0-[a-z0-9-]+\.pooler\.supabase\.com$/);
    if (pool && getEnv('STAGING_SUPABASE_URL')) {
      const u2 = new URL(getEnv('STAGING_SUPABASE_URL'));
      const m2 = u2.hostname.match(/^([a-z0-9]+)\.supabase\.co$/i);
      if (m2) return m2[1];
    }
  } catch (_) {
    /* ignore */
  }
  return '(unknown)';
}

function assertStagingOnly(dbUrl) {
  const host = (() => {
    try {
      return new URL(dbUrl).hostname.toLowerCase();
    } catch (_) {
      return '';
    }
  })();
  if (!host || host.includes('rds.amazonaws.com')) {
    console.error('[ABORT] Connection host looks like prod RDS — refusing.');
    process.exit(1);
  }
  if (!host.includes('supabase')) {
    console.error('[ABORT] Connection host is not a Supabase host — refusing.');
    process.exit(1);
  }
  const prodLogical = (getEnv('PROD_RDS_HOST') || '').toLowerCase();
  if (prodLogical && host === prodLogical.split(':')[0]) {
    console.error('[ABORT] STAGING URL host matches PROD_RDS_HOST — refusing.');
    process.exit(1);
  }
}

function stagingSsl() {
  return { rejectUnauthorized: false };
}

async function fkReport(client) {
  const q = `
    SELECT
      tc.table_schema,
      tc.table_name,
      kcu.column_name,
      ccu.table_schema AS ref_schema,
      ccu.table_name AS ref_table,
      ccu.column_name AS ref_column,
      rc.delete_rule
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name
    JOIN information_schema.referential_constraints rc
      ON rc.constraint_name = tc.constraint_name AND rc.constraint_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND (
        (ccu.table_schema = 'public' AND ccu.table_name = 'users')
        OR (ccu.table_schema = 'auth' AND ccu.table_name = 'users')
      )
    ORDER BY tc.table_schema, tc.table_name, kcu.column_name;
  `;
  return (await client.query(q)).rows;
}

async function tableExists(client, schema, name) {
  const r = await client.query(`SELECT to_regclass($1::text) IS NOT NULL AS ok`, [`${schema}.${name}`]);
  return r.rows[0].ok;
}

async function countTable(client, schema, name) {
  if (!(await tableExists(client, schema, name))) return { skip: true, count: null };
  const r = await client.query(`SELECT count(*)::bigint AS c FROM ${schema}.${name}`);
  return { skip: false, count: Number(r.rows[0].c) };
}

async function countUserOwned(client, table, col, uidSubquery) {
  const r = await client.query(
    `SELECT count(*)::bigint AS c FROM public.${table} t
     WHERE t.${col} IN (${uidSubquery})`,
  );
  return Number(r.rows[0].c);
}

async function investigate(client) {
  const fks = await fkReport(client);
  const keyTables = [
    'users',
    'patients',
    'doctors',
    'medical_stores',
    'labs',
    'ambulances',
    'appointments',
    'prescriptions',
    'health_records',
    'promoted_ads',
    'in_app_notifications',
    'admin_audit_logs',
    'otp_challenges',
    'notification_outbox',
    'provisioning_errors',
    'user_devices',
    'family_members',
  ];

  const counts = {};
  counts['auth.users'] = await countTable(client, 'auth', 'users');
  counts['public.users'] = await countTable(client, 'public', 'users');

  for (const t of keyTables) {
    counts[`public.${t}`] = await countTable(client, 'public', t);
  }

  const sysAdmin = await client.query(`
    SELECT id, email, role, is_system_admin, mobile, display_name, profile_completed, deactivated, status
    FROM public.users
    WHERE is_system_admin IS TRUE
       OR lower(trim(email)) = 'admin@doctornect.com'
    ORDER BY created_at ASC
  `);

  const usersByRole = await client.query(`
    SELECT role, count(*)::int AS c FROM public.users GROUP BY role ORDER BY role
  `);

  const legacyPhones = await client.query(
    `
    SELECT id, email, role, mobile, display_name, is_system_admin
    FROM public.users
  WHERE mobile IS NOT NULL AND (
      regexp_replace(mobile, '\\D', '', 'g') = ANY($1::text[])
      OR right(regexp_replace(mobile, '\\D', '', 'g'), 10) = ANY($1::text[])
    )
    ORDER BY mobile
  `,
    [LEGACY_DEMO_PHONES],
  );

  const targetPhones = await client.query(
    `
    SELECT id, email, role, mobile, display_name
    FROM public.users
    WHERE mobile IS NOT NULL AND (
      right(regexp_replace(mobile, '\\D', '', 'g'), 10) = ANY($1::text[])
    )
  `,
    [DEMO_PHONES.map((d) => d.digits)],
  );

  let systemConfigDemo = { skip: true };
  if (await tableExists(client, 'public', 'system_config')) {
    const sc = await client.query(
      `SELECT config_key, jsonb_typeof(config_value) AS t,
              left(config_value::text, 200) AS preview
       FROM public.system_config
       WHERE config_key IN ('demo_accounts', 'promoted_ads', 'patient_module_status')`,
    );
    systemConfigDemo = { rows: sc.rows };
  }

  const triggers = await client.query(`
    SELECT tgname, pg_get_triggerdef(oid, true) AS def
    FROM pg_trigger
    WHERE tgrelid = 'public.users'::regclass AND NOT tgisinternal
    ORDER BY tgname
  `);

  const uidColSamples = {};
  for (const roleTable of ['patients', 'doctors', 'medical_stores', 'labs', 'ambulances']) {
    const cols = await client.query(
      `
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = $1
      ORDER BY ordinal_position
    `,
      [roleTable],
    );
    uidColSamples[roleTable] = cols.rows;
  }

  const userCols = await client.query(`
    SELECT column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users'
    ORDER BY ordinal_position
  `);

  const authCols = await client.query(`
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'users'
    ORDER BY ordinal_position
  `);

  const deleteImpact = {};
  const nonAdmin = `
    SELECT id FROM public.users
    WHERE NOT (
      is_system_admin IS TRUE
      OR lower(trim(email)) = 'admin@doctornect.com'
    )
  `;
  for (const row of fks) {
    if (row.ref_schema !== 'public' || row.ref_table !== 'users') continue;
    const full = `${row.table_schema}.${row.table_name}`;
    try {
      const r = await client.query(
        `SELECT count(*)::bigint AS c FROM ${full} t
         WHERE t.${row.column_name} IN (${nonAdmin})`,
      );
      deleteImpact[full] = { column: row.column_name, delete_rule: row.delete_rule, rows: Number(r.rows[0].c) };
    } catch (e) {
      deleteImpact[full] = { error: e.message, delete_rule: row.delete_rule };
    }
  }

  return {
    fks,
    counts,
    sysAdmin: sysAdmin.rows,
    usersByRole: usersByRole.rows,
    legacyPhones: legacyPhones.rows,
    targetPhones: targetPhones.rows,
    systemConfigDemo,
    triggers: triggers.rows.map((r) => ({ name: r.tgname, def: r.def })),
    userCols: userCols.rows,
    authCols: authCols.rows,
    roleTableColumns: uidColSamples,
    deleteImpact,
  };
}

function demoUidForPhone(digits) {
  return FIREBASE_DEMO_UID_BY_DIGITS[digits] || `demo_staging_${digits}`;
}

function profileIdForRole(role, digits) {
  const map = {
    patient: `demo_pat_${digits}`,
    doctor: `demo_doc_${digits}`,
    medicalStore: `demo_store_${digits}`,
    lab: `demo_lab_${digits}`,
    ambulance: `demo_amb_${digits}`,
  };
  return map[role] || `demo_${digits}`;
}

function mobileE164(digits) {
  return `+91${digits}`;
}

async function tableRowCounts(client, tables = KEY_TABLES, extra = []) {
  const names = [...new Set([...tables, ...extra])];
  const out = {};
  for (const t of names) {
    const parts = t.includes('.') ? t.split('.') : ['public', t];
    out[t] = (await countTable(client, parts[0], parts[1])).count;
  }
  const au = await countTable(client, 'private', 'admin_users');
  out['private.admin_users'] = au.count;
  const authU = await countTable(client, 'auth', 'users');
  out['auth.users'] = authU.count;
  return out;
}

async function adminFootprint(client) {
  const needles = [
    STAGING_ADMIN.id,
    STAGING_ADMIN.email,
    STAGING_ADMIN.mobileDigits,
    mobileE164(STAGING_ADMIN.mobileDigits),
    `+91${STAGING_ADMIN.mobileDigits}`,
  ];
  const byTable = {};
  for (const { schema, table, cols } of ADMIN_TABLES) {
    if (!(await tableExists(client, schema, table))) {
      byTable[`${schema}.${table}`] = { skip: true };
      continue;
    }
    const parts = [];
    const params = [];
    let i = 1;
    for (const col of cols) {
      for (const n of needles) {
        parts.push(`${col}::text = $${i}`);
        params.push(n);
        i += 1;
      }
      if (col === 'phone' || col === 'mobile') {
        for (const n of [STAGING_ADMIN.mobileDigits, mobileE164(STAGING_ADMIN.mobileDigits)]) {
          parts.push(`right(regexp_replace(${col}::text, '\\D', '', 'g'), 10) = $${i}`);
          params.push(STAGING_ADMIN.mobileDigits);
          i += 1;
          break;
        }
      }
    }
    const sql = `SELECT count(*)::int AS c FROM ${schema}.${table} WHERE ${parts.join(' OR ')}`;
    try {
      const r = await client.query(sql, params);
      byTable[`${schema}.${table}`] = { count: r.rows[0].c, cols: cols };
    } catch (e) {
      byTable[`${schema}.${table}`] = { error: e.code, message: e.message };
    }
  }

  const dynamic = [];
  const colRes = await client.query(`
    SELECT table_schema, table_name, column_name, data_type
    FROM information_schema.columns
    WHERE table_schema IN ('public', 'private', 'auth')
      AND table_name NOT IN ('_schema_migrations')
      AND (
        data_type IN ('text', 'character varying', 'uuid')
        OR udt_name = 'uuid'
      )
    ORDER BY 1, 2, 3
  `);
  const seen = new Set(ADMIN_TABLES.map((t) => `${t.schema}.${t.table}`));
  for (const row of colRes.rows) {
    const full = `${row.table_schema}.${row.table_name}`;
    if (seen.has(full)) continue;
    const cond = needles.map((_, idx) => `${row.column_name}::text = $${idx + 1}`).join(' OR ');
    const sql = `SELECT count(*)::int AS c FROM ${row.table_schema}."${row.table_name}" WHERE ${cond}`;
    try {
      const r = await client.query(sql, needles);
      if (r.rows[0].c > 0) {
        dynamic.push({ table: full, column: row.column_name, count: r.rows[0].c });
      }
    } catch (_) {
      /* skip */
    }
  }

  const fks = await fkReport(client);
  const fkToUsers = fks.filter((f) => f.ref_schema === 'public' && f.ref_table === 'users');

  const triggers = await client.query(`
    SELECT tgname, tgenabled
    FROM pg_trigger
    WHERE tgrelid = 'public.users'::regclass
      AND tgname IN ('users_protect_system_admin', 'users_protect_system_admin_delete')
    ORDER BY tgname
  `);

  const priv = await client.query(`
    SELECT
      current_user,
      has_table_privilege(current_user, 'public.users', 'TRIGGER') AS can_alter_trigger,
      has_table_privilege(current_user, 'public.users', 'TRIGGER') AS can_disable_user_triggers
  `);

  return { byTable, dynamic_hits: dynamic, fk_to_public_users: fkToUsers, triggers: triggers.rows, privileges: priv.rows[0] };
}

function buildPlanSqlNoAdmin() {
  const admin = STAGING_ADMIN.id.replace(/'/g, "''");
  const demoIds = DEMO_PHONES.map((d) => `'${demoUidForPhone(d.digits).replace(/'/g, "''")}'`).join(', ');
  const lines = [];
  lines.push('BEGIN;');
  lines.push('-- 0) Orphan profiles (no owner in demo set)');
  lines.push(`DELETE FROM public.doctors WHERE owner_uid IS NULL OR owner_uid NOT IN (${demoIds});`);
  lines.push(`DELETE FROM public.medical_stores WHERE owner_uid IS NULL OR owner_uid NOT IN (${demoIds});`);
  lines.push(`DELETE FROM public.labs WHERE owner_uid IS NULL OR owner_uid NOT IN (${demoIds});`);
  lines.push(`DELETE FROM public.ambulances WHERE auth_uid IS NULL OR auth_uid NOT IN (${demoIds});`);
  lines.push(`DELETE FROM public.patients WHERE owner_uid IS NULL OR owner_uid NOT IN (${demoIds});`);
  lines.push('-- 1) Admin-linked rows');
  lines.push(`DELETE FROM public.in_app_notifications WHERE recipient_uid = '${admin}';`);
  lines.push(`DELETE FROM public.admin_audit_logs WHERE admin_uid = '${admin}';`);
  lines.push(`DELETE FROM public.security_events WHERE uid = '${admin}';`);
  lines.push(`UPDATE public.support_tickets SET user_id = NULL WHERE user_id = '${admin}';`);
  lines.push(`DELETE FROM private.admin_users WHERE user_id = '${admin}' OR granted_by = '${admin}';`);
  lines.push(`DELETE FROM public.super_admins WHERE user_uid = '${admin}';`);
  lines.push('CREATE TEMP TABLE _non_demo_user_deletes (id text PRIMARY KEY) ON COMMIT DROP;');
  lines.push('-- 2) Bypass system-admin delete protection (re-enable before COMMIT)');
  lines.push('ALTER TABLE public.users DISABLE TRIGGER users_protect_system_admin;');
  lines.push('ALTER TABLE public.users DISABLE TRIGGER users_protect_system_admin_delete;');
  lines.push(`
WITH deleted AS (
  DELETE FROM public.users
  WHERE id = '${admin}' OR is_system_admin IS TRUE OR lower(trim(email)) = 'admin@doctornect.com'
  RETURNING id
)
INSERT INTO _non_demo_user_deletes SELECT id FROM deleted;
`);
  lines.push(`
WITH deleted AS (
  DELETE FROM public.users WHERE id NOT IN (${demoIds})
  RETURNING id
)
INSERT INTO _non_demo_user_deletes SELECT id FROM deleted ON CONFLICT DO NOTHING;
`);
  lines.push(`DELETE FROM auth.users WHERE lower(trim(email)) = 'admin@doctornect.com';`);
  lines.push('ALTER TABLE public.users ENABLE TRIGGER users_protect_system_admin;');
  lines.push('ALTER TABLE public.users ENABLE TRIGGER users_protect_system_admin_delete;');
  lines.push('-- 3) Upsert 5 demo users + profiles');
  for (const d of DEMO_PHONES) {
    const uid = demoUidForPhone(d.digits);
    const pid = profileIdForRole(d.role, d.digits);
    const mob = mobileE164(d.digits);
    lines.push(`
INSERT INTO public.users (
  id, firebase_uid, role, profile_id, display_name, email, mobile,
  profile_completed, verified, status, deactivated, created_at, updated_at, is_system_admin
) VALUES (
  '${uid}', '${uid}', '${d.role}', '${pid}', '${d.name}', '${d.email}', '${mob}',
  true, true, 'approved', false, NOW(), NOW(), false
) ON CONFLICT (id) DO UPDATE SET
  role = EXCLUDED.role,
  profile_id = EXCLUDED.profile_id,
  display_name = EXCLUDED.display_name,
  email = EXCLUDED.email,
  mobile = EXCLUDED.mobile,
  profile_completed = true,
  verified = true,
  status = 'approved',
  is_system_admin = false,
  updated_at = NOW();
`);
    if (d.role === 'patient') {
      lines.push(`
INSERT INTO public.patients (patient_id, owner_uid, name, mobile, verified)
VALUES ('${pid}', '${uid}', '${d.name}', '${mob}', true)
ON CONFLICT (patient_id) DO UPDATE SET owner_uid = EXCLUDED.owner_uid, name = EXCLUDED.name, mobile = EXCLUDED.mobile;
`);
    } else if (d.role === 'doctor') {
      lines.push(`
INSERT INTO public.doctors (
  doctor_id, owner_uid, name, email, mobile, specialization, qualification,
  verified, deactivated, experience_years
) VALUES (
  '${pid}', '${uid}', '${d.name}', '${d.email}', '${mob}', 'General Medicine', 'MBBS',
  true, false, 5
) ON CONFLICT (doctor_id) DO UPDATE SET
  owner_uid = EXCLUDED.owner_uid, verified = true, name = EXCLUDED.name, mobile = EXCLUDED.mobile;
`);
    } else if (d.role === 'medicalStore') {
      lines.push(`
INSERT INTO public.medical_stores (
  store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified
) VALUES (
  '${pid}', '${uid}', '${d.name}', 'Demo Owner', 'DL-DEMO-${d.digits}', '${mob}', '${d.email}', true
) ON CONFLICT (store_id) DO UPDATE SET owner_uid = EXCLUDED.owner_uid, verified = true;
`);
    } else if (d.role === 'lab') {
      lines.push(`
INSERT INTO public.labs (
  lab_id, owner_uid, lab_name, license_number, phone, email, verified
) VALUES (
  '${pid}', '${uid}', '${d.name}', 'LAB-DEMO-${d.digits}', '${mob}', '${d.email}', true
) ON CONFLICT (lab_id) DO UPDATE SET owner_uid = EXCLUDED.owner_uid, verified = true;
`);
    } else if (d.role === 'ambulance') {
      lines.push(`
INSERT INTO public.ambulances (
  ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified, is_available, profile_completed
) VALUES (
  '${pid}', '${uid}', '${d.name}', 'Demo Driver', '${mob}', 'DL01D${d.digits.slice(-4)}', 'bls', 'Delhi', true, true, true
) ON CONFLICT (ambulance_id) DO UPDATE SET auth_uid = EXCLUDED.auth_uid, verified = true, profile_completed = true;
`);
    }
  }
  lines.push('-- 4) Pre-COMMIT guards (failure aborts transaction)');
  lines.push(`
DO $guard$
DECLARE
  del_count int;
  bad_demo int;
  trig_ok int;
BEGIN
  SELECT count(*)::int INTO del_count FROM _non_demo_user_deletes;
  IF del_count <> 1 THEN
    RAISE EXCEPTION 'GUARD_FAIL: expected exactly 1 non-demo public.users delete, got %', del_count;
  END IF;
  IF (SELECT count(*)::int FROM _non_demo_user_deletes WHERE id = '${admin}') <> 1 THEN
    RAISE EXCEPTION 'GUARD_FAIL: deleted user was not the platform admin id';
  END IF;
  IF (SELECT count(*)::int FROM _non_demo_user_deletes WHERE id IN (${demoIds})) > 0 THEN
    RAISE EXCEPTION 'GUARD_FAIL: a demo user id was deleted';
  END IF;
  SELECT count(*)::int INTO bad_demo FROM public.users
  WHERE id IN (${demoIds})
    AND (is_system_admin IS TRUE OR lower(trim(email)) = 'admin@doctornect.com');
  IF bad_demo > 0 THEN
    RAISE EXCEPTION 'GUARD_FAIL: demo user has admin flags';
  END IF;
  IF (SELECT count(*)::int FROM public.users) <> 5 THEN
    RAISE EXCEPTION 'GUARD_FAIL: expected 5 public.users rows, got %', (SELECT count(*) FROM public.users);
  END IF;
  IF (SELECT count(*)::int FROM public.users WHERE id NOT IN (${demoIds})) > 0 THEN
    RAISE EXCEPTION 'GUARD_FAIL: non-demo user rows remain in public.users';
  END IF;
  SELECT count(*)::int INTO trig_ok
  FROM pg_trigger
  WHERE tgrelid = 'public.users'::regclass
    AND tgname IN ('users_protect_system_admin', 'users_protect_system_admin_delete')
    AND tgenabled = 'O';
  IF trig_ok <> 2 THEN
    RAISE EXCEPTION 'GUARD_FAIL: protect triggers not enabled (tgenabled=O), count=%', trig_ok;
  END IF;
END $guard$;
`);
  lines.push('ROLLBACK; -- dry-run; execute phase uses COMMIT');
  return lines.join('\n');
}

async function dryRunNoAdmin(client) {
  const before = await tableRowCounts(client);
  const plan = buildPlanSqlNoAdmin();
  const body = plan
    .replace(/^BEGIN;\n/, '')
    .replace(/\nROLLBACK;[^\n]*\n?$/, '');
  await client.query('BEGIN');
  try {
    await client.query(body);
    const afterInsideTxn = await tableRowCounts(client);
    const triggers = await client.query(`
      SELECT tgname, tgenabled
      FROM pg_trigger
      WHERE tgrelid = 'public.users'::regclass
        AND tgname IN ('users_protect_system_admin', 'users_protect_system_admin_delete')
      ORDER BY tgname
    `);
    await client.query('ROLLBACK');
    const after = await tableRowCounts(client);
    return {
      before,
      after_expected_if_committed: afterInsideTxn,
      after_connection_state: after,
      triggers_after_rollback: triggers.rows,
      planSql: `BEGIN;\n${body}\nCOMMIT;`,
    };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  }
}

function buildPlanSql(superAdminIds) {
  const keepSet = superAdminIds.map((id) => `'${id.replace(/'/g, "''")}'`).join(', ');
  const keepPredicate =
    keepSet.length > 0
      ? `(owner_uid IS NULL OR owner_uid NOT IN (${keepSet}))`
      : 'TRUE';
  const keepAuth =
    keepSet.length > 0
      ? `(auth_uid IS NULL OR auth_uid NOT IN (${keepSet}))`
      : 'TRUE';
  const lines = [];
  lines.push('BEGIN;');
  lines.push('-- 0) Orphan / stale role profiles (no owning user row, or not super admin)');
  lines.push(`DELETE FROM public.doctors WHERE ${keepPredicate};`);
  lines.push(`DELETE FROM public.medical_stores WHERE ${keepPredicate};`);
  lines.push(`DELETE FROM public.labs WHERE ${keepPredicate};`);
  lines.push(`DELETE FROM public.ambulances WHERE ${keepAuth};`);
  lines.push(`DELETE FROM public.patients WHERE ${keepPredicate};`);
  lines.push('-- 1) Remove user-owned rows (non–system-admin users only)');
  lines.push(`
DELETE FROM public.users u
WHERE NOT (u.is_system_admin IS TRUE OR lower(trim(u.email)) = 'admin@doctornect.com')
  AND u.id NOT IN (${keepSet || "''"});
`);
  if (keepSet) {
    lines.push(`
DELETE FROM auth.users au
WHERE au.id::text NOT IN (${keepSet})
  AND NOT EXISTS (
    SELECT 1 FROM public.users pu
    WHERE pu.id = au.id::text
      AND (pu.is_system_admin IS TRUE OR lower(trim(pu.email)) = 'admin@doctornect.com')
  );
`);
  }
  lines.push('-- 2) Insert 5 demo users + profiles');
  for (const d of DEMO_PHONES) {
    const uid = demoUidForPhone(d.digits);
    const pid = profileIdForRole(d.role, d.digits);
    const mob = mobileE164(d.digits);
    lines.push(`
INSERT INTO public.users (
  id, firebase_uid, role, profile_id, display_name, email, mobile,
  profile_completed, verified, status, deactivated, created_at, updated_at
) VALUES (
  '${uid}', '${uid}', '${d.role}', '${pid}', '${d.name}', '${d.email}', '${mob}',
  true, true, 'approved', false, NOW(), NOW()
) ON CONFLICT (id) DO UPDATE SET
  role = EXCLUDED.role,
  profile_id = EXCLUDED.profile_id,
  display_name = EXCLUDED.display_name,
  email = EXCLUDED.email,
  mobile = EXCLUDED.mobile,
  profile_completed = true,
  verified = true,
  status = 'approved',
  updated_at = NOW();
`);
    if (d.role === 'patient') {
      lines.push(`
INSERT INTO public.patients (patient_id, owner_uid, name, mobile, verified)
VALUES ('${pid}', '${uid}', '${d.name}', '${mob}', true)
ON CONFLICT (patient_id) DO UPDATE SET owner_uid = EXCLUDED.owner_uid, name = EXCLUDED.name, mobile = EXCLUDED.mobile;
`);
    } else if (d.role === 'doctor') {
      lines.push(`
INSERT INTO public.doctors (
  doctor_id, owner_uid, name, email, mobile, specialization, qualification,
  verified, deactivated, experience_years
) VALUES (
  '${pid}', '${uid}', '${d.name}', '${d.email}', '${mob}', 'General Medicine', 'MBBS',
  true, false, 5
) ON CONFLICT (doctor_id) DO UPDATE SET
  owner_uid = EXCLUDED.owner_uid, verified = true, name = EXCLUDED.name, mobile = EXCLUDED.mobile;
`);
    } else if (d.role === 'medicalStore') {
      lines.push(`
INSERT INTO public.medical_stores (
  store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified
) VALUES (
  '${pid}', '${uid}', '${d.name}', 'Demo Owner', 'DL-DEMO-${d.digits}', '${mob}', '${d.email}', true
) ON CONFLICT (store_id) DO UPDATE SET owner_uid = EXCLUDED.owner_uid, verified = true;
`);
    } else if (d.role === 'lab') {
      lines.push(`
INSERT INTO public.labs (
  lab_id, owner_uid, lab_name, license_number, phone, email, verified
) VALUES (
  '${pid}', '${uid}', '${d.name}', 'LAB-DEMO-${d.digits}', '${mob}', '${d.email}', true
) ON CONFLICT (lab_id) DO UPDATE SET owner_uid = EXCLUDED.owner_uid, verified = true;
`);
    } else if (d.role === 'ambulance') {
      lines.push(`
INSERT INTO public.ambulances (
  ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified, is_available, profile_completed
) VALUES (
  '${pid}', '${uid}', '${d.name}', 'Demo Driver', '${mob}', 'DL01D${d.digits.slice(-4)}', 'bls', 'Delhi', true, true, true
) ON CONFLICT (ambulance_id) DO UPDATE SET auth_uid = EXCLUDED.auth_uid, verified = true, profile_completed = true;
`);
    }
  }
  lines.push('ROLLBACK; -- dry-run; execute phase uses COMMIT');
  return lines.join('\n');
}

async function dryRun(client, superAdminRows) {
  const ids = superAdminRows.map((r) => r.id);
  const plan = buildPlanSql(ids);
  await client.query(plan.replace('ROLLBACK; -- dry-run; execute phase uses COMMIT', 'ROLLBACK'));
  const after = await client.query(`SELECT count(*)::int AS c FROM public.users`);
  const authC = await countTable(client, 'auth', 'users');
  return {
    usersAfterDryRunStillOriginal: after.rows[0].c,
    authUsersCount: authC.count,
    planSql: buildPlanSql(ids).replace('ROLLBACK; -- dry-run; execute phase uses COMMIT', 'COMMIT;'),
  };
}

function resolvePgBin(name) {
  const pgHome = process.env.PG18_BIN || 'C:\\Program Files\\PostgreSQL\\18\\bin';
  const candidate = path.join(pgHome, `${name}.exe`);
  if (fs.existsSync(candidate)) return candidate;
  return name;
}

function runPgDump(dbUrl, outFile) {
  const parsed = new URL(dbUrl);
  const env = { ...process.env, PGPASSWORD: parsed.password || '' };
  const pgDumpBin = resolvePgBin('pg_dump');
  const pgArgs = [
    '-h',
    parsed.hostname,
    '-p',
    parsed.port || '5432',
    '-U',
    decodeURIComponent(parsed.username),
    '-d',
    parsed.pathname.replace(/^\//, ''),
    '-Fc',
    '--no-owner',
    '--no-acl',
    '-f',
    outFile,
  ];
  const ssl = parsed.searchParams.get('sslmode');
  if (ssl) env.PGSSLMODE = ssl;
  else env.PGSSLMODE = 'require';

  let r = spawnSync(pgDumpBin, pgArgs, { env, encoding: 'utf8' });
  if (r.status === 0 || r.error?.code !== 'ENOENT') {
    return { code: r.status, stderr: (r.stderr || '').slice(0, 2000), outFile, via: 'host_pg_dump' };
  }

  const dir = path.dirname(outFile);
  const base = path.basename(outFile);
  const dockerArgs = [
    'run',
    '--rm',
    '-e',
    `PGPASSWORD=${parsed.password || ''}`,
    '-e',
    `PGSSLMODE=${env.PGSSLMODE}`,
    '-v',
    `${dir}:/backup`,
    'postgres:16',
    'pg_dump',
    ...pgArgs.slice(0, -1),
    '-f',
    `/backup/${base}`,
  ];
  r = spawnSync('docker', dockerArgs, { encoding: 'utf8' });
  return { code: r.status, stderr: (r.stderr || '').slice(0, 2000), outFile, via: 'docker_postgres_16' };
}

function pgRestoreList(dumpFile) {
  const pgRestoreBin = resolvePgBin('pg_restore');
  let r = spawnSync(pgRestoreBin, ['--list', dumpFile], { encoding: 'utf8' });
  if (r.error?.code === 'ENOENT') {
    const dir = path.dirname(dumpFile);
    const base = path.basename(dumpFile);
    r = spawnSync(
      'docker',
      ['run', '--rm', '-v', `${dir}:/backup`, 'postgres:16', 'pg_restore', '--list', `/backup/${base}`],
      { encoding: 'utf8' },
    );
  }
  const lines = (r.stdout || '').split('\n').filter(Boolean);
  return { code: r.status, lineCount: lines.length, stderr: (r.stderr || '').slice(0, 500) };
}

async function main() {
  const destructive =
    PHASE === 'dry-run' || PHASE === 'execute' || PHASE === 'dry-run-no-admin' || PHASE === 'execute-no-admin';
  const guard = assertDatabaseGuard({
    targetKind: 'staging',
    operationName: `staging_demo_user_reset:${PHASE}`,
    allowDestructive: destructive,
  });
  const dbUrl = guard.dbUrl;
  assertStagingOnly(dbUrl);

  const ref = extractSupabaseRef(dbUrl, getEnv('STAGING_SUPABASE_URL') || getEnv('SUPABASE_URL'));
  console.log(JSON.stringify({
    phase: PHASE,
    target: 'staging_supabase_only',
    masked_connection: maskConnectionString(dbUrl),
    project_ref: ref,
    not_prod_rds: true,
  }, null, 2));

  if (PHASE === 'backup') {
    const dirArg = process.argv.find((a) => a.startsWith('--backup-dir='));
    const date = new Date().toISOString().slice(0, 10);
    const dir = dirArg
      ? dirArg.split('=').slice(1).join('=')
      : `C:\\Users\\khije\\Backups\\staging-before-demo-reset-${date}`;
    fs.mkdirSync(dir, { recursive: true });
    const dumpPath = path.join(dir, 'staging_full.dump');
    console.log(`Backup target file: ${dumpPath}`);
    const dump = runPgDump(dbUrl, dumpPath);
    if (dump.code !== 0) {
      console.error('[FAIL] pg_dump exited', dump.code);
      console.error(dump.stderr);
      process.exit(1);
    }
    const stat = fs.statSync(dumpPath);
    const list = pgRestoreList(dumpPath);
    if (list.code !== 0) {
      console.error('[FAIL] pg_restore --list', list.stderr);
      process.exit(1);
    }
    console.log(JSON.stringify({
      backup_bytes: stat.size,
      pg_restore_list_lines: list.lineCount,
      backup_dir: dir,
    }, null, 2));
    return;
  }

  const pool = new Pool({ connectionString: dbUrl, ssl: stagingSsl(), max: 2 });
  const client = await pool.connect();
  try {
    if (PHASE === 'investigate') {
      const report = await investigate(client);
      console.log(JSON.stringify(report, null, 2));
      return;
    }
    if (PHASE === 'admin-footprint') {
      const fp = await adminFootprint(client);
      console.log(JSON.stringify(fp, null, 2));
      return;
    }
    if (PHASE === 'dry-run-no-admin') {
      const fp = await adminFootprint(client);
      const dr = await dryRunNoAdmin(client);
      console.log(JSON.stringify({ admin_footprint: fp, dry_run: dr }, null, 2));
      console.log('\n--- EXECUTE SQL (NO ADMIN, COMMIT) — approval only ---\n');
      console.log(dr.planSql);
      console.log('\n--- Waiting for APPROVED: STAGING USER RESET (NO ADMIN) ---\n');
      return;
    }
    if (PHASE === 'dry-run') {
      const inv = await investigate(client);
      const dr = await dryRun(client, inv.sysAdmin);
      console.log(JSON.stringify({
        pre_users: inv.counts['public.users'],
        pre_auth_users: inv.counts['auth.users'],
        sys_admin_keep: inv.sysAdmin,
        delete_impact: inv.deleteImpact,
        legacy_phone_users: inv.legacyPhones,
        dry_run_users_count_unchanged: dr.usersAfterDryRunStillOriginal,
        demo_users_planned: DEMO_PHONES.map((d) => ({
          phone: d.digits,
          role: d.role,
          uid: demoUidForPhone(d.digits),
          profile_id: profileIdForRole(d.role, d.digits),
          mobile: mobileE164(d.digits),
        })),
        execute_sql_file_hint: 'See plan below',
      }, null, 2));
      console.log('\n--- EXECUTE SQL (COMMIT) — for approval only ---\n');
      console.log(dr.planSql);
      console.log('\n--- Waiting for APPROVED: STAGING USER RESET ---\n');
      return;
    }
    if (PHASE === 'execute') {
      if (!process.argv.includes('--approved-staging-user-reset')) {
        console.error('[BLOCKED] Missing --approved-staging-user-reset');
        process.exit(1);
      }
      const inv = await investigate(client);
      const before = {
        users: inv.counts['public.users']?.count,
        doctors: inv.counts['public.doctors']?.count,
        medical_stores: inv.counts['public.medical_stores']?.count,
        labs: inv.counts['public.labs']?.count,
        patients: inv.counts['public.patients']?.count,
        ambulances: inv.counts['public.ambulances']?.count,
        notification_outbox: inv.counts['public.notification_outbox']?.count,
        system_config: (await countTable(client, 'public', 'system_config')).count,
      };
      const planSql = buildPlanSql(inv.sysAdmin.map((r) => r.id)).replace(
        'ROLLBACK; -- dry-run; execute phase uses COMMIT',
        'COMMIT;',
      );
      await client.query(planSql);
      const invAfter = await investigate(client);
      const after = {
        users: invAfter.counts['public.users']?.count,
        doctors: invAfter.counts['public.doctors']?.count,
        medical_stores: invAfter.counts['public.medical_stores']?.count,
        labs: invAfter.counts['public.labs']?.count,
        patients: invAfter.counts['public.patients']?.count,
        ambulances: invAfter.counts['public.ambulances']?.count,
        notification_outbox: invAfter.counts['public.notification_outbox']?.count,
        system_config: (await countTable(client, 'public', 'system_config')).count,
      };
      console.log(JSON.stringify({ phase: 'execute', committed: true, before, after, sys_admin: invAfter.sysAdmin }, null, 2));
      return;
    }
    if (PHASE === 'execute-no-admin') {
      if (!process.argv.includes('--approved-staging-user-reset-no-admin')) {
        console.error('[BLOCKED] Missing --approved-staging-user-reset-no-admin');
        process.exit(1);
      }
      const before = await tableRowCounts(client);
      before['public.super_admins'] = (await countTable(client, 'public', 'super_admins')).count;
      const planSql = buildPlanSqlNoAdmin().replace(
        'ROLLBACK; -- dry-run; execute phase uses COMMIT',
        'COMMIT;',
      );
      await client.query(planSql);
      const after = await tableRowCounts(client);
      after['public.super_admins'] = (await countTable(client, 'public', 'super_admins')).count;
      const triggers = await client.query(`
        SELECT tgname, tgenabled
        FROM pg_trigger
        WHERE tgrelid = 'public.users'::regclass
          AND tgname IN ('users_protect_system_admin', 'users_protect_system_admin_delete')
        ORDER BY tgname
      `);
      console.log(
        JSON.stringify({
          phase: 'execute-no-admin',
          committed: true,
          before,
          after,
          triggers,
        }, null, 2),
      );
      return;
    }
    console.error('Unknown --phase');
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error('[FAIL]', e.message);
  process.exit(1);
});