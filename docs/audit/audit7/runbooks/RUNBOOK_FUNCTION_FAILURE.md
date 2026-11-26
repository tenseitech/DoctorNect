# RUNBOOK — Cloud Function failure

**Symptoms:** Callable timeouts, webhook 5xx, GCP error rate spike.

**Severity:** SEV-2 for patient-critical callables (auth, booking).

## Triage

1. GCP Logging: `severity>=ERROR`, `callable` name from `logApiError`.
2. Check recent Functions deploy.
3. **SAFE DIAGNOSTIC:** `npm test` in `backend/functions` on release commit.

## Logs

- `securityEvent` + `structured_ops_log` events.
- Redacted messages only — no OTP/token fields.

## Recovery

- Roll back Functions revision (**OPERATOR ACTION**).
- Scale concurrency / fix dependency secret rotation.

## Verification

Invoke staging callable smoke (synthetic data only).