'use strict';

const fs = require('fs');
const path = require('path');

function scanFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');
  const results = [];

  // Match expressions like:
  // v_x.col != ...
  // OLD.col != ...
  // NEW.col != ...
  // v_x.col <> ...
  // v_x.col NOT IN ...
  // ... != v_x.col
  // ... <> v_x.col
  const regexes = [
    /\b([a-zA-Z0-9_]+\.[a-zA-Z0-9_]+)\s*(?:!=|<>)\s*([^\s;,\)]+)/g,
    /\b([^\s;,\(]+)\s*(?:!=|<>)\s*([a-zA-Z0-9_]+\.[a-zA-Z0-9_]+)/g,
    /\b([a-zA-Z0-9_]+\.[a-zA-Z0-9_]+)\s+NOT\s+IN\s*\(([^\)]+)\)/gi
  ];

  for (let lineNum = 0; lineNum < lines.length; lineNum++) {
    const line = lines[lineNum];
    // Skip comments
    const trimmed = line.trim();
    if (trimmed.startsWith('--')) continue;

    for (const re of regexes) {
      re.lastIndex = 0;
      let match;
      while ((match = re.exec(line)) !== null) {
        // Exclude schema-qualified table names like public.appointments or pg_catalog.x
        const fullExpr = match[0];
        const left = match[1];
        const right = match[2];
        
        const isRecordField = (str) => {
          if (!str) return false;
          const parts = str.split('.');
          if (parts.length !== 2) return false;
          const prefix = parts[0].toLowerCase();
          return prefix === 'old' || prefix === 'new' || prefix.startsWith('v_');
        };

        if (isRecordField(left) || isRecordField(right)) {
          results.push({
            line: lineNum + 1,
            code: line.trim(),
            expression: fullExpr,
            left,
            right
          });
        }
      }
    }
  }

  return results;
}

const targetFile = 'db/migrations/20261026000001_rpc_null_safe_authz.sql';
console.log(`Scanning ${targetFile} for !=, <>, NOT IN on record fields (v_x.col, OLD.col, NEW.col)...`);
const hits = scanFile(targetFile);

console.log(`\nFound ${hits.length} occurrences in ${targetFile}:`);
for (const h of hits) {
  console.log(`Line ${h.line}: ${h.code}`);
  console.log(`  Expression: "${h.expression}"\n`);
}

module.exports = { scanFile };

