'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

let _envModule;

function loadFirebaseToolsEnvModule() {
  if (_envModule) return _envModule;
  try {
    _envModule = require('firebase-tools/lib/functions/env');
    return _envModule;
  } catch (_) {
    const appData = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
    const globalPath = path.join(appData, 'npm', 'node_modules', 'firebase-tools', 'lib', 'functions', 'env.js');
    if (!fs.existsSync(globalPath)) {
      throw new Error(
        'firebase-tools lib/functions/env not found; install firebase-tools globally or add as a dependency.',
      );
    }
    _envModule = require(globalPath);
    return _envModule;
  }
}

/** True when firebase-tools would reject the key in functions .env (runtime-injected / reserved only). */
function isFirebaseToolsReservedEnvKey(key) {
  const { validateKey, KeyValidationError } = loadFirebaseToolsEnvModule();
  try {
    validateKey(key);
    return false;
  } catch (err) {
    if (err instanceof KeyValidationError) {
      const msg = String(err.message || '');
      if (msg.includes('reserved for internal use') || msg.includes('reserved prefix')) {
        return true;
      }
    }
    return false;
  }
}

/** Strip Cloud Run / deploy snapshot keys that firebase-tools injects at runtime. */
function filterBaselineRuntimeEnv(env) {
  const out = {};
  for (const [key, value] of Object.entries(env || {})) {
    if (isFirebaseToolsReservedEnvKey(key)) continue;
    out[key] = value;
  }
  return out;
}

function assertFunctionsEnvFilePassesFirebaseValidation(filePath) {
  const { parseStrict } = loadFirebaseToolsEnvModule();
  const data = fs.readFileSync(filePath, 'utf8');
  parseStrict(data);
}

module.exports = {
  filterBaselineRuntimeEnv,
  isFirebaseToolsReservedEnvKey,
  assertFunctionsEnvFilePassesFirebaseValidation,
  loadFirebaseToolsEnvModule,
};