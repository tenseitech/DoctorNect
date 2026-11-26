# RUNBOOK — Backup failure

**Symptoms:** No recent RDS snapshot; logical backup job failed; manifest hash mismatch.

**Severity:** SEV-2 until resolved (blocks confident restore).

## Triage

1. AWS RDS snapshot list / Supabase backup UI (**OPERATOR ACTION**).
2. Review `backups/*/manifest` SHA logs.

## Recovery

- Re-run backup job per `docs/ops/MANUAL_ACTIONS.md`.
- Fix IAM/disk space issues.

## Verification

Restore drill on isolated instance — **NON-PRODUCTION TEST** per `AUDIT_7_BACKUP_RESTORE_PLAN.md`.