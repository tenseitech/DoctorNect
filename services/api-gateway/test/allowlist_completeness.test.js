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

    const clientTables = new Set();
    const clientRpcs = new Set();
    const backendTables = new Set();
    const backendRpcs = new Set();
    const nonLiterals = [];

    // Regexes to extract table and RPC names from Flutter and Cloud Functions
    const fromRegex = /\.from\(\s*['"]([a-zA-Z0-9_]+)['"]\s*\)/g;
    const streamTableRegex = /streamTable\s*\(\s*[^)]*table:\s*['"]([a-zA-Z0-9_]+)['"]/g;
    const tableParamRegex = /\btable:\s*['"]([a-zA-Z0-9_]+)['"]/g;
    const rpcRegex = /\.rpc\(\s*['"]([a-zA-Z0-9_]+)['"]/g;

    function scanFile(file, isClient) {
      const content = fs.readFileSync(file, 'utf8');

      let m;
      while ((m = fromRegex.exec(content)) !== null) {
        if (isClient) clientTables.add(m[1]); else backendTables.add(m[1]);
      }
      while ((m = streamTableRegex.exec(content)) !== null) {
        if (isClient) clientTables.add(m[1]); else backendTables.add(m[1]);
      }
      while ((m = tableParamRegex.exec(content)) !== null) {
        if (isClient) clientTables.add(m[1]); else backendTables.add(m[1]);
      }
      while ((m = rpcRegex.exec(content)) !== null) {
        if (isClient) clientRpcs.add(m[1]); else backendRpcs.add(m[1]);
      }

      // Check for non-literal .from(, .rpc(, table: (ignoring built-in type constructors like List.from, Map.from, Buffer.from)
      const lines = content.split('\n');
      lines.forEach((line, idx) => {
        const trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')) return;

        // Skip typed collection constructors like Type.from or Type<...>.from
        if (/[A-Z_][a-zA-Z0-9]*(?:<[^>]*>)?\s*\.from\(/.test(line) && !line.includes('_client.from')) return;
        if (/>\s*\.from\(/.test(line)) return;

        const fromMatch = line.match(/(?:([a-zA-Z0-9_]+)\s*)?\.from\(\s*([^)]*)\)/);
        if (fromMatch) {
          const arg = fromMatch[2].trim();
          if (!arg.startsWith("'") && !arg.startsWith('"') && arg.length > 0) {
            nonLiterals.push({
              file: path.relative(repoRoot, file).replace(/\\/g, '/'),
              line: idx + 1,
              type: (fromMatch[1] || 'client') + '.from()',
              expr: arg,
            });
          }
        }

        const rpcMatch = line.match(/\.rpc\(\s*([^,\)]*)/);
        if (rpcMatch) {
          const arg = rpcMatch[1].trim();
          if (!arg.startsWith("'") && !arg.startsWith('"') && arg.length > 0) {
            nonLiterals.push({
              file: path.relative(repoRoot, file).replace(/\\/g, '/'),
              line: idx + 1,
              type: '.rpc()',
              expr: arg,
            });
          }
        }

        const streamMatch = line.match(/\bstreamTable\s*\([^)]*table:\s*([^,\)]*)/);
        if (streamMatch) {
          const arg = streamMatch[1].trim();
          if (!arg.startsWith("'") && !arg.startsWith('"') && arg.length > 0) {
            nonLiterals.push({
              file: path.relative(repoRoot, file).replace(/\\/g, '/'),
              line: idx + 1,
              type: 'streamTable(table:)',
              expr: arg,
            });
          }
        }
      });
    }

    const allFiles = [...dartFiles, ...jsFiles];
    for (const f of dartFiles) scanFile(f, true);
    for (const f of jsFiles) scanFile(f, false);

    const tablesFound = new Set([...clientTables, ...backendTables]);
    const rpcsFound = new Set([...clientRpcs, ...backendRpcs]);

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

    console.log(`\nDiscovered ${nonLiterals.length} non-literal calls:`);
    for (const nl of nonLiterals) {
      console.log(`  [${nl.type}] ${nl.file}:${nl.line} -> ${nl.expr}`);
    }

    const allowedTablesSet = new Set(config.allowedTables);
    const allowedRpcsSet = new Set(config.allowedRpcs);

    // Known non-literal resolvers and verification:
    // Every non-literal call must be registered here and map to allowlisted tables.
    const knownNonLiteralResolvers = {
      'frontend/lib/core/supabase/supabase_stream_table.dart': [
        // Generic helper; callers pass literal table names audited by clientTables scanner
      ],
      'frontend/lib/features/profile/profile_completion_modal.dart': [
        'doctors',
        'patients',
        'medical_stores',
        'labs',
        'ambulances',
        'users',
      ],
      'backend/functions/registration_otp.js': [
        'patients',
        'doctors',
        'labs',
        'medical_stores',
        'ambulances',
      ],
    };

    const unresolvedNonLiterals = [];
    for (const nl of nonLiterals) {
      const resolvedTables = knownNonLiteralResolvers[nl.file];
      if (resolvedTables === undefined) {
        unresolvedNonLiterals.push(nl);
      } else {
        // Assert all resolved tables are in the allowlist
        for (const tbl of resolvedTables) {
          assert.ok(
            allowedTablesSet.has(tbl),
            `Non-literal at ${nl.file}:${nl.line} resolves to unallowlisted table '${tbl}'`
          );
        }
      }
    }

    assert.strictEqual(
      unresolvedNonLiterals.length,
      0,
      `Unresolved non-literal table/RPC calls found: ${JSON.stringify(unresolvedNonLiterals, null, 2)}`
    );

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
