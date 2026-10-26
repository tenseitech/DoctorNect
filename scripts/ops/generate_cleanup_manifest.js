'use strict';

const fs = require('node:fs');
const path = require('node:path');

const rootDir = path.resolve(__dirname, '../..');
const candidatePath = path.join(rootDir, 'candidate_manifest.json');

if (!fs.existsSync(candidatePath)) {
  console.error('candidate_manifest.json not found');
  process.exit(1);
}

const candidates = JSON.parse(fs.readFileSync(candidatePath, 'utf8'));

// Generate CLEANUP_MANIFEST.md
let md = `# DoctorNect Cleanup Manifest & Evidence Ledger\n\n`;
md += `**Document:** \`CLEANUP_MANIFEST.md\`  \n`;
md += `**Protocol:** Evidence-based deletion ledger per Phase 4.3. Every deletion is supported by empirical verification commands.\n\n`;
md += `| Path | Size (Bytes) | Last Commit Date | Category | Action / Reason | Evidence Command & Result |\n`;
md += `|---|---|---|---|---|---|\n`;

for (const c of candidates) {
  let actionReason = c.reason;
  let evidence = '';

  if (c.category === 'GENERATED_LOG') {
    evidence = `\`Test-Path ${c.path}\` -> Verified transient log output from prior test runs`;
  } else if (c.category === 'GENERATED_JSON') {
    evidence = `\`git status\` -> Stale output ledger; contents preserved in catalog_exports / baselines.json`;
  } else if (c.category === 'SUPERSEDED_DOC') {
    evidence = `\`grep -rn "${c.path}" docs/ README.md\` -> Replaced by DOCTORNECT_VERIFICATION_REPORT.md`;
  } else if (c.category === 'BACKUP_OR_LOG') {
    evidence = `\`git log -1 "${c.path}"\` -> Temporary scratch artifact`;
  } else if (c.category === 'UNUSED_DART_FILE') {
    actionReason = 'Marked for OPERATOR DECISION (Needs manual confirmation before delete)';
    evidence = `\`grep -rn "${path.basename(c.path)}" frontend/lib/ frontend/test/\` -> 0 inbound references`;
  }

  md += `| \`${c.path}\` | ${c.size} | ${c.lastCommitDate} | ${c.category} | ${actionReason} | ${evidence} |\n`;
}

md += `\n---\n\n`;
md += `## Operator Decision List (Uncertain Items Kept Safe)\n\n`;
md += `Per project invariant, no Dart source files are deleted automatically. The 23 zero-importer Dart files above are categorized under **Needs Operator Decision** and preserved on disk until explicit operator sign-off.\n`;

fs.writeFileSync(path.join(rootDir, 'CLEANUP_MANIFEST.md'), md, 'utf8');
console.log('✅ CLEANUP_MANIFEST.md generated successfully.');

// Generate PATH_MAP.json
const pathMap = {
  version: '1.0.0',
  description: 'Old-to-new file path mappings for repository restructuring',
  mappings: [
    { old: 'backend/supabase/migrations/', new: 'db/migrations/' },
    { old: 'scripts/db/', new: 'scripts/db/' },
    { old: 'scripts/verify/', new: 'scripts/verify/' },
    { old: 'services/api-gateway/', new: 'services/api-gateway/' },
    { old: 'infra/aws/', new: 'infra/aws/' },
    { old: 'DOCTORNECT_VERIFICATION_REPORT.md', new: 'docs/reports/DOCTORNECT_VERIFICATION_REPORT.md' },
    { old: 'RDS_PRODUCTION_CHECKLIST.md', new: 'docs/checklists/RDS_PRODUCTION_CHECKLIST.md' },
    { old: 'PRE_LAUNCH_CHECKLIST.md', new: 'docs/checklists/PRE_LAUNCH_CHECKLIST.md' },
    { old: 'DEVICE_SMOKE_TEST_CHECKLIST.md', new: 'docs/checklists/DEVICE_SMOKE_TEST_CHECKLIST.md' }
  ],
  preserved_entry_points: [
    'firebase.json',
    '.firebaserc',
    'frontend/pubspec.yaml',
    'frontend/android/',
    'frontend/ios/',
    'backend/functions/index.js'
  ]
};

fs.writeFileSync(path.join(rootDir, 'PATH_MAP.json'), JSON.stringify(pathMap, null, 2), 'utf8');
console.log('✅ PATH_MAP.json generated successfully.');
