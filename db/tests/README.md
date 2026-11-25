# SQL tests

`npm run test:db` (repo root, Docker running) starts throwaway `postgres:17` (Supabase staging
parity) and `postgres:18` (RDS production parity) containers on 127.0.0.1:5541/5542, then:

1. applies `db/rds_bootstrap/01-03` (roles: anon, authenticated, service_role, authenticator; auth shim),
2. replays every migration in `db/migrations` (+ `db/migrations/rds`, RDS overrides) in order,
3. applies `db/rds_bootstrap/04_rds_runtime_grants.sql` (post-migrate, as on RDS cutover),
4. re-applies every migration dated >= 20261124 to prove it is idempotent,
5. runs each `db/tests/NN_*.sql` in its own transaction (rolled back) with `00_helpers.sql`,
6. runs `scripts/db/rls_coverage_audit.js` and `scripts/db/grant_matrix_audit.js`.

Options: `--only=17|18`, `--keep` (leave containers up), `--no-audits`.
Without Docker: `SQL_TEST_DB_URLS=postgresql://postgres:pw@127.0.0.1:5541/postgres npm run test:db`.
The runner refuses any non-loopback host.

| File | Covers |
|---|---|
| 10_promoted_ads_payment_guard | 20261124000001 + 20261125000001: owner cannot set status / payment_status / razorpay_* / amount_paid, cannot edit paid or live ads, can create and edit drafts; ledgers server-only |
| 20_prescriptions_care_relationship | 20261124000002: no insert without care relationship, insert with one, no deletes, no re-targeting, `create_prescription_atomic` still works |
| 30_submit_ambulance_rating | 20261124000003: one rating per completed trip, second call rejected and aggregates unchanged, client roles cannot EXECUTE |
| 40_appointment_booking | `book_appointment_atomic` / `reschedule_appointment_atomic` / cancel: no double booking, capacity 3, cannot book or move another patient's slot |
| 50_policy_functions_executable | 20261125000002: every authenticated-readable table evaluates its RLS policies without "permission denied for function" |
