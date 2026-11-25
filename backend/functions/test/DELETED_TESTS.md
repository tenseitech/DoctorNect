# Removed test files and their Postgres-path replacements

Firestore was removed from the backend (commit 7824a2a). A test file was deleted only when it
exercised Firestore-only behaviour (security rules, Firestore triggers, Firestore<->Postgres
sync bridges, emulator flows). Each row says what the file covered and where the same
guarantee is now tested.

| Deleted file | What it covered | Replacement coverage |
|---|---|---|
| `otp_retry_fallback.test.js` | MSG91 send retry when a Firestore OTP challenge existed; "never touch Redis when mirror off" | `otp_send_policy.test.js` (cooldown, resend issues a new code, SMS failure deletes the challenge, templates, TTL, HMAC key in prod, timeout) |
| `doctor_slots.test.js`, `doctor_slots_emulator.test.js` | Slot booking / reschedule / cancel via Firestore transactions + slot reconciliation trigger | `db/tests/` SQL tests for `book_appointment_atomic` / `reschedule_appointment_atomic` / cancel (no double booking, cannot book or move another patient's slot); gateway allowlist tests in `services/api-gateway/test` |
| `promoted_ads_verification.test.js` | `verifyRazorpayPayment` + webhook activation on the Firestore ledger | `promoted_ads_verify_postgres.test.js` (signature, owner, order binding, notes binding, amount/currency, replay idempotency, payment re-use), `security_audit_2026_11_fixes.test.js` (server pricing, compare-and-set activation), `razorpay_webhook_security.test.js` (Postgres webhook replay / out-of-order / tamper) |
| `ambulance_sync.test.js` | Firestore -> Postgres ambulance mirror incl. rating aggregation | `submit_ambulance_rating.test.js` (callable -> RPC, single use, booker only, completed only) + `db/tests` SQL test for `submit_ambulance_rating` |
| `cross_role_sync.test.js`, `doctor_sync.test.js`, `pharmacy_lab_sync.test.js`, `review_public_sync.test.js`, `sync_to_firestore*.test.js`, `supabase_sync_gate.test.js`, `lib/cross_role_sync_bridge.js` | Firestore <-> Postgres dual-write sync bridges | No longer exists (single Postgres source of truth). Cross-provider access is enforced by RLS: `db/tests` + `scripts/db/rls_coverage_audit.js` |
| `client_payload_replay.rules.test.js`, `client_read_replay.rules.test.js`, `profile_claims_rules.test.js`, `firestore_reviews.rules.test.js`, `firestore_rules_regex.test.js`, `sync_dead_letters.rules.test.js` | Firestore security rules | Rules file removed. Equivalent table authz: RLS policies + gateway allowlists (`services/api-gateway/test`, `db/tests`) |
| `firestore_s3_rules.test.js`, `storage_doctor_kyc.rules.test.js`, `storage_live_app_paths.rules.test.js`, `storage_provider_kyc.rules.test.js` | Firebase Storage / Firestore-backed S3 authz rules | `s3_storage.test.js` (60 tests, Postgres ownership), `s3_plane_prefix.test.js`, `security_audit_2026_11_fixes.test.js` |
| `firestore_forbidden_runtime.test.js`, `production_legacy_firestore_guard.test.js` | Runtime guard that Firestore is not used in production | Firestore SDK no longer imported; `delete_my_account_supabase.test.js` runs with `FIRESTORE_FORBIDDEN=1`, `supabase_webhook_idempotency.test.js` asserts the Firestore modules are gone |
