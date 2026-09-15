'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..', '..');

function readHostingCsp() {
  const firebaseJson = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'firebase.json'), 'utf8'),
  );
  const globalHeaders = firebaseJson.hosting.headers.find((entry) => entry.source === '**');
  const cspHeader = globalHeaders.headers.find((entry) => entry.key === 'Content-Security-Policy');
  return cspHeader.value;
}

function scriptSrcDirective(csp) {
  return csp
    .split(';')
    .map((part) => part.trim())
    .find((part) => part.startsWith('script-src '));
}

test('hosting script-src disallows unsafe-inline and unsafe-eval', () => {
  const scriptSrc = scriptSrcDirective(readHostingCsp());
  assert.ok(scriptSrc);
  assert.doesNotMatch(scriptSrc, /'unsafe-inline'/);
  assert.doesNotMatch(scriptSrc, /'unsafe-eval'/);
});

test('hosting script-src allows wasm-unsafe-eval for self-hosted CanvasKit', () => {
  const scriptSrc = scriptSrcDirective(readHostingCsp());
  assert.match(scriptSrc, /'wasm-unsafe-eval'/);
  assert.match(scriptSrc, /'self'/);
});

test('hosting script-src allows Razorpay checkout CDN and known inline hash', () => {
  const scriptSrc = scriptSrcDirective(readHostingCsp());
  assert.match(scriptSrc, /https:\/\/cdn\.razorpay\.com/);
  assert.match(scriptSrc, /https:\/\/checkout\.razorpay\.com/);
  assert.match(scriptSrc, /'sha256-wv\/MkaW\+e2bdw8mgY\/lUXEmxvFXYRbAowmoG67zWW4='/);
});

test('web/index.html has no inline script blocks', () => {
  const html = fs.readFileSync(path.join(repoRoot, 'web', 'index.html'), 'utf8');
  const inlineScripts = html.match(/<script(?![^>]*\bsrc=)[^>]*>[\s\S]*?<\/script>/gi) || [];
  assert.equal(inlineScripts.length, 0, `Inline scripts remain: ${inlineScripts.join(' | ')}`);
});

test('externalized bootstrap scripts exist under web/scripts', () => {
  for (const file of ['force-https.js', 'pdfjs-config.js', 'splash-bootstrap.js']) {
    assert.ok(
      fs.existsSync(path.join(repoRoot, 'web', 'scripts', file)),
      `Missing web/scripts/${file}`,
    );
  }
});
