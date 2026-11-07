# RPC definition lineage (000015 / 000017)

## `reschedule_appointment_atomic`
1. `db/migrations/20261022000001_phase_f_complete_cutover.sql`
2. `db/migrations/20261025000001_least_privilege_grants_and_rls.sql`
3. **`db/migrations/20261026000001_rpc_null_safe_authz.sql`** ← latest deployed
4. `db/proposed/20261103000017_proposed_rpc_verified_checks.sql`

**Proposed diff intent:** after ownership check, require `private.is_verified_doctor()` when `v_appt.doctor_id = v_profile_id` (caller acts as assigned doctor — no `p_rescheduled_by` trust).

## `update_pharmacy_delivery_status`
1. `db/migrations/20261021000002_phase_d_pharmacy_lab_ambulance.sql`
2. **`db/migrations/20261026000001_rpc_null_safe_authz.sql`**
3. `db/proposed/20261103000017_proposed_rpc_verified_checks.sql`

**Diff intent:** verified medical store guard at start of `IF v_is_store` branch.

## `create_prescription_atomic`
1. `db/migrations/20261020000002_phase_c_doctor_patient_cutover.sql`
2. `db/migrations/20261026000001_rpc_null_safe_authz.sql`
3. **`db/migrations/20261029000001_guard_and_drift_fixes.sql`** ← latest deployed
4. `db/proposed/20261103000017_proposed_rpc_verified_checks.sql`

**Diff intent:** non-admin caller must pass `private.is_verified_doctor()`.

## `update_lab_booking_status` / `update_lab_order_status`
1. `db/migrations/20261021000002_phase_d_pharmacy_lab_ambulance.sql`
2. `db/migrations/20261026000001_rpc_null_safe_authz.sql` (3-arg, no report key)
3. `db/proposed/20261103000015_proposed_lab_report_storage_key.sql` (4-arg + key validation)
4. `db/proposed/20261103000017_proposed_rpc_verified_checks.sql` (verified lab + completed-only key + replace)

**Diff intent (000017 vs 000015):** `private.is_verified_lab()` in lab branch; key only when `p_new_status = 'completed'`; completed→completed key replacement.

Generate unified diffs:
`node scripts/db/rpc_proposed_unified_diff.js <function_name>`

## Client-parameter authorization audit (000015/000017)

| Function | Client param used for auth? | Notes |
|----------|----------------------------|-------|
| `reschedule_appointment_atomic` | ~~`p_rescheduled_by`~~ | **Fixed:** identity = `v_profile_id` vs `v_appt.doctor_id` |
| `update_lab_*_status` | `p_new_status` | Used for state machine only; role from row ownership |
| `update_pharmacy_delivery_status` | `p_new_status` | State machine; store/patient from `v_delivery` row |
| `create_prescription_atomic` | `payload` ids | Doctor resolved from JWT + `doctors` table, not payload alone |
