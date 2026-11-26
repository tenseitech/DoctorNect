# Audit 8 — Test inventory (static)

| Layer | Approx. test files | Runner |
|-------|-------------------|--------|
| Flutter `frontend/test` | 101 `*_test.dart` | `flutter test` |
| Functions `backend/functions/test` | 92+ `*.test.js` | `npm test` |
| Gateway `services/api-gateway/test` | 22 `*.test.js` | `npm test` |
| Scripts `scripts/test` | 28+ | `node --test` |

## CI coverage

| Workflow | Scope |
|----------|--------|
| `flutter-ci.yml` | Full `flutter test` + analyze (main PRs) |
| `backend-functions-ci.yml` | Functions (path-filtered) |
| `gateway_ci.yml` | Gateway |
| `audit8_quality_gates.yml` | Critical subsets + gateway + scripts |
| `ops_synthetic_probes.yml` | Ops + gateway |

## E2E

No `integration_test/` or Patrol suite in repo — **E2E not automated**.