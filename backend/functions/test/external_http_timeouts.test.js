'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

// Every raw https.request to MSG91 / Razorpay must set a timeout and handle 'error', otherwise a
// slow provider holds the function until its 60 s limit.
for (const file of ['registration_otp.js', 'promoted_ads.js']) {
  test(`${file}: every https.request has a timeout and an error handler`, () => {
    const src = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
    const starts = [...src.matchAll(/const req = (?:https|protocol)\.request\(/g)].map((m) => m.index);
    assert.ok(starts.length > 0);
    for (const start of starts) {
      const end = src.indexOf('req.end()', start);
      assert.ok(end > start, 'request without req.end()');
      const body = src.slice(start, end);
      const line = src.slice(0, start).split('\n').length;
      assert.match(body, /req\.setTimeout\(\s*(\d+|[A-Z][A-Z0-9_]*_MS)\b/,`${file}:${line} https.request without req.setTimeout`);
      assert.match(body, /req\.on\('error'/, `${file}:${line} https.request without an error handler`);
    }
  });
}
