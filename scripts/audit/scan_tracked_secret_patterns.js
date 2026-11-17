'use strict';

const { execSync } = require('child_process');
const fs = require('fs');

const patterns = [
  { t: 'AWS_AKIA', re: /AKIA[0-9A-Z]{16}/g },
  { t: 'sb_secret', re: /sb_secret_/g },
  { t: 'sb_publishable', re: /sb_publishable_/g },
  { t: 'rzp_live', re: /rzp_live_/g },
  { t: 'jwt_eyj', re: /eyJ[A-Za-z0-9_-]{20,}\.eyJ/g },
  { t: 'PEM_BEGIN', re: /-----BEGIN/g },
  { t: 'password_eq', re: /password=/gi },
  { t: 'postgres_user_pass', re: /postgres:\/\/user:pass@/gi },
];

const files = execSync('git ls-files', { encoding: 'utf8' })
  .trim()
  .split(/\r?\n/)
  .filter(Boolean);

const hits = [];
for (const f of files) {
  let content;
  try {
    content = fs.readFileSync(f, 'utf8');
  } catch (_) {
    continue;
  }
  const lines = content.split(/\r?\n/);
  lines.forEach((line, i) => {
    for (const p of patterns) {
      if (p.re.test(line)) {
        hits.push(`${f}:${i + 1} ${p.t}`);
        p.re.lastIndex = 0;
      }
    }
  });
}

if (!hits.length) {
  console.log('NO_MATCHES');
} else {
  console.log(hits.join('\n'));
}