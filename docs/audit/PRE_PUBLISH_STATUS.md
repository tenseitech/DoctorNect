# Pre-publish status — DoctorNect (working tree)

**Date:** 2026-11-06  
**Source rating (audit doc):** `DOCTORNECT_FULL_AUDIT.md` — **Overall 6.5 / 10** (“READY WITH CONDITIONS”).  
**This pass:** ENV-01 restored (document `AMBULANCE_ENABLED`); backend **495 pass / 0 fail / 22 skip**; `flutter analyze` **0 issues**; full `flutter test --reporter json` **749 passed / 0 failed** (652 visible `testDone` + 97 hidden loaders per `frontend/tools/summarize_flutter_json_reporter.js` on the Tee’d NDJSON file).

---

## What improved vs previous audit snapshot

| Item | Notes |
|------|--------|
| ENV-01 | `AMBULANCE_ENABLED` added to `frontend/.env.example` so `node scripts/check_env_parity.js` is green. Breaking commit was `97beabf` (Flutter referenced `AMBULANCE_ENABLED` without documenting it). |
| Backend tests | `backend/functions`: **495** pass (was 494/1 when ENV was undocumented). |
| Debug hooks | `debugPatientFirestoreRefresh`, `debugDoctorFirestoreRefresh`, `ProfileCompletionService.debugFirestoreOverride`, `InAppNotificationSupabaseRepository.debugMarkReadOverride` use `@visibleForTesting`, release-mode assertions, and `debugForceReleaseMode` tests (`frontend/test/debug_hooks_release_guard_test.dart`). |
| Firestore guard | `FirestoreReadHelper` and `ProfileCompletionService._effectiveFirestore()` call `FirestoreForbiddenGuard` so default `FIRESTORE_FORBIDDEN=true` does not silently hit `FirebaseFirestore.instance` in tests/production. |
| Ambulance push | `AmbulancePushService` no-ops when `AmbulanceEnabled.isOn` is false (release default). |
| Proposed SQL | `000015` uses `starts_with` + path traversal/control char rejects; `000016` split (notifications vs `db/proposed/later/` ambulance); `000017` documents RPC verified-check alignment with `000014`. |

---

## Remaining issues (severity + verify)

1. **High — Residual Firestore in `frontend/lib`**  
   - **Risk:** Many files still import `cloud_firestore`; under deny-all rules, user-visible failures persist on unmigrated paths (see `docs/audit/FIRESTORE_FINAL_STATE.md`).  
   - **Fix:** Continue module-by-module migration to Supabase or gate behind `FirestoreForbiddenGuard.assertNotForbidden` / feature flags; remove dead Firestore branches.  
   - **Verify:** Release build with `FIRESTORE_FORBIDDEN=true`; exercise doctor/patient/lab/pharmacy flows; expect no unhandled `permission-denied`.

2. **High — `DEPLOY_ORDER` / staging parity**  
   - **Risk:** Proposed files in `db/proposed/` are not applied until owner runs them on staging/RDS.  
   - **Fix:** Apply `000014` → `000015` → `000016` (in-app only) in order on staging; keep ambulance “later” file until product enables ambulance.  
   - **Verify:** `scripts/audit/rls_staging_verified_role_matrix.sql` (non-destructive rollback probe).

3. **Medium — Android default FCM channel id `ambulance_requests`**  
   - **Risk:** Naming suggests ambulance-only; still declared when ambulance feature is off.  
   - **Fix:** Rename to a generic default channel or gate meta-data in Gradle manifest merges.  
   - **Verify:** Install release APK with `AMBULANCE_ENABLED=false`; notification channels list.

4. **Medium — Welcome copy still lists ambulance**  
   - **Risk:** Marketing strings reference ambulances while role tile is hidden (`welcome_screen.dart`).  
   - **Fix:** Parameterize copy from `AmbulanceEnabled.isOn` or neutral wording.  
   - **Verify:** Screenshot diff for release build.

5. **Low — JSON test reporter file encoding**  
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
