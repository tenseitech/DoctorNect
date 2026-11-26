# DoctorNect — Audit 2 Report (Dependency & Supply Chain)

**Date:** 2026-11-25  
**Branch:** `main` (uncommitted Audit 1 + Audit 2 work preserved)  
**Audit 1 status:** **NOT CLOSED** (SEC-04/07/08 staging pending — independent of Audit 2)

**Audit 2 status:** **PARTIALLY COMPLETED** — DEP-01–DEP-10 remediated in tree; **Gateway Docker build, container startup, and `/healthz` not validated** on this host (Docker CLI/daemon absent, 2026-11-25 final pass). CI retains container build step.

---

## 1. Executive summary

Audit 2 scope: **DEP-01 … DEP-10** (Dependency & Supply Chain per `CODEBASE_AUDIT_REPORT.md` § AUDIT 2).

**Remediation applied** for all open findings except local-only Docker runtime proof for DEP-03/DEP-09. Production npm audit trees for gateway (omit dev), functions, migration scripts, and MSG91 proxy report **zero** vulnerabilities. Gateway **dev** tree still reports advisories tied to `redis-memory-server` (test-only).

No production deploy, no secret exposure, no Audit 1 closure, no Audit 3.

---

## 2. Findings summary

| ID | Title | Severity | Status | Validation |
|----|-------|----------|--------|------------|
| DEP-01 | Unbounded `timezone: any` | Medium | **FIXED** | `flutter pub get`, `flutter analyze --no-pub` |
| DEP-02 | Missing lockfiles (root, scripts, msg91) | Medium | **FIXED** | `npm ci` root + `scripts/` + msg91 |
| DEP-03 | Gateway Docker: no `npm ci` | **High** | **FIXED** | Dockerfile + `npm ci` local; Docker build **BLOCKED** locally |
| DEP-04 | `firebase-admin` skew (backend/scripts) | Medium | **FIXED** | `^14.4.0` + lock |
| DEP-05 | Gateway CI: no `npm ci` | Low | **FIXED** | `gateway_ci.yml` + local `npm ci`/`npm test` |
| DEP-06 | Functions CI Node 20 vs engines 22 | Low | **FIXED** | CI Node 22 |
| DEP-07 | CVE / advisories | Medium | **FIXED** (prod) | Audits 0 prod; gateway dev-only redis-memory-server chain remains |
| DEP-08 | MSG91 proxy unlocked install | Low | **FIXED** | Lock + `npm ci` in Dockerfile |
| DEP-09 | Gateway Docker missing `scripts/lib` | **High** | **FIXED** | COPY list + require smoke; container smoke **BLOCKED** locally |
| DEP-10 | Duplicate `devDependencies` (gateway) | Low | **FIXED** | Prior pass |

---

## 3. Detailed findings (post-remediation)

### DEP-01 — Unbounded `timezone: any`

- **Remediation:** `timezone: ^0.10.1` in `frontend/pubspec.yaml`.
- **Validation:** `flutter analyze --no-pub` → no issues.

### DEP-02 — Missing lockfiles

- **Remediation:** Generated locks at repo root, `scripts/`, `backend/gcp-msg91-proxy/`.
- **Validation:** `npm ci` succeeds in each npm project listed in original finding.

### DEP-03 — Gateway Docker dependency install

- **Remediation:** Multi-stage image; `npm ci --omit=dev`; build from repo root (`docker build -f services/api-gateway/Dockerfile .`).
- **Validation:** `npm ci` in `services/api-gateway`; production audit clean. **Local `docker build` not run** (CLI missing).

### DEP-04 — firebase-admin major skew

- **Remediation:** `backend/scripts` aligned to `^14.4.0`.
- **Validation:** `npm ci`, `npm audit` → 0.

### DEP-05 — Gateway CI

- **Remediation:** Install, test, audit, Docker build with root context.
- **Validation:** 121 gateway tests pass locally.

### DEP-06 — Functions CI Node version

- **Remediation:** Workflow uses Node 22.
- **Validation:** Workflow file review; functions tests on local Node 24 (engine mismatch warning only).

### DEP-07 — CVE verification

- **Remediation:** Gateway `overrides`; `npm audit fix` (non-force) gateway + functions; scripts `uuid` bump; functions `@opentelemetry/api` after audit-induced missing module.
- **Production audit:** 0 issues (gateway `--omit=dev`, functions, scripts, msg91).
- **Residual:** Gateway full audit (dev) — `redis-memory-server` / `tar` / `extract-zip`; fix requires breaking upgrade — **dev-only ACCEPTED RISK**.

### DEP-08 — MSG91 proxy

- **Remediation:** Lockfile + Dockerfile `npm ci --omit=dev`.
- **Validation:** `npm ci --omit=dev` → 0 vulnerabilities.

### DEP-09 — Gateway Docker `scripts/lib`

- **Remediation:** Explicit COPY of required `scripts/lib` modules + `.env.example` for repo-root discovery.
- **Validation:** Static paths + `node -e` require from host; in-image layout verified by path analysis.

### DEP-10 — Duplicate JSON key

- **Status:** Fixed in earlier pass (single `devDependencies` block).

---

## 4. Testing summary

| Command | Pass | Fail | Skip |
|---------|------|------|------|
| `services/api-gateway && npm test` | 121 | 0 | 1 |
| `backend/functions && npm test` | 562 | 0 | 23 |
| `flutter analyze --no-pub` | — | 0 issues | — |
| Gateway `docker build` / container `/healthz` | — | — | **BLOCKED** |

---

## 5. Remaining blockers / open items

1. **Local Docker validation** for DEP-03/DEP-09 — run `docker build -f services/api-gateway/Dockerfile .` and smoke `/healthz` on a host with Docker (or rely on CI job **Test & Build Gateway Container**).
2. **Gateway dev-only CVEs** — optional future `redis-memory-server` major bump when test harness can absorb breaking change.
3. **Migration scripts** — live Firebase dry-run not executed (no production credentials).

---

## 6. Git summary

- **Branch:** `main`
- **Commit / push:** None this pass
- **Modified:** Gateway Dockerfile/locks/manifest, CI workflows, Flutter pubspec, root/scripts/msg91 locks, backend/scripts + functions manifests/locks
- **Audit 1:** Uncommitted work preserved

---

## 7. Audit status

**PARTIALLY COMPLETED** — all DEP-* remediations implemented; **closure criteria for DEP-03/DEP-09 require evidenced `docker build`, container startup, and `/healthz`** — not satisfied on this environment.

**Audit 3:** Not started.

---

## 8. Final Docker validation & closure assessment (2026-11-25)

| Validation | Status | Evidence |
|------------|--------|----------|
| Docker CLI | **BLOCKED** | `docker version` → command not recognized; no `docker.exe` under `Program Files\Docker\...` or `%LOCALAPPDATA%\Docker\...` |
| Docker daemon | **BLOCKED** | Cannot query (`docker info` unavailable) |
| Image build | **BLOCKED** | Expected: `docker build -f services/api-gateway/Dockerfile -t doctornect/api-gateway:audit2-validation .` — not executed |
| Dockerfile COPY sources | **PASS** (static) | All 9 `COPY` paths exist at repo root |
| Shared module layout (static) | **PASS** (static) | `server.js` requires `../../../scripts/lib/*` → `/app/scripts/lib` when `WORKDIR` is `/app/gateway` |
| Runtime deps in prod install | **PASS** (static) | `npm ci --omit=dev` tree: `firebase-admin@14.5.0`, `ioredis@5.11.1`; `redis-memory-server` absent with `--omit=dev` |
| `npm audit --omit=dev` | **PASS** | 0 vulnerabilities |
| Container startup | **BLOCKED** | No image built |
| `/healthz` | **BLOCKED** | No running container |

**Closure decision:** Audit 2 **cannot be marked COMPLETE** until an operator or CI run records successful image build, non–MODULE_NOT_FOUND startup, and `/healthz` HTTP evidence. Remediation statuses for DEP-03/DEP-09 remain **FIXED** (code/config); **runtime Docker proof** remains open.

**Accepted risk (unchanged):** Gateway `devDependencies.redis-memory-server` pulls `tar` / `extract-zip` advisories in **full** `npm audit` only; excluded from image via `npm ci --omit=dev` in Dockerfile deps stage.

**Migration scripts:** Live Firebase execution remains **out of scope** (no production credentials).

**Commands this pass:** `git branch --show-current`; `git status -sb`; `docker version` (failed); `Get-Command docker` + common path probe; `npm audit --omit=dev`; `npm ls firebase-admin ioredis redis-memory-server --omit=dev`; Dockerfile COPY path checklist.

---

## 9. Gateway CI Docker runtime validation (2026-11-25 — configured)

**File:** `.github/workflows/gateway_ci.yml`

| Step | Purpose |
|------|---------|
| Build with `load: true` | Image available on runner as `doctornect/api-gateway:audit2-validation` (no registry push) |
| **Audit 2 — In-image module resolution** | Files under `/app/scripts/lib`; `require()` for `firebase-admin`, `ioredis`, shared libs |
| **Audit 2 — Container startup and /healthz** | Isolated bridge network; `hashicorp/http-echo` mock PostgREST; gateway with `NODE_ENV=development`, `APP_ENV=ci-audit2`, `PGRST_URL=http://audit2-mock-pgrst:3001`, `FIREBASE_REVOCATION_CHECK=false` (non-production smoke only; image default `NODE_ENV=production` unchanged) |
| **Audit 2 — Docker runtime cleanup** | `if: always()` removes `audit2-gateway`, `audit2-mock-pgrst`, `audit2-gateway-ci-net` |

**CI execution status:** **Not yet evidenced** — workflow in commit `e9c42b7` on branch `audit2/docker-ci-evidence`; **not pushed**; no GitHub Actions run ID.

**Job permissions:** `contents: read` only; no secrets; no registry push.

---

## 10. Local verification readiness (2026-11-26)

**Branch:** `audit2/docker-ci-evidence` @ `e9c42b758eb3dd08b854b3492dae7401ba25ed6f`  
**Git writes this pass:** none

| DEP | Working tree | Committed (`e9c42b7`) | Locally verified (2026-11-26) | Docker / GHA |
|-----|--------------|------------------------|-------------------------------|--------------|
| DEP-01 | `timezone: ^0.10.1`, lock 0.10.1 | No | `flutter analyze --no-pub` **2026-11-26** → no issues (215s). Earlier inconclusive run: analyze ~3–5+ min; buffered `Select-Object` pipeline, not a dependency fault | — |
| DEP-02 | Root/scripts/msg91 locks (untracked) | No | `npm ci` + audit 0 (root, scripts, msg91); `backend/package-lock.json` tracked, `npm ci` 0 | — |
| DEP-03 | Same as commit (gateway tree) | **Yes** | `npm ci`, tests 120 pass, audit `--omit=dev` 0 | **BLOCKED** (no Docker CLI) |
| DEP-04 | scripts Admin ^14.4.0, uuid ^11.1.0 | No | `npm ci`, audit 0 | — |
| DEP-05 | Same as commit | **Yes** | Static workflow + local test/audit mirror | **Not run** |
| DEP-06 | Functions CI Node 22 | No | Workflow vs `engines` 22 aligned on disk | **Not run** |
| DEP-07 | Functions lock/deps uncommitted | Partial (gateway overrides in commit) | All npm projects audit 0 prod; gateway dev `redis-memory-server` chain **accepted** | — |
| DEP-08 | msg91 Dockerfile `npm ci`, untracked lock | No | `npm ci --omit=dev`, audit 0 | **BLOCKED** |
| DEP-09 | demo_routing + trusted_client_ip in commit | **Yes** | Static COPY 9/9 OK; CI steps in commit | **BLOCKED** |
| DEP-10 | — | **Yes** | Single `devDependencies` in committed manifest | — |

**Regression (2026-11-26 final pass):** Gateway **120** pass / **0** fail; Functions **560** pass / **25** skip; `npm ci` + `npm audit` (prod where applicable) **0** vulns on root, scripts, backend, backend/scripts, msg91, gateway `--omit=dev`, functions; `npm ls --omit=dev` at gateway shows **no** `redis-memory-server`.

**Closure readiness:** **READY FOR EXTERNAL EVIDENCE** — local remediation and regression complete; pending push + GHA + Docker runtime only (no Git integration authorized in verification passes).

---

*End of Audit 2 Report.*