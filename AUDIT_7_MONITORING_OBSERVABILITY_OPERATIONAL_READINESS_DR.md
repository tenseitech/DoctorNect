# Audit 7 — Monitoring, observability, operational readiness & disaster recovery

**Date:** 2026-11-26  
**Branch:** `audit7/operational-readiness`  
**Base:** Audit 6 `e9dfe64`  
**Status:** **AUDIT 7 REMEDIATION COMPLETE — EXTERNAL CONFIGURATION/RUNTIME VERIFICATION PENDING**  
**Final verification:** [`AUDIT_7_FINAL_OPERATIONAL_VERIFICATION_REPORT.md`](AUDIT_7_FINAL_OPERATIONAL_VERIFICATION_REPORT.md)

## Executive summary

Static audit of DoctorNect’s Flutter app, Auth Gateway, Firebase Functions, Supabase/RDS paths, Redis rate limiting, storage (S3), and cross-role sync. Implemented shared log redaction, enriched gateway audit schema, structured DLQ ops events, Flutter operational logging helper, alert templates, SLO/DR documentation, and incident runbooks. **No production deploy, no migrations, Audit 4 ON HOLD.**

## Architecture reviewed (verified in repo)

| Layer | Components |
|-------|------------|
| Client | Flutter (`medibond`), Supabase client, Firebase Auth, push |
| Edge | `services/api-gateway` → PostgREST / RDS |
| Compute | `backend/functions` (Firebase Functions v2) |
| Data | Supabase staging; RDS + migrations in repo; Firestore legacy paths |
| Cache | Redis (gateway rate limit, OTP paths in functions) |
| Storage | AWS S3 presign/confirm in functions |
| CI | `.github/workflows/*` (Flutter, gateway, functions, env-policy) |

## Findings

| ID | Sev | Component | Problem | Status | Evidence |
|----|-----|-----------|---------|--------|----------|
| OPS-01 | HIGH | Platform | No unified operational log schema across services | **PARTIALLY FIXED** | `log_redaction.js`, gateway `emitAuditLog`, `structured_ops_log.js` |
| OPS-02 | HIGH | Logging | Risk of tokens/PHI in free-text logs | **PARTIALLY FIXED** | Redaction lib + DLQ log no longer dumps full payload |
| OPS-03 | MEDIUM | Metrics | No first-party Prometheus/Datadog in repo | **DOCUMENTED** | `AUDIT_7_MONITORING_METRICS_SPECIFICATION.md` |
| OPS-04 | MEDIUM | Gateway | Health probes exist but external probes not configured | **VERIFIED STATIC** | `/livez`, `/readyz`, `health_probes.test.js` (Audit 4/6) |
| OPS-05 | HIGH | Alerting | No checked-in alert destinations | **DOCUMENTED** | `audit7/alerting/alert_templates.yaml` |
| OPS-06 | MEDIUM | Dashboards | No app dashboards in repo | **DOCUMENTED** | Metrics spec + Cloud/GCP log queries |
| OPS-07 | MEDIUM | SLO | No published SLOs | **DOCUMENTED** | `AUDIT_7_SLI_SLO.md` (proposed) |
| OPS-08 | MEDIUM | Incidents | No DoctorNect-specific IR playbook in repo | **FIXED** | `AUDIT_7_INCIDENT_RESPONSE.md` + runbooks |
| OPS-09 | HIGH | Backup/DR | Backup evidence in ops docs; restore not CI-gated | **DOCUMENTED** | `AUDIT_7_BACKUP_RESTORE_PLAN.md`, existing `docs/runbooks/RDS_*` |
| OPS-10 | HIGH | Restore test | No automated restore verification in CI | **NOT VERIFIED** | Checklist in backup plan |
| OPS-11 | LOW | Flutter | No Crashlytics/Sentry in pubspec | **DOCUMENTED** | Manual crash visibility gap |
| OPS-12 | MEDIUM | CI/CD | Deploy observability relies on GH Actions pass/fail | **DOCUMENTED** | `AUDIT_7_OPERATIONAL_READINESS_CHECKLIST.md` |
| OPS-13 | LOW | Cost | stdout JSON volume on high-traffic gateway | **DOCUMENTED** | Retention guidance in report §Cost |

## Remediation implemented (this audit)

- `scripts/lib/log_redaction.js` — shared redaction + envelope.
- `services/api-gateway/src/security.js` — `service`, `environment`, `severity`, `outcome`.
- `backend/functions/src/observability/structured_ops_log.js` — DLQ ops events.
- `backend/functions/cross_role_sync_infra.js` — redacted DLQ logging.
- `frontend/lib/core/observability/operational_log.dart` — debug-safe client ops logs.
- Tests: `scripts/test/log_redaction.test.js`, `structured_ops_log.test.js`, gateway request_context, Flutter ops test.
- Docs: SLI/SLO, metrics, alerting, incident, DR, backup, checklist, 12 runbooks.

## Test evidence

| Command | Pass | Fail |
|---------|-----:|-----:|
| `node --test scripts/test/log_redaction.test.js` | 3 | 0 |
| `node --test backend/functions/test/structured_ops_log.test.js` | 1 | 0 |
| `cd services/api-gateway && npm test` | 131 | 0 |
| `flutter test test/core/observability/operational_log_test.dart` | 1 | 0 |

## Runtime verification

**Not performed:** production/staging probes, alert delivery, backup restore, dashboard wiring.

## Audit preservation

Audits 1–6 preserved. **Audit 4 ON HOLD** — no migration or DB operator actions.

## Final classification

**AUDIT 7 REMEDIATION COMPLETE — EXTERNAL CONFIGURATION/RUNTIME VERIFICATION PENDING**

## Related documents

- `docs/audit/audit7/AUDIT_7_SLI_SLO.md`
- `docs/audit/audit7/AUDIT_7_MONITORING_METRICS_SPECIFICATION.md`
- `docs/audit/audit7/AUDIT_7_ALERTING_SPECIFICATION.md`
- `docs/audit/audit7/AUDIT_7_INCIDENT_RESPONSE.md`
- `docs/audit/audit7/AUDIT_7_DISASTER_RECOVERY_PLAN.md`
- `docs/audit/audit7/AUDIT_7_BACKUP_RESTORE_PLAN.md`
- `docs/audit/audit7/AUDIT_7_OPERATIONAL_READINESS_CHECKLIST.md`
- `docs/audit/audit7/runbooks/*.md`