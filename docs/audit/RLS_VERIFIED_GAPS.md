# RLS gaps: `current_profile_id()` without verified/approved (baseline: `20261020000001`)

| Table | Policy | Command | Missing check | Proposed fix |
|-------|--------|---------|---------------|--------------|
| `appointments` | `appointments_select` | SELECT | Doctor may read via `doctor_id = current_profile_id()` while unverified | Require `private.is_verified_doctor()` for doctor rows |
| `appointments` | `appointments_update` | UPDATE | Doctor may update/accept while unverified | Require `is_verified_doctor()` on doctor branch (see `20261103000014_proposed_role_verified_rls_hardening.sql`) |
| `prescriptions` | `prescriptions_select` | SELECT | Doctor reads own Rx without verified | Add `is_verified_doctor()` on doctor branch (INSERT/UPDATE already gated) |
| `lab_bookings` | `lab_bookings_update` | UPDATE | Lab operator via `lab_id` without `labs.verified` | Add `private.is_verified_lab()` |
| `lab_orders` | `lab_orders_insert` / `lab_orders_update` | INSERT/UPDATE | Doctor/lab without verified | Add `is_verified_doctor()` / `is_verified_lab()` |
| `pharmacy_connections` | `pharmacy_connections_*` | ALL | Doctor/store via profile id without verified | Add verified helpers for doctor + medical store |
| `patient_doctor_links` | `pdl_select` | SELECT | Doctor link visibility while unverified | Add `is_verified_doctor()` on doctor branch |
| `patients` | `patients_select` | SELECT | — | **OK**: uses `doctor_can_access_patient()` → includes `is_verified_doctor()` |
| `health_records` | `health_records_*` | SELECT/INSERT | — | **OK** for doctor clinical access via `doctor_can_access_patient()` |
| `prescriptions` | `prescriptions_insert` / `update` | INSERT/UPDATE | — | **OK**: `is_verified_doctor()` |
| RPC | `create_prescription_atomic` | EXECUTE | — | **OK**: checks `doctors.verified` (`20261029000001`) |

Apply proposed SQL manually: `db/migrations/20261103000014_proposed_role_verified_rls_hardening.sql` (idempotent).
