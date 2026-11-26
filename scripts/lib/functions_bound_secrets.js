'use strict';

const fs = require('fs');
const path = require('path');
const { collectDefineSecretNames } = require('./functions_define_secrets');

const DEFINE_SECRET_VAR_RE =
  /(?:const|let|var)\s+(\w+)\s*=\s*defineSecret\s*\(\s*['"]([A-Z][A-Z0-9_]*)['"]\s*\)/g;

/** Map SecretParam variable names (e.g. supabaseServiceRoleKey) → env key names. */
function buildSecretVarNameMap(functionsDir) {
  const map = new Map();
  const root = functionsDir || path.join(__dirname, '..', '..', 'backend', 'functions');
  walkJsForVars(root, root, map);
  return map;
}

function walkJsForVars(dir, root, map) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (_) {
    return;
  }
  for (const ent of entries) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (ent.name === 'node_modules' || ent.name === 'test') continue;
      walkJsForVars(full, root, map);
      continue;
    }
    if (!ent.name.endsWith('.js')) continue;
    const src = fs.readFileSync(full, 'utf8');
    let m;
    DEFINE_SECRET_VAR_RE.lastIndex = 0;
    while ((m = DEFINE_SECRET_VAR_RE.exec(src)) !== null) {
      map.set(m[1], m[2]);
    }
  }
}

const SPREAD_IDENTIFIERS = ['OTP_REDIS_SECRET_OPTIONS', 'OTP_DATA_PLANE_SECRETS'];

/** Keys added by withDataPlaneSecrets() (backend/functions/demo_plane_secrets.js). */
const DATA_PLANE_SECRET_KEYS = ['PROD_GATEWAY_SERVICE_KEY', 'DEMO_SUPABASE_SERVICE_ROLE_KEY'];

function resolveSecretArraySpread(identifier, indexSrc, varToName) {
  const re = new RegExp(`const\\s+${identifier}\\s*=\\s*\\[([\\s\\S]*?)\\];`, 'm');
  const m = re.exec(indexSrc);
  if (!m) return [];
  const ids = m[1].match(/[A-Za-z_$][\w$]*/g) || [];
  const keys = [];
  for (const id of ids) {
    if (varToName.has(id)) keys.push(varToName.get(id));
  }
  return keys;
}

/**
 * Secret env keys bound on specific index.js exports (parsed from source).
 * @param {string[]} exportNames
 * @param {string} [functionsDir]
 * @returns {Set<string>}
 */
function collectBoundSecretEnvKeysForExports(exportNames, functionsDir) {
  const root = functionsDir || path.join(__dirname, '..', '..', 'backend', 'functions');
  const indexPath = path.join(root, 'index.js');
  const src = fs.readFileSync(indexPath, 'utf8');
  const varToName = buildSecretVarNameMap(root);
  const keys = new Set();

  for (const exportName of exportNames) {
    const blockRe = new RegExp(
      `exports\\.${exportName}\\s*=\\s*onCall\\(\\s*\\{([\\s\\S]*?)\\}\\s*,`,
    );
    const block = blockRe.exec(src);
    if (!block) continue;
    const opts = block[1];
    // secrets: [..] or secrets: withDataPlaneSecrets([..]); the wrapper always adds the data-plane keys.
    const secretsRe = /secrets:\s*(withDataPlaneSecrets\(\s*)?\[([\s\S]*?)\]/;
    const sec = secretsRe.exec(opts);
    if (!sec) continue;
    if (sec[1]) for (const k of DATA_PLANE_SECRET_KEYS) keys.add(k);
    const list = sec[2];
    const idents = list.match(/[A-Za-z_$][\w$]*/g) || [];
    for (const id of idents) {
      if (SPREAD_IDENTIFIERS.includes(id)) {
        if (id === 'OTP_REDIS_SECRET_OPTIONS') {
          const mirrorOn =
            /OTP_REDIS_MIRROR_ON\s*=\s*String\(process\.env\.OTP_REDIS_MIRROR/.test(src) &&
            String(process.env.OTP_REDIS_MIRROR || '').trim().toLowerCase() === 'on';
          if (mirrorOn) {
            for (const k of ['REDIS_HOST', 'REDIS_PORT', 'REDIS_PASSWORD']) keys.add(k);
          }
        } else if (id === 'OTP_DATA_PLANE_SECRETS') {
          for (const k of resolveSecretArraySpread(id, src, varToName)) keys.add(k);
        }
        continue;
      }
      if (varToName.has(id)) {
        keys.add(varToName.get(id));
      }
    }
  }
  return keys;
}

const NARROW_OTP_EXPORTS = [
  'sendUserRegistrationOtp',
  'verifyUserRegistrationOtp',
  'completeMobileOtpLogin',
  'completeAmbulanceMobileOtpLogin',
];

function collectNarrowOtpBoundSecretKeys(functionsDir) {
  return collectBoundSecretEnvKeysForExports(NARROW_OTP_EXPORTS, functionsDir);
}

function assertNoOverlapWithBoundSecrets(env, boundKeys) {
  const overlaps = Object.keys(env || {})
    .filter((k) => boundKeys.has(k))
    .sort();
  if (overlaps.length) {
    throw new Error(
      `functions .env overlaps secret bindings for OTP deploy: ${overlaps.join(', ')}`,
    );
  }
}

module.exports = {
  NARROW_OTP_EXPORTS,
  buildSecretVarNameMap,
  collectBoundSecretEnvKeysForExports,
  collectNarrowOtpBoundSecretKeys,
  assertNoOverlapWithBoundSecrets,
};