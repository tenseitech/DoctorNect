# Pre-publish status — DoctorNect (working tree)

**Date:** 2026-11-07  
**Source rating (audit doc):** `DOCTORNECT_FULL_AUDIT.md` — **Overall 6.5 / 10** (“READY WITH CONDITIONS”).  
**After this pass:** **7.2 / 10** — Firestore release inventory + CI grep; `FirestoreService` / `FirestoreClient` central gates; executable **000017/000018**; S3 lab-report key match; ambulance copy/FCM/deep-link gates; lab RPC `p_report_storage_key` (no PostgREST key patch).

**Prior pass:** ENV-01 restored; backend **495+ pass**; `flutter analyze` clean; full JSON suite **749 passed** (see `summarize_flutter_json_reporter.js`).

---

## What improved vs previous audit snapshot

| Item | Notes |
|------|--------|
| ENV-01 | `AMBULANCE_ENABLED` added to `frontend/.env.example` so `node scripts/check_env_parity.js` is green. Breaking commit was `97beabf` (Flutter referenced `AMBULANCE_ENABLED` without documenting it). |
| Backend tests | `backend/functions`: **495** pass (was 494/1 when ENV was undocumented). |
| Debug hooks | `debugPatientFirestoreRefresh`, `debugDoctorFirestoreRefresh`, `ProfileCompletionService.debugFirestoreOverride`, `InAppNotificationSupabaseRepository.debugMarkReadOverride` use `@visibleForTesting`, release-mode assertions, and `debugForceReleaseMode` tests (`frontend/test/debug_hooks_release_guard_test.dart`). |
| Firestore guard | `FirestoreReadHelper` and `ProfileCompletionService._effectiveFirestore()` call `FirestoreForbiddenGuard` so default `FIRESTORE_FORBIDDEN=true` does not silently hit `FirebaseFirestore.instance` in tests/production. |
| Ambulance push | `AmbulancePushService` no-ops when `AmbulanceEnabled.isOn` is false (release default). |
| Proposed SQL | `000017` full `CREATE OR REPLACE` RPC bodies; `000018` report-key triggers; staging probe SQL files under `scripts/audit/`. |
| Firestore reachability | `docs/audit/FIRESTORE_REACHABLE_RELEASE.md` + `npm run audit:firestore-reachability`. |
| FCM / ambulance UX | Default channel `doctornect_default`; welcome/deep-link ambulance gated on `AmbulanceEnabled`. |

---

## Remaining issues (severity + verify)

1. **High — Residual Firestore call sites (gated, not all migrated)**  
   - **Risk:** `FirestoreService` / `FirestoreClient` throw `StateError` when `FIRESTORE_FORBIDDEN=true`; screens that still call Firestore without Supabase fallback need UI error handling (see `FIRESTORE_REACHABLE_RELEASE.md`).  
   - **Fix:** Finish Supabase-primary paths for doctor profile/community catalogs; wrap remaining feature calls with user-visible errors.  
   - **Verify:** `npm run audit:firestore-reachability`; release smoke doctor/patient/lab/pharmacy.

2. **High — `DEPLOY_ORDER` / staging parity**  
   - **Risk:** Proposed files in `db/proposed/` are not applied until owner runs them on staging/RDS.  
   - **Fix:** Apply `000014` → `000015` → `000016` (in-app only) in order on staging; keep ambulance “later” file until product enables ambulance.  
   - **Verify:** `scripts/audit/rls_staging_verified_role_matrix.sql` (non-destructive rollback probe).

3. **Medium — Apply proposed SQL on staging/RDS**  
   - **Risk:** `000014`–`000018` not live → client RPC/RLS assumptions fail in prod.  
   - **Fix:** Follow `docs/audit/DEPLOY_ORDER.md`.  
   - **Verify:** `rls_staging_verified_role_matrix.sql` + new probe files.

4. **Low — JSON test reporter file encoding**  
   - **Risk:** PowerShell `Tee-Object` writes UTF-16; `count_json_tests.js` expects UTF-8 JSON lines.  
   - **Fix:** Use `Out-File -Encoding utf8` or `summarize_flutter_json_reporter.js` (handles BOM).  
   - **Verify:** Run summarizer on CI artifact.

---

## Owner manual checklist

1. **Firestore rules:** Deploy deny-all rules; run a release build against staging Firebase project; confirm no client path throws outside tests.  
2. **SQL:** Apply `db/proposed/` to **staging** first → validate with `rls_staging_verified_role_matrix.sql` → promote to **RDS** with migration runner + backup.  
3. **Docker integration tests:** `docs/audit/DOCKER_RUN.md` / Supabase local stack for RPC/regression.  
4. **Play Console:** Reviewer account, OTP allowlist docs (`docs/audit/PLAY_REVIEWER_SERVER_OTP.md` if present), Data safety form, production signing.  
5. **Env / secrets:** Reconcile `backend/functions/.env.example` and `frontend/.env.example` with prod secret manager; rotate if any example ever leaked.  

---

## Verification commands (re-run before tag)

```bash
node scripts/check_env_parity.js
cd backend/functions && npm test
cd frontend && flutter analyze
cd frontend && flutter test --reporter json | Tee-Object flutter_test_json.ndjson
node frontend/tools/summarize_flutter_json_reporter.js frontend/flutter_test_json.ndjson
```

---

## Test name diff (`compare_worktree_test_names.js 97beabf^ HEAD`)

- **Removed:** `patient_refresh_firestore_test.dart` (2 tests), renamed merge test string.  
- **Added:** `debug_hooks_release_guard_test.dart` (4 tests), merged appointment refresh coverage into `firestore_removal_supabase_and_ambulance_test.dart` (+3).  
- **Net:** +4 named tests vs `97beabf^` per script JSON.
