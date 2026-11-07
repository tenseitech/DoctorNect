# Pre-publish status — DoctorNect (HEAD)

**Date:** 2026-11-07  
**Baseline audit:** `DOCTORNECT_FULL_AUDIT.md` — **6.5 / 10**.  
**After this pass:** **6.6 / 10** — tests green; SQL/staging probes improved; Firestore **LIVE_AND_THROWS** rows remain in doctor/patient/lab/pharmacy features (see `FIRESTORE_REACHABLE_RELEASE.md`). Rating held below 7.0 until those rows are migrated or wrapped with `FirestoreUi` at screen boundaries.

---

## Verification (HEAD)

| Suite | Result |
|-------|--------|
| `flutter test --reporter json` + summarizer | **755 passed, 0 failed** |
| `backend/functions` `npm test` | **496 pass, 0 fail, 22 skip** (518 tests) |
| `flutter analyze` | **No issues found** |
| `npm run audit:firestore-reachability` | exit 0 |

---

## Per-area justification

| Area | Status | Why not higher |
|------|--------|----------------|
| Tests | ✅ | Full Flutter + backend green; `flutter_test_config.dart` enables Firestore fakes without changing `FIRESTORE_FORBIDDEN` default |
| SQL proposed 000014–000018 | 🟡 | Executable RPCs + staging probes; **not applied** on staging/RDS yet |
| Firestore release | 🔴 | **LIVE_AND_THROWS** call sites still reachable; `FirestoreUi` helper added, not wired on every screen |
| Ambulance / FCM | ✅ | Default channel `doctornect_default`; copy gated |
| Lab report keys | ✅ | RPC-only key path; S3 download validation; 000018 trigger |

---

## Remaining issues

1. **High — LIVE_AND_THROWS Firestore rows** (`docs/audit/FIRESTORE_REACHABLE_RELEASE.md`)  
   - Wrap feature entry points with `FirestoreUi.guardSync` / `guardAsync` or migrate to Supabase.  
   - Run `test/release_firestore_forbidden_smoke_test.dart` in CI with `debugForceReleaseMode`.

2. **High — Apply proposed SQL on staging** (`DEPLOY_ORDER.md` order 000014→000018).

3. **Medium — Admin routes** (`promoted_ad_review_screen.dart`) still LIVE if super-admin opens them.

4. **Low — JSON reporter encoding** — use UTF-8 `Out-File` or summarizer on CI artifacts.

---

## Commands

```bash
node scripts/check_env_parity.js
cd backend/functions && npm test
cd frontend && flutter analyze
cd frontend && flutter test --reporter json 2>&1 | Out-File -Encoding utf8 flutter_test_full.ndjson
node frontend/tools/summarize_flutter_json_reporter.js flutter_test_full.ndjson
npm run audit:firestore-reachability
```
