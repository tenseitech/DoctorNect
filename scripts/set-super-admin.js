'use strict';

/**
 * Idempotent Super Admin bootstrap (staging by default).
 *
 * - Firebase Auth: create/update user, password from SUPER_ADMIN_PASSWORD (.env only)
 * - Custom claims: role=authenticated, app_role/user_role=super_admin
 * - Postgres (staging): public.users, public.super_admins, private.admin_users
 *
 * Usage:
 *   node scripts/set-super-admin.js --confirm-live-data            # dry-run preview
 *   node scripts/set-super-admin.js --confirm-live-data --execute  # apply
 *
 * Env (gitignored .env in repo root):
 *   SUPER_ADMIN_EMAIL
 *   SUPER_ADMIN_PASSWORD
 *   STAGING_SUPABASE_DB_URL (repo root .env)
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { bootstrapMutatingScript } = require('./lib/mutating_script_bootstrap');
const { getEnv, maskConnectionString } = require('./lib/env_loader');

const args = process.argv.slice(2);
const isExecute = args.includes('--execute');
const targetArg = args.find((a) => a.startsWith('--target='));
const target = targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging';

function supabaseCompatibleCustomClaims(extra) {
  return {
    role: 'authenticated',
    app_role: 'super_admin',
    user_role: 'super_admin',
  ...(extra || {}),
  };
}

function initFirebaseAdmin() {
  const admin = require('firebase-admin');
  if (admin.apps.length > 0) return admin;

  const candidates = [
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    path.join(__dirname, 'service-account.json'),
    path.join(__dirname, '..', 'service-account.json'),
  ];
  const saPath = candidates.find((p) => p && fs.existsSync(p));
  if (saPath) {
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId: sa.project_id || 'medibond-45fad',
    });
  } else {
    admin.initializeApp({ projectId: getEnv('FIREBASE_PROJECT_ID') || 'medibond-45fad' });
  }
  return admin;
}

async function reportOtherSuperAdmins(client, primaryEmail) {
  const res = await client.query(
    `SELECT id, email, role, display_name
     FROM public.users
     WHERE role IN ('super_admin', 'superAdmin', 'admin')
       AND lower(email) <> lower($1)
     ORDER BY created_at ASC`,
    [primaryEmail],
  );
  if (res.rows.length === 0) {
    console.log('[Report] No other super_admin rows in public.users.');
    return;
  }
  console.log(`[Report] Other super_admin accounts in public.users (${res.rows.length}) — not deleted:`);
  for (const row of res.rows) {
    console.log(`  - uid=${row.id} email=${row.email} role=${row.role} name=${row.display_name || ''}`);
  }
}

async function syncPostgres(client, uid, email, displayName, dryRun) {
  const now = new Date().toISOString();
  const profileId = uid;

  const statements = [
    {
      label: 'public.users upsert',
      sql: `INSERT INTO public.users (
              id, firebase_uid, role, profile_id, display_name, email, mobile,
              profile_completed, verified, status, created_at, updated_at
            ) VALUES (
              $1::text, $1::text, 'super_admin', $1::varchar, $2::varchar, lower($3::text), '+919999999999',
              true, true, 'approved', $4::timestamptz, $4::timestamptz
            )
            ON CONFLICT (id) DO UPDATE SET
              firebase_uid = EXCLUDED.firebase_uid,
              role = 'super_admin',
              profile_id = EXCLUDED.profile_id,
              display_name = EXCLUDED.display_name,
              email = EXCLUDED.email,
              verified = true,
              status = 'approved',
              profile_completed = true,
              updated_at = EXCLUDED.updated_at`,
      params: [uid, displayName, email, now],
    },
    {
      label: 'public.super_admins upsert',
      sql: `INSERT INTO public.super_admins (user_uid, created_at, created_by)
            VALUES ($1, NOW(), NULL)
            ON CONFLICT (user_uid) DO NOTHING`,
      params: [uid],
    },
    {
      label: 'private.admin_users upsert',
      sql: `INSERT INTO private.admin_users (user_id, granted_by, granted_at)
            VALUES ($1, NULL, NOW())
            ON CONFLICT (user_id) DO NOTHING`,
      params: [uid],
    },
  ];

  for (const st of statements) {
    if (dryRun) {
      console.log(`[DRY-RUN] Would run: ${st.label}`);
    } else {
      await client.query(st.sql, st.params);
      console.log(`[OK] ${st.label}`);
    }
  }

  await reportOtherSuperAdmins(client, email);
}

async function main() {
  const guard = bootstrapMutatingScript('scripts/set-super-admin.js');
  const dryRun = guard.dryRun !== false || !isExecute;

  if (target !== 'staging') {
    console.error(`Only --target=staging is supported from this workstation script. Got: ${target}`);
    process.exit(1);
  }

  const email = (getEnv('SUPER_ADMIN_EMAIL') || 'admin@doctornect.com').trim().toLowerCase();
  const password = getEnv('SUPER_ADMIN_PASSWORD');
  if (!password) {
    console.error('SUPER_ADMIN_PASSWORD is missing. Set it in gitignored .env (never commit).');
    process.exit(1);
  }

  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.error('STAGING_SUPABASE_DB_URL is missing (repo root .env).');
    process.exit(1);
  }

  console.log('================================================================');
  console.log(`DoctorNect set-super-admin | target=${target} | mode=${dryRun ? 'DRY-RUN' : 'EXECUTE'}`);
  console.log(`Email: ${email}`);
  console.log(`DB: ${maskConnectionString(dbUrl)}`);
  console.log('================================================================\n');

  const admin = initFirebaseAdmin();
  const auth = admin.auth();

  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    console.log(`[Auth] Found existing Firebase user uid=${userRecord.uid}`);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
    console.log('[Auth] No Firebase user for email — will create on execute.');
    userRecord = null;
  }

  const displayName = 'DoctorNect Super Admin';
  const claims = supabaseCompatibleCustomClaims({ verified: true, profileId: userRecord?.uid || '<new>' });

  if (dryRun) {
    console.log('[DRY-RUN] Would set Firebase user: emailVerified=true, disabled=false');
    console.log('[DRY-RUN] Would set custom claims:', JSON.stringify(claims));
    if (!userRecord) {
      console.log('[DRY-RUN] Would create Firebase Auth user and assign password from SUPER_ADMIN_PASSWORD');
    } else {
      console.log('[DRY-RUN] Would update password from SUPER_ADMIN_PASSWORD');
    }
  } else {
    if (!userRecord) {
      userRecord = await auth.createUser({
        email,
        password,
        displayName,
        emailVerified: true,
        disabled: false,
      });
      console.log(`[Auth] Created Firebase user uid=${userRecord.uid}`);
    } else {
      await auth.updateUser(userRecord.uid, {
        displayName,
        emailVerified: true,
        disabled: false,
        password,
      });
      console.log(`[Auth] Updated Firebase user uid=${userRecord.uid}`);
    }

    const merged = { ...(userRecord.customClaims || {}), ...supabaseCompatibleCustomClaims({ verified: true, profileId: userRecord.uid }) };
    await auth.setCustomUserClaims(userRecord.uid, merged);
    console.log('[Auth] Custom claims applied (super_admin / authenticated).');
  }

  const uid = userRecord?.uid;
  if (!uid && dryRun) {
    console.log('\n[DRY-RUN] Postgres sync skipped until Firebase uid exists (run with --execute).');
    console.log('\nDry-run complete. Re-run with --confirm-live-data --execute to apply.');
    return;
  }

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();
  try {
    await syncPostgres(client, uid, email, displayName, dryRun);
    if (!dryRun) {
      console.log('\n✔ Super Admin bootstrap complete.');
    } else {
      console.log('\nDry-run complete. Re-run with --confirm-live-data --execute to apply.');
    }
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
