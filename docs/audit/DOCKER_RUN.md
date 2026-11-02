# Docker-gated backend tests (local only)

Prerequisites: **Docker Desktop running**, Supabase local stack on port **54322** (see `backend/supabase/config.toml`).

## 1. Start local Postgres (Supabase)

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor\backend
npx -y supabase start
```

Confirm DB URL (default):

```text
postgres://postgres:postgres@127.0.0.1:54322/postgres
```

Optional override:

```powershell
$env:LOCAL_DOCKER_PG_URL = "postgres://postgres:postgres@127.0.0.1:54322/postgres"
```

Apply migrations if the DB is fresh:

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor\backend
npx -y supabase db reset
```

## 2. Four Docker-gated integration tests

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor\backend\functions
npm ci
$env:LOCAL_DOCKER_PG_URL = "postgres://postgres:postgres@127.0.0.1:54322/postgres"
node --require ./test/setup_env.js --test `
  test/delete_account_schema_reflection.test.js `
  test/delete_my_account_docker_integration.test.js `
  test/razorpay_webhook_security.test.js `
  test/s3_supabase_docker_integration.test.js
```

Each file skips with `Local Docker Postgres unreachable on 127.0.0.1:54322` when Docker is down.

## 3. Registration orphan rollback tests (no Docker)

Uses in-memory Firestore mocks and legacy doctor/patient mode — **default `npm test`**, no Postgres:

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor\backend\functions
node --require ./test/setup_env.js --test test/registration_orphan_rollback.test.js
```

## 4. `pg_policies` diff (DELETE on profile tables)

Inspect DELETE policies on `users`, `patients`, and `doctors` after migrations:

```powershell
$env:PGPASSWORD = "postgres"
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "
SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('users', 'patients', 'doctors')
  AND cmd = 'DELETE'
ORDER BY tablename, policyname;
"
```

Expected at consolidated RLS (`db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql`):

| tablename | policyname | qual (summary) |
|-----------|------------|----------------|
| `users` | `users_delete_admin` | `private.is_super_admin()` |
| `patients` | `patients_delete_admin` | `private.is_super_admin()` |
| `doctors` | `doctors_delete_admin` | `private.is_super_admin()` |

No owner-self DELETE policy for these tables — client-side `.delete()` from the Flutter Supabase client (authenticated role) does not pass RLS.

Full catalog parity (optional, needs second DB URL):

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor
node scripts/db/schema_diff.js
```

(See script env vars in `scripts/lib/env_loader.js`; not run as part of default CI.)
