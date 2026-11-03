-- Rollback companion for 20261103000014 (restore prior policy names from 20261020000001 baseline).
-- STAGING ONLY — review diff against baseline migration before executing.

BEGIN;

-- Re-run policies from db/migrations/20261020000001_rls_policies.sql (appointments_select/update,
-- prescriptions_select, lab_bookings_update, lab_orders_insert/update, pharmacy_connections_*, pdl_select)
-- OR restore from pg_dump of policy definitions taken before 000014.

-- Drop verified-only helpers if no other migration depends on them:
DROP FUNCTION IF EXISTS private.is_verified_lab();
DROP FUNCTION IF EXISTS private.is_verified_medical_store();

-- NOTE: This file is a pointer rollback — paste the exact CREATE POLICY statements from your
-- pre-000014 snapshot here before running on staging.

ROLLBACK;
