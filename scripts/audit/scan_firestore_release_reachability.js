#!/usr/bin/env node
/**
 * Scans frontend/lib for Firestore reachability in release builds.
 * Writes docs/audit/FIRESTORE_REACHABLE_RELEASE.md and exits 1 if
 * FirebaseFirestore.instance appears outside allowlist (CI gate).
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const LIB = path.join(ROOT, 'frontend/lib');
const OUT = path.join(ROOT, 'docs/audit/FIRESTORE_REACHABLE_RELEASE.md');
const ALLOWLIST = path.join(__dirname, 'firestore_instance_allowlist.txt');

const PATTERNS = [
  { re: /FirebaseFirestore\.instance/g, kind: 'FirebaseFirestore.instance' },
  { re: /FirestoreService\.instance/g, kind: 'FirestoreService.instance' },
  { re: /FirestoreReadHelper\./g, kind: 'FirestoreReadHelper' },
];

function moduleFor(file) {
  const rel = file.replace(/\\/g, '/');
  if (rel.includes('/features/ambulance/')) return 'ambulance';
  if (rel.includes('/features/doctor/')) return 'doctor';
  if (rel.includes('/features/patient/')) return 'patient';
  if (rel.includes('/features/pharmacy/')) return 'pharmacy';
  if (rel.includes('/features/lab/')) return 'lab';
  if (rel.includes('/features/admin/')) return 'admin';
  if (rel.includes('/core/')) return 'shared-core';
  return 'other';
}

function featureHint(file) {
  const base = path.basename(file, '.dart');
  return base.replace(/_/g, ' ');
}

function forbiddenBehavior(file, line, kind) {
  if (file.includes('firestore_read_helper.dart')) {
    return 'throws StateError via assertNotForbidden (caller should catch → UI)';
  }
  if (file.includes('firestore_forbidden_guard.dart')) return 'definition only';
  if (file.includes('firestore_service.dart')) {
    return 'getter throws StateError if FIRESTORE_FORBIDDEN (caller should catch → UI)';
  }
  if (file.includes('profile_completion_service.dart')) {
    return '_effectiveFirestore: throws or debug override';
  }
  if (file.includes('/repositories/')) {
    return 'dead in release unless FirestoreService accessed (throws at gateway)';
  }
  if (file.includes('/ambulance/')) {
    return 'gated AMBULANCE_ENABLED=false → screen not routed; else throws if reached';
  }
  if (kind === 'FirestoreService.instance') {
    return 'throws at FirestoreService gateway unless caught';
  }
  if (kind === 'FirebaseFirestore.instance') {
    return 'throws only if caller wrapped; direct use may throw uncaught — migrate to Supabase';
  }
  return 'see FirestoreForbiddenGuard / Supabase primary paths';
}

function effortFor(file, kind) {
  if (file.includes('/repositories/')) return 'S';
  if (kind === 'FirestoreReadHelper') return 'S';
  if (file.includes('firebase_bootstrap.dart')) return 'S';
  if (file.includes('doctor_profile_store') || file.includes('community_')) return 'L';
  if (file.includes('features/patient/')) return 'M';
  return 'M';
}

function statusFor(file) {
  if (file.includes('firestore_forbidden_guard')) return 'n/a';
  if (file.includes('firestore_read_helper')) return 'gated';
  if (file.includes('firestore_service.dart')) return 'gated';
  if (file.includes('ambulance')) return 'gated-off';
  if (
    file.includes('shared_appointments_store') ||
    file.includes('in_app_notification_supabase') ||
    file.includes('supabase_')
  ) {
    return 'migrated';
  }
  return 'gated-or-migrate';
}

function walk(dir, acc = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, acc);
    else if (ent.name.endsWith('.dart')) acc.push(p);
  }
  return acc;
}

function loadAllowlist() {
  if (!fs.existsSync(ALLOWLIST)) return new Set();
  return new Set(
    fs
      .readFileSync(ALLOWLIST, 'utf8')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#')),
  );
}

function relPosix(p) {
  return path.relative(ROOT, p).replace(/\\/g, '/');
}

function main() {
  const allowlist = loadAllowlist();
  const files = walk(LIB);
  const rows = [];
  const violations = [];

  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    const lines = text.split(/\r?\n/);
    const rel = relPosix(file);

    for (const { re, kind } of PATTERNS) {
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].match(re)) {
          rows.push({
            loc: `${rel}:${i + 1}`,
            module: moduleFor(rel),
            feature: featureHint(file),
            collection: kind.includes('ReadHelper') ? '(varies via helper)' : '(via repository)',
            behavior: forbiddenBehavior(rel, i + 1, kind),
            effort: effortFor(rel, kind),
            status: statusFor(rel),
          });
        }
      }
    }

    if (text.includes('FirebaseFirestore.instance')) {
      const allowed =
        allowlist.has(rel) ||
        rel.startsWith('frontend/lib/core/firebase/repositories/') ||
        rel === 'frontend/lib/core/config/firestore_forbidden_guard.dart' ||
        rel === 'frontend/lib/core/firebase/firestore_client.dart' ||
        rel === 'frontend/lib/core/auth/profile_completion_service.dart' ||
        rel === 'frontend/lib/core/firebase/firebase_bootstrap.dart';
      if (!allowed) {
        violations.push(rel);
      }
    }
  }

  rows.sort((a, b) => a.loc.localeCompare(b.loc));

  const md = [];
  md.push('# Firestore reachability in release builds');
  md.push('');
  md.push(
    'Generated by `node scripts/audit/scan_firestore_release_reachability.js`.',
  );
  md.push(
    'Default `FIRESTORE_FORBIDDEN=true`: client must not read application Firestore; failures must surface in UI.',
  );
  md.push('');
  md.push(
    '| file:line | module | feature/screen | collection | FIRESTORE_FORBIDDEN=true | effort | status |',
  );
  md.push(
    '|-----------|--------|----------------|------------|---------------------------|--------|--------|',
  );
  for (const r of rows) {
    md.push(
      `| ${r.loc} | ${r.module} | ${r.feature} | ${r.collection} | ${r.behavior} | ${r.effort} | ${r.status} |`,
    );
  }
  md.push('');
  md.push(`Total rows: **${rows.length}**`);
  md.push('');
  md.push('## CI allowlist');
  md.push(
    'Direct `FirebaseFirestore.instance` outside `frontend/lib/core/firebase/repositories/` and allowlist → **fail**.',
  );

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, md.join('\n'), 'utf8');

  const uniqueViolations = [...new Set(violations)];
  if (uniqueViolations.length > 0) {
    console.error(
      'FirebaseFirestore.instance outside allowlist:\n' + uniqueViolations.join('\n'),
    );
    process.exit(1);
  }
  console.log(`Wrote ${OUT} (${rows.length} rows)`);
}

main();
