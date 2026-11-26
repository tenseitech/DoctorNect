# RUNBOOK — Database outage

**Symptoms:** Gateway `/readyz` postgrest not ok; Functions DB errors; booking/RPC failures.

**Severity:** SEV-1.

## Triage

1. **SAFE DIAGNOSTIC:** Gateway `/readyz` JSON.
2. **SAFE DIAGNOSTIC:** PostgREST root GET from gateway network.
3. Review RDS/Supabase status page (**OPERATOR ACTION**).

## Recovery

- Staging: verify Supabase project status.
- Production RDS: failover or restore — see `docs/runbooks/RDS_MIGRATION_RUNBOOK.md`, `AUDIT_7_BACKUP_RESTORE_PLAN.md` (**OPERATOR ACTION — NOT EXECUTED in audit**).

## Do not

- Apply migrations under Audit 4 hold without explicit approval.
- Run destructive SQL without verified backup.

## Verification

RLS smoke or `scripts/db/rls_sql_harness.js` on **staging** only (**NON-PRODUCTION TEST**).