# RUNBOOK — Deployment rollback

**Symptoms:** Errors after release; CI passed but runtime fails.

## Preconditions

- Identify commit SHA and artifact version.

## Rollback

1. **OPERATOR ACTION:** Revert ECS/Gateway task to previous image tag.
2. **OPERATOR ACTION:** `firebase deploy` previous Functions bundle from known good CI artifact — **PRODUCTION ACTION — NOT EXECUTED in audit**.
3. Flutter: ship previous store build / internal track.

## Verification

- Health probes green.
- Smoke: login, list appointments, doctor directory (staging).

## CI reference

- Re-run failed workflow on fix branch; do not bypass tests.