# Audit 7 — Proposed SLI / SLO (not historically measured)

All objectives below are **proposed**. No claim of current attainment unless staging/production metrics exist outside this repo.

| Service | SLI | Measurement | Proposed SLO (30d) | Data source |
|---------|-----|-------------|-------------------|-------------|
| Auth Gateway | Availability | `/readyz` == 200 | 99.5% | Synthetic probe / LB health |
| Auth Gateway | Success rate | `api_request` status < 500 | 99.0% | stdout JSON logs |
| Auth Gateway | Latency | p95 `latency_ms` | < 800ms | stdout JSON logs |
| PostgREST path | Error rate | 5xx from proxy | < 1% | Gateway logs |
| Cloud Functions | Success | invocations without uncaught error | 99.5% | GCP metrics |
| Cloud Functions | Duration | p95 execution time | Callable-specific | GCP metrics |
| Cross-role sync | Success | no `cross_role_sync_dlq` event | 99.9% | Ops logs |
| Patient booking | Success | `book_appointment_atomic` success / attempts | 98% | App + DB metrics (pending) |
| Authentication | Success | `auth.success` / attempts | 99% | `security_logger` |
| Realtime | Connected sessions | client reconnect recovery | Best-effort | Client telemetry (gap) |
| Storage confirm | Success | S3 confirm RPC success | 99.5% | Functions logs |

**Error budget:** 0.5% monthly downtime ≈ 3.6h for gateway availability SLO.

## Verification status (Audit 7 final follow-up)

| SLI | Target | Measured | Status |
|-----|--------|----------|--------|
| `/readyz` synthetic success | 100% in CI | Local mock tests pass | **TESTED** |
| Gateway availability from logs | 99.5% | Use `rollupGatewaySli()` on log export | **CONFIGURED** |
| Production historical attainment | — | No ingest in repo | **NOT VERIFIED** |