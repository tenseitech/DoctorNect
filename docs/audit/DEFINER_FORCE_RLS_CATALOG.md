# DEFINER × FORCE RLS catalog (static + audit tool)

**Updated:** 2026-11-17  
**Live catalog query:** `node scripts/db/definer_force_rls_audit.js --target=rehearsal` (read-only; requires migrated `doctornect_rehearsal`).

## Criteria

`SECURITY DEFINER` function owned by a role **without** `rolbypassrls`, whose body performs DML against a table with `relforcerowsecurity = true`.

## Re-homed in `20261118000005` (9 functions)

| # | Function | FORCE RLS / internal tables touched | Fix |
|---|----------|-------------------------------------|-----|
| 1 | `private.doctor_can_access_patient(text)` | (RLS helper; no direct deny-all DML) | `OWNER service_role` |
| 2 | `private.current_profile_id()` | — | `OWNER service_role` |
| 3 | `private.is_verified_doctor()` | — | `OWNER service_role` |
| 4 | `public.fn_sync_review_aggregates()` | `review_public`, `doctors`, `reviews` | `OWNER service_role` |
| 5 | `private.trg_ambulance_broadcast_contact_guard()` | `ambulance_trip_contacts` | `OWNER service_role` |
| 6 | `public.enqueue_notification_outbox()` | `notification_outbox` | `OWNER service_role` |
| 7 | `public.accept_ambulance_request(varchar,varchar)` | `ambulance_trip_contacts` (+ broadcasts) | `OWNER service_role` |
| 8 | `public.update_ambulance_location(...)` | `ambulance_locations` | `OWNER service_role` |
| 9 | `public.check_and_increment_rate_limit(text,int,int,text)` | `abuse_rate_limits` | `OWNER service_role` |

**Count for gate:** **9** (pending automated audit exit 0 on fresh DB).

## Not moved (callable with in-body authz; no deny-all DML hit)

Other `SECURITY DEFINER` RPCs (`book_appointment_atomic`, pharmacy/lab RPCs, etc.) DML domain tables under normal RLS policies — left on migrator owner unless live audit finds a FORCE RLS write.