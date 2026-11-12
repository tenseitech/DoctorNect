'use strict';

/** Neutral placeholders allowed in committed docs/tests (never real project refs). */
const ALLOWED_SUPABASE_PROJECT_REFS = new Set([
  'your-project-ref',
  'staging-project-ref',
  'example-project-ref',
  'examplestagingref',
]);

const ALLOWED_RDS_HOST_PATTERN = /^example-db\.xxxxxxxx\.ap-south-1\.rds\.amazonaws\.com$/i;

/** Known real refs — always forbidden in git (guard + hygiene). */
const FORBIDDEN_SUPABASE_REFS = new Set([
  'rnltknemwnjrjxthtull',
  'irpkyedfmdsuvapfnrim',
]);

const SUPABASE_CLOUD_HOST_RE = /\.supabase\.co\b/i;
const RDS_HOST_RE = /\.rds\.amazonaws\.com\b/i;
const SUPABASE_REF_IN_URL_RE = /([a-z0-9]{12,30})\.supabase\.co/gi;
const RDS_HOST_CAPTURE_RE = /([a-z0-9.-]+)\.rds\.amazonaws\.com/gi;

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

function isAllowedSupabaseProjectRef(ref) {
  if (!ref) return false;
  const r = ref.toLowerCase();
  if (FORBIDDEN_SUPABASE_REFS.has(r)) return false;
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

function scanTextForInfraFingerprints(text, relPath = '') {
  const hits = [];
  if (!text || typeof text !== 'string') return hits;

  for (const ref of FORBIDDEN_SUPABASE_REFS) {
    if (text.toLowerCase().includes(ref)) {
      hits.push({ kind: 'supabase_ref', value: ref, path: relPath });
    }
  }

  let m;
  const rdsRe = new RegExp(RDS_HOST_CAPTURE_RE.source, 'gi');
  while ((m = rdsRe.exec(text)) !== null) {
    const host = m[0].toLowerCase();
    if (isForbiddenRdsHostname(host)) {
      hits.push({ kind: 'rds_host', value: host, path: relPath });
    }
  }

  return hits;
}

module.exports = {
  ALLOWED_SUPABASE_PROJECT_REFS,
  ALLOWED_RDS_HOST_PATTERN,
  FORBIDDEN_SUPABASE_REFS,
  isSupabaseCloudUrl,
  resolveStagingProjectRefFromEnv,
  urlContainsStagingProjectRef,
  isAllowedSupabaseProjectRef,
  isAllowedRdsHostname,
  scanTextForInfraFingerprints,
};
