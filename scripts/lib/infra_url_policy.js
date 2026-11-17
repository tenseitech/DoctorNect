'use strict';

const crypto = require('crypto');

/** Neutral placeholders allowed in committed docs/tests (never real project refs). */
const ALLOWED_SUPABASE_PROJECT_REFS = new Set([
  'your-project-ref',
  'staging-project-ref',
  'example-project-ref',
  'examplestagingref',
]);

const ALLOWED_RDS_HOST_PATTERN = /^example-db\.xxxxxxxx\.ap-south-1\.rds\.amazonaws\.com$/i;

/**
 * SHA-256(project_ref)[0:8] uppercase — forbidden Supabase refs (no plaintext refs in repo).
 */
const FORBIDDEN_SUPABASE_REF_HASHES = new Set([
  '750202DA',
  'F1A1FE09',
]);

const SUPABASE_CLOUD_HOST_RE = /\.supabase\.co\b/i;
const RDS_HOST_RE = /\.rds\.amazonaws\.com\b/i;
const SUPABASE_REF_IN_URL_RE = /([a-z0-9]{12,30})\.supabase\.co/gi;
const RDS_HOST_CAPTURE_RE = /([a-z0-9.-]+)\.rds\.amazonaws\.com/gi;

function infraTokenHash8(token) {
  if (!token) return '';
  const normalized = String(token).trim().toLowerCase();
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex').slice(0, 8).toUpperCase();
}

function isSupabaseCloudUrl(url) {
  if (!url || typeof url !== 'string') return false;
  return SUPABASE_CLOUD_HOST_RE.test(url);
}

function resolveStagingProjectRefFromEnv(env = {}) {
  const candidates = [env.STAGING_SUPABASE_URL, env.STAGING_SUPABASE_DB_URL].filter(Boolean);
  for (const raw of candidates) {
    try {
      const normalized = String(raw).replace(/^postgres:\/\//i, 'https://');
      const host = new URL(normalized).hostname;
      const m = host.match(/^([a-z0-9-]+)\.supabase\.co$/i);
      if (m) return m[1].toLowerCase();
      const pooler = host.match(/^postgres\.([a-z0-9-]+)/i);
      if (pooler && String(host).includes('supabase')) return pooler[1].toLowerCase();
    } catch (_) {
      // fall through
    }
    const inline = String(raw).match(/\/\/([a-z0-9]{10,30})\.supabase\.co/i);
    if (inline) return inline[1].toLowerCase();
  }
  return '';
}

function urlContainsStagingProjectRef(url, stagingRef) {
  if (!url || !stagingRef) return false;
  const lower = String(url).toLowerCase();
  const ref = stagingRef.toLowerCase();
  return (
    lower.includes(`${ref}.supabase.co`)
    || lower.includes(`postgres.${ref}`)
    || lower.includes(`//${ref}.`)
  );
}

function isForbiddenSupabaseProjectRef(ref) {
  if (!ref) return false;
  const r = ref.toLowerCase();
  if (ALLOWED_SUPABASE_PROJECT_REFS.has(r)) return false;
  return FORBIDDEN_SUPABASE_REF_HASHES.has(infraTokenHash8(r));
}

function isAllowedSupabaseProjectRef(ref) {
  if (!ref) return false;
  const r = ref.toLowerCase();
  if (isForbiddenSupabaseProjectRef(r)) return false;
  return ALLOWED_SUPABASE_PROJECT_REFS.has(r);
}

function isAllowedRdsHostname(host) {
  if (!host) return false;
  const h = host.toLowerCase();
  if (h === 'truststore.pki.rds.amazonaws.com') return true;
  if (ALLOWED_RDS_HOST_PATTERN.test(h)) return true;
  if (/^your-db\.x+/i.test(h)) return true;
  if (/^your-existing-rds-endpoint\.rds\.amazonaws\.com$/i.test(h)) return true;
  if (h === 'wrong-host.rds.amazonaws.com' || h === 'myhost.rds.amazonaws.com') return true;
  return false;
}

function isForbiddenRdsHostname(host) {
  if (!host || !RDS_HOST_RE.test(host)) return false;
  return !isAllowedRdsHostname(host);
}

function collectSupabaseRefCandidates(text) {
  const candidates = new Set();
  if (!text || typeof text !== 'string') return candidates;

  let m;
  const urlRe = new RegExp(SUPABASE_REF_IN_URL_RE.source, 'gi');
  while ((m = urlRe.exec(text)) !== null) {
    candidates.add(m[1].toLowerCase());
  }

  const tokenRe = /\b([a-z0-9]{12,30})\b/gi;
  while ((m = tokenRe.exec(text)) !== null) {
    const t = m[1].toLowerCase();
    if (t.length >= 18) candidates.add(t);
  }

  return candidates;
}

function scanTextForInfraFingerprints(text, relPath = '') {
  const hits = [];
  if (!text || typeof text !== 'string') return hits;

  for (const ref of collectSupabaseRefCandidates(text)) {
    if (isForbiddenSupabaseProjectRef(ref)) {
      hits.push({
        kind: 'supabase_ref',
        value: infraTokenHash8(ref),
        path: relPath,
      });
    }
  }

  let rdsM;
  const rdsRe = new RegExp(RDS_HOST_CAPTURE_RE.source, 'gi');
  while ((rdsM = rdsRe.exec(text)) !== null) {
    const host = rdsM[0].toLowerCase();
    if (isForbiddenRdsHostname(host)) {
      hits.push({ kind: 'rds_host', value: host, path: relPath });
    }
  }

  return hits;
}

module.exports = {
  ALLOWED_SUPABASE_PROJECT_REFS,
  ALLOWED_RDS_HOST_PATTERN,
  FORBIDDEN_SUPABASE_REF_HASHES,
  infraTokenHash8,
  isSupabaseCloudUrl,
  resolveStagingProjectRefFromEnv,
  urlContainsStagingProjectRef,
  isForbiddenSupabaseProjectRef,
  isAllowedSupabaseProjectRef,
  isAllowedRdsHostname,
  scanTextForInfraFingerprints,
};
