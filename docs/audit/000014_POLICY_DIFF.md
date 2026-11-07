# 000014 policy diff (legacy → proposed)

## `pdl_select` (patient_doctor_links)

| | Text |
|---|------|
| **Legacy** `doc_links_select` | `db/migrations/20260923000002_doctornect_rls.sql` L234–236: `patient_id = current_profile_id() OR doctor_id = current_profile_id()` |
| **Legacy** `pdl_select` | `db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql` L1815–1826: doctor **or** patient `owner_uid` **or** super_admin |
| **Proposed** `pdl_select` | `db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql` L225+: doctor branch requires `private.is_verified_doctor()`; patient `owner_uid` + family paths retained |

**Branches preserved:** patient via `owner_uid`, doctor own row (stricter: verified), super_admin.

## `pharmacy_connections_*`

| | Text |
|---|------|
| **Legacy** `pharmacy_conn_policy` | `20260923000002` L536–545: verified doctor OR `medical_store_id = current_profile_id()` |
| **Legacy** consolidated | `20261020000001` L2086–2104: select/write split, doctor OR store id match (no verified on store) |
| **Proposed** | `000014` L175–193: verified doctor **and** verified medical_store on respective branches; super_admin |

**Branches preserved:** doctor, store, admin. Store now must be **verified** to write (tightening).

## `lab_connections_*`

| | Text |
|---|------|
| **Legacy** `lab_conn_policy` | `20260923000002` L547–556: verified doctor OR `lab_id = current_profile_id()` |
| **Legacy** consolidated | `20261020000001` L2219–2237: doctor OR lab id |
| **Proposed** | `000014` L201–214: verified doctor + verified lab on respective branches |

**Branches preserved:** doctor, lab, admin. Lab must be **verified** to write.
