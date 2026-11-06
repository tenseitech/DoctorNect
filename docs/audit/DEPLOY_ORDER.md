# Deploy order — proposed SQL + app builds

## Proposed migrations (staging first)

Apply to **staging** Supabase Postgres in this order ( filenames under `db/proposed/` ):

1. **`20261103000014_proposed_role_verified_rls_hardening.sql`**  
   - Hardens RLS on appointments, prescriptions, lab bookings/orders, etc.  
   - **Apply before** app versions that rely on verified-doctor / verified-lab checks for writes.

2. **`20261103000015_proposed_lab_report_storage_key.sql`**  
   - Extends `update_lab_order_status` (and related) with `p_report_storage_key` validation.  
   - **Apply before** clients that pass lab report storage keys to the RPC.

3. **`20261103000016_proposed_ambulance_in_app_notifications_supabase.sql`**  
   - Extends `in_app_notifications` (columns + index + RLS for select/update).  
   - Adds ambulance request/broadcast columns and RLS adjustments.  
   - **Required** for the current Flutter in-app notification inbox (merge/mark-read) and sync paths that read `in_app_notifications` via Supabase.

## App / build dependencies

| Build / feature | Depends on |
|-----------------|------------|
| Lab order report key uploads | **000015** (function signature + validation) |
| In-app notification inbox (patient/doctor), mark read, RLS-aligned reads | **000016** |
| Stricter multi-role RLS on appointments / labs / prescriptions | **000014** |

## If the app ships **before** `000016` is applied

- Client calls to `in_app_notifications` (select / update `is_read`) may **fail** with Postgres/PostgREST errors (missing columns, policy mismatch, or 42501).  
- **Observable behavior**: inbox stays **empty** or stale, **`InAppNotificationService.lastRemoteError`** set on mark-read failures, repeated errors in logs; push/local notifications may still fire but **remote** inbox sync is broken.  
- **Mitigation**: ship app only after staging verification of `000016`, or feature-flag off Supabase inbox polling (not recommended for launch).

## If the app ships **before** `000015**

- RPC calls sending `p_report_storage_key` to an older `update_lab_order_status` signature may **fail** (argument mismatch) or ignore keys.  
- Lab report linking in UI may **stall** until SQL catches up.

## Rollback

1. **Database**: restore staging from pre-migration snapshot or re-apply previous known-good migration set from `db/migrations/` (coordinate with DBA; do not drop columns in production without a plan).  
2. **App**: roll back to the previous store build that matched the prior API.  
3. **Order**: rollback SQL in **reverse** order only if each script’s changes are reversible (policy drops/recreates are safe; `ALTER TABLE ADD COLUMN` may require manual rollback scripts).

## Docker / local Postgres (integration tests)

- Compose: Supabase local stack via CLI (see `docs/audit/DOCKER_RUN.md`).  
- Command:  
  `cd backend` → `npx -y supabase start`  
- DB URL: `postgres://postgres:postgres@127.0.0.1:54322/postgres`
