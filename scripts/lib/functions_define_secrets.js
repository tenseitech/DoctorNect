'use strict';

const fs = require('fs');
const path = require('path');

const DEFINE_SECRET_RE = /defineSecret\s*\(\s*['"]([A-Z][A-Z0-9_]*)['"]\s*\)/g;

/** Declared firebase-functions/params secret names from backend/functions source (no hardcoded list). */
function collectDefineSecretNames(functionsDir) {
  const root = functionsDir || path.join(__dirname, '..', '..', 'backend', 'functions');
  const names = new Set();
  walkJs(root, root, names);
  return names;
}

function walkJs(dir, root, names) {
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
      walkJs(full, root, names);
      continue;
    }
    if (!ent.name.endsWith('.js')) continue;
    const src = fs.readFileSync(full, 'utf8');
    let m;
    DEFINE_SECRET_RE.lastIndex = 0;
    while ((m = DEFINE_SECRET_RE.exec(src)) !== null) {
      names.add(m[1]);
    }
  }
}

/** Remove keys that collide with defineSecret bindings (plain env + secret mount). */
function filterSecretBoundEnv(env, secretNames = null) {
  const secrets = secretNames || collectDefineSecretNames();
  const out = {};
  for (const [key, value] of Object.entries(env || {})) {
    if (secrets.has(key)) continue;
    out[key] = value;
  }
  return out;
}

function assertNoSecretBoundEnvKeys(env, secretNames = null) {
  const secrets = secretNames || collectDefineSecretNames();
  const overlaps = Object.keys(env || {}).filter((k) => secrets.has(k)).sort();
  if (overlaps.length) {
    throw new Error(
      `functions .env must not contain defineSecret keys (use Secret Manager binding only): ${overlaps.join(', ')}`,
    );
  }
}

module.exports = {
  collectDefineSecretNames,
  filterSecretBoundEnv,
  assertNoSecretBoundEnvKeys,
};