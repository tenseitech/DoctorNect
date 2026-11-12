# Behavior diff: proposed `000015` vs deployed `20261026000001_rpc_null_safe_authz.sql`

Deployed `update_lab_booking_status(p_booking_id, p_new_status, p_notes)`:

- Auth: JWT required; profile or admin; lab/patient via `current_profile_id()` or `owner_uid` match.
- Patient: may set status only to `cancelled` when current status is `confirmed`.
- Lab: state machine `confirmed` → `sampleCollected`|`cancelled`; `sampleCollected` → `inAnalysis`; `inAnalysis` → `completed`; terminal blocks.
- Updates: `status`, `updated_at` only (`p_notes` ignored).
- Returns `old_status`, `new_status`.

Proposed adds (does **not** remove or widen):

- Optional 4th arg `p_report_storage_key`.
- `notes` updated only when `p_notes` is non-null and does not look like `lab_reports/...`.
- `report_storage_key` / `report_s3_key` set only when key validated.
- Key validation: prefix `lab_reports/{patient_id}/{booking_id}/`; only **lab or admin** may set; **patient rejected**.
- Same auth, patient/lab status rules, and transitions as deployed.

Deployed `update_lab_order_status`:

- Auth: lab, doctor, or admin (owner_uid fallbacks).
- Doctor: cancel only; not after `inProgress`/`completed`.
- Lab: state machine on `ordered`/`received`/`inProgress`/`completed`/`cancelled`.
- Updates `status`, `updated_at` only.

Proposed adds:

- Same report key rules with prefix `lab_reports/{patient_id}/{order_id}/`; **lab or admin only** (doctor cannot set key).
- Same transitions and auth as deployed.

**Privilege widening:** None intended. Patient/doctor cannot set storage keys. Status machine unchanged.
