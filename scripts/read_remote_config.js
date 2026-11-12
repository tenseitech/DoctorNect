#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
module.paths.push(path.resolve(ROOT_DIR, 'backend/functions/node_modules'));

async function inspectRemoteConfig() {
  const saPath = path.resolve(ROOT_DIR, 'scripts/service-account.json');
  if (!fs.existsSync(saPath)) {
    console.error('scripts/service-account.json missing');
    process.exit(1);
  }

  const { initializeApp, cert, getApps } = require('firebase-admin/app');
  const { getRemoteConfig } = require('firebase-admin/remote-config');

  const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  const app = getApps().length === 0 ? initializeApp({ credential: cert(sa) }) : getApps()[0];

  try {
    const rc = getRemoteConfig(app);
    const template = await rc.getTemplate();
    console.log('REMOTE_CONFIG_FETCH_SUCCESS');
    console.log(JSON.stringify(template.parameters, null, 2));
  } catch (err) {
    console.error('REMOTE_CONFIG_FETCH_ERROR:', err.message);
  }
}

inspectRemoteConfig().catch(console.error);
