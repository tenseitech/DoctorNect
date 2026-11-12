# Release gate (ordered)

Each gate needs an **owner** (role) and **proof** artifact. No production deploy until Gate 1–3 pass.

| # | Gate | Owner | Proof |
|---|------|-------|-------|
| 1 | **Pre-push history check** | Engineering lead | `docs/audit/PRE_PUSH_HISTORY_CHECK.md` tables re-run; **no `real-looking` credential hit** on `origin/*` pickaxe scan |
| 2 | **Check 0 resolved** | Backend / release | `node scripts/predeploy_secret_check.js` exit **0**; deploy `.env` has no plain `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` (names only in docs) |
| 3 | **`cleanupPendingRegistration` canary** | Backend / release | `firebase deploy --only functions:cleanupPendingRegistration` (**no `--force`**) after Gate 2; callable visible in console; smoke `{ok,cleaned}` with test auth (operator) |
| 4 | **Login hotfix (G1) decision** | Product + backend | Written decision in `docs/audit/LOGIN_HOTFIX_DEPLOY_PLAN.md`: deploy post-OTP `exists`/`role` patch **or** accept legacy fallback; if deploy, proof = revision hash / cohort doc |
| 5 | **Role matrix manual test** | QA | Checklist signed against `docs/audit/ROLE_RELEASE_MATRIX.md` — one smoke path per role (patient, doctor, lab, pharmacy, ambulance, admin) |
| 6 | **Docker integration + RLS** | Backend / DBA | Commands in `docs/audit/DOCKER_RUN.md`: four docker-gated integration tests green; `pg_policies` DELETE diff shows admin-only deletes |
| 7 | **Rotation + artifact purge** | Security / ops | `docs/audit/ROTATION_RUNBOOK.md` ticks complete; **only after rotation**, purge old source zip exposure via **redeploy** (not manual GCS delete) and review `gcf-artifacts` image dates per `docs/audit/ENV_BAK_EXPOSURE.md` |
| 8 | **Stale cohort redeploy** | Release manager | Decision vs traffic: `docs/audit/DEPLOY_HASH_COHORT.md` — env-only STALE_REF refresh **vs** hotfix cohort; proof = traffic metrics + chosen tier list |

**App store / client release** should not ship before **Gates 1–3** minimum (registration rollback + deploy hygiene). Gate 4 strongly recommended if login UX depends on G1 fields.

**Worktree redeploys:** Any redeploy from an old commit must copy current `firebase.json` `functions.ignore` block and run Gate 2 first (`docs/audit/ROTATION_RUNBOOK.md`).
