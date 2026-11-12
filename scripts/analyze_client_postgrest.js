const fs = require('fs');
const path = require('path');

function scanDir(dir, filterExt, results = []) {
  if (!fs.existsSync(dir)) return results;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules' && entry.name !== '.git' && entry.name !== 'build') {
        scanDir(fullPath, filterExt, results);
      }
    } else if (filterExt.some(ext => entry.name.endsWith(ext))) {
      results.push(fullPath);
    }
  }
  return results;
}

const flutterFiles = scanDir(path.join(__dirname, '../frontend/lib'), ['.dart']);
const backendFiles = scanDir(path.join(__dirname, '../backend/functions'), ['.js', '.ts']);

const tableUsage = {}; // table -> { operations: Set, files: Set }
const rpcUsage = {};   // rpc -> { files: Set }

function analyzeFile(filePath, content) {
  // PostgREST calls: .from('table') or .from("table")
  const fromRegex = /\.from\(\s*['"]([a-zA-Z0-9_]+)['"]\s*\)([\s\S]*?)(?=;|\.from\(|\n\s*\n)/g;
  let match;
  while ((match = fromRegex.exec(content)) !== null) {
    const table = match[1];
    const chain = match[2];
    if (!tableUsage[table]) {
      tableUsage[table] = { select: false, insert: false, update: false, delete: false, upsert: false, files: new Set() };
    }
    tableUsage[table].files.add(path.relative(path.join(__dirname, '..'), filePath));
    if (/\.select\(/.test(chain)) tableUsage[table].select = true;
    if (/\.insert\(/.test(chain)) tableUsage[table].insert = true;
    if (/\.update\(/.test(chain)) tableUsage[table].update = true;
    if (/\.delete\(/.test(chain)) tableUsage[table].delete = true;
    if (/\.upsert\(/.test(chain)) {
      tableUsage[table].insert = true;
      tableUsage[table].update = true;
    }
    // If no explicit method found in snippet, check broader line
    if (!tableUsage[table].select && !tableUsage[table].insert && !tableUsage[table].update && !tableUsage[table].delete) {
      tableUsage[table].select = true; // default safe assumption
    }
  }

  // RPC calls: .rpc('function') or .rpc("function")
  const rpcRegex = /\.rpc\(\s*['"]([a-zA-Z0-9_]+)['"]/g;
  while ((match = rpcRegex.exec(content)) !== null) {
    const rpcName = match[1];
    if (!rpcUsage[rpcName]) {
      rpcUsage[rpcName] = new Set();
    }
    rpcUsage[rpcName].add(path.relative(path.join(__dirname, '..'), filePath));
  }
}

for (const f of flutterFiles) {
  analyzeFile(f, fs.readFileSync(f, 'utf8'));
}
for (const f of backendFiles) {
  analyzeFile(f, fs.readFileSync(f, 'utf8'));
}

const summary = {
  tables: Object.fromEntries(
    Object.entries(tableUsage).map(([tbl, data]) => [
      tbl,
      {
        select: data.select,
        insert: data.insert,
        update: data.update,
        delete: data.delete,
        filesCount: data.files.size,
        files: Array.from(data.files)
      }
    ])
  ),
  rpc: Object.fromEntries(
    Object.entries(rpcUsage).map(([rpc, files]) => [rpc, Array.from(files)])
  )
};

fs.writeFileSync(path.join(__dirname, 'client_postgrest_usage.json'), JSON.stringify(summary, null, 2));
console.log('Client PostgREST usage analyzed. Tables found:', Object.keys(summary.tables).length, 'RPCs found:', Object.keys(summary.rpc).length);
