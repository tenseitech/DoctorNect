# `pdl_select`: `owner_uid` vs `current_profile_id()`

## `private.current_profile_id()` (deployed)

From `db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql` L1290–1297:

```sql
SELECT profile_id FROM public.users WHERE id = (auth.jwt() ->> 'sub') LIMIT 1;
```

Returns the caller's **domain id** (`patient_id`, `doctor_id`, …) from `public.users.profile_id`.

## Legacy branches

| Policy | Line | Patient access |
|--------|------|----------------|
| `doc_links_select` | `20260923000002` L234–236 | `patient_id = current_profile_id()` |
| `pdl_select` (consolidated) | `20261020000001` L1816–1826 | `doctor_id = current_profile_id()` OR `EXISTS (patients p WHERE p.patient_id = link.patient_id AND p.owner_uid = jwt sub)` |

## Equivalence

- **Self patient:** `patient_id = current_profile_id()` when the logged-in user is the patient and `users.profile_id` equals that patient's `patient_id` (normal case).
- **Guardian / multi-account:** `owner_uid = jwt sub` matches when the JWT is the **Firebase uid of the account that owns** the patient row, even if `profile_id` on the session is the guardian's id or a family flow uses `owner_uid` without `profile_id = patient_id`.
- **Not equivalent in general:** family members booked as `member_id` may need other policies (`family_members`); `owner_uid` does **not** replace `current_profile_id()` for all cases — **proposed 000014 keeps `owner_uid` OR** and tightens doctor branch with `is_verified_doctor()`.

## Proposed `pdl_select` (`000014` L226–236)

Keeps patient `owner_uid` branch; doctor must be verified; drops unverified doctor reading via `doctor_id = current_profile_id()` alone.
