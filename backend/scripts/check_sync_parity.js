/**
 * DoctorNect: Cross-System Parity Auditor (Read-Only)
 * 
 * Verifies data consistency between Supabase PostgreSQL and Firebase Firestore
 * during the staged transition window. Strictly read-only: counts only, no writes,
 * no PII or identifiers printed.
 * 
 * Usage:
 *   node scripts/check_sync_parity.js
 *   node scripts/check_sync_parity.js --audit
 *   node scripts/check_sync_parity.js --collection-prefix="staging_"
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

require('./load_env').loadEnv();

let _admin = null;
function getAdmin() {
  if (_admin) return _admin;
  try {
    _admin = require('firebase-admin');
  } catch (_) {
    try {
      const fnReq = createRequire(path.resolve(__dirname, '..', 'functions', 'package.json'));
      _admin = fnReq('firebase-admin');
    } catch (_) {
      _admin = null;
    }
  }
  return _admin;
}

let _Client = null;
function getPgClientClass() {
  if (_Client) return _Client;
  try {
    _Client = require('pg').Client;
  } catch (_) {
    try {
      const fnReq = createRequire(path.resolve(__dirname, '..', 'functions', 'package.json'));
      _Client = fnReq('pg').Client;
    } catch (_) {
      _Client = null;
    }
  }
  return _Client;
}

/**
 * Parses and validates CLI flags for check_sync_parity.js.
 */
function parseCliArgs(rawArgs = process.argv.slice(2)) {
  const flags = {
    isAudit: false,
    prefix: '',
    isHelp: false,
    errors: [],
  };

  for (let i = 0; i < rawArgs.length; i++) {
    const arg = rawArgs[i];
    if (arg === '--help' || arg === '-h') {
      flags.isHelp = true;
    } else if (arg === '--audit') {
      flags.isAudit = true;
    } else if (arg.startsWith('--collection-prefix=')) {
      const val = arg.slice('--collection-prefix='.length);
      flags.prefix = val.replace(/^["']|["']$/g, '');
    } else if (arg === '--collection-prefix' && i + 1 < rawArgs.length) {
      i++;
      flags.prefix = rawArgs[i].replace(/^["']|["']$/g, '');
    } else {
      flags.errors.push(`Unknown option: ${arg}`);
    }
  }

  // Default to audit mode
  if (!flags.isHelp && flags.errors.length === 0) {
    flags.isAudit = true;
  }

  return flags;
}

function printUsage() {
  console.log(`
DoctorNect Cross-System Parity Auditor (Read-Only)

Usage:
  node scripts/check_sync_parity.js [options]

Options:
  --audit                     Run read-only parity check across appointments, prescriptions, and DLQ (default)
  --collection-prefix=<pfx>   Firestore collection prefix (e.g., staging_)
  --help, -h                  Display this help message
`);
}

/**
 * Compares effective state between a PostgreSQL appointment row and a Firestore document.
 * 
 * Rules:
 * 1. Primary lifecycle is driven by doctorStatus.
 * 2. In Firestore, patientStatus only stores 'pending' or 'confirmed'. Terminal states
 *    ('completed', 'cancelled') in PostgreSQL are intentionally represented via doctorStatus.
 *    Therefore, when PostgreSQL patient_status is terminal, effective state matches if doctorStatus matches.
 *    Otherwise, strict patientStatus equality is enforced.
 */
function isStatusMismatch(pgRow, fsDoc) {
  if (!pgRow || !fsDoc) return true;

  // 1. Primary lifecycle check
  if (fsDoc.doctorStatus !== pgRow.doctor_status) {
    return true;
  }

  // 2. Effective patient status comparison
  if (pgRow.patient_status === 'cancelled') {
    return fsDoc.doctorStatus !== 'cancelled';
  }
  if (pgRow.patient_status === 'completed') {
    return fsDoc.doctorStatus !== 'completed';
  }

  return fsDoc.patientStatus !== pgRow.patient_status;
}

function initFirebase() {
  const admin = getAdmin();
  if (!admin) {
    throw new Error('firebase-admin module could not be loaded. Please install dependencies in backend/scripts or backend/functions.');
  }
  if (!admin.apps.length) {
    const saCandidates = [
      process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
      process.env.GOOGLE_APPLICATION_CREDENTIALS,
      path.join(__dirname, 'service-account.json'),
      path.join(process.cwd(), 'service-account.json'),
    ];
    const saPath = saCandidates.find(p => p && fs.existsSync(p));
    if (saPath) {
      const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
      admin.initializeApp({
        credential: admin.credential.cert(sa),
        projectId: sa.project_id || 'medibond-45fad',
      });
    } else {
      admin.initializeApp({ projectId: 'medibond-45fad' });
    }
  }
  return admin.firestore();
}

function createPgClient() {
  const Client = getPgClientClass();
  if (!Client) {
    throw new Error('pg module could not be loaded. Please install dependencies in backend/scripts or backend/functions.');
  }
  const connectionString = process.env.STAGING_SUPABASE_DB_URL || process.env.SUPABASE_DB_URL;
  if (!connectionString) {
    throw new Error('Database connection string not found (STAGING_SUPABASE_DB_URL or SUPABASE_DB_URL).');
  }

  return new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
  });
}

async function auditAppointments(pgClient, firestore, { prefix = '' } = {}) {
  console.log(`\n--- [1/3] Auditing Appointments Parity (Firestore: ${prefix}appointments vs Postgres: appointments) ---`);
  const pgRes = await pgClient.query(`SELECT appointment_id, doctor_id, patient_id, doctor_status, patient_status, updated_at FROM appointments;`);
  const pgMap = new Map();
  for (const r of pgRes.rows) {
    pgMap.set(r.appointment_id, r);
  }

  const fsSnap = await firestore.collection(`${prefix}appointments`).get();
  const fsMap = new Map();
  for (const doc of fsSnap.docs) {
    fsMap.set(doc.id, doc.data());
  }

  let inPgNotFsCount = 0;
  let mismatchedCount = 0;

  for (const [id, pgRow] of pgMap.entries()) {
    if (!fsMap.has(id)) {
      inPgNotFsCount++;
    } else {
      const fsDoc = fsMap.get(id);
      if (isStatusMismatch(pgRow, fsDoc)) {
        mismatchedCount++;
      }
    }
  }

  let inFsNotPgCount = 0;
  for (const [id] of fsMap.entries()) {
    if (!pgMap.has(id)) {
      inFsNotPgCount++;
    }
  }

  console.log(`Total Postgres Rows: ${pgMap.size} | Total Firestore Docs: ${fsMap.size}`);
  console.log(`Missing in Firestore: ${inPgNotFsCount} | Missing in Postgres: ${inFsNotPgCount} | Status Mismatches: ${mismatchedCount}`);

  return {
    pgCount: pgMap.size,
    fsCount: fsMap.size,
    inPgNotFs: inPgNotFsCount,
    inFsNotPg: inFsNotPgCount,
    mismatched: mismatchedCount,
  };
}

async function auditPrescriptions(pgClient, firestore, { prefix = '' } = {}) {
  console.log(`\n--- [2/3] Auditing Prescriptions Parity (Firestore: ${prefix}prescriptions vs Postgres: prescriptions) ---`);
  const pgRes = await pgClient.query(`SELECT prescription_id, doctor_id, patient_id, appointment_id FROM prescriptions;`);
  const pgMap = new Map();
  for (const r of pgRes.rows) {
    pgMap.set(r.prescription_id, r);
  }

  const fsSnap = await firestore.collection(`${prefix}prescriptions`).get();
  const fsMap = new Map();
  for (const doc of fsSnap.docs) {
    fsMap.set(doc.id, doc.data());
  }

  let inFsNotPgCount = 0;
  for (const [id] of fsMap.entries()) {
    if (!pgMap.has(id)) inFsNotPgCount++;
  }

  console.log(`Total Postgres Rows: ${pgMap.size} | Total Firestore Docs: ${fsMap.size}`);
  console.log(`Prescriptions in Firestore missing in Postgres: ${inFsNotPgCount}`);

  return {
    pgCount: pgMap.size,
    fsCount: fsMap.size,
    inFsNotPg: inFsNotPgCount,
  };
}

async function checkDlqHealth(pgClient) {
  console.log(`\n--- [3/3] Checking Dead-Letter Queue (DLQ) Health ---`);
  const dlqRes = await pgClient.query(`
    SELECT status, count(*) AS count 
    FROM sync_dead_letter_queue 
    GROUP BY status;
  `);

  console.log('Dead-Letter Queue status breakdown:');
  if (dlqRes.rows.length === 0) {
    console.log('  PASS: DLQ is completely empty (0 failures recorded).');
  } else {
    console.table(dlqRes.rows);
  }
}

async function main() {
  const cli = parseCliArgs(process.argv.slice(2));

  if (cli.isHelp) {
    printUsage();
    process.exit(0);
  }

  if (cli.errors.length > 0) {
    console.error('CLI Argument Errors:');
    cli.errors.forEach(e => console.error(`  - ${e}`));
    printUsage();
    process.exit(1);
  }

  console.log('================================================================');
  console.log(`DOCTORNECT CROSS-SYSTEM PARITY AUDITOR (READ-ONLY)`);
  if (cli.prefix) console.log(`FIRESTORE PREFIX: ${cli.prefix}`);
  console.log('================================================================');

  let firestore;
  let pgClient;

  try {
    firestore = initFirebase();
    pgClient = createPgClient();
    await pgClient.connect();

    const aptResult = await auditAppointments(pgClient, firestore, { prefix: cli.prefix });
    const rxResult = await auditPrescriptions(pgClient, firestore, { prefix: cli.prefix });
    await checkDlqHealth(pgClient);

    console.log('\n================================================================');
    console.log('AUDIT SUMMARY');
    console.log('================================================================');
    console.table([
      { Entity: 'Appointments', PostgresCount: aptResult.pgCount, FirestoreCount: aptResult.fsCount, Divergence: aptResult.inPgNotFs + aptResult.inFsNotPg + aptResult.mismatched },
      { Entity: 'Prescriptions', PostgresCount: rxResult.pgCount, FirestoreCount: rxResult.fsCount, Divergence: rxResult.inFsNotPg },
    ]);
  } catch (err) {
    console.error('Parity auditor failed:', err);
    process.exit(1);
  } finally {
    if (pgClient) {
      await pgClient.end().catch(() => {});
    }
  }
}

module.exports = {
  parseCliArgs,
  printUsage,
  isStatusMismatch,
  auditAppointments,
  auditPrescriptions,
  checkDlqHealth,
};

if (require.main === module) {
  main();
}
