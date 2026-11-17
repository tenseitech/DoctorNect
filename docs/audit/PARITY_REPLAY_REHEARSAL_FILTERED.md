# Parity: `replay_check` vs `doctornect_rehearsal` (pg_stat filtered)

**Tool:** `node scripts/db/schema_diff.js --pair=replay_check-vs-rehearsal` (filters `pg_stat_statements*` noise in-tool).  
**Last full run:** 2026-11-16 local (`docs/audit-local/schema_diff_gate.txt`). **Re-run after 2026-11-17 harness fix: UNVERIFIED** (Docker `127.0.0.1:5442` down on 2026-11-17).

## Noise dropped automatically

- `COLUMN` rows for `pg_stat_statements.*` (view columns on replay baseline only).
- `FUNCTION_MISSING` for `pg_stat_statements`, `pg_stat_statements_info`, `pg_stat_statements_reset`.
- `EXTENSION_MISSING` / `EXTENSION_EXTRA` for `pg_stat_statements`.

## Prior unfiltered residual (2026-11-16, **re-verify**)

| Category | n (unfiltered) | Typical object / direction | Expected? |
|----------|---------------:|----------------------------|-----------|
| `CONSTRAINT_EXTRA` | 84 | Mostly stats-view constraints **extra on rehearsal** | **Expected noise** until both sides align on `pg_stat_statements` |
| `COLUMN_EXTRA` | 18 | Stats-related columns **only on rehearsal** | **Expected noise** |
| `FUNCTION_BODY` | 5 | Same `proname`, hash differs (owner/`search_path`) | **UNVERIFIED** — fetch `pg_get_functiondef` both sides |
| `GRANT_EXTRA` | 4 | Table grant triplets **only on rehearsal** | **UNVERIFIED** — inspect `information_schema.role_table_grants` |
| `TRIGGER_EXTRA` | 1 | Trigger on rehearsal not on replay | **UNVERIFIED** — identify table/trigger name from diff output |

### GRANT_EXTRA / FUNCTION_BODY (exact diff procedure)

```sql
-- Grants (example key: table:grantee:privilege from diff)
SELECT grantee, privilege_type FROM information_schema.role_table_grants
 WHERE table_schema='public' AND table_name='<table>' ORDER BY 1,2;

-- Function body
SELECT pg_get_functiondef(p.oid) FROM pg_proc p
 JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='<name>' LIMIT 1;
```

Run on **both** DBs; differences after 000005 owner changes are often **expected** on replay until replay is migrated with same ledger head.