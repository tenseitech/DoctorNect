'use strict';

/**
 * Server-side demo vs real data-plane resolution.
 * Client hints (headers, query, is_demo body fields) are never trusted.
 */

const crypto = require('node:crypto');

const DEMO_PHONE_ENV_KEYS = [
  'REVIEW_PATIENT_PHONES',
  'REVIEW_DOCTOR_PHONES',
  'REVIEW_MEDICALSTORE_PHONES',
  'REVIEW_PHARMACY_PHONES',
  'REVIEW_LAB_PHONES',
  'REVIEW_AMBULANCE_PHONES',
  'DEMO_PHONE_PATIENT',
  'DEMO_PHONE_DOCTOR',
  'DEMO_PHONE_MEDICAL_STORE',
  'DEMO_PHONE_PHARMACY',
  'DEMO_PHONE_LAB',
  'DEMO_PHONE_AMBULANCE',
];

function normalizeDigits(mobile) {
  return String(mobile || '').replace(/\D/g, '').slice(-10);
}

function parseCsv(raw) {
  return String(raw || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function parseFirebaseUidAllowlist(env = process.env) {
  const raw = env.DEMO_FIREBASE_UID_ALLOWLIST || env.DEMO_ACCOUNT_FIREBASE_UIDS || '';
  return new Set(parseCsv(raw));
}

function collectDemoPhonesFromEnv(env = process.env) {
  const phones = new Set();
  for (const key of DEMO_PHONE_ENV_KEYS) {
    for (const part of parseCsv(env[key])) {
      const d = normalizeDigits(part);
      if (d.length === 10) phones.add(d);
    }
  }
  const roleKeys = ['PATIENT', 'DOCTOR', 'MEDICALSTORE', 'PHARMACY', 'LAB', 'AMBULANCE'];
  for (const role of roleKeys) {
    const key = `REVIEW_${role}_PHONES`;
    for (const part of parseCsv(env[key])) {
      const d = normalizeDigits(part);
      if (d.length === 10) phones.add(d);
    }
  }
  return phones;
}

function isDemoFirebaseUid(uid, env = process.env) {
  const id = String(uid || '').trim();
  if (!id) return false;
  const allow = parseFirebaseUidAllowlist(env);
  if (allow.has(id)) return true;
  const prefixRouting =
    String(env.DEMO_UID_PREFIX_ROUTING || '').trim() === '1';
  if (prefixRouting && (id.startsWith('demo_') || id.startsWith('demo_user_'))) {
    return true;
  }
  return false;
}

function isDemoPhoneDigits(digits, env = process.env) {
  const d = normalizeDigits(digits);
  if (d.length !== 10) return false;
  return collectDemoPhonesFromEnv(env).has(d);
}

/**
 * @returns {'supabase'|'rds'|'staging'}
 */
function resolveDataPlane({
  appEnv = (process.env.APP_ENV || 'staging').toLowerCase(),
  firebaseUid = null,
  env = process.env,
} = {}) {
  if (appEnv !== 'production') {
    return 'staging';
  }
  const routingOn = String(env.DEMO_REAL_ROUTING_ENABLED || '').trim() === '1';
  if (!routingOn) {
    return 'rds';
  }
  if (firebaseUid && isDemoFirebaseUid(firebaseUid, env)) {
    return 'supabase';
  }
  return 'rds';
}

function assertClientRoutingHintIgnored(headers = {}) {
  const blocked = [];
  for (const [k, v] of Object.entries(headers || {})) {
    const key = String(k).toLowerCase();
    if (key === 'x-demo' || key === 'x-data-plane' || key === 'is_demo') {
      blocked.push(key);
    }
    if (key.startsWith('x-demo-')) blocked.push(key);
  }
  return { ok: blocked.length === 0, blocked };
}

function redisKeyNamespace({ appEnv, firebaseUid, env = process.env }) {
  const plane = resolveDataPlane({ appEnv, firebaseUid, env });
  return plane === 'supabase' ? 'demo:' : 'real:';
}

function objectStoragePrefix({ appEnv, firebaseUid, env = process.env }) {
  const plane = resolveDataPlane({ appEnv, firebaseUid, env });
  return plane === 'supabase' ? 'demo/' : 'prod/';
}

function hashUidForLog(uid) {
  if (!uid) return null;
  return crypto.createHash('sha256').update(String(uid)).digest('hex').slice(0, 12);
}

/** Masked summary for audit docs (no secrets). */
function summarizeDemoAllowlistForAudit(env = process.env) {
  const uids = [...parseFirebaseUidAllowlist(env)];
  const phonesByRole = {};
  for (const role of ['patient', 'doctor', 'medicalStore', 'lab', 'ambulance']) {
    const envRole = role === 'medicalStore' ? 'MEDICALSTORE' : role.toUpperCase();
    const list = parseCsv(env[`REVIEW_${envRole}_PHONES`]).map((p) => {
      const d = normalizeDigits(p);
      return d ? `${d.slice(0, 2)}****${d.slice(-2)}` : null;
    }).filter(Boolean);
    phonesByRole[role] = list;
  }
  return {
    firebaseUidAllowlistCount: uids.length,
    firebaseUidSamples: uids.map((u) => hashUidForLog(u)),
    reviewerPhonesMasked: phonesByRole,
    seedScriptRoles: {
      patient: 1,
      doctor: 1,
      medicalStore: 1,
      lab: 1,
      ambulance: 1,
      superAdmin: 0,
    },
  };
}

module.exports = {
  resolveDataPlane,
  isDemoFirebaseUid,
  isDemoPhoneDigits,
  parseFirebaseUidAllowlist,
  collectDemoPhonesFromEnv,
  assertClientRoutingHintIgnored,
  redisKeyNamespace,
  objectStoragePrefix,
  hashUidForLog,
  summarizeDemoAllowlistForAudit,
  normalizeDigits,
};