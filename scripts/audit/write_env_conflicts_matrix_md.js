#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const jsonPath = path.join(__dirname, '../../docs/audit/_audit_env_runtime.json');
const outPath = path.join(__dirname, '../../docs/audit/ENV_CONFLICTS_MATRIX.md');
const raw = fs.readFileSync(jsonPath, 'utf8').replace(/^\uFEFF/, '');
const { rows } = JSON.parse(raw);

function primaryReader(readers) {
  if (!readers.length) return 'none scanned (template/docs only)';
  const order = [
    'backend/functions (process.env)',
    'frontend (String.fromEnvironment)',
    'frontend (bool.fromEnvironment)',
    'services/api-gateway (process.env)',
    'scripts/ (process.env)',
    'backend/scripts (process.env)',
  ];
  for (const r of order) if (readers.includes(r)) return r;
  return readers[0];
}

const lines = [
  '# Env variable conflicts (names only)',
  '',
  'Variables defined in more than one env file with **different value hashes** (no secret values).',
  'Regenerate: `node scripts/audit/env_runtime_readers.js` then `node scripts/audit/write_env_conflicts_matrix_md.js`.',
  '',
  '| Variable | Files defining it | Values differ | Primary runtime reader |',
  '|----------|-------------------|---------------|-------------------------|',
];
for (const r of rows) {
  const files = r.files.map((f) => `\`${f}\``).join(', ');
  lines.push(`| \`${r.variable}\` | ${files} | yes | ${primaryReader(r.runtimeReaders)} |`);
}
lines.push('');
fs.writeFileSync(outPath, lines.join('\n'));
console.log('Wrote', outPath, 'rows', rows.length);
