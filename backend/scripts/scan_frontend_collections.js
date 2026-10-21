const fs = require('fs');
const path = require('path');

function walk(dir) {
  let res = [];
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) res = res.concat(walk(p));
    else if (p.endsWith('.dart')) res.push(p);
  }
  return res;
}

const files = walk(path.join(__dirname, '../../frontend/lib'));
const collMap = new Map();

for (const f of files) {
  const content = fs.readFileSync(f, 'utf8');
  const matches = [...content.matchAll(/\.collection\(['"]([^'"]+)['"]\)/g)];
  if (matches.length > 0) {
    const rel = path.relative(path.join(__dirname, '../..'), f).replace(/\\/g, '/');
    for (const m of matches) {
      if (!collMap.has(m[1])) collMap.set(m[1], []);
      collMap.get(m[1]).push(rel);
    }
  }
}

for (const [coll, flist] of Array.from(collMap.entries()).sort()) {
  console.log(`Collection: ${coll} (${flist.length} files)`);
  for (const fl of flist) console.log(`  - ${fl}`);
}
