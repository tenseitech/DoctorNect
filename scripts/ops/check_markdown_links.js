'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const MD_LINK = /\[[^\]]*\]\(([^)]+)\)/g;
const MD_REF_LINK = /\[[^\]]*\]:\s*(\S+)/g;

function stripFencedCode(content) {
  return content.replace(/```[\s\S]*?```/g, '');
}

function existsTarget(fromRelFile, raw) {
  let t = raw.trim();
  if (
    !t ||
    t.startsWith('http://') ||
    t.startsWith('https://') ||
    t.startsWith('mailto:') ||
    t.startsWith('file://')
  ) {
    return true;
  }
  if (t.startsWith('#')) return true;
  t = t.split('#')[0].split('?')[0];
  if (!t) return true;
  const fromDir = path.dirname(path.join(ROOT, fromRelFile));
  const abs = t.startsWith('/')
    ? path.join(ROOT, t.replace(/^\//, ''))
    : path.resolve(fromDir, t);
  return fs.existsSync(abs);
}

function scanFile(filePath) {
  const rel = path.relative(ROOT, filePath);
  const content = stripFencedCode(fs.readFileSync(filePath, 'utf8'));
  const broken = [];
  for (const re of [MD_LINK, MD_REF_LINK]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(content))) {
      const target = m[1];
      if (!existsTarget(rel, target)) broken.push({ file: rel, target });
    }
  }
  return broken;
}

function main() {
  const targets = process.argv.slice(2);
  const files =
    targets.length > 0
      ? targets.map((f) => path.resolve(ROOT, f))
      : walkMd(path.join(ROOT, 'docs')).concat(
          ['README.md', 'PROJECT_STRUCTURE.md', 'CLEANUP_REPORT.md', 'ENVIRONMENTS.md'].map((f) =>
            path.join(ROOT, f),
          ),
        );

  const all = [];
  for (const f of files) {
    if (fs.existsSync(f)) all.push(...scanFile(f));
  }
  if (all.length) {
    console.error('Broken markdown links:');
    for (const b of all) console.error(`  ${b.file} -> ${b.target}`);
    process.exit(1);
  }
  console.log(`Markdown link check PASS (${files.length} files scanned).`);
}

function walkMd(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) out.push(...walkMd(p));
    else if (ent.name.endsWith('.md')) out.push(p);
  }
  return out;
}

main();
