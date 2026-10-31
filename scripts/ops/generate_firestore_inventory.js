'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '../..');

function rg(pattern, glob, extraArgs = '') {
  try {
    return execSync(`rg -l "${pattern}" ${glob} ${extraArgs}`, {
      cwd: ROOT,
      encoding: 'utf8',
      maxBuffer: 8 * 1024 * 1024,
    })
      .split('\n')
      .map((l) => l.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}

const flutterFirestore = rg(
  'cloud_firestore|FirebaseFirestore|DoctorPatientCutoverFlag|debugFirestore',
  'frontend/lib frontend/test',
  "--glob '!**/admin/**'",
);
const backendFirestore = rg(
  'getFirestore|admin\\.firestore|onDocumentWritten|isDoctorPatientSupabasePrimary',
  'backend/functions',
  "--glob '!**/node_modules/**'",
);
const flags = rg('USE_SUPABASE|CUTOVER|ENABLE_SUPABASE|FIRESTORE_FORBIDDEN|SupabaseAuthService', '.');

const out = `# Firestore removal inventory (generated)

Generated: ${new Date().toISOString()}
Branch: feature/postgres-only-architecture

## Scope

- **In scope:** doctor, patient, pharmacy, lab, ambulance modules + shared auth/notifications/storage.
- **Out of scope (Admin):** \`frontend/lib/features/admin/\`, \`frontend/lib/core/admin/\`

## Flutter files (${flutterFirestore.length})

${flutterFirestore.map((f) => `- \`${f}\``).join('\n')}

## Backend functions files (${backendFirestore.length})

${backendFirestore.map((f) => `- \`${f}\``).join('\n')}

## Flag / auth references (${flags.length} files)

${[...new Set(flags)].slice(0, 80).map((f) => `- \`${f}\``).join('\n')}

## Scripts marked for deletion

- \`backend/scripts/migrate_firestore_to_supabase.js\` — one-off migration; Postgres is canonical.

## Allowed post-cleanup exceptions

- Admin module (out of scope)
- \`backend/firestore.rules\` deny-all
- Historical docs mentioning Firestore
- Removed rules tests (obsolete after deny-all)
`;

const dest = path.join(ROOT, 'docs/ops/FIRESTORE_REMOVAL_INVENTORY.md');
fs.writeFileSync(dest, out, 'utf8');
console.log('Wrote', dest);
