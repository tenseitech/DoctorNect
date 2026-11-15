#!/usr/bin/env node
'use strict';

/**
 * Static require() graph from backend/functions/index.js (deploy entry).
 * Proves production-reachable modules do not include pg_pool / cross_role_sync.
 */

const fs = require('fs');
const path = require('path');

const FUNCTIONS_ROOT = path.resolve(__dirname, '../../backend/functions');
const ENTRY = path.join(FUNCTIONS_ROOT, 'index.js');
const OUT = path.resolve(__dirname, '../../docs/audit/FUNCTIONS_INDEX_IMPORT_GRAPH.txt');

const SKIP_DIRS = new Set(['node_modules', 'test', '.git']);

function resolveRequire(fromFile, spec) {
  if (!spec.startsWith('.')) return null;
  const base = path.resolve(path.dirname(fromFile), spec);
  const candidates = [
    base,
    `${base}.js`,
    path.join(base, 'index.js'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) return path.normalize(c);
  }
  return null;
}

function extractRequires(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const re = /require\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
  const specs = [];
  let m;
  while ((m = re.exec(content)) !== null) specs.push(m[1]);
  return specs;
}

function walkGraph(startFile) {
  const queue = [startFile];
  const visited = new Set();
  const edges = [];

  while (queue.length) {
    const file = queue.shift();
    if (visited.has(file)) continue;
    visited.add(file);

    for (const spec of extractRequires(file)) {
      const target = resolveRequire(file, spec);
      if (!target) continue;
      if (!target.startsWith(FUNCTIONS_ROOT)) continue;
      const rel = path.relative(FUNCTIONS_ROOT, target).replace(/\\/g, '/');
      if (rel.split('/').includes('test')) continue;
      edges.push({ from: path.relative(FUNCTIONS_ROOT, file).replace(/\\/g, '/'), to: rel });
      queue.push(target);
    }
  }

  return { visited, edges };
}

function main() {
  const { visited, edges } = walkGraph(ENTRY);
  const relFiles = [...visited]
    .map((f) => path.relative(FUNCTIONS_ROOT, f).replace(/\\/g, '/'))
  .sort();

  const hasPgPoolModule = relFiles.some((f) => f === 'src/db/pg_pool.js');
  const hasCrossRoleSync = relFiles.some((f) => f === 'cross_role_sync.js');
  const pgPoolSqlCallers = relFiles.filter((rel) => {
    const abs = path.join(FUNCTIONS_ROOT, rel);
    const content = fs.readFileSync(abs, 'utf8');
    return /\bgetPgPool\s*\(/.test(content);
  });

  const lines = [];
  lines.push('DoctorNect Cloud Functions import graph (static require from index.js)');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Entry: backend/functions/index.js`);
  lines.push(`Reachable module files: ${relFiles.length}`);
  lines.push('');
  lines.push('=== REACHABILITY VERDICT ===');
  lines.push(`src/db/pg_pool.js in graph: ${hasPgPoolModule ? 'YES' : 'NO'}`);
  lines.push(`getPgPool() callers in graph: ${pgPoolSqlCallers.length ? pgPoolSqlCallers.join(', ') : 'none'}`);
  lines.push(`cross_role_sync.js in graph: ${hasCrossRoleSync ? 'YES (unexpected)' : 'NO'}`);
  lines.push('');
  lines.push('=== SYNC / DLQ (not exported) ===');
  lines.push(
    'cross_role_sync.js is NOT imported from index.js. Firestore→Postgres bridge and DLQ SQL are offline when ENABLE_SUPABASE_SYNC=0 (cutover default).',
  );
  lines.push(
    'Live prod data path: client + callables → Auth Gateway (getDatabaseClient); Postgres triggers/RPC for writes; no deployed cross_role_sync listener.',
  );
  lines.push('');
  lines.push('=== MODULE LIST ===');
  for (const f of relFiles) lines.push(`  ${f}`);
  lines.push('');
  lines.push('=== EDGES (sample) ===');
  for (const e of edges.slice(0, 200)) lines.push(`  ${e.from} -> ${e.to}`);
  if (edges.length > 200) lines.push(`  ... ${edges.length - 200} more edges`);

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, `${lines.join('\n')}\n`, 'utf8');
  console.log(`Wrote ${OUT}`);
  if (hasPgPoolModule || hasCrossRoleSync || pgPoolSqlCallers.length) process.exit(1);
}

main();