'use strict';

const fs = require('fs');
const path = require('path');

/** Origins required by Flutter Web + Firebase SDK loader (compile-time / static analysis). */
const REQUIRED_FLUTTER_WEB_CONNECT_ORIGINS = [
  'https://api.doctornect.com',
  'https://doctornect.com',
  'https://www.doctornect.com',
  'https://app.doctornect.com',
  'https://medibond-45fad.web.app',
  'https://medibond-45fad.firebaseapp.com',
  'https://medibond-45fad.firebaseio.com',
  'wss://medibond-45fad.firebaseio.com',
  'https://asia-south1-medibond-45fad.cloudfunctions.net',
  'https://firestore.googleapis.com',
  'https://identitytoolkit.googleapis.com',
  'https://securetoken.googleapis.com',
  'https://www.googleapis.com',
  'https://firebase.googleapis.com',
  'https://firebaseinstallations.googleapis.com',
  'https://fcmregistrations.googleapis.com',
  'https://firebasestorage.googleapis.com',
  'https://maps.googleapis.com',
  'https://api.razorpay.com',
  'https://lumberjack.razorpay.com',
  'https://www.gstatic.com',
  'https://content-firebaseappcheck.googleapis.com',
  'https://firebaseappcheck.googleapis.com',
];

const REQUIRED_CONNECT_PATTERNS = [
  'https://*.supabase.co',
  'wss://*.supabase.co',
];

function readFirebaseHostingCsp(repoRoot = path.join(__dirname, '..', '..')) {
  const firebaseJson = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'firebase.json'), 'utf8'),
  );
  const globalHeaders = firebaseJson.hosting.headers.find((entry) => entry.source === '**');
  const cspHeader = globalHeaders.headers.find((entry) => entry.key === 'Content-Security-Policy');
  return cspHeader.value;
}

function parseCspDirectives(csp) {
  const map = new Map();
  for (const part of String(csp || '').split(';')) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const space = trimmed.indexOf(' ');
    if (space === -1) {
      map.set(trimmed, []);
      continue;
    }
    const name = trimmed.slice(0, space);
    const values = trimmed.slice(space + 1).trim().split(/\s+/).filter(Boolean);
    map.set(name, values);
  }
  return map;
}

function hostMatchesCspEntry(origin, entry) {
  const normalized = String(origin || '').trim().toLowerCase();
  const rule = String(entry || '').trim().toLowerCase();
  if (!normalized || !rule) return false;
  if (rule === normalized) return true;
  if (rule.startsWith('https://*.') || rule.startsWith('wss://*.') || rule.startsWith('http://*.')) {
    const suffix = rule.replace(/^wss?:\/\/\*\./, '');
    try {
      const host = new URL(normalized).hostname.toLowerCase();
      return host === suffix || host.endsWith(`.${suffix}`);
    } catch (_) {
      return false;
    }
  }
  return false;
}

function originAllowedByConnectSrc(connectSrcValues, origin) {
  return connectSrcValues.some((entry) => hostMatchesCspEntry(origin, entry));
}

function assertConnectSrcCoversRequiredOrigins(csp) {
  const directives = parseCspDirectives(csp);
  const connectSrc = directives.get('connect-src') || [];
  const missing = [];
  for (const origin of REQUIRED_FLUTTER_WEB_CONNECT_ORIGINS) {
    if (!originAllowedByConnectSrc(connectSrc, origin)) {
      missing.push(origin);
    }
  }
  for (const pattern of REQUIRED_CONNECT_PATTERNS) {
    const hasPattern = connectSrc.some((e) => e.toLowerCase() === pattern.toLowerCase());
    if (!hasPattern) missing.push(pattern);
  }
  return { ok: missing.length === 0, missing, connectSrc };
}

function assertConnectSrcNotWildcarded(csp) {
  const directives = parseCspDirectives(csp);
  const connectSrc = directives.get('connect-src') || [];
  const bad = connectSrc.filter((v) => v === 'https:' || v === 'http:' || v === 'wss:' || v === 'ws:');
  return { ok: bad.length === 0, bad, connectSrc };
}

module.exports = {
  REQUIRED_FLUTTER_WEB_CONNECT_ORIGINS,
  REQUIRED_CONNECT_PATTERNS,
  readFirebaseHostingCsp,
  parseCspDirectives,
  hostMatchesCspEntry,
  originAllowedByConnectSrc,
  assertConnectSrcCoversRequiredOrigins,
  assertConnectSrcNotWildcarded,
};