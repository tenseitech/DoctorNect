# Audit 2 — Remediation Report (Dependency & Supply Chain)

**Date:** 2026-11-25 (remediation execution)  
**Branch:** `main` (uncommitted; Audit 1 work preserved)  
**Audit 1:** **NOT CLOSED** (unchanged)  
**Audit 3:** Not started  

No commit, push, merge, or deploy was performed for this pass.

---

## Findings summary (DEP-01 … DEP-10)

| ID | Severity | Status | Fix implemented | Validation |
|----|----------|--------|-----------------|------------|
| DEP-01 | Medium | **FIXED** | `timezone: ^0.10.1` in `frontend/pubspec.yaml` | `flutter pub get`; `flutter analyze --no-pub` → no issues |
| DEP-02 | Medium | **FIXED** | `package-lock.json` at repo root, `scripts/`, `backend/gcp-msg91-proxy/` | `npm ci` root + `scripts/` |
| DEP-03 | **High** | **FIXED** | Multi-stage Dockerfile; `npm ci --omit=dev` from repo-root context | Static COPY-path check; `npm ci` local; **Docker build/smoke BLOCKED** (no Docker CLI on host); CI builds image |
| DEP-04 | Medium | **FIXED** | `backend/scripts` `firebase-admin` → `^14.4.0`; lock updated | `npm ci` + `npm audit` → 0 vulns |
| DEP-05 | Low | **FIXED** | `gateway_ci.yml`: `npm ci`, `npm test`, `npm audit --omit=dev --audit-level=high` | Workflow review; gateway `npm ci` + test locally |
| DEP-06 | Low | **FIXED** | `backend-functions-ci.yml` Node **22** (matches `engines`) | Workflow review |
| DEP-07 | Medium | **FIXED** (prod) | Gateway `overrides`; `npm audit fix` gateway + functions; scripts `uuid` ^11.1.0; functions `@opentelemetry/api` after audit tree fix | `npm audit --omit=dev` gateway **0**; functions **0**; scripts **0**; msg91 **0** |
| DEP-08 | Low | **FIXED** | MSG91 proxy lock + Dockerfile `npm ci --omit=dev` | `npm ci --omit=dev` in `backend/gcp-msg91-proxy` |
| DEP-09 | **High** | **FIXED** | Copy required `scripts/lib/*.js` + `.env.example` for `findRepoRoot()` | Require smoke: `node -e` loads `scripts/lib/*`; path math for `/app/gateway/src` → `/app/scripts/lib`; **container smoke BLOCKED** (no Docker) |
| DEP-10 | Low | **FIXED** (prior) | Single `devDependencies` block in gateway `package.json` | JSON review |

**Overall Audit 2:** **PARTIALLY COMPLETED** — all code/config remediations applied; **Gateway Docker build/startup/`/healthz` not evidenced** (Docker CLI/daemon unavailable on 2026-11-25 final validation host). CI workflow retains `docker build` for verification on `ubuntu-latest`.

---

## Final Docker validation & closure (2026-11-25)

| Check | Result |
|-------|--------|
| Docker installed | **No** (CLI not on PATH; standard Windows install paths empty) |
| `docker build -f services/api-gateway/Dockerfile .` | **Not run** |
| In-image module / startup / `/healthz` | **Not run** |
| Static: Dockerfile COPY paths | **9/9 present** |
| Static: prod dependency tree | `firebase-admin`, `ioredis` only; audit **0** with `--omit=dev` |
| Dev-only CVE chain | `redis-memory-server` → `tar` / `extract-zip` — **ACCEPTED RISK** (dev-only; not in image) |
| Migration live test | **Not in scope** — no production Firebase |

**Closure:** **PARTIALLY COMPLETED** — pending Docker runtime validation. No remediation changes in this pass.

---

## Gateway CI Docker runtime validation (2026-11-25)

**Implemented in** `.github/workflows/gateway_ci.yml`:

1. Docker build tag `doctornect/api-gateway:audit2-validation` with `load: true`
2. In-container file + `require()` checks (DEP-09)
3. Mock PostgREST + gateway container startup + `/healthz` HTTP 200 + `"status":"healthy"` (DEP-03)
4. `if: always()` cleanup of job-scoped containers/network

**CI execution:** **Pending** — changes uncommitted/unpushed; no workflow run ID to cite.

**Smoke env:** Non-production (`NODE_ENV=development`) — does not weaken production Dockerfile defaults or production assertion code paths.

---

## Per-finding evidence

### DEP-01 — Flutter `timezone`

- **Original:** `timezone: any`
- **Root cause:** Unpinned direct dependency.
- **Files:** `frontend/pubspec.yaml`, `frontend/pubspec.lock` (resolved `timezone` 0.10.1).
- **Commands:** `flutter pub get`; `flutter analyze --no-pub` (141.7s) → **No issues found**.
- **Remaining risk:** None for this finding.

### DEP-02 — Missing lockfiles

- **Locations:** Repo root (`doctornect-workspace`), `scripts/`, `backend/gcp-msg91-proxy/`.
- **Files created/updated:** `package-lock.json`, `scripts/package-lock.json`, `backend/gcp-msg91-proxy/package-lock.json`.
- **Commands:** `npm ci` at root and `scripts/` → success, 0 audit issues.
- **Note:** `backend/package-lock.json` pre-existed; not part of original DEP-02 list.

### DEP-03 + DEP-09 — Gateway Docker

- **Root cause:** Image copied only `src/`; no `npm ci`; no `scripts/lib` for monorepo requires.
- **Files:** `services/api-gateway/Dockerfile`, `.github/workflows/gateway_ci.yml` (`context: .`, `file: ./services/api-gateway/Dockerfile`).
- **Implementation:** Two-stage build; production `node_modules` via `npm ci --omit=dev`; copies `scripts/lib/{bootstrap_root_env,repo_root,parse_env_file,env_duplicate_keys,demo_routing,trusted_client_ip}.js` and `.env.example`.
- **Build instruction:** `docker build -f services/api-gateway/Dockerfile .` (from repo root).
- **Static validation:** All Dockerfile `COPY` sources exist on disk.
- **Module resolution:** `server.js` requires resolve to `/app/scripts/lib` inside image layout.
- **Local Docker:** **BLOCKED** — `docker` not installed on Windows remediation host.
- **Remaining risk:** Production image smoke depends on CI Docker build or operator with Docker locally.

### DEP-04 — firebase-admin alignment

- **Files:** `backend/scripts/package.json`, `backend/scripts/package-lock.json` (`firebase-admin` 14.5.1 resolved).
- **Validation:** `npm ci`; migration script dry-run not executed (no Firebase credentials in scope).

### DEP-05 — Gateway CI

- **File:** `.github/workflows/gateway_ci.yml`
- **Validation:** Local mirror: `npm ci`, `npm test` → 121 pass / 0 fail / 1 skip.

### DEP-06 — Functions CI Node version

- **File:** `.github/workflows/backend-functions-ci.yml` → `node-version: "22"`.

### DEP-07 — CVE / advisories

| Project | Command | Result |
|---------|---------|--------|
| Gateway (production) | `npm audit --omit=dev` | **0 vulnerabilities** (after overrides + `npm audit fix`) |
| Gateway (full incl. dev) | `npm audit` | **3** (high/critical via `redis-memory-server` → `extract-zip`/`tar`; fix needs `--force` / breaking `redis-memory-server` bump) — **dev-only test harness** |
| Functions | `npm audit` | **0** (after `npm audit fix`; added `@opentelemetry/api` to restore Firestore telemetry import) |
| backend/scripts | `npm audit` | **0** (after `uuid` ^11.1.0) |
| gcp-msg91-proxy | `npm audit` (post `npm ci`) | **0** |

**Remaining risk:** Dev dependency chain in gateway (`redis-memory-server`); acceptable for local/CI tests only; not in production image (`--omit=dev`).

### DEP-08 — MSG91 proxy

- **Files:** `backend/gcp-msg91-proxy/Dockerfile`, `backend/gcp-msg91-proxy/package-lock.json`.
- **Validation:** `npm ci --omit=dev` → 69 packages, 0 vulnerabilities.

---

## Test results (executed)

| Suite | Pass | Fail | Skip | Notes |
|-------|------|------|------|-------|
| `services/api-gateway` `npm test` | 121 | 0 | 1 | After `npm ci` |
| `backend/functions` `npm test` | 562 | 0 | 23 | After `@opentelemetry/api` |
| Flutter `flutter analyze --no-pub` | — | — | — | No issues |
| Gateway Docker build | — | — | — | **BLOCKED** (no Docker CLI) |

---

## Files changed (Audit 2 remediation)

| File | Change |
|------|--------|
| `services/api-gateway/Dockerfile` | Multi-stage `npm ci`, `scripts/lib` copy, repo-root build context |
| `services/api-gateway/package.json` | `overrides` for transitive CVEs (DEP-07) |
| `services/api-gateway/package-lock.json` | Refreshed |
| `.github/workflows/gateway_ci.yml` | `npm ci`, test, audit, Docker context `.` |
| `.github/workflows/backend-functions-ci.yml` | Node 22 |
| `frontend/pubspec.yaml` | Pin `timezone` |
| `frontend/pubspec.lock` | Updated by `flutter pub get` |
| `package-lock.json` | New (root workspace) |
| `scripts/package-lock.json` | New |
| `backend/gcp-msg91-proxy/Dockerfile` | `npm ci` |
| `backend/gcp-msg91-proxy/package-lock.json` | New |
| `backend/scripts/package.json` | `firebase-admin` ^14.4.0, `uuid` ^11.1.0 |
| `backend/scripts/package-lock.json` | Updated |
| `backend/functions/package-lock.json` | Audit fix + lock refresh |
| `backend/functions/package.json` | `@opentelemetry/api` (post-audit fix) |

Audit 2 report artifacts: `AUDIT_2_REPORT.md`, `docs/audit/AUDIT_2_CHECKLIST.md`, `CODEBASE_AUDIT_REPORT.md` §19 pointer.

---

## Git safety

- **Branch:** `main`
- **Commit / push / deploy:** None
- **Audit 1 files:** Preserved in working tree; status not altered to CLOSED

---

*End of Audit 2 Remediation Report.*