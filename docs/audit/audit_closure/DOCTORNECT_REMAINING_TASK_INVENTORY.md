# DoctorNect — Remaining Task Inventory (verified 2026-11-26)

| Audit | ID | Verified repo state | Remaining | Type | Audit 4 block |
|-------|-----|---------------------|-----------|------|----------------|
| 1 | SEC-04 | `firebase_revocation.test.js`, staging script `audit1_staging_sec04_revocation_e2e.js` | Staging e2e | Staging | No |
| 1 | SEC-07 | `hosting_csp_connect_src.test.js` **PASS** locally | Browser on hosted URL | Staging | No |
| 1 | SEC-08 | `gateway_redis_multi_instance.test.js` (local Redis) | ECS multi-task staging | Staging/infra | No |
| 2 | Docker | Dockerfile + `gateway_ci.yml` | Local Docker **BLOCKED**; GHA on closure branch | CI | No |
| 3 | CQ | No regressions on closure branch | Accepted debt only | — | No |
| 4 | ALL | ON HOLD | Operator migrate/deploy | **EXCLUDED** | — |
| 5 | PERF | Pagination mostly done per Audit 5 follow-up | Lab/pharmacy pagination; DevTools | Code/optional | Partial |
| 6 | REL-10 | `request_correlation.test.js` | Staging log correlation | Staging | No |
| 6 | REL-04 | Proposal only | **BLOCKED** | Schema | **Yes** |
| 7 | OPS | Scripts + runbooks | Alert destinations, DR drill, Crashlytics console | External | No |
| 8 | QA-03 | env parity **PASS** | — | — | No |
| 8 | QA-04 | `e2e_auth_welcome_smoke_test.dart` added | Full device E2E | Manual/CI | No |
| 8 | QA-07 | `npm run test:rules` in GHA (optional fail) | Emulator pass evidence | CI/env | No |
| 9 | UX-11 | ~65+ IconButtons remain | Incremental | Code | No |
| 9 | UX-17-19 | Manual checklist doc | Device QA | Manual | No |

**Staging scripts (do not run without prereqs):**

- `node scripts/security/audit1_staging_prereq_check.js`
- `node scripts/security/audit1_staging_sec04_revocation_e2e.js`