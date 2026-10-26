'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const config = require('../src/config');

describe('Gateway Allowlist Completeness Scanner', () => {
  function findFiles(dir, exts, list = []) {
    if (!fs.existsSync(dir)) return list;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!['node_modules', '.git', 'build', '.dart_tool'].includes(entry.name)) {
          findFiles(full, exts, list);
        }
      } else if (exts.some((ext) => entry.name.endsWith(ext))) {
        list.push(full);
      }
    }
    return list;
  }

  it('scans frontend/lib and backend/functions for tables and RPCs and confirms 100% gateway allowlist coverage', () => {
    const repoRoot = path.resolve(__dirname, '../../..');
    const frontendLib = path.join(repoRoot, 'frontend', 'lib');
    const backendFunctions = path.join(repoRoot, 'backend', 'functions');

    const dartFiles = findFiles(frontendLib, ['.dart']);
    const jsFiles = findFiles(backendFunctions, ['.js']);

    const tablesFound = new Set();
    const rpcsFound = new Set();

    // Regexes to extract table and RPC names from Flutter and Cloud Functions
    const fromRegex = /\.from\(\s*['"]([a-zA-Z0-9_]+)['"]\s*\)/g;
    const streamTableRegex = /streamTable\s*\(\s*[^)]*table:\s*['"]([a-zA-Z0-9_]+)['"]/g;
    const tableParamRegex = /\btable:\s*['"]([a-zA-Z0-9_]+)['"]/g;
    const rpcRegex = /\.rpc\(\s*['"]([a-zA-Z0-9_]+)['"]/g;

    const allFiles = [...dartFiles, ...jsFiles];

    for (const file of allFiles) {
      const content = fs.readFileSync(file, 'utf8');

      let m;
      while ((m = fromRegex.exec(content)) !== null) {
        tablesFound.add(m[1]);
      }
      while ((m = streamTableRegex.exec(content)) !== null) {
        tablesFound.add(m[1]);
      }
      while ((m = tableParamRegex.exec(content)) !== null) {
        tablesFound.add(m[1]);
      }
      while ((m = rpcRegex.exec(content)) !== null) {
        rpcsFound.add(m[1]);
      }
    }

    const sortedTables = Array.from(tablesFound).sort();
    const sortedRpcs = Array.from(rpcsFound).sort();

    console.log(`\n=== GATEWAY ALLOWLIST SCANNER REPORT ===`);
    console.log(`Scanned ${allFiles.length} source files (${dartFiles.length} Dart, ${jsFiles.length} JS)`);
    console.log(`Discovered ${sortedTables.length} distinct tables/views:`);
    for (const tbl of sortedTables) {
      console.log(`  - ${tbl}`);
    }
    console.log(`Discovered ${sortedRpcs.length} distinct RPC functions:`);
    for (const rpc of sortedRpcs) {
      console.log(`  - ${rpc}`);
    }

    const allowedTablesSet = new Set(config.allowedTables);
    const allowedRpcsSet = new Set(config.allowedRpcs);

    const missingTables = sortedTables.filter((t) => !allowedTablesSet.has(t));
    const missingRpcs = sortedRpcs.filter((r) => !allowedRpcsSet.has(r));

    if (missingTables.length > 0) {
      console.error('MISSING TABLES IN GATEWAY ALLOWLIST:', missingTables);
    }
    if (missingRpcs.length > 0) {
      console.error('MISSING RPCS IN GATEWAY ALLOWLIST:', missingRpcs);
    }

    assert.strictEqual(
      missingTables.length,
      0,
      `Gateway allowedTables is missing tables used in client/backend: ${missingTables.join(', ')}`
    );
    assert.strictEqual(
      missingRpcs.length,
      0,
      `Gateway allowedRpcs is missing RPC functions used in client/backend: ${missingRpcs.join(', ')}`
    );

    // Explicit check for reschedule_appointment_atomic
    assert.ok(
      allowedRpcsSet.has('reschedule_appointment_atomic'),
      'reschedule_appointment_atomic must be explicitly allowlisted in gateway allowedRpcs'
    );
  });
});
