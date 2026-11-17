'use strict';

/** Emit db/rds_bootstrap/04_rds_runtime_grants.sql from gateway config (no DB connection). */

const fs = require('fs');
const path = require('path');
const cfg = require('../../services/api-gateway/src/config');

const backendDmlTables = [
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
  'reviews',
  'in_app_notifications',
  'user_devices',
  'promoted_ads',
  'ambulance_broadcasts',
  'ambulance_requests',
  'referrals',
  'patient_doctor_links',
  'support_tickets',
  'support_ticket_messages',
];

const serviceRpcs = [...cfg.serviceRoleOnlyRpcs, 'expire_stale_ambulance_broadcasts', 'upsert_system_config'];

function lines() {
  const out = [];
  out.push('-- =============================================================================');
  out.push('-- DoctorNect RDS Bootstrap: 04_rds_runtime_grants.sql');
  out.push('-- Idempotent least-privilege grants for PostgREST roles on AWS RDS.');
  out.push('-- Run AFTER db/migrations/*.sql on cutover. Does not use GRANT ALL.');
  out.push('-- =============================================================================');
  out.push('');
  out.push('GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;');
  out.push('');

  const publicServiceTables = new Set(cfg.serviceRoleOnlyTables.filter((t) => t !== 'admin_users'));
  const privateServiceTables = ['admin_users'];

  out.push('GRANT USAGE ON SCHEMA private TO service_role;');
  out.push('');
  out.push('-- --- service_role: gateway serviceRoleOnlyTables (backend / ops) ---');
  for (const t of [...publicServiceTables].sort()) {
    out.push(`DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', '${t}');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', '${t}';
END $$;`);
  }
  for (const t of privateServiceTables) {
    out.push(`GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.${t} TO service_role;`);
  }
  out.push('');

  out.push('-- --- service_role: Cloud Functions maintenance (delete account, sync, webhooks) ---');
  const svcTables = new Set([...publicServiceTables, ...backendDmlTables]);
  for (const t of [...svcTables].sort()) {
    if (publicServiceTables.has(t)) continue;
    out.push(`DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', '${t}');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', '${t}';
END $$;`);
  }
  out.push('');

  out.push('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;');
  out.push('');

  out.push('-- --- service_role RPCs (cron/maintenance; client RPCs stay authenticated-only) ---');
  const knownServiceFunctions = [
    'expire_stale_ambulance_broadcasts()',
  ];
  for (const sig of knownServiceFunctions) {
    out.push(`GRANT EXECUTE ON FUNCTION public.${sig} TO service_role;`);
  }
  out.push('-- delete_my_account is enforced at API Gateway allowlist (no public SQL RPC in repo migrations).');
  out.push('');

  out.push('-- --- anon hardening (re-assert; matches 20261103000008) ---');
  out.push(`REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;`);
  out.push(`GRANT USAGE ON SCHEMA public TO anon;`);
  out.push(`GRANT SELECT ON public.doctor_directory TO anon;`);
  out.push(`GRANT SELECT ON public.lab_catalog_tests TO anon;`);
  out.push(`GRANT SELECT ON public.system_config TO anon;`);
  out.push(`GRANT SELECT ON public.review_public TO anon;`);
  out.push(`REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon;`);
  out.push('');

  out.push('-- --- PostgREST authenticator ---');
  out.push(`GRANT anon, authenticated, service_role TO authenticator;`);
  out.push('');

  return out.join('\n');
}

const target = path.resolve(__dirname, '../../db/rds_bootstrap/04_rds_runtime_grants.sql');
fs.writeFileSync(target, `${lines()}\n`, 'utf8');
console.log(`Wrote ${target}`);
