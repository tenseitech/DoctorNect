# Audit 7 — Disaster recovery plan

**Proposed RTO/RPO — not verified by live DR test.**

## Dependency map

```
Flutter → Firebase Auth / Gateway (REST) → PostgREST/RDS
         → Functions (callables/webhooks) → S3, Supabase admin, Redis, Firestore legacy
         → Realtime (Supabase)
```

## Proposed objectives

| Tier | Components | RTO (proposed) | RPO (proposed) |
|------|------------|----------------|----------------|
| Critical | Gateway + RDS + Auth | 4h | 15m (RDS PITR/snapshot policy) |
| High | Functions, Redis | 2h | 1h |
| Medium | Firestore legacy, caches | 8h | 24h |
| Artifacts | S3 objects | 24h | 0 (versioning) |

## Scenarios

| Scenario | Detection | Recovery outline |
|----------|-----------|------------------|
| RDS outage | `/readyz` fail, app errors | Failover / restore snapshot — **OPERATOR ACTION** |
| Region outage | Multi-signal | DNS to secondary region if configured — pending infra |
| Gateway task crash | `/livez` fail | ECS/K8s restart — **OPERATOR ACTION** |
| Credential compromise | Security incident runbook | Rotate secrets, invalidate sessions |
| Bad deploy | Error spike post-release | `RUNBOOK_DEPLOYMENT_ROLLBACK.md` |

## DR test plan (staging only)

1. Snapshot staging DB (**NON-PRODUCTION TEST**).
2. Simulate gateway stop; verify alert template would fire.
3. Restore snapshot to scratch instance; run RLS smoke subset.
4. Record duration and gaps — do not use production patient data.

**Restore testing status: NOT VERIFIED in this audit execution.**