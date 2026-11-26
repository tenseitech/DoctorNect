# Audit 2 — Dependency & Supply Chain Checklist

**Source scope:** `CODEBASE_AUDIT_REPORT.md` § AUDIT 2 (DEP-01 … DEP-10).

**Remediation date:** 2026-11-25  
**Final Docker validation (local):** 2026-11-26 — **BLOCKED** (no Docker CLI)  
**CI Docker validation:** In commit `e9c42b7` — **NOT YET EXECUTED** (branch not pushed)  
**Local npm/flutter verification:** 2026-11-26 final — **PASS** (`flutter analyze --no-pub` no issues, 215s; see `AUDIT_2_REPORT.md` §10)  
**Overall:** **READY FOR EXTERNAL EVIDENCE** (GHA + Docker not run)

| Step | Action | Evidence | Status |
|------|--------|----------|--------|
| 1 | Flutter `timezone` pinned | `pubspec.yaml` `^0.10.1`; `flutter analyze --no-pub` clean | DEP-01 **FIXED** |
| 2 | Lockfiles: root, `scripts/`, msg91 proxy | `package-lock.json` files; `npm ci` | DEP-02 **FIXED** |
| 3 | Gateway Docker `npm ci --omit=dev` | `services/api-gateway/Dockerfile` multi-stage | DEP-03 **FIXED** (Docker build local **BLOCKED**) |
| 4 | Copy `scripts/lib` into gateway image | Dockerfile COPY list; require smoke | DEP-09 **FIXED** (container smoke local **BLOCKED**) |
| 5 | `firebase-admin` ^14.x in `backend/scripts` | `package.json` / lock | DEP-04 **FIXED** |
| 6 | Gateway CI: `npm ci` → test → audit → Docker build | `.github/workflows/gateway_ci.yml` | DEP-05 **FIXED** |
| 7 | Functions CI Node 22 | `.github/workflows/backend-functions-ci.yml` | DEP-06 **FIXED** |
| 8 | `npm audit` gateway (prod), functions, scripts, msg91 | All **0** production; gateway dev-only redis-memory-server advisories | DEP-07 **FIXED** (prod) |
| 9 | MSG91 `npm ci` + lock | `backend/gcp-msg91-proxy/Dockerfile` | DEP-08 **FIXED** |
| 10 | Gateway `package.json` duplicate key | Single `devDependencies` | DEP-10 **FIXED** |

**Re-run CVE (2026-11-25 post-fix):**

```text
cd services/api-gateway && npm audit --omit=dev   # 0 vulnerabilities
cd backend/functions && npm audit                 # 0 vulnerabilities
cd backend/scripts && npm audit                   # 0 vulnerabilities
cd backend/gcp-msg91-proxy && npm audit           # 0 vulnerabilities
```

**Docker smoke — automated (preferred):** GitHub Actions job **Test & Build Gateway Container** steps *Audit 2 — In-image module resolution*, *Container startup and /healthz*, *Docker runtime cleanup*.

**Docker smoke (manual fallback):** see `AUDIT_2_REPORT.md` §8 operator commands.

**Final validation pass (static only):**

| Step | 2026-11-25 result |
|------|-------------------|
| Docker CLI | BLOCKED |
| Image build | BLOCKED |
| Container startup | BLOCKED |
| `/healthz` | BLOCKED |
| COPY paths | PASS |
| `npm audit --omit=dev` (gateway) | 0 vulns |
| Prod deps exclude `redis-memory-server` | PASS (`npm ls --omit=dev`) |

---

*End of Audit 2 Checklist.*