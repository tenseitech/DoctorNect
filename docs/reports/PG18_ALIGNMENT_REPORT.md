# PostgreSQL 18.3 production alignment report

**Date:** 2026-11-12 (updated for **PROD_PG_VERSION=18.3**)  
**Production target:** `PROD_PG_MAJOR=18`, **`PROD_PG_VERSION=18.3`** (documented RDS engine).  
**Local replay image:** `postgres:18.3` (`REPLAY_PG_DOCKER_TAG=18.3`, port **5440**).  
**Staging:** Supabase **PostgreSQL 17.11** (read-only report; not a production gate).

**Staging vs production (authoritative):** [STAGING_VS_PRODUCTION_PG_GAP.md](./STAGING_VS_PRODUCTION_PG_GAP.md) — corrects historical **PG15** misstatements; lists PG **17→18** impacts; **PG18.3 replay is mandatory** before prod migrations.

---

## 1. Version pins (env)

| Variable | Value | Role |
|----------|-------|------|
| `PROD_PG_MAJOR` | `18` | Asserted on production RDS connect |
| `PROD_PG_VERSION` | `18.3` | Asserted minor on production RDS (`SHOW server_version`) |
| `REPLAY_PG_DOCKER_TAG` | `18.3` | Docker replay (`replay_from_scratch.js`) |
| `LOCAL_REPLAY_PG_PORT` | `5440` | Isolated from RDS tunnel `5433` |

Readiness probe and `verifyConnectedRdsSession` print:

- Full `version()` line  
- `SHOW server_version`  
- `Production documented target: PROD_PG_MAJOR=… PROD_PG_VERSION=…`  
- SSL status + connect host fingerprint  

---

## 2. Server versions observed per test (this session)

| Suite / script | Database | `SHOW server_version` | Notes |
|----------------|----------|------------------------|--------|
| `db_connectivity_smoke.js --env=staging` | Supabase pooler | **17.11** | Report-only; not compared to `PROD_PG_VERSION` |
| `rpc_body_parity_staging.js --confirm-live-data` | Staging **17.11** vs local `doctornect_fresh_zero` | Local: **not queried** (existing DB on **localhost:5432** — major/minor **unverified**, likely not 18.3) | **11/11** RPC normalized MATCH |
| `rds_readiness_probe.js --target=production` | Production RDS | **BLOCKED** (no tunnel; `PROD_RDS_PORT` / `5433`) | Would require **18.3** when tunnel up |
| Bootstrap 01–04 + migrations on `postgres:18.3:5440` | Local replay | **BLOCKED** | Docker Desktop engine not running |
| `rds_connect_guard` / `pg_version_policy` unit tests | N/A | N/A | **PASS** (8 tests) |

**Rule:** Any result row without a live `SHOW server_version` from a **18.3** replay is **BLOCKED** for production parity claims, not PASS.

---

## 3. Repository changes (18.3 pin)

- `scripts/lib/pg_version_policy.js` — `getProdPgVersion()`, `getReplayPgDockerTag()`, minor matching  
- `scripts/lib/rds_connect_guard.js` — prints and enforces `PROD_PG_VERSION` on RDS sessions  
- `scripts/db/rds_readiness_probe.js` — documents target at start; version checks via `verifyConnectedRdsSession`  
- `scripts/db/replay_from_scratch.js` — `postgres:${REPLAY_PG_DOCKER_TAG}` default **18.3**  
- `scripts/db/db_connectivity_smoke.js` — staging prints `SHOW server_version` + production target  
- `.env.example` / operator `.env` — `PROD_PG_VERSION=18.3`, `REPLAY_PG_DOCKER_TAG=18.3`  
- Runbooks: `RDS_CUTOVER_STEPS.md`, `RDS_PROD_TUNNEL_WINDOWS.md`, `PRODUCTION_ENV_WIRING.md`  
- **PostgREST:** `postgrest/postgrest:v16.5` (PostgreSQL 18.x; no separate 18.3 pin required)

---

## 4. PostgreSQL 18.3 release notes — impact on DoctorNect

Source: [PostgreSQL 18.3 release notes](https://www.postgresql.org/docs/18/release-18-3.html) (2026-02-26). Patch release; no dump/restore required from 18.x.

### 4.1 Items with **no** expected impact (not used in repo)

| 18.3 fix | Why low risk |
|----------|----------------|
| `json_strip_nulls()` / `jsonb_strip_nulls()` volatility | No migration or index uses these functions |
| `pg_trgm` / `strict_word_similarity` (CVE-2026-2007 follow-up) | Extension not enabled in bootstrap/migrations |
| `contrib/hstore` duplicate-key crash | `hstore` not used |
| `substring()` on toasted data (CVE-2026-2006 follow-up) | General planner fix; no app-specific dependency |
| `LATERAL UNION ALL` null-test bug | No known queries rely on this edge case in SQL migrations |

### 4.2 Items **relevant** to operations or verification

| Topic | Relevance |
|-------|-----------|
| **WAL multixid replay** (standby newer minor than primary) | If Multi-AZ: keep **primary and standbys on the same 18.x minor** (18.3) to avoid `"could not access status of transaction"` on WAL replay |
| **NOT NULL constraint naming** (18.3 fixes collisions with user constraints) | PostgreSQL **18** stores `NOT NULL` in `pg_constraint` ([major release](https://www.postgresql.org/docs/18/release-18.html)); 18.3 fixes edge-case name clashes in single `CREATE TABLE`. May affect **`schema_diff`** noise vs PG17 staging — treat auto-generated `NOT NULL` names as **noise** unless tables fail to create on replay |
| **PL/pgSQL composite → domain cast returning NULL** | Migrations use many `SECURITY DEFINER` plpgsql functions; 18.3 fixes a NULL-return edge case. Low risk unless you hit `cache lookup failed for type 0` in prod — retest RPCs after upgrade |
| **`pg_stat_get_backend_wait_event*`** for auxiliary processes | Observability only |
| **`json_strip_nulls` catalog fix for clusters upgraded from 18.0–18.2** | N/A if RDS is provisioned **directly at 18.3**; if ever upgraded from 18.0–18.2, apply manual `pg_proc` update from release notes (unlikely on fresh RDS) |

### 4.3 PostgreSQL **18** major features (not 18.3-specific) that affect parity / cutover

| Feature | DoctorNect impact |
|---------|-------------------|
| **`NOT NULL` in `pg_constraint`** | More catalog entries vs PG17 staging → `schema_diff` / grant audits may list extra constraint names; not logic changes |
| **MD5 password deprecation warnings** | RDS should use **scram-sha-256** (`password_encryption` in parameter group); align role passwords |
| **Replication / logical decoding** | `supabase_realtime` publication stub in bootstrap — supported on PG18 RDS |

### 4.4 PostgREST **v16.5**

- Pinned in `infra/aws/variables.tf` for **PostgreSQL 18** protocol/catalog compatibility.  
- **18.3** is a server patch only; PostgREST does not require a separate 18.3 build.  
- Redeploy ECS task after cutover if still on v12.x in live AWS.

---

## 5. Verification matrix (updated)

| Suite | Result | Server version used |
|-------|--------|---------------------|
| Staging smoke | **PASS** | Staging **17.11** |
| RPC body parity | **PASS** (logic) | Staging **17.11** vs local DB (**minor unverified**) |
| Production RDS probe | **BLOCKED** | Expected **18.3** when tunnel active |
| PG18.3 replay chain | **BLOCKED** | Docker unavailable |
| Unit tests (`pg_version_policy`, `rds_connect_guard`) | **PASS** | — |

---

## 6. Operator checklist (18.3)

1. RDS console: engine **PostgreSQL 18.3** (update `PROD_PG_VERSION` if AWS only offers a newer 18.x patch).  
2. Tunnel → `rds_readiness_probe.js` must show **✔ Server release matches PROD_PG_VERSION=18.3**.  
3. `docker pull postgres:18.3` → run replay chain on **5440**.  
4. Install **PostgreSQL 18.3** (or ≥18) client tools for `pg_dump`/`pg_restore`.  
5. Multi-AZ: same **18.3** on all instances in the replication set.

---

## 7. Windows local replay (exact image)

```powershell
docker pull postgres:18.3
docker run -d --name doctornect-pg18-replay -e POSTGRES_PASSWORD=postgres -p 5440:5432 postgres:18.3
```

`.env`:

```ini
PROD_PG_MAJOR=18
PROD_PG_VERSION=18.3
REPLAY_PG_DOCKER_TAG=18.3
LOCAL_REPLAY_PG_PORT=5440
REPLAY_DB_URL=postgresql://postgres:postgres@127.0.0.1:5440/postgres
```

No git commit in this alignment pass.

---

## 10. Staging 17.11 vs production 18.3 (summary)

See full matrix and PG18 replay gate: **[STAGING_VS_PRODUCTION_PG_GAP.md](./STAGING_VS_PRODUCTION_PG_GAP.md)**.

- **Wrong (corrected in repo):** staging = PG15; RPC hash diffs = “PG17 vs PG15 formatting.”  
- **Right:** staging = **17.11**; local replays for parity work were **17.11-aligned**; prod = **18.3**; `FUNCTION_BODY` cache diffs = catalog text / stale head; logic = **normalized RPC parity**.  
- **PG18.3 replay verification:** **BLOCKED** (Docker) — static migration scan in gap doc; runtime suites must pass on **18.3** before prod migrate.
