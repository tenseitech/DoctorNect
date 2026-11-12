# Branch plan: chore audit vs postgres-only history

**Constraint:** no history rewrite (no force-push, no rebase that drops commits from shared refs).

**Current branch:** `chore/dedupe-structure-audit` (verify with `git branch --show-current`).

**Safety snapshot for chore-only slice:** `5c107e9` (pre-dedupe safety point on this line).

**Chore commits (`5c107e9..HEAD`, newest first — audit/docs/test harness only):**

| Commit | Summary |
|--------|---------|
| `cd7875d` | gitignore jscpd / phase1 SQL audit artifacts |
| `dc8b9e0` | Dart line endings via gitattributes |
| `2edf34f` | archive superseded verification reports |
| `2184a0a` | `npm run test:emulators`, backend baseline |
| `75d5277` | drop `USE_SUPABASE_DB_DOCTOR_PATIENT` |
| `c4fe502` | docs/env safe flag defaults |
| `baa2faa` | `setup_env` isolation, env parity test-only vars |
| `dd9e563` | audit exposure window, npm baseline docs |
| `41f8498` | gitignore audit snapshots / local test logs |
| `5080f48` | consolidate env + baseline under `docs/audit/` |
| `413c866` | env parity scripts, audit output paths |
| `47ce0ca` | canonical `S3_BUCKET` fail-fast |
| `f8d17b7` | isolate npm test from `backend/functions/.env` |
| `92a983c` | canonical `S3_BUCKET`, stricter env parity |
| `ab88816` | Phase 1 near-duplicate docs, Dart scan |
| `81336d0` | consolidate env example templates |
| `83144fa` | gitignore backups / staging snapshots |
| `0ed5b58` | pre-dedupe baselines (flutter, emulator, env matrix) |
| `6104d5c` | revert root `/functions/` gitignore |
| `d08c033` | remove duplicate firestore security_rules ref |
| `dcc228f` | backend emulator baseline, phase1 gitignore |
| `fff59e4` | clear pre-existing analyze issues |
| `a3c39dd` | Phase 0 dedupe audit inventory |

**Postgres / architecture slice (not chore):** commits such as `4dfae67` (*Postgres-only functions, outbox worker, tests*) and the long `main..HEAD` tail that predates `5c107e9` on this branch. Treat that as **`feature/postgres-only-architecture`** (or equivalent) work, not dedupe-structure audit.

---

## Option A — Cherry-pick chore onto a clean branch (recommended before merge)

1. Branch from **`origin/main`** (or the agreed integration branch):  
   `git checkout -b chore/dedupe-structure-audit-clean origin/main`
2. Cherry-pick **`a3c39dd^..cd7875d`** or cherry-pick the table above one-by-one (oldest first: `a3c39dd` → … → `cd7875d`).
3. Resolve conflicts only in docs/scripts/tests touched by both slices.
4. Open PR **chore-only**; land before or in parallel with postgres-only PR.

**Pros:** Reviewers see a small, reviewable diff. **Cons:** Cherry-pick conflict resolution once.

---

## Option B — Merge postgres-first, then rebase chore locally (after merge, no rewrite of shared history)

1. Merge **`feature/postgres-only-architecture`** → `main` via normal PR.
2. Rebase **`chore/dedupe-structure-audit`** onto updated `main` locally (`git rebase main`) and fix conflicts.
3. PR chore branch; history on the chore branch is linearized locally but **`main` is never force-pushed**.

**Pros:** Single source of truth for architecture first. **Cons:** Large rebase if postgres PR is huge.

---

## Option C — Two PRs from current branch (minimal git gymnastics)

1. PR1: postgres-only range (explicit commit list / compare URL from merge-base to before first chore commit).
2. PR2: chore range `5c107e9..HEAD`.

**Pros:** No cherry-pick. **Cons:** GitHub compare must be carefully scoped; easy to include wrong commits.

---

## Recommendation

- If **postgres-only is not ready to merge:** **Option A** (cherry-pick chore table onto `main`).
- If **postgres-only merges first:** **Option B** (rebase chore onto `main` after merge).
- Avoid **Option C** unless compare URLs are double-checked against the commit table above.

**Do not:** `git push --force` to `main`, filter-branch, or drop `4dfae67` from any branch that others may have pulled.

---

## Deploy policy (cutover vs chore)

| Rule | Detail |
|------|--------|
| **Cutover deploy** | Production deploy is **`feature/postgres-only-architecture` / full audit branch content**, not the chore-only slice (`5c107e9..HEAD` docs/tests/gitignore). |
| **Chore-only** | Commits from `a3c39dd` through `cd7875d` (**env parity, baselines, emulators, archives**) must **not** be deployed alone — they do not constitute a safe production functions release. |
| **Pre-deploy gate** | **No** `npm run deploy` until local `backend/functions/.env` **`SUPABASE_URL` hash** is matched against **deployed** function env hashes (see `docs/audit/PROD_WIRING_CHECK.md`; populate from user-run gcloud, no secrets in git). |
| **Full functions deploy forbidden pre-cutover** | **Never** `firebase deploy --only functions` (unscoped) from **`chore/dedupe-structure-audit`** / postgres-only tips — removes **22** Firestore trigger functions from the live project. Use STALE_REF **tier** `--only` lists in `docs/audit/DEPLOY_HASH_COHORT.md` only. **Never** use **`--force`**. |
| **Service account quarantine** | Do **not** delete or relocate `scripts/service-account.json` until explicitly confirmed by repo owner (see dedupe audit proposal). |

Deploying **`chore/dedupe-structure-audit` as a whole** implies the postgres/cutover code path that shares the branch — treat that as the intentional cutover vehicle, but still satisfy the hash gate and staged tiers in `docs/ops/STALE_REF_REDEPLOY_PLAN.md` before changing production traffic.

| **Stale function redeploy** | Use the **git commit / build hash that produced the revision currently live** for that function (e.g. **`fb8e2e13`** on 2026-10-06 per SECURITY_AUDIT), or the commit recorded when a tier is actually executed — **not** an arbitrary tip of `chore/dedupe-structure-audit` unless that tip is what you intend to ship after full test matrix. |
| **Chore-only tip** | Docs/tests/gitignore commits alone must **not** be deployed as a functions release. |
