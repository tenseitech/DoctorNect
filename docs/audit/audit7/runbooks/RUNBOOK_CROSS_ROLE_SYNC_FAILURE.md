# RUNBOOK — Cross-role sync failure

**Symptoms:** `event=cross_role_sync_dlq` or `SYNC_BRIDGE_DLQ_FAILURE` in logs; data mismatch Firestore vs Supabase.

**Severity:** SEV-2.

## Triage

1. Filter logs `cross_role_sync_dlq`.
2. Inspect `sync_dead_letter_queue` table (**OPERATOR ACTION** — staging first).
3. Check transient retry exhaustion (Audit 6).

## Recovery

- Replay DLQ after fixing root cause — use existing bridge tooling; no production replay without approval.
- Do not delete DLQ rows without audit trail.

## Verification

Entity-level reconcile on staging synthetic records.