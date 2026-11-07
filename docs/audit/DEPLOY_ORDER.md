# Deploy order — proposed SQL + app builds

## Proposed migrations (staging first)

Apply to **staging** Supabase Postgres in this order ( filenames under `db/proposed/` ):

1. **`20261103000014_proposed_role_verified_rls_hardening.sql`**  
   - Hardens RLS on appointments, prescriptions, lab bookings/orders, etc.  
   - **Apply before** app versions that rely on verified-doctor / verified-lab checks for writes.

2. **`20261103000015_proposed_lab_report_storage_key.sql`**  
   - Extends `update_lab_order_status` (and related) with `p_report_storage_key` validation.  
   - **Apply before** clients that pass lab report storage keys to the RPC.

3. **`20261103000016_proposed_in_app_notifications_supabase.sql`**  
   - Extends `in_app_notifications` (columns + index + RLS for select/update + recipient read-only trigger).  
   - **Required** for the current Flutter in-app notification inbox (merge/mark-read) and sync paths that read `in_app_notifications` via Supabase.  
   - **Ambulance-related** policy draft: `db/proposed/later/20261103000016_later_ambulance_notifications_policies.sql` (not needed while `AMBULANCE_ENABLED` is off; policies incomplete per file header).

4. **`20261103000017_proposed_rpc_verified_checks.sql`** (after **000014**)  
   - Verified-guarded SECURITY DEFINER RPCs; lab status functions include **000015** report-key rules + completed-only key updates.  
   - Ambulance RPC patches: `db/proposed/later/20261103000017_later_rpc_ambulance_verified.sql`.

5. **`20261103000018_proposed_lab_report_key_column_guard.sql`** (after **000015** columns exist)  
   - BEFORE UPDATE trigger: direct PostgREST key writes rejected; keys only via RPC session guard.

## App / build dependencies

| Build / feature | Depends on |
|-----------------|------------|
| Lab order report key uploads | **000015** (function signature + validation) |
| In-app notification inbox (patient/doctor), mark read, RLS-aligned reads | **000016** |
| Stricter multi-role RLS on appointments / labs / prescriptions | **000014** |
| Lab report upload via RPC `p_report_storage_key` (not PostgREST column patch) | **000015** + **000018** + client that calls RPC |
| Unverified provider cannot mutate deliveries / lab status / doctor reschedule | **000017** (after **000014**) |
| Direct PostgREST mutation of lab `report_storage_key` | **000018** (after **000015** columns) |

## Client build ↔ SQL matrix

| Client capability | Minimum SQL on server |
|-------------------|----------------------|
| In-app inbox mark-read + columns | **000016** |
| Lab `p_report_storage_key` on RPC (no PostgREST PATCH) | **000015** + **000017**; **000018** to block PATCH |
| Verified-only doctor reschedule / rx / store status | **000014** + **000017** |
| Unverified store/lab can read own connection rows (onboarding) | **000014** (select allows own `store_id` / `lab_id`) |

Staging probes: `scripts/audit/rls_staging_verified_role_matrix.sql`, `in_app_notifications_staging_probes.sql`, `lab_report_key_staging_probes.sql`, `rpc_verified_staging_probes.sql`.

## If the app ships **before** `000016` is applied

- Client calls to `in_app_notifications` (select / update `is_read`) may **fail** with Postgres/PostgREST errors (missing columns, policy mismatch, or 42501).  
- **Observable behavior**: inbox stays **empty** or stale, **`InAppNotificationService.lastRemoteError`** set on mark-read failures, repeated errors in logs; push/local notifications may still fire but **remote** inbox sync is broken.  
- **Mitigation**: ship app only after staging verification of `000016`, or feature-flag off Supabase inbox polling (not recommended for launch).

## If the app ships **before** `000015**

- RPC calls sending `p_report_storage_key` to an older `update_lab_order_status` signature may **fail** (argument mismatch) or ignore keys.  
- Lab report linking in UI may **stall** until SQL catches up.

## If the app is **newer** than **000015+000018** (client uses RPC keys, SQL not applied)

- Lab completes upload in S3 but **PostgREST** `report_storage_key` patch may **42501** once **000018** is live without matching RPC client → UI shows persist error (`LabReportSubmitFlow.persistFailedMessage`).  
- **Mitigation**: deploy **000015** before **000018**, then ship client that passes `p_report_storage_key` in `update_lab_*_status`.

## If SQL is **newer** than the app (000018 applied, old client)

- Old app may still PATCH keys via PostgREST → **rejected** (intended). User must upgrade to RPC-based client.  
- Download URLs still work when stored key matches (`s3_storage.js` validates prefix + stored key).

## Rollback

1. **Database**: restore staging from pre-migration snapshot or re-apply previous known-good migration set from `db/migrations/` (coordinate with DBA; do not drop columns in production without a plan).  
2. **App**: roll back to the previous store build that matched the prior API.  
3. **Order**: rollback SQL in **reverse** order only if each script’s changes are reversible (policy drops/recreates are safe; `ALTER TABLE ADD COLUMN` may require manual rollback scripts).

## Docker / local Postgres (integration tests)

- Compose: Supabase local stack via CLI (see `docs/audit/DOCKER_RUN.md`).  
- Command:  
  `cd backend` → `npx -y supabase start`  
- DB URL: `postgres://postgres:postgres@127.0.0.1:54322/postgres`
