# Pre-push history check (names only — no values)

**Gate:** Do **not** push `chore/dedupe-structure-audit` until the **Remote origin scan** table has **no `real-looking` credential hits** (documentation hits and `.env.example` **non-secret config** rows may remain — see notes).

Regenerate: `node scripts/audit/pre_push_history_scan.js` (writes JSON to stdout; do not commit output with values).

Host hash rule: `sha256(hostname).slice(0, 8)` compared to **`40d01c23`** (production Supabase cohort label) and **`800db356`** (legacy/stale cohort label) — **yes/no only**.

---

## Flagged example-template commits

| Commit | File | Variable | Value class | Password-length class | Hash `40d01c23` | Hash `800db356` | On `origin/*` |
|--------|------|----------|-------------|----------------------|-----------------|-----------------|---------------|
| `73860fc8` | `backend/functions/.env.example` | `S3_BUCKET` | real-looking (heuristic: long token) | n/a | no | no | **no** |
| `73860fc8` | `backend/functions/.env.example` | `S3_BUCKET_NAME` | real-looking (same) | n/a | no | no | **no** |
| `73860fc8` | `backend/functions/.env.example` | `AWS_S3_VAULT_BUCKET` | real-looking (same) | n/a | no | no | **no** |
| `b1a700fb` | `backend/functions/.env.example` | `SUPABASE_WEBHOOK_SECRET` | real-looking | real-looking-len | no | no | **no** |
| `36e2177a` | `.env.migration.example` | `STAGING_SUPABASE_DB_URL` | real-looking (remote DB URL pattern) | n/a | no | no | **yes** |
| `36e2177a` | `.env.migration.example` | `SUPABASE_URL` | real-looking (`.supabase.co` host) | n/a | no | no | **yes** |

**Notes**

- `73860fc8` / `b1a700fb` are **not** on any `origin/*` branch in this clone (local-only lines).
- `36e2177a` **is** on `origin/main` (and related remotes). Values are **example/migration templates** — still run manual review before push; prefer replacing with obvious placeholders in a follow-up docs commit if audit requires zero `real-looking` on main.
- S3 bucket **names** are not API secrets; treat `73860fc8` rows as **config-shape** for gate purposes unless your policy treats all `real-looking` heuristics as blockers.

---

## Remote origin scan (`git log --remotes=origin`)

Patterns (no line content printed): `-S"eyJhbGci"`, `-S"rzp_live_"`, `-S"AKIA"`, `-G"postgres(ql)?://[^:/@]+:[^@\[<]{6,}@"`.

| Commit | File (names only) | Pattern | Classification |
|--------|-------------------|---------|----------------|
| `36e2177` | `.env.migration.example` | `-S"eyJhbGci"` | placeholder-looking |
| `7d616f1` | `docs/PRE_CUTOVER_CHECKLIST.md` | `-S"rzp_live_"` | placeholder-looking |
| `7d616f1` | `scripts/verify_production_build_config.js` | `-S"rzp_live_"` | placeholder-looking |

**Gate status:** No **`real-looking`** credential hit in tracked **origin** history from these pickaxe scans. Re-run before every push.

---

## Operator commands (read-only)

```powershell
git --no-pager branch -r --contains <commit>
git --no-pager log --remotes=origin --format="== %h" --name-only -S"eyJhbGci" --
git --no-pager log --remotes=origin --format="== %h" --name-only -S"rzp_live_" --
git --no-pager log --remotes=origin --format="== %h" --name-only -S"AKIA" --
git --no-pager log --remotes=origin --format="== %h" --name-only -G"postgres(ql)?://[^:/@]+:[^@\[<]{6,}@" --
```
