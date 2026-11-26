'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const SMOKE_PASSTHROUGH = [
  'PATH',
  'PATHEXT',
  'SYSTEMROOT',
  'SystemRoot',
  'WINDIR',
  'TEMP',
  'TMP',
  'USERPROFILE',
  'COMSPEC',
  'HOME',
  'HOMEDRIVE',
  'HOMEPATH',
];

function parseDotEnvFile(envPath) {
  const out = {};
  if (!fs.existsSync(envPath)) return out;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    const k = t.slice(0, eq);
    let v = t.slice(eq + 1);
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    out[k] = v;
  }
  return out;
}

function buildFunctionsSmokeChildEnv({ functionsDir, boundSecretKeys = [] }) {
  const base = {
    NODE_ENV: 'production',
    K_SERVICE: 'senduserregistrationotp',
    FUNCTION_TARGET: 'sendUserRegistrationOtp',
    GCLOUD_PROJECT: 'medibond-45fad',
    GOOGLE_CLOUD_PROJECT: 'medibond-45fad',
  };
  for (const key of SMOKE_PASSTHROUGH) {
    if (process.env[key] !== undefined) base[key] = process.env[key];
  }
  const fileEnv = parseDotEnvFile(path.join(functionsDir, '.env'));
  Object.assign(base, fileEnv);
  for (const key of boundSecretKeys) {
    base[key] = `mock-${key.toLowerCase()}-smoke`;
  }
  return base;
}

function maskSmokeErrorText(text) {
  let s = String(text || '');
  const patterns = [
    /sb_secret_[A-Za-z0-9_-]+/g,
    /sb_publishable_[A-Za-z0-9_-]+/g,
    /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,
    /mock-[a-z0-9_]+-smoke/gi,
    /\b\d{10}\b/g,
  ];
  for (const re of patterns) {
    s = s.replace(re, '[masked]');
  }
  return s;
}

module.exports = {
  buildFunctionsSmokeChildEnv,
  parseDotEnvFile,
  maskSmokeErrorText,
  SMOKE_PASSTHROUGH,
};