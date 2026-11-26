# RUNBOOK — High error rate

**Symptoms:** Gateway 5xx > threshold; function error spike; user complaints.

**Severity:** SEV-2.

## Triage

1. Break down by `path`, `status`, `role` in gateway logs.
2. Correlate with `request_id` across gateway + client reports.
3. Identify deploy correlation (timeboxed).

## Mitigation

- Scale gateway; disable non-critical features via Remote Config if available.
- Roll back if deploy-related → `RUNBOOK_DEPLOYMENT_ROLLBACK.md`.

## Verification

Error rate below SLO for 30 minutes (`AUDIT_7_SLI_SLO.md`).