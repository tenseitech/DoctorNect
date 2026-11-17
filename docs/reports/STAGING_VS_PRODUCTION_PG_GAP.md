# Staging (PostgreSQL 17.11) vs production (PostgreSQL 18.3)

**Facts (2026-11-12):**

| Environment | Version | Source |
|-------------|---------|--------|
| **Staging** (Supabase) | **17.11** | `db_connectivity_smoke.js --env=staging` → `SHOW server_version: 17.11` |
| **Production** (AWS RDS) | **18.3** | Operator-declared engine; `PROD_PG_VERSION=18.3` enforced on RDS probes |
| **Historical local replay** | **17.11** (same major/minor as staging) | `grant_matrix_local.json`, prior replays on localhost / Docker aligned with staging |

**Corrections:** Staging was **never PostgreSQL 15** in verified smoke. Older docs/reports that described staging as PG15, or explained **11 × `FUNCTION_BODY`** `schema_diff` hashes as “PG17 local vs PG15 staging formatting,” are **incorrect** — see [§ Historical doc errors corrected](#historical-doc-errors-corrected).

---

## Production-like gate (mandatory)

**Before any production migration apply**, the full verification chain must pass on a **`postgres:18.3`** replay database (`REPLAY_PG_DOCKER_TAG=18.3`, `LOCAL_REPLAY_PG_PORT=5440`) — **not** on staging and **not** on a PG17 replay.

Staging remains useful for **read-only** grant/RPC parity checks against repo migrations, but **cannot** substitute for PG18.3 replay because production is **18.3**.

Minimum gate (mutates replay DB only):

```powershell
docker pull postgres:18.3
docker run -d --name doctornect-pg18-replay -e POSTGRES_PASSWORD=postgres -p 5440:5432 postgres:18.3
# .env: REPLAY_DB_URL on 5440, PROD_PG_VERSION=18.3
node scripts/db/replay_from_scratch.js
node scripts/db/fresh_local_parity_test.js
node scripts/db/grant_matrix_audit.js
node scripts/db/rls_coverage_audit.js
node scripts/db/gateway_rls_authorization_suite.js
node scripts/db/service_role_paths_test.js
node scripts/db/real_path_authorization_e2e.js
```

Documented in [RDS_CUTOVER_STEPS.md](../runbooks/RDS_CUTOVER_STEPS.md) and [PG18_ALIGNMENT_REPORT.md](./PG18_ALIGNMENT_REPORT.md).

**PG18.3 replay status on audit machine:** **BLOCKED** (Docker Desktop not running). Until replay passes, production migration apply stays **gated**.

---

## PostgreSQL 17 → 18: changes that can affect DoctorNect

Assessment method: [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html) + static scan of `db/migrations/`, `db/rds_bootstrap/`, and the 11 parity RPCs. **Runtime proof on PG18.3 replay** is **BLOCKED** until Docker replay runs.

| Area | PG 18 change | Relevance to this app | Migration / RPC scan | PG18.3 replay verify |
|------|----------------|------------------------|----------------------|----------------------|
| **Catalog / `schema_diff`** | Column **`NOT NULL`** stored in `pg_constraint` with generated names | Extra diff lines vs PG17 staging (`*_not_null` keys in cached JSON); **not** application logic | All migrations use normal `NOT NULL`; no reliance on pre-18 catalog shape | **BLOCKED** — expect noise, not failures |
| **`pg_get_functiondef` / hashes** | Planner/catalog tweaks can change **decompiled function text** | Explains historical **`FUNCTION_BODY`** hash mismatches in `fresh_local_vs_staging_schema_diff.json` when comparing across versions or stale staging head — **not** PG15 formatting | **11 RPCs** match staging with **normalized** parity (`rpc_body_parity_staging.js`) on PG17-era local DB | **BLOCKED** — re-run normalized parity after PG18.3 replay |
| **RLS** | No breaking RLS syntax removal in PG18 notes | Policies use standard `CREATE POLICY` / `FORCE ROW LEVEL SECURITY` | Extensive RLS in migrations; harness `rls_coverage_audit.js` | **BLOCKED** |
| **Grants** | Removed non-functional **rule** privileges in `GRANT`/`REVOKE` | Migrations grant table/routine privileges, not rules | No `GRANT ... ON RULE` in repo | **BLOCKED** (grant matrix) |
| **`SECURITY DEFINER`** | No removal; PG18.3 fixes edge **PL/pgSQL** NULL composite→domain return | Many RPCs/migrations use `SECURITY DEFINER` + `SET search_path = ''` | Pattern present in `20261026000001_rpc_null_safe_authz.sql`, guards, provisioning | **BLOCKED** — gateway + RPC suites |
| **Triggers** | **`AFTER`** triggers run as role active when **queued**, not at `COMMIT` | Behaviour change if migrations used deferred `AFTER` + mid-xact `SET ROLE` | Repo triggers are predominantly **`BEFORE`** (`doctornect_schema`, guards, audit) | **BLOCKED** — low static risk |
| **Authentication** | **MD5 password** deprecation warnings; SCRAM default push | RDS: `password_encryption=scram-sha-256`; roles from bootstrap/migrations | `md5(text)` still used **inside** prescription RPC for deterministic keys — **not** password auth | **PASS** (static) — password auth N/A in SQL |
| **UUID / JSON** | `uuidv7()` added; `gen_random_uuid()` unchanged | App uses **`gen_random_uuid()`** and `pgcrypto` | No `uuidv7()` in migrations | **BLOCKED** — apply migrations on 18.3 |
| **JSON** | `jsonb` null→scalar cast; `json_strip_nulls` volatility fix (18.3) | No indexes on `json_strip_nulls` in migrations | Grep: no `json_strip_nulls` in migrations | **PASS** (static) |
| **Extensions** | Same names; RDS ships PG18 builds of `pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `pg_cron` | Bootstrap `01` + migrations | `CREATE EXTENSION` idempotent | **BLOCKED** — `rds_readiness_probe` extension list |
| **`pg_stat_statements`** | Query jumbling / new columns (parallel, WAL buffers) | Ops/monitoring only; parameter group preloads extension | Terraform `shared_preload_libraries` | **BLOCKED** (RDS) |
| **Planner / statistics** | General optimizer changes 17→18 | Possible plan shifts for heavy reports; OLTP RPC paths unchanged SQL | No version-specific hints in SQL | **BLOCKED** — optional `EXPLAIN` on replay |
| **Default privileges** | `ALTER DEFAULT PRIVILEGES` extended to large objects | Migrations set explicit grants + `04_rds_runtime_grants.sql` | No LO default priv migrations | **PASS** (static) |
| **Logical replication / publications** | Continued support | `supabase_realtime` publication stub in bootstrap | `CREATE PUBLICATION` in `01_roles_and_extensions.sql` | **BLOCKED** |
| **PostgREST** | Server patch **18.3**; client **`postgrest:v16.5`** for PG18 protocol | ECS pin in `infra/aws/variables.tf` | No server version in SQL | **BLOCKED** — deploy + e2e |

---

## Staging 17.11 vs PG18.3 replay — what to trust

| Check | Staging 17.11 | PG18.3 replay (required for prod) |
|-------|---------------|-----------------------------------|
| Migration SQL applies cleanly | Useful signal (already at head) | **Authoritative** for production |
| `schema_diff` vs staging | Many diffs expected (major + Supabase grants) | Compare replay to **staging read-only** only for grants/RPC; catalog noise expected |
| RPC logic | **11/11** normalized MATCH (read-only, 2026-11-12) | Must re-pass after **18.3** `fresh_local_parity_test` |
| RLS / gateway auth | Staging exercises live Supabase stack | **`gateway_rls_authorization_suite.js`** on replay + gateway against replay PostgREST |

---

## Historical doc errors corrected

| Incorrect claim | Correction |
|-----------------|------------|
| Staging is PostgreSQL **15** | Staging is **17.11** (verified read-only smoke) |
| 11 RPC/`FUNCTION_BODY` diffs = **PG17 vs PG15** formatting | Diffs were **catalog/`pg_get_functiondef` text** and **stale staging head** vs local replay; both sides were **PG17-era** for verified parity work |
| RDS / replay target **15.x** | Production **18.3**; replay **`postgres:18.3`** |
| Optional **PG15** Docker container | Removed from runbooks; use **18.3** only for production-like replay |

Files updated in this pass: `STAGING_VERIFIED_AFTER_20261113000003.md`, `generate_schema_diff_breakdown.js`, `RDS_CUTOVER_STEPS.md`, `DB_MIGRATION_VERIFICATION.md`, `CRON_PLAN.md`, `PRODUCTION_CUTOVER_RDS.md`, `REMAINING_WORK.md` (historical note), `PG18_ALIGNMENT_REPORT.md`.

---

## References

- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)
- [PostgreSQL 18.3 release notes](https://www.postgresql.org/docs/18/release-18-3.html)
- [PG18_ALIGNMENT_REPORT.md](./PG18_ALIGNMENT_REPORT.md)
