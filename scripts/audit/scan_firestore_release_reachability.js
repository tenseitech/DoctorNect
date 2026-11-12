#!/usr/bin/env node
/**
 * Scans frontend/lib for Firestore reachability in release builds.
 * Writes docs/audit/FIRESTORE_REACHABLE_RELEASE.md
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const LIB = path.join(ROOT, 'frontend/lib');
const OUT = path.join(ROOT, 'docs/audit/FIRESTORE_REACHABLE_RELEASE.md');
const ALLOWLIST = path.join(__dirname, 'firestore_instance_allowlist.txt');

const SUPABASE_PRIMARY_MARKERS = [
  'SupabaseLabRepository',
  'InAppNotificationSupabaseRepository',
  'SupabasePatientRepository',
  'SupabaseBootstrap.isReady',
  'DoctorPatientCutoverFlag',
];

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
  return path.basename(file, '.dart').replace(/_/g, ' ');
}

function releaseClassFor(rel, fileText, kind) {
  if (rel.includes('/repositories/')) {
    return {
      cls: 'DEAD_IN_RELEASE',
      note: 'Only entered via FirestoreService (throws at gateway in release)',
    };
  }
  if (rel.includes('/features/ambulance/') || rel.includes('/ambulance/')) {
    return {
      cls: 'DEAD_IN_RELEASE',
      note: 'AMBULANCE_ENABLED=false: routes not mounted',
    };
  }
  if (rel.includes('firestore_forbidden_guard.dart') || rel.includes('firestore_client.dart')) {
    return { cls: 'TEST_ONLY', note: 'guard implementation' };
  }
  if (rel.includes('firestore_read_helper.dart') || rel.includes('firestore_service.dart')) {
    return { cls: 'TEST_ONLY', note: 'central gate' };
  }
  const supaPrimary =
    SUPABASE_PRIMARY_MARKERS.some((m) => fileText.includes(m)) &&
    !/FirestoreService\.instance/.test(fileText);
  if (supaPrimary) {
    return {
      cls: 'DEAD_IN_RELEASE',
      note: 'File uses Supabase-primary APIs; Firestore lines are legacy/unreachable in release flow',
    };
  }
  if (rel.includes('shared_appointments_store.dart')) {
    return {
      cls: 'DEAD_IN_RELEASE',
      note: 'Supabase refresh path; Firestore branch not taken when forbidden (shared_appointments_store.dart)',
    };
  }
  return {
    cls: 'LIVE_AND_THROWS',
    note: 'Reachable in release → StateError unless caught; show FirestoreUi.userMessage',
  };
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
  const counts = {};
  const byModule = {};

  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    const lines = text.split(/\r?\n/);
    const rel = relPosix(file);

    for (const { re, kind } of PATTERNS) {
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].match(re)) {
          const mod = moduleFor(rel);
          const { cls, note } = releaseClassFor(rel, text, kind);
          counts[cls] = (counts[cls] || 0) + 1;
          if (!byModule[mod]) byModule[mod] = {};
          byModule[mod][cls] = (byModule[mod][cls] || 0) + 1;
          rows.push({
            loc: `${rel}:${i + 1}`,
            module: mod,
            feature: featureHint(file),
            kind,
            releaseClass: cls,
            note,
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
      if (!allowed) violations.push(rel);
    }
  }

  rows.sort((a, b) => a.loc.localeCompare(b.loc));

  const md = [];
  md.push('# Firestore reachability in release builds');
  md.push('');
  md.push('Generated by `node scripts/audit/scan_firestore_release_reachability.js`.');
  md.push('');
  md.push('## Allowlist rationale (`scripts/audit/firestore_instance_allowlist.txt`)');
  md.push('- **profile_completion_service.dart** — guarded `_effectiveFirestore()` + test fake only; release uses Supabase profile paths.');
  md.push('- **firebase_bootstrap.dart** — touches `settings` only when `!isForbidden` (no data reads).');
  md.push('- **profile_photo_uploader.dart** — guarded getter; production uploads use Supabase/S3 primary.');
  md.push('');
  md.push('## Admin screens in release');
  md.push('`features/admin/*` (e.g. **promoted_ad_review_screen.dart**) is **reachable** if a super-admin session opens those routes; they still call `FirestoreClient` → **LIVE_AND_THROWS** unless migrated. Not in consumer doctor/patient/lab/pharmacy shells.');
  md.push('');
  md.push('## Counts by class');
  md.push('| class | count |');
  md.push('|-------|------:|');
  for (const c of ['DEAD_IN_RELEASE', 'LIVE_AND_THROWS', 'TEST_ONLY']) {
    md.push(`| ${c} | ${counts[c] || 0} |`);
  }
  md.push('');
  md.push('## Counts by module × class');
  md.push('| module | DEAD_IN_RELEASE | LIVE_AND_THROWS | TEST_ONLY |');
  md.push('|--------|----------------:|----------------:|----------:|');
  for (const mod of Object.keys(byModule).sort()) {
    const b = byModule[mod];
    md.push(
      `| ${mod} | ${b.DEAD_IN_RELEASE || 0} | ${b.LIVE_AND_THROWS || 0} | ${b.TEST_ONLY || 0} |`,
    );
  }
  md.push('');
  md.push(
    '| file:line | module | feature | accessor | release class | note |',
  );
  md.push(
    '|-----------|--------|---------|----------|---------------|------|',
  );
  for (const r of rows) {
    md.push(
      `| ${r.loc} | ${r.module} | ${r.feature} | ${r.kind} | ${r.releaseClass} | ${r.note} |`,
    );
  }
  md.push('');
  md.push(`Total rows: **${rows.length}**`);
  md.push('');
  md.push('CI: `npm run audit:firestore-reachability`');

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, md.join('\n'), 'utf8');

  if (violations.length > 0) {
    console.error(
      'FirebaseFirestore.instance outside allowlist:\n' + violations.join('\n'),
    );
    process.exit(1);
  }
  console.log(`Wrote ${OUT} (${rows.length} rows)`);
}

main();
