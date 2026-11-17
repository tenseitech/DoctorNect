'use strict';

const fs = require('fs');
const path = require('path');
const cfg = require('../../services/api-gateway/src/config');

const report = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../docs/reports/grant_matrix_local.json'), 'utf8'));
const diffs = report.tableDiffs || [];

const serviceTables = new Set([
  ...cfg.serviceRoleOnlyTables,
  'admin_audit_logs',
  'notification_outbox',
  'sync_dead_letter_queue',
  'otp_challenges',
  'otp_verification_sessions',
  'abuse_rate_limits',
  'mail_queue',
  'security_events',
  'razorpay_payments',
  'users',
  'patients',
  'doctors',
  'medical_stores',
  'labs',
  'ambulances',
  'appointments',
  'prescriptions',
  'pharmacy_deliveries',
  'lab_bookings',
  'lab_orders',
  'health_records',
  'family_members',
  'in_app_notifications',
  'user_devices',
  'promoted_ads',
  'ambulance_broadcasts',
  'ambulance_requests',
  'referrals',
  'patient_doctor_links',
  'support_tickets',
  'support_ticket_messages',
]);

const supabaseNoise = new Set(['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);

function parsePrivs(s) {
  return new Set((s || '').split(',').filter(Boolean));
}

function isSupabaseAll(stagingPrivs) {
  const p = parsePrivs(stagingPrivs);
  return [...supabaseNoise].every((x) => p.has(x)) && p.size === supabaseNoise.size;
}

function classify(d) {
  const [table, grantee] = d.key.split(':');
  const localP = parsePrivs(d.local);
  const stagingP = parsePrivs(d.staging);

  if (d.kind === 'missing_in_a') {
    return { table, grantee, class: 'b', note: 'local missing row (staging only)' };
  }
  if (d.kind === 'missing_in_b') {
    return { table, grantee, class: 'c', note: 'staging missing grant row vs local' };
  }

  const stagingMore = [...stagingP].filter((p) => !localP.has(p));
  const localMore = [...localP].filter((p) => !stagingP.has(p));

  if (grantee === 'service_role' && isSupabaseAll(d.staging) && localP.size <= 4) {
    return { table, grantee, class: 'a', note: `staging GRANT ALL pattern; local DML-only (${[...localP].join('/')})` };
  }
  if (stagingMore.length && !localMore.length) {
    return { table, grantee, class: 'a', note: `staging extra: ${stagingMore.join(', ')}` };
  }
  if (localMore.length && !stagingMore.length) {
    const needed = grantee === 'service_role' && serviceTables.has(table);
    return {
      table,
      grantee,
      class: needed ? 'b_expected' : 'b',
      note: `local extra: ${localMore.join(', ')}`,
    };
  }
  return {
    table,
    grantee,
    class: 'mixed',
    note: `staging+ ${stagingMore.join(',') || '-'} | local+ ${localMore.join(',') || '-'}`,
  };
}

const classified = diffs.map(classify);
const counts = { a: 0, b: 0, b_expected: 0, c: 0, mixed: 0 };
for (const c of classified) {
  const k = c.class.startsWith('b') ? 'b' : c.class;
  counts[k] = (counts[k] || 0) + 1;
}

console.log(JSON.stringify({ total: diffs.length, counts, rows: classified }, null, 2));
