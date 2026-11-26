'use strict';

/**
 * Serves Flutter Web build with firebase.json CSP headers for local browser smoke (SEC-07).
 * Usage: node scripts/security/csp_local_smoke_server.js
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const {
  readFirebaseHostingCsp,
  parseCspDirectives,
} = require('../lib/hosting_csp');

const repoRoot = path.join(__dirname, '..', '..');
const publicDir = path.join(repoRoot, 'frontend', 'build', 'web');
const port = parseInt(process.env.CSP_SMOKE_PORT || '8765', 10);

const csp = readFirebaseHostingCsp(repoRoot);
const securityHeaders = [
  ['Content-Security-Policy', csp],
  ['X-Content-Type-Options', 'nosniff'],
  ['X-Frame-Options', 'DENY'],
  ['Referrer-Policy', 'strict-origin-when-cross-origin'],
];

const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json',
  '.css': 'text/css',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
};

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  let filePath = path.join(publicDir, urlPath === '/' ? 'index.html' : urlPath);
  if (!filePath.startsWith(publicDir)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(publicDir, 'index.html');
  }
  const ext = path.extname(filePath).toLowerCase();
  const body = fs.readFileSync(filePath);
  const headers = { 'Content-Type': contentTypes[ext] || 'application/octet-stream' };
  for (const [k, v] of securityHeaders) headers[k] = v;
  res.writeHead(200, headers);
  res.end(body);
});

server.listen(port, '127.0.0.1', () => {
  const directives = parseCspDirectives(csp);
  const connectCount = (directives.get('connect-src') || []).length;
  process.stdout.write(
    JSON.stringify({
      event: 'csp_smoke_server_ready',
      url: `http://127.0.0.1:${port}/`,
      connectSrcEntries: connectCount,
    }) + '\n',
  );
});