'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const rootDir = path.resolve(__dirname, '../..');

const trackedOutput = execSync('git ls-files', { cwd: rootDir, encoding: 'utf8' });
const trackedFiles = trackedOutput.split('\n').map(f => f.trim()).filter(Boolean);

const testRunsDir = path.join(rootDir, 'docs/ops/test_runs');
let testRunsFiles = [];
if (fs.existsSync(testRunsDir)) {
  testRunsFiles = fs.readdirSync(testRunsDir).map(f => path.join('docs/ops/test_runs', f));
}

const allFiles = Array.from(new Set([...trackedFiles, ...testRunsFiles]));

const URI_PASS_PATTERN = /postgres(?:ql)?:\/\/([^:]+):([^@]+)@/ig;
const DUMMY_VALUES = new Set([
  '****', 'postgres', 'password', 'pass', 'scratchpass',
  '[password]', '[rotated_db_password]', '${encodepassword}',
  '${encodeuricomponent(rdspass)}'
]);

let realSecretsFound = 0;
let dummyOrPlaceholderCount = 0;
let realPrivateKeysFound = 0;
let docExampleKeysFound = 0;
let totalFilesScanned = 0;

for (const relPath of allFiles) {
  const fullPath = path.join(rootDir, relPath);
  if (!fs.existsSync(fullPath)) continue;
  try {
    const stat = fs.statSync(fullPath);
    if (!stat.isFile()) continue;
    if (relPath.endsWith('.png') || relPath.endsWith('.jpg') || relPath.endsWith('.jar') || relPath.endsWith('.jks') || relPath.endsWith('.zip')) {
      continue;
    }
    const content = fs.readFileSync(fullPath, 'utf8');
    totalFilesScanned++;

    let match;
    const regex = new RegExp(URI_PASS_PATTERN);
    while ((match = regex.exec(content)) !== null) {
      const pass = (match[2] || '').trim().toLowerCase();
      if (DUMMY_VALUES.has(pass) || pass.includes('****') || pass.includes('placeholder') || pass.includes('[') || pass.includes('${')) {
        dummyOrPlaceholderCount++;
      } else {
        realSecretsFound++;
        console.error(`[LEAK DETECTED] File ${relPath} contains unmasked password: ${match[0]}`);
      }
    }

    if (/-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/.test(content)) {
      if (relPath.includes('RUNBOOK') || relPath.includes('docs/')) {
        docExampleKeysFound++;
      } else {
        realPrivateKeysFound++;
        console.error(`[LEAK DETECTED] File ${relPath} contains real private key block`);
      }
    }
  } catch (_) {}
}

console.log('=== CREDENTIALS & SECRETS AUDIT REPORT ===');
console.log(`Total files scanned: ${totalFilesScanned}`);
console.log(`Documented placeholders / masked / mock test passwords: ${dummyOrPlaceholderCount}`);
console.log(`Doc example private key blocks: ${docExampleKeysFound}`);
console.log(`Unmasked production passwords count: ${realSecretsFound}`);
console.log(`Real private key leaks count: ${realPrivateKeysFound}`);
console.log(`Audit result: ${realSecretsFound === 0 && realPrivateKeysFound === 0 ? 'CLEAN (Zero credentials leaked)' : 'FAILED (Leaks found)'}`);
