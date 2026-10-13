# Supabase Database Tests

This directory contains SQL test suites for verifying database policies and functions against a local Supabase PostgreSQL database.

## Running Tests

Ensure local Supabase containers are running (`npx supabase start` in `backend/` or Docker Desktop active with container `supabase_db_doctor`).

### 1. Firebase Identity & RLS Smoke Test (TASK 1d)
Verifies that simulated Firebase third-party JWTs (`request.jwt.claims` with non-UUID alphanumeric `sub`), RLS policies, column locks, atomic appointment booking, and dropped defaults work cleanly without SQLSTATE `22P02` or `42883`:

- **Via Node runner (recommended)**:
  ```bash
  node backend/scripts/run_firebase_identity_smoke_test.js
  ```
- **Via Docker psql (PowerShell)**:
  ```powershell
  Get-Content backend\supabase\tests\firebase_identity_smoke_test.sql | docker exec -i supabase_db_doctor psql -U postgres -d postgres
  ```
- **Via Docker psql (bash)**:
  ```bash
  docker exec -i supabase_db_doctor psql -U postgres -d postgres < backend/supabase/tests/firebase_identity_smoke_test.sql
  ```

### 2. General RLS Test Suite
Verifies cross-role blocking, verification gating, and isolation under UUID subjects:
```powershell
Get-Content backend\supabase\tests\rls_suite.sql | docker exec -i supabase_db_doctor psql -U postgres -d postgres
```
