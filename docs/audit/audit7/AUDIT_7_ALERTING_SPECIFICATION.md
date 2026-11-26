# Audit 7 — Alerting specification

**Status:** Templates validated in CI — see `alerting/alert_templates.yaml` and `scripts/test/alert_templates_validation.test.js`. Destinations **not activated**.

## Principles

- Page on **user-visible** or **data-integrity** failures (SEV-1/2).
- Ticket on elevated noise (SEV-3/4).
- Dedupe by `request_id`, `entity_id`, or 15m windows.
- Never route raw logs containing redaction failures to third parties.

## Routing (operator-defined)

| Severity | Example | Channel |
|----------|---------|---------|
| SEV-1 | Gateway ready probe down + patient traffic | On-call phone |
| SEV-2 | DLQ spike, 5xx > 5% | On-call chat |
| SEV-3 | Auth failure elevation | Email |
| SEV-4 | Single isolated 5xx | Dashboard only |

## Pending external configuration

- CloudWatch / GCP alert policies.
- PagerDuty/Opsgenie endpoints.
- Synthetic monitors for `/readyz`.