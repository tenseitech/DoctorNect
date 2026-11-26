# Audit 7 — Monitoring metrics specification

## Gateway (stdout JSON — `event: api_request`)

| Metric | Field | Aggregation |
|--------|-------|-------------|
| RPS | count by minute | log metric filter |
| 4xx/5xx rate | `status` | ratio |
| Latency p50/p95 | `latency_ms` | percentile |
| Rate limit | 429 count | status==429 |
| Role mix | `role` | cardinality low |

## Functions

| Metric | Source |
|--------|--------|
| Invocation errors | GCP Cloud Logging `severity>=ERROR` |
| Security events | `securityEvent: true` |
| Sync DLQ | `event: cross_role_sync_dlq` |
| OTP/auth anomalies | `category: auth` |

## Health probes

| Endpoint | Purpose |
|----------|---------|
| `/livez` | Liveness — process up |
| `/readyz` | Readiness — PostgREST + Redis (if required) |
| `/healthz` | Legacy LB compatibility |

## Redis

| Signal | Source |
|--------|--------|
| Ready failure | `/readyz` dependencies.redis |
| Limiter errors | gateway rate limit fail-closed logs |

## Flutter (gaps)

- No Crashlytics — recommend Firebase Crashlytics with PHI scrubbing before enable.
- Use `OperationalLog` in debug only; production should rely on backend correlation (`request_id`).

## Dashboard widgets (recommended)

1. Gateway status + error rate + p95 latency.
2. Function error count + top callables.
3. DLQ events timeline.
4. Auth failure rate.
5. CI last success per workflow.