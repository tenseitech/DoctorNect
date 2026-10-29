'use strict';

const fs = require('fs');
const path = require('path');

const migrationsDir = path.resolve(__dirname, '../../db/migrations');
const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();

console.log(`Scanning ${files.length} migrations for current_user / session_user inside SECURITY DEFINER functions...\n`);

const results = [];

for (const file of files) {
  const content = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
  // Match functions: CREATE ... FUNCTION ... SECURITY DEFINER ... $$ ... $$
  // Or scan line by line with function boundaries
  const lines = content.split('\n');
  let currentFunc = null;
  let isSecDef = false;
  let funcStartLine = 0;
  let funcBodyLines = [];

  for (let idx = 0; idx < lines.length; idx++) {
    const line = lines[idx];
    const lineNum = idx + 1;

    const funcMatch = line.match(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-zA-Z0-9_\.]+)/i);
    if (funcMatch) {
      currentFunc = funcMatch[1];
      funcStartLine = lineNum;
      isSecDef = false;
      funcBodyLines = [];
    }

    if (currentFunc) {
      funcBodyLines.push({ lineNum, line });
      if (/SECURITY\s+DEFINER/i.test(line)) {
        isSecDef = true;
      }

      // Check if function definition ended
      // usually ends with `$$ ...;` or `LANGUAGE ...;`
      if (line.includes('$$') && funcBodyLines.length > 2 && /;\s*$/.test(line.trim())) {
        if (isSecDef) {
          for (const item of funcBodyLines) {
            if (/\bcurrent_user\b/i.test(item.line) || /\bsession_user\b/i.test(item.line)) {
              results.push({
                file,
                func: currentFunc,
                startLine: funcStartLine,
                hitLine: item.lineNum,
                text: item.line.trim()
              });
            }
          }
        }
        currentFunc = null;
        isSecDef = false;
        funcBodyLines = [];
      }
    }
  }
}

console.log(`Found ${results.length} occurrences:`);
for (const r of results) {
  console.log(`${r.file}:${r.hitLine} in ${r.func}: ${r.text}`);
}

