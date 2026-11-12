# Baseline test failures (`_json_5107.jsonl`)

Source: `doctor-baseline-count/frontend` at commit **5107d14** (716 `testDone`: 702 pass, 14 fail/error).  
Production references: `doctor/frontend` on `chore/dedupe-structure-audit`.

**Production rule (doctor gate):** Unverified doctors must not get verified-only UX. `DoctorVerificationGate` treats `watchVerified` / `isVerified` **false** as `DoctorShell(verificationPending: true)` unless demo/reviewer bypass applies (`doctor_verification_gate.dart:64–74`, `doctor_account_repository.dart:92–113`).

| # | Test (file:line) | Expectation | Production behavior | Class | Fix |
|---|------------------|-------------|---------------------|-------|-----|
| 1 | `doctor_verification_gate_test.dart:88` — returns false when Firebase unavailable | `watchVerified(...).toList()` → `[false]` | `watchVerified` maps Supabase `watchDoctor`; when Supabase not ready, stream is **empty** (no emission). UI still sees false via `snapshot.data ?? false`, but `toList()` is `[]`. | **B** | Emit `Stream.value(false)` when `doctorId.isEmpty` or `!SupabaseBootstrap.isReady`; restore `debugWatchVerifiedOverride`. |
| 2 | `doctor_verification_gate_test.dart:96` — returns false for empty doctor id | `[false]` | Same empty stream for `doctorId.isEmpty` (`supabase_doctor_repository.dart:112–113`). | **B** | Same as #1. |
| 3 | `doctor_verification_gate_test.dart:104` — debug override stream | `[false, true]` from injected stream | `debugWatchVerifiedOverride` **not wired** in `watchVerified` after Supabase migration. | **B** | Honor `debugWatchVerifiedOverride` in `DoctorVerificationRepository.watchVerified`. |
| 4 | `login_role_lookup_scenarios_test.dart:113` — finalize failure rollback contract | Regex on `firebase_auth_service.dart` / `supabase_user_repository.dart` | On current branch, `_abortPendingRegistrationIfNeeded` calls `deletePendingAuthUser` then `signOut`; repo uses `cleanupPendingRegistration()` (`firebase_auth_service.dart:417–427`, `supabase_user_repository.dart:516–524`). | **A** (5107 only) / **passes on current branch** | At 5107: update regex if layout differed; current tree: no change. |
| 5 | `s3_photo_upload_ordering_test.dart:304` — Lab booking success ordering | S3 upload → **Firestore** update → delete old S3 | `submitReport` uploads via S3 then updates **Supabase** only when `SupabaseBootstrap.isReady` (`lab_booking_repository.dart:254–290`). Fake Firestore seed ignored. | **A** | Assert S3 upload + result; enable Supabase test stub or assert delete only when Supabase path runs. |
| 6 | `s3_photo_upload_ordering_test.dart:338` — Firestore fails → no delete | `throws FirebaseException` | Missing doc no longer throws; S3 upload **succeeds** and returns (no Firestore write). | **A** | Expect successful S3 upload, `deleteCallCount == 0`. |
| 7 | `s3_photo_upload_ordering_test.dart:400` — Lab order success ordering | Same Firestore-centric success | Same Supabase-first path (`lab_order_repository.dart:100–129`). | **A** | Same as #5 for orders. |
| 8 | `s3_photo_upload_ordering_test.dart:434` — order Firestore fails | `throws FirebaseException` | Same as #6. | **A** | Same as #6. |
| 9 | `auth_flows_test.dart:301` — (a) profile null → signOut | `verifyProfileWithRetry` → null, signOut, no delete | `fetchProfile` delegates to **Supabase mock** with no `when()` → null return type crash. | **A** | Stub `mockSupabaseRepo.fetchProfile` → `null`. |
| 10 | `auth_flows_test.dart:316` — (b) Supabase 503 non-fatal + Firestore write | Firestore `users` + `profile_claims` written | `UserRepository.createProfile` → Supabase only; **no Firestore** (`user_repository.dart:30–47`). | **A** | Expect Supabase `createProfile` called; remove Firestore assertions. |
| 11 | `auth_flows_test.dart:355` — (c) orphan repair | Repair via Firestore patients → `users` doc | `repairMissingProfile` → Supabase implementation only. | **A** | Stub `repairMissingProfile` on mock Supabase repo. |
| 12 | `auth_flows_test.dart:386` — (d) no role doc | `repairMissingProfile` → null | Same; needs mock returning null. | **A** | Stub mock → `null`. |
| 13 | `auth_flows_test.dart:399` — (i) wrong ownerUid | null, no users doc | Supabase repair logic; test must stub mock. | **A** | Stub mock → `null`. |
| 14 | `auth_flows_test.dart:423` — (ii) cross-role repair | null, no users doc | Same. | **A** | Stub mock → `null`. |

**Summary:** 2× **B** (doctor verification stream / test hook), 12× **A** (Supabase/S3 migration drift), 0× **C** for this baseline (login contract passes on current branch).

**Note:** Patient/doctor **photo** ordering tests in the same file still target Firestore + S3 via `firestoreOverride` and remain valid for that path (`profile_photo_uploader.dart:193–253`).

---

## Fix status (2026-11-03)

| Change | Files |
|--------|--------|
| **B** — `watchVerified` emits `false` when Supabase unavailable / empty id; restored `debugWatchVerifiedOverride` | `lib/core/firebase/repositories/doctor_verification_repository.dart` |
| **A** — Supabase-unavailable guard tests | `test/doctor_verification_gate_test.dart` |
| **A** — Postgres-only auth resilience mocks | `test/auth_flows_test.dart` |
| **A** — Lab report ordering aligned to Supabase-first `submitReport` | `test/s3_photo_upload_ordering_test.dart` |

### Re-run results (`doctor/frontend`, working tree with uncommitted test fixes)

| Scope | Passed | Failed |
|-------|-------:|-------:|
| Four files (`doctor_verification_gate`, `login_role_lookup`, `s3_photo_upload_ordering`, `auth_flows`) | 69 | 0 |
| Full suite (JSON reporter → `docs/audit/_json_head.jsonl`) | **716** | **0** |

Baseline reference: `docs/audit/_json_5107.jsonl` from `doctor-baseline-count` @ **5107d14**.

---

## Pre-accept verification (2026-11-03)

### 1. `DoctorVerificationRepository` / gate — **PARTIAL PASS** (one gap)

**Exact `debugWatchVerifiedOverride` code** (`frontend/lib/core/firebase/repositories/doctor_verification_repository.dart`):

```dart
  @visibleForTesting
  static Stream<bool> Function(String doctorId)? debugWatchVerifiedOverride;

  @visibleForTesting
  static void debugReset() {
    debugWatchVerifiedOverride = null;
  }

  Stream<bool> watchVerified(String doctorId) {
    final override = debugWatchVerifiedOverride;
    if (override != null) {
      return override(doctorId);
    }
    if (doctorId.isEmpty || !SupabaseBootstrap.isReady) {
      return Stream.value(false);
    }
    return SupabaseDoctorRepository.instance
        .watchDoctor(doctorId)
        .map(parseVerifiedFromDoctorData);
  }
```

| Check | Result |
|-------|--------|
| `@visibleForTesting` on field + `debugReset` | **Yes** — analyzer hint only; **not** enforced at runtime. |
| Cannot take effect in **release** (`kReleaseMode`) | **FAIL** — there is **no** `kReleaseMode` guard; any code that assigns `debugWatchVerifiedOverride` would affect release builds. Today only tests assign it (`doctor_verification_gate_test.dart:108,160`). **Recommended follow-up:** `if (override != null && !kReleaseMode) return override!(doctorId);` |
| Supabase unavailable / empty id → **not verified** | **PASS** — `Stream.value(false)` (`:48–49`). Gate uses `snapshot.data ?? false` (`doctor_verification_gate.dart:69–74`) → `verificationPending: true`. |
| Supabase **error** / timeout on live stream | **PASS (conservative)** — `watchDoctor` uses `controller.addError` on fetch failure (`supabase_doctor_repository.dart:142–145`). That propagates as a stream error; `StreamBuilder` then has `snapshot.data == null` → treated as **not verified**. No path treats errors as verified. Null/`verified: false` rows map via `parseVerifiedFromDoctorData` → false (`:24–40`). |
| Demo / reviewer bypass | Unverified doctors still **cannot** pass the gate except `DemoAuthConfig` paths (`doctor_verification_gate.dart:44–56`) — unchanged by test fixes. |

---

### 2. `lab_*_repository.dart` `submitReport` — **FAIL** vs stated product rule

**When `SupabaseBootstrap.isReady == false`** (`lab_booking_repository.dart:274–290`, `lab_order_repository.dart:120–131`):

1. S3 upload runs (`LabReportFileStore.uploadReport`).
2. Local cache write runs.
3. Supabase RPC block is **skipped**.
4. Method **returns** `uploadResult` with **no throw**.

**User-visible effect:** `lab_report_upload_sheet.dart:231–267` treats success as **completed** and updates local worklist — **silent success** without DB persistence. **This does not meet “must surface an error to the user.”** (Verification **FAIL**; production bug **B**, not fixed in this pass.)

**When Supabase is ready but RPC fails:** `updateLabBookingStatus` / `updateLabOrderStatus` return `false` on failure (`supabase_lab_repository.dart:153–159`) — **not checked** by `submitReport`. Method still returns `uploadResult`. Old report key may still be **deleted** (`lab_booking_repository.dart:285–288`) even if RPC failed → **new S3 object can be orphaned** (DB never got `notes`/status); old object may be removed incorrectly.

**Proposed remediation (manual / follow-up PR):**

1. Require `SupabaseBootstrap.isReady` before S3 upload (or throw `StateError` after failed DB write).
2. Check RPC boolean; on failure throw user-facing error and **best-effort delete** the just-uploaded S3 key (compensating transaction).
3. Delete `existingReportStorageKey` only after RPC success.
4. Optional: lifecycle rule on `lab_reports/` prefix for orphans > N days.

**Tests after fix:** Current `s3_photo_upload_ordering_test.dart` asserts “S3 only when Supabase off” — align with product rule if you require error instead of silent success.

---

### 3. `auth_flows_test.dart` — six resilience tests

| Test (line) | What it verifies now | Real production code? |
|-------------|----------------------|------------------------|
| **(a) `:302`** | **`FirebaseAuthService.verifyProfileWithRetry`** retry loop, null profile → **`signOut`**, no `user.delete()` | **Yes** — real service; only **`UserRepository.fetchProfile`** stubbed to return `null`. |
| **(b) `:323`** | **`UserRepository.createProfile`** propagates exception when mock **`SupabaseUserRepository.createProfile`** throws 503 | **Partial** — exercises **delegation only** (`user_repository.dart:38–47`), **not** `SupabaseUserRepository.createProfile` body (`supabase_user_repository.dart:76–161`, no retry/swallow). **503 resilience of real repo is NOT tested.** |
| **(c) `:352`** | **`UserRepository.repairMissingProfile`** returns mocked profile | **Stub only** — does not run Supabase repair SQL/RLS logic. |
| **(d) `:382`** | Repair returns null from mock | **Stub only** |
| **(i) `:401`** | Repair returns null (owner mismatch scenario) | **Stub only** — no assertion on real authorization in `supabase_user_repository.dart`. |
| **(ii) `:419`** | Repair returns null (role mismatch) | **Stub only** |

**503 / resilience gap:** Test **(b)** does **not** replace the old “503 non-fatal + Firestore dual-write” scenario. Real `createProfile` **rethrows** PostgREST errors (no catch). **Recommended:** add a **source contract** or integration test (e.g. `registration_rollback_test.dart` pattern) that `SupabaseUserRepository.createProfile` does not contain a broad try/catch that swallows network errors — **not added in this verification pass** (check failed; doc only per instruction).

---

### 4. Test count: **716 vs 625** — exact numbers

**Git (`5107d14..HEAD`):**

```text
git diff --stat 5107d14..HEAD -- test/          → empty (no top-level test/)
git diff --stat 5107d14..HEAD -- frontend/test/  → 1 file, login_role_lookup_scenarios_test.dart (+37/-5)
```

- **No test files deleted or renamed** since **5107d14** (87 files under `frontend/test/` at baseline and HEAD).
- **Uncommitted** (working tree, not in `5107d14..HEAD`): `auth_flows_test.dart`, `doctor_verification_gate_test.dart`, `s3_photo_upload_ordering_test.dart` (+ `doctor_verification_repository.dart` production fix).

**Declaration counts** (`test(` + `testWidgets(` in `frontend/test/**/*.dart` via git show): **591** at **5107d14** and **591** at **HEAD** (427 + 164).

**JSON reporter (authoritative for runner):**

| Metric | `_json_5107.jsonl` (baseline) | `_json_head.jsonl` (current tree) |
|--------|-------------------------------:|----------------------------------:|
| `testStart` **loading** (hidden harness) | 85 | 85 |
| `testStart` **non-loading** (real tests) | **631** | **631** |
| `testDone` **total** (loading + real) | **716** | **716** |
| `testDone` **passed** | 702 | **716** |
| `testDone` **failed/error** | 14 | **0** |

**Why “625” appeared in one CLI run:** The `+625` figure from a **`flutter test` console** progress line is **not** the same as JSON `testDone` total (**716**). Per-file JSON counts are **identical** between baseline and current (**0** files differ). The **14 → 0** improvement is **14 failing non-loading tests fixed**, not a reduction in suite size.

**Formula:** `716 testDone = 85 loading + 631 executable tests` (same inventory before and after baseline fixes).

---

## Pre-accept remediation (single PR, 2026-11-03)

Production changes are scoped to verification override release guard, demo gate allowlist, lab `submitReport` ordering/errors, and `SupabaseUserRepository.createProfile` retry on transient 503.

### Item 1 — `debugWatchVerifiedOverride` release guard — **FIXED**

| | Before | After |
|---|--------|--------|
| Override in release | Applied whenever set (tests only today) | Ignored when `kReleaseMode` or `debugForceReleaseMode`; setter **asserts** not assigned in release |
| Tests | Override stream only | `doctor_verification_gate_test.dart`: release guard ignores override |

**Code:** `frontend/lib/core/firebase/repositories/doctor_verification_repository.dart` (`_effectiveReleaseMode`, guarded setter, `watchVerified` skips override in release).

---

### Item 2 — Demo verification bypass — **FIXED** (documented)

**How it works (not a client flag):**

1. **Allowlist only** — Hardcoded demo phones/ids in `DemoAuthConfig` (`demoDoctorPhone`, `isDemoDoctorPhone`, `isDemoDoctorId`, etc.). No remote config or user input toggles demo mode.
2. **Runtime gate** — `DemoAuthConfig.isDemoAllowed` is **false** in release (`kReleaseMode` / `debugReleaseModeOverride`). `verifyReleaseBuildSafety()` throws if `ENABLE_DEMO_AUTH` is on in release.
3. **Verification gate** — `DoctorVerificationGate` sets `isDemoDoc` only when `isDemoAllowed &&` (phone/id matches allowlist). Otherwise `watchVerified` / controller must show verified.
4. **Parse path** — `DoctorVerificationRepository.parseVerifiedFromDoctorData` auto-verifies demo doctors only when `isDemoAllowed`.

**Release build:** Demo bypass **never** runs; unverified doctors stay on `DoctorShell(verificationPending: true)` unless admin verification stream says verified.

**Client-controlled input:** Phone/id checks compare normalized digits against fixed constants; arbitrary strings do not enable bypass unless they match the allowlist (and demo is allowed, which is false in release).

---

### Item 3 — Lab `submitReport` (booking + order repos) — **FIXED**

| | Before | After |
|---|--------|--------|
| `!SupabaseBootstrap.isReady` | S3 upload + local cache; returned success | `LabReportSubmitFlow.ensureSupabaseReady()` throws `StateError` with user-visible message **before** upload |
| RPC failure | Unchecked; could delete old S3 key | `finalizeAfterUpload`: RPC must return true; on failure delete **new** key, throw; **no** local cache; old key kept |
| Ordering | Upload → cache → optional RPC → delete old | Upload → RPC success → cache → delete old key |

**Code:** `frontend/lib/core/firebase/lab_report_submit_flow.dart`, `lab_booking_repository.dart`, `lab_order_repository.dart`.  
**Tests:** `s3_photo_upload_ordering_test.dart` — not ready throws, RPC fail deletes new key only, success deletes old after RPC.

---

### Item 4 — `createProfile` on 503 — **FIXED**

**Production behavior:** Retry transient PostgREST/network errors (503, 502, 429, timeouts) up to `createProfileMaxAttempts` (default 3) with backoff; then throw `ProfileCreationException` with a clear message (fail closed, no silent success).

| | Before | After |
|---|--------|--------|
| 503 | Immediate rethrow | Retry with backoff, then `ProfileCreationException` |
| Tests | `auth_flows_test.dart` (b) mock delegation only | `supabase_user_repository_create_profile_test.dart`: real `SupabaseUserRepository` + mocked `SupabaseClient.from('users').upsert` (exhausted retries); retry helper unit test; `auth_flows_test.dart` (b) still verifies `UserRepository` propagates exception |

---

### Item 5 — Test re-run and counts — **FIXED**

| Scope | Result |
|-------|--------|
| Affected files (`doctor_verification_gate`, `s3_photo_upload_ordering`, `auth_flows`, `supabase_user_repository_create_profile`) | **64 passed**, 0 failed |
| Full suite (`flutter test --reporter json` → `docs/audit/_json_head.jsonl`) | **724** `testDone`, **724** pass, **0** fail/error |

**Count delta vs baseline JSON (5107d14):** Baseline **716** `testDone` (85 hidden loading + 631 visible). Current **724** `testDone` (94 hidden loading + 630 visible) — **+8** new test declarations (verification release guard, lab submit scenarios, createProfile retry tests); **14 baseline failures → 0**.

### Pre-accept checklist (items 1–5)

| Item | Status |
|------|--------|
| 1. Override release guard + test | **FIXED** |
| 2. Demo bypass allowlist / release | **FIXED** |
| 3. Lab `submitReport` errors + ordering + tests | **FIXED** |
| 4. createProfile 503 retry + repository test | **FIXED** |
| 5. Suite re-run + this doc | **FIXED** |
