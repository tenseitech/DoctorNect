# Harness seed failure — root cause (verified in code / prior local run)

**Updated:** 2026-11-17

## Symptom

`rls_sql_harness.js` seed aborted with:

`new row violates row-level security policy for table "ambulance_trip_contacts"`

while `withHarnessSeedDml` had set `SET LOCAL ROLE service_role` (`service_role_member=true`, `rolbypassrls=true` on direct probe).

## Were any seed statements outside `withHarnessSeedDml`?

**No.** All fixture `INSERT` batches lived inside a single `withHarnessSeedDml` callback.  
Indirect DML from **SECURITY DEFINER triggers** is not covered by the session role of the outer `INSERT`.

## Actual failing path

1. Seed step `appointments_ambulance_pharmacy_lab` inserts a **pending** row into `public.ambulance_broadcasts` (`test_ambbc_pending`).
2. `BEFORE INSERT` trigger `trg_ambulance_broadcast_contact_guard` runs `private.trg_ambulance_broadcast_contact_guard()` (SECURITY DEFINER).
3. Trigger function owner was **`doctornect_admin`** (migrator), **without** BYPASSRLS → trigger body `INSERT INTO public.ambulance_trip_contacts` is subject to `deny_all_ambulance_trip_contacts`.
4. Error surfaces as trip_contacts RLS even though the outer `current_user` was `service_role`.

At failure time (outer session): `session_user=doctornect_admin`, `current_user=service_role`, `bypassrls=true`.  
Inside trigger execution: `current_user` = function owner (`doctornect_admin`) until fixed.

## Fix (prod-safe)

`20261118000005_rls_helper_definer_service_role.sql` also runs:

`ALTER FUNCTION private.trg_ambulance_broadcast_contact_guard() OWNER TO service_role;`

(temporary `GRANT CREATE ON SCHEMA … TO service_role` for `ALTER OWNER`, then **`REVOKE CREATE`**).

## Harness instrumentation

- `scripts/lib/harness_seed_sql.js` — all seed SQL steps + table list audit.
- `scripts/lib/harness_seed_role.js` — `logHarnessSeedSession` / `runHarnessSeedSteps` logs `session_user`, `current_user`, `bypassrls` per step.