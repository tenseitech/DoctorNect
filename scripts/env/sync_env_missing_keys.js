'use strict';

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');

const root = findRepoRoot();
const envPath = path.join(root, '.env');
const examplePath = path.join(root, '.env.example');
const env = parseEnvFile(envPath);
const example = parseEnvFile(examplePath);
const merged = { ...example };
for (const [k, v] of Object.entries(env)) {
  if (v !== '') merged[k] = v;
  else if (!Object.prototype.hasOwnProperty.call(merged, k)) merged[k] = v;
}
let added = 0;
for (const k of Object.keys(example)) {
  if (!Object.prototype.hasOwnProperty.call(env, k)) added++;
}
const lines = [
  '# DoctorNect — local environment (gitignored). Template: .env.example',
  `# Keys: ${Object.keys(merged).length}`,
  '',
];
for (const key of Object.keys(merged).sort()) {
  lines.push(`${key}=${merged[key] ?? ''}`);
}
fs.writeFileSync(envPath, `${lines.join('\n')}\n`);
console.log(`sync_env_missing_keys: ${added} keys added as empty; total ${Object.keys(merged).length}`);
