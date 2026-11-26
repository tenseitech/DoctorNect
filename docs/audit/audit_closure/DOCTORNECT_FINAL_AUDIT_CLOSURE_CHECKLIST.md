# DoctorNect — Final Audit Closure Checklist (Audits 1–9)

**Branch:** `audit-closure/remaining-audits`  
**Updated:** 2026-11-26

| Audit | ID | Description | Status | Evidence |
|-------|-----|-------------|--------|----------|
| 1 | SEC-04 | Staging revoke → 401 | PENDING OPERATOR | `audit1_staging_prereq_check.js` exit 2 |
| 1 | SEC-07 | Hosted CSP browser | PENDING OPERATOR | No `AUDIT1_STAGING_HOSTING_URL` |
| 1 | SEC-08 | ECS shared Redis 429 | PENDING ENVIRONMENT | No AWS CLI |
| 1 | SEC-01–03,05–06,09–13 | In-repo fixes | FIXED / TESTED | Prior Audit 1 reports |
| 2 | DEP-01–10 | Dependency remediation | FIXED | Locks, Dockerfiles, CI |
| 2 | DEP-03/09 | Local Docker build/healthz | PENDING ENVIRONMENT | No Docker CLI locally |
| 2 | DEP-03/09 | GHA Docker evidence | PENDING CI | `audit_closure_gates.yml` on push |
| 2 | DEP-07 dev | redis-memory-server advisories | ACCEPTED RISK | Prod `npm audit` clean |
| 3 | CQ-* | Code quality | CLOSED | `AUDIT_3_REPORT.md` |
| 3 | CQ debt | cross_role_sync / large screens | ACCEPTED RISK | Documented |
| 4 | ALL | Database & infra | ON HOLD | No migration/deploy in closure pass |
| 5 | PERF-* | Static remediation | CLOSED | Audit 5 reports |
| 5 | Profiling | DevTools / prod load | PENDING ENVIRONMENT | Not run |
| 6 | REL-* | Reliability code | FIXED / TESTED | Gateway 135 pass |
| 6 | REL-10 | Staging correlation | PENDING OPERATOR | Runbook § REL-10 |
| 6 | REL-04 | RPC idempotency | BLOCKED | Audit 4 ON HOLD |
| 7 | OPS-* | Docs, probes, runbooks | FIXED | Audit 7 branch |
| 7 | Synthetic schedules | Staging cron | PENDING OPERATOR | URL required |
| 7 | Alerts / DR drill | Production paths | PENDING OPERATOR | No prod activation |
| 8 | QA-01–02 | CI + booking guard test | FIXED / TESTED | Prior audit 8 |
| 8 | QA-03 | env_parity | FIXED / VERIFIED | `npm run test:env-parity` 5/5 |
| 8 | QA-04 | Device/browser E2E | OPEN | No framework run |
| 8 | QA-05 | Global coverage % gate | OPEN | Not enforced |
| 8 | QA-07 | Emulator rules suites | PENDING ENVIRONMENT | Emulators not started |
| 8 | Staging E2E | Manual matrix | PENDING OPERATOR | Runbook § Audit 8 |
| 9 | UX-01–10 | Theme/a11y remediation | FIXED / TESTED | Audit 9 + 704 Flutter tests |
| 9 | UX-11 | Remaining IconButtons | OPEN | Incremental migration |
| 9 | UX-12 | Semantics coverage | PARTIALLY FIXED | Auth screens improved |
| 9 | UX-16 | Full contrast review | PARTIALLY FIXED | `audit_closure_app_colors_contrast_test.dart` |
| 9 | UX-17–19 | Device a11y manual | PENDING ENVIRONMENT | Runbook § Audit 9 |
| 9 | UX-13 | Text scale clamp | ACCEPTED RISK | `main.dart` 0.9–1.3 |