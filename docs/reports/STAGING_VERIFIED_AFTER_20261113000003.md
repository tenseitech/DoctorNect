# Staging verified (read-only) — after `20261113000003`

**Date:** 2026-11-12  
**Staging migrations applied (operator):** `20261112000006`, `20261113000002`, `20261113000003`  
**Commands (read-only):**  
`node scripts/db/grant_matrix_audit.js --compare-staging --confirm-live-data`  
`node scripts/db/rpc_body_parity_staging.js --confirm-live-data`

---

## 1. Grant matrix — 64 table diffs (local + migrations vs staging)

All **64** diffs are **`service_role` only**. **`anon` / `authenticated`:** **0** table-grant diffs (see §2).

| Class | Count | Meaning |
|-------|------:|---------|
| **(a) Staging has MORE than local** | **45** | Same table+role row exists on both sides; staging includes Supabase default extras **`REFERENCES, TRIGGER, TRUNCATE`** (and sometimes full seven privs). Local/RDS intent is **DML only** (`SELECT` / `INSERT` / `UPDATE` / `DELETE` as needed). |
| **(a′) Staging has MORE rows (no local `service_role` grant)** | **19** | Staging still has default `service_role` grants on tables the app never uses via service JWT (community_* embeds, `_schema_migrations`, etc.). **`04_rds_runtime_grants.sql` intentionally omits these** — not a staging deficit. |
| **(b) Local has MORE than staging** | **0** | — |
| **(c) Staging has FEWER than the app needs** | **0** | Probed paths: `service_role_paths_test.js` **10/10** on local replay after migrations. |

### (a) Privilege superset pattern (45 tables) — summary

Staging `service_role` on operational tables matches Supabase **`GRANT ALL`**-style ACLs; local after least-privilege migrations + `04` keeps only:

- **`SELECT, INSERT, UPDATE, DELETE`** on gateway `serviceRoleOnlyTables` + Functions DML set (`generate_rds_runtime_grants.js`).
- **`INSERT, SELECT, UPDATE`** on `ambulance_location_updates` (no `DELETE` in local ACL).
- **`SELECT` only** on `doctor_directory` / `doctor_directory_updates` for any residual service-role reads (migrations; not widened by `04`).

No case found where staging lacks a privilege the gateway/functions paths require.

### (a′) Staging-only `service_role` rows (19 tables) — not granted on RDS

`_schema_migrations`, `community_body_parts`, `community_diagnoses`, `community_lab_tests`, `community_medicines`, `community_radiology`, `doctor_availability`, `doctor_blocked_dates`, `facilities`, `lab_catalog_tests`, `lab_connections`, `medical_directory`, `pharmacy_connections`, `pharmacy_delivery_medicines`, `prescription_investigations`, `prescription_medicines`, `prescription_referrals`, `review_public`, `review_votes`.

Clients use **`authenticated`**; anon uses allowlist tables only. **No change needed for cutover.**

### Service-role paths → required grants vs `04`

| Code path | Resource | Privileges required | `04_rds_runtime_grants.sql` |
|-----------|----------|---------------------|-----------------------------|
| Notification worker / outbox | `notification_outbox` | `SELECT`, `INSERT`, `UPDATE` (status) | `SELECT, INSERT, UPDATE, DELETE` (no TRIGGER/TRUNCATE/REFERENCES) |
| `admin_platform_actions.js` | `admin_audit_logs` | `INSERT` | `INSERT` (+ SELECT; no client INSERT — RLS) |
| `security_logger.js` | `security_events` | `INSERT` | DML set |
| OTP / abuse (Functions) | `otp_challenges`, `abuse_rate_limits` | `SELECT` / DML per worker | Listed in `serviceRoleOnlyTables` |
| Sync DLQ | `sync_dead_letter_queue` | `SELECT`, `INSERT` | DML set |
| Razorpay webhooks | `razorpay_*`, `promoted_ads` | `INSERT`, `UPDATE` | DML on payment tables + `promoted_ads` |
| `delete_my_account.js` (via service client) | Core profile + clinical tables | `SELECT`, `DELETE`, `UPDATE` on `users`, `patients`, `doctors`, … | `backendDmlTables` ∪ `serviceRoleOnlyTables` — DML only |
| `s3_storage.js` audit | `storage_audit_logs` | `INSERT` | `serviceRoleOnlyTables` |
| KYC / private rows | `doctor_private`, `doctor_education`, … | `SELECT`, `UPDATE` | `serviceRoleOnlyTables` |
| Maintenance RPC | `expire_stale_ambulance_broadcasts()` | `EXECUTE` | Explicit `GRANT EXECUTE` |
| `delete_my_account` HTTP | — | Gateway blocks client RPC | No SQL RPC grant |
| `book_appointment_atomic` | RPC | **`authenticated` EXECUTE** (not service_role) | Unchanged by `04` |

**`04` does not grant** `REFERENCES`, `TRIGGER`, or `TRUNCATE` to `service_role`. Staging’s extra privileges are **(a)** noise only.

**Routine note:** staging grants `service_role` **EXECUTE** on trigger helpers (`enqueue_notification_outbox`, `trigger_set_timestamp`, `rls_auto_enable`, …). Repo migrations **REVOKE** these from `service_role`; triggers run as **SECURITY DEFINER**. RDS does not need service_role EXECUTE on triggers.

---

## 2. `anon` and `authenticated` vs RDS intent

Live compare: **`docs/reports/anon_authenticated_grant_diff_staging.json`** → **0** table-level diffs.

- **`anon`:** migrations + `20261103000008`; `04` re-asserts **only** `doctor_directory`, `lab_catalog_tests`, `system_config`, `review_public` (**SELECT**). Matches staging.
- **`authenticated`:** entirely from **`db/migrations/`** (least privilege). `04` does **not** broaden `authenticated`. After replay, local matches staging.

---

## 3. RPC `FUNCTION_BODY` — 11 vs 10 reconciliation

| Source | Count | Notes |
|--------|------:|-------|
| `fresh_local_vs_staging_schema_diff.json` (cached, pre–staging head) | **11 × `FUNCTION_BODY`** | **Catalog / `pg_get_functiondef` text** noise and stale staging head — **not** PG15 vs PG17 (staging is **17.11**, same as historical local replay) |
| Same file | **1 × `FUNCTION_MISSING`** | `rls_auto_enable` (Supabase-only; not in repo) |
| Prior doc typo | **“10”** | Counted bodies only and dropped one name |

**Live check (staging at head vs `doctornect_fresh_zero` replay):**  
`docs/reports/rpc_body_staging_vs_repo_local.json` — **11/11 normalized MATCH** (comment/whitespace stripped).

Functions: `accept_ambulance_request`, `book_appointment_atomic`, `cancel_ambulance_broadcast`, `complete_ambulance_trip`, `get_ambulance_trip_contact`, `get_ambulance_trip_location`, `reschedule_appointment_atomic`, `update_ambulance_location`, `update_lab_booking_status`, `update_lab_order_status`, `update_pharmacy_delivery_status`.

**Conclusion:** No logic drift between staging and repo migrations at current head; earlier hash diffs were **not** substantive once staging caught up (and/or normalization). **Production gate:** PG **18.3** replay must pass before prod migrations — see [STAGING_VS_PRODUCTION_PG_GAP.md](./STAGING_VS_PRODUCTION_PG_GAP.md) (staging **17.11** ≠ production **18.3**).

---

## 4. Artifacts

| File | Purpose |
|------|---------|
| `docs/reports/grant_matrix_local.json` | Full matrices + 64 `tableDiffs` |
| `docs/reports/grant_table_diffs_classified.json` | (a)/(a′) classification |
| `docs/reports/anon_authenticated_grant_diff_staging.json` | Client role parity |
| `docs/reports/rpc_body_staging_vs_repo_local.json` | Normalized RPC bodies |
