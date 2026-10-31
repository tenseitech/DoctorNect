#!/usr/bin/env node
/**
 * Blocks accidental Cloud Functions deploy before notification_outbox migration is applied.
 * Does not connect to any database. Operator must confirm migration out-of-band.
 *
 * Skip: DEPLOY_SKIP_OUTBOX_GUARD=1 (e.g. fallback release from pre-outbox git tag).
 * Ack:  DEPLOY_CONFIRM_NOTIFICATION_OUTBOX_MIGRATION=1
 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const indexPath = path.join(root, 'backend/functions/index.js');

if (process.env.DEPLOY_SKIP_OUTBOX_GUARD === '1') {
  console.log('predeploy_notification_outbox_guard: skipped (DEPLOY_SKIP_OUTBOX_GUARD=1).');
  process.exit(0);
}

if (process.env.DEPLOY_CONFIRM_NOTIFICATION_OUTBOX_MIGRATION === '1') {
  console.log('predeploy_notification_outbox_guard: acknowledged (migration applied).');
  process.exit(0);
}

let src = '';
try {
  src = fs.readFileSync(indexPath, 'utf8');
} catch (_) {
  console.warn('predeploy_notification_outbox_guard: index.js not found; skipping.');
  process.exit(0);
}

if (!src.includes('processNotificationOutboxScheduled')) {
  process.exit(0);
}

console.error(`
DEPLOY BLOCKED: backend/functions exports processNotificationOutboxScheduled.

Apply migration db/migrations/20261103000010_notification_outbox.sql to the target database
BEFORE deploying these functions, then re-run deploy with:

  DEPLOY_CONFIRM_NOTIFICATION_OUTBOX_MIGRATION=1 firebase deploy --only functions --project medibond-45fad

Fallback deploy from a git tag without the outbox worker:

  DEPLOY_SKIP_OUTBOX_GUARD=1 firebase deploy --only functions --project medibond-45fad
`);
process.exit(1);
