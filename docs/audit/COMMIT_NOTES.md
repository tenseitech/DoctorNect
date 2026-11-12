# Commit notes (audit only — no history rewrite)

Documenting commits that do not match their messages or intended scope. **Do not** amend, rebase, or otherwise rewrite these commits.

## `8342580`

- **Message intent:** Implies server-side registration rollback / orphan Auth cleanup.
- **Actual contents:** **Docs-only** — deploy/env/baseline updates under `docs/audit/` (and related audit artifacts). **No** `backend/functions/registration_otp.js` or runtime code in this commit.
- **Where rollback lives:** Server orphan handling is in **`a947d81`** (`maybeDeleteOrphanRegistrationAuthUser` in `finalizePatientOtpVerification`) and follow-up work on this branch (fresh orphan **profile row** compensation).

## `a947d81`

- **Message intent:** Single focused change (typical for one concern).
- **Actual contents:** **Mixed scope** — should have been split:
  - **Backend:** `backend/functions/registration_otp.js` — `maybeDeleteOrphanRegistrationAuthUser`, `authUserHasPersistedProfile`, wired in `finalizePatientOtpVerification` catch.
  - **Backend tests:** `backend/functions/test/registration_orphan_rollback.test.js`.
  - **Frontend tests:** `frontend/test/registration_rollback_test.dart`.
  - **Frontend tests (minor):** `frontend/test/login_role_lookup_scenarios_test.dart` (rollback wiring assertion).
- **Follow-up on branch:** Orphan **Supabase/Firestore profile row** delete (same 10-minute / unverified guards) so registration retry after finalize failure does not hit duplicate mobile/email.
