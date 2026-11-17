# RLS SQL harness failures (2026-11-15 re-run)

Sources: `migration_audit_rls_harness_staging_2026-11-15.txt` (**20 FAIL** on staging), `migration_audit_rds_scratch_replay_5440_2026-11-15.txt` embedded harness (**12 FAIL** on clean `replay_check`).

| Case (short) | Expected | Actual | Classification | Action |
|--------------|----------|--------|----------------|--------|
| User `display_name` update (all roles) | `00000` | `42501` | **Security policy** (users column guard) | New migration: allow owner `UPDATE` on whitelisted profile columns only (`db/migrations` + RDS override) |
| Anon `doctor_directory` / `review_public` / `promoted_ads` | `00000` | `42501` | **Drift** on staging (grants exist in `20261025000001` / `20261103000008`) | Re-apply staging migrations; on clean replay fix grants if still 42501 |
| Users upsert re-login (verified roles) | `00000` | `42501` | **Security / fixture** | Align `users` upsert policy with verified re-login; verify harness JWT claims |
| `doctor_directory` anon visibility cases | `00000` or 0 rows | `42501` | **Drift or FORCE RLS** | Confirm `GRANT SELECT` + view owner; avoid weakening RLS |
| Privileged columns / reviews aggregate | mixed | `FAIL` | **Test ordering / fixture** | Fix harness seed + trusted writer triggers on clean DB |
| Super admin verify doctor | `00000` + row | `FAIL` partial | **Policy gap** | Ensure `private.is_super_admin()` + admin_users path on staging |

**Target:** 210/210 on **clean** `replay_check` after migrations; staging may differ until staging ledger matches head.

**Do not** weaken tests for anon deny cases that are intentional security controls.