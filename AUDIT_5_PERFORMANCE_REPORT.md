# Audit 5 — Performance, scalability & resource optimization

**Date:** 2026-11-26  
**Branch:** `audit5/performance-scalability`  
**Parent HEAD:** `ce948b1022aeadc703fe175acf6d2f80bda71b0e` (Audit 3 tip; prior Audit 4 work uncommitted on same tree)

---

## 1. Executive summary

Audit 5 reviewed Flutter client data paths, Supabase polling/watchers, gateway in-memory rate limiting, and static ECS/Functions configuration. **Six remediations** were implemented with regression tests. No production deploy, no database migrations, and **Audit 4 remains ON HOLD** (no changes to Audit 4 artifacts).

**Overall status:** **AUDIT 5 COMPLETE — Static/code verification completed; runtime profiling limited.**

---

## 2. Scope

Performance, scalability, resource use, API/client request patterns, caching, concurrency, and bottleneck analysis across Flutter, Cloud Functions, Auth Gateway, PostgREST usage, Redis (read-only analysis), and Terraform/ECS (static).

---

## 3. Git baseline

| Item | Value |
|------|--------|
| Start branch | `audit4/database-remediation` (uncommitted Audit 1–4 dirty tree) |
| Work branch | `audit5/performance-scalability` |
| Base commit | `ce948b1` |
| Audit 4 | **Not modified** in this audit commit set |

---

## 4. Architecture (reviewed)

- **Flutter** → Supabase PostgREST (staging) or Gateway → PostgREST (production polling).
- **Functions** → PostgREST client + optional `pg_pool` direct SQL.
- **Gateway** → JWT mint + proxy; in-memory or Redis rate limits.
- **Data plane** performance notes reference Audit 4 connection budget; **no Audit 4 SQL applied.**

---

## 5. Performance baseline matrix

| Component | Current implementation | Bottleneck | Evidence | Priority |
|-----------|------------------------|------------|----------|----------|
| `SupabaseWatcherStateMachine` | Periodic `resync()` | Overlapping fetches during slow polls | Source: no in-flight guard before fix | **High** |
| `in_app_notifications` fetch | `.select()` all columns | Large JSON payloads | Static: many unused columns | Medium |
| `health_records` list | `.select()` all columns | Wide clinical rows | `CODEBASE_AUDIT_REPORT` PERF-04 | Medium |
| `markAllRead` | Sequential `update` per id | N round-trips | Source loop | **High** |
| `streamTable` polling | `.select()` | Same as repos | Production polling path | Medium |
| Gateway `RateLimiter` | `Map` per client key | Unbounded keys under IP flood | Static analysis | **High** |
| Lab/ambulance repos | `.limit(500)` etc. | Client payload size | PERF-02 (documented) | Medium |
| ECS PostgREST | 2 tasks × pool 10 | Aggregate DB connections | Audit 4 doc only | Info |
| Clinical assets (gz/fonts) | Bundled assets | APK/web weight | PERF-01 | Low |

---

## 6–15. Findings summary (by area)

### Flutter

- **PERF-05 (High)** — Poll/resync request stampede: **fixed** (coalescing).
- **PERF-04 (Medium)** — Broad PostgREST selects on notifications/health records: **fixed** (column lists + `streamTable.selectColumns`).
- **PERF-06 (High)** — `markAllRead` N+1 updates: **fixed** (single `inFilter` batch).
- **PERF-02 (Medium)** — Cursor/pagination gaps across repos: **documented** (no broad refactor).
- Polling intervals 3–10s across repos: **accepted** (production Realtime bypass by design).

### Frontend / API

- `streamTable` already dedupes via JSON hash (strength); extended with optional column projection.
- No global response cache added (auth-sensitive data).

### Backend / API gateway

- **PERF-12 (High)** — In-memory rate limiter unbounded `Map`: **fixed** (`maxTrackedKeys` default 50_000).
- Proxy path: header allowlist, single body buffer — **acceptable** (static).
- JWKS / Firebase verify per request — **documented**; no change (security trade-off).

### Database queries (analysis only)

- N+1 patterns in notification mark-read: **fixed** client-side.
- Index recommendations: existing migration indexes on `recipient_uid`, `health_records.patient_id` — **no new migrations** (Audit 4 HOLD).
- Reference: **DB-03** connection budget in `docs/audit/AUDIT_4_CONNECTION_BUDGET.md`.

### Redis / cache

- Audit 4 key prefix isolation — **unchanged**.
- Production gateway expects Redis for rate limits (Audit 1/4 docs) — not modified.

### Memory / CPU

- Rate limiter micro-benchmark: 10k keys processed in **~259 ms** local, map capped at 500 keys in test.

### ECS / Cloud Functions (static)

| Setting | Source | Note |
|---------|--------|------|
| ECS `desired_count` | 2 | Throughput horizontal |
| `PGRST_DB_POOL` | 10 | Per task |
| `PG_POOL_MAX` | 10 default | Per function instance |
| Function timeout | up to 540s | `index.js` callable config |

**Recommendations only** — no Terraform edits.

---

## 16. Findings table

| ID | Severity | Component | Issue | Evidence | Remediation | Status |
|----|----------|-----------|-------|----------|-------------|--------|
| PERF-05 | High | Flutter watcher | Overlapping resync | Source | Coalesced `resync()` | **Fixed** |
| PERF-06 | High | Notifications | N× mark-read HTTP | Source | Batch `inFilter` update | **Fixed** |
| PERF-04 | Medium | PostgREST client | Broad `.select()` | Static | Column projections | **Partial** (2 tables) |
| PERF-02 | Medium | Lists | Pagination/cursors | Master audit | Documented | **Open** |
| PERF-12 | High | Gateway | Unbounded rate-limit map | Static | `maxTrackedKeys` | **Fixed** |
| PERF-01 | Low | Assets | Large bundled clinical data | `assets/` | Documented | **Open** |
| PERF-03 | Medium | Dependencies | Heavy SDK surface | pubspec | Documented | **Open** |
| PERF-07 | Info | DB connections | Pool sizing | Audit 4 | See DB-03 doc | **Referenced** |
| PERF-08 | Info | Polling | Multi-repo 4–10s timers | Source | By design | **Accepted** |

---

## 17. Code changes

| File | Change |
|------|--------|
| `frontend/lib/core/supabase/supabase_watcher_state_machine.dart` | Resync coalescing |
| `frontend/lib/core/supabase/in_app_notification_supabase_repository.dart` | Column projection; batch mark-all-read |
| `frontend/lib/core/supabase/repositories/supabase_health_records_repository.dart` | Column projection; polling select |
| `frontend/lib/core/supabase/supabase_stream_table.dart` | Optional `selectColumns` |
| `services/api-gateway/src/security.js` | Rate limiter memory cap |
| `frontend/test/core/supabase/watcher_resync_coalesce_test.dart` | New tests |
| `services/api-gateway/test/rate_limit_memory_cap.test.js` | New tests + micro-bench |

**Audit 4 files not touched:** migrations, `in_app_notifications.js`, gateway health probes, etc.

---

## 18. Tests

| Command | Suite | Pass | Fail | Skip | Duration |
|---------|-------|-----:|-----:|-----:|---------|
| `flutter test test/core/supabase/watcher_resync_coalesce_test.dart` | Flutter | 2 | 0 | 0 | ~7s |
| `flutter test test/phase_e_supabase_support_and_notifications_test.dart` | Flutter | 6 | 0 | 0 | ~6s |
| `node --test test/rate_limit_memory_cap.test.js` | Gateway | 2 | 0 | 0 | ~0.34s |

Environment: Windows 10, local dev, no staging/production endpoints.

---

## 19. Benchmarks (measured)

| Benchmark | Before | After | Conditions |
|-----------|--------|-------|------------|
| RateLimiter 10k distinct keys | N/A (no cap) | **259 ms**, map size ≤500 | `maxTrackedKeys=500`, local Node |
| Watcher concurrent fetches | Unbounded possible | **≤1** in flight | Unit test, 80ms window |

End-to-end API latency and Flutter frame times: **not measured** (runtime evidence pending).

---

## 20. Runtime limitations

- No production/staging load tests.
- No Flutter DevTools timeline captures.
- No RDS `EXPLAIN` on live queries (Audit 4 HOLD).

---

## 21. Recommendations (future)

1. Extend `listSelectColumns` pattern to high-traffic repos (`lab_bookings`, `appointments`).
2. Adopt shared cursor pagination (`DataPage`) per PERF-02.
3. Operator: model RDS connections using `AUDIT_4_CONNECTION_BUDGET.md` (Audit 4 deploy).
4. Optional: gateway JWKS token cache with short TTL (security review required).

---

## 22. Audit 1–4 preservation

| Audit | Status in this pass |
|-------|---------------------|
| Audit 1 | **Unchanged** (not in commit scope) |
| Audit 2 | **Unchanged** |
| Audit 3 | **Unchanged** |
| Audit 4 | **ON HOLD — untouched** |

---

## 23. Final Audit 5 status

**AUDIT 5 COMPLETE — Static/code verification completed, runtime evidence limited.**

See also: `docs/audit/AUDIT_5_CHECKLIST.md`, `docs/audit/PERF_FOLLOWUP_RECOMMENDATIONS.md`.