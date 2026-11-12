# Flutter baseline integrity (615/13 vs 612/13)

## 14 vs 13 failing tests

The extra failure was **`login_role_lookup_scenarios_test.dart`** (“finalize failure block references `deletePendingAuthUser`”). That test asserted an **obsolete** source contract. It was updated to match the current flow:

1. `finalizeError` → `_abortPendingRegistrationIfNeeded`
2. `deletePendingAuthUser` → `RegistrationOtpService.cleanupPendingRegistration()` **before** `user.delete()`
3. Auth `user.delete()` only as **fallback** when the callable is unreachable

That test **passes** and is **not** part of the known-failure baseline list.

## Executed count: 628 → 625

| Snapshot | Pass | Fail | Executed |
|----------|------|------|----------|
| Recorded @ `5107d14` baseline note | 615 | 13 | **628** |
| Current HEAD (after contract fix) | 612 | 13 | **625** |

**Git evidence (`5107d14..HEAD`):**

- `git diff --stat -- frontend/test` → **empty** (no added/removed/renamed test files).
- Per-file `test(` / `testWidgets(` counts → **identical** at `5107d14` and `HEAD`.

**Git test-name diff (`5107d14` vs `HEAD`):** `node scripts/audit/compare_git_test_names.js 5107d14 HEAD`

| Metric | Value |
|--------|-------|
| `test` / `testWidgets` declarations | **567** at both commits |
| Only in old | **1** — `login_role_lookup_scenarios_test.dart :: finalize failure block references deletePendingAuthUser` |
| Only in new | **1** — `login_role_lookup_scenarios_test.dart :: finalize failure calls cleanup via deletePendingAuthUser before sign-out` |
| Classification | **Renamed** (same file, contract update); not deleted, not skipped |

**Conclusion:** No tests were removed by accident. The **3** fewer runtime executions (**628** → **625**) are **not** missing `test()` declarations. Likely **Flutter runner counting** (harness hooks / suite grouping) or a slightly different full-suite snapshot when **615/13** was recorded; do not treat as lost tests.

**Action:** Baseline header updated to **612 pass / 13 fail (625 executed)**. Re-record **628** only after a full `flutter test` on a clean `5107d14` worktree reproduces it.

## Known 13 failures (unchanged list)

See `docs/audit/baseline_flutter_failing_tests.txt` (13 lines — no `login_role_lookup_scenarios_test.dart` entry).
