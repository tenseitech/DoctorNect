# pg_pool vs gateway caller audit (`APP_ENV=production`)

Audit date: 2026-11-15 (code-level; no deploy).

## Summary

| Path | Production deploy (`index.js` exports) | Direct RDS (`pg_pool`) |
|------|----------------------------------------|-------------------------|
| Hot paths (OTP, booking callables, payments, profile, delete account, workers) | **gateway** (`getDatabaseClient` / `getSupabaseAdminClient` → `client.js`) | **none** |
| Batch / maintenance | N/A (not exported) | **`cross_role_sync.js` only** |

`assertProductionCutoverBoot` does **not** require `DATABASE_URL` while no exported handler uses `pg_pool`.

## Table (backend/functions)

| file | function / area | path | hot path |
|------|-----------------|------|----------|
| `registration_otp.js` | OTP send/verify, login finalize | gateway | OTP |
| `delete_my_account.js` | account deletion REST cleanup | gateway (`PROD_GATEWAY_*` HTTP) | delete account |
| `promoted_ads.js` | ads review / expire | gateway | payments/ads |
| `index.js` | mail queue + notification outbox schedulers | gateway | batch workers |
| `notification_outbox_worker.js` | FCM outbox | gateway | notifications |
| `in_app_notifications.js` | in-app feed writes | gateway | profile/notifications |
| `admin_platform_actions.js` | admin mutations | gateway | admin |
| `admin_console_read_api.js` | admin reads | gateway | admin |
| `caller_identity.js` | identity resolution | gateway | auth |
| `s3_storage.js` | storage audit rows | gateway | profile/KYC |
| `security_logger.js` | security events | gateway | auth |
| `fcm_push.js` | device tokens | gateway | notifications |
| `supabase_database_webhook.js` | DB webhook fan-out | gateway | webhooks |
| `src/db/read_user_profile.js` | profile read helper | gateway | profile |
| `appointment_slots.js` | book / reschedule | legacy Firestore (guarded); not pg_pool | booking (legacy) |
| `cross_role_sync.js` | Firestore→PG sync, DLQ SQL fallback | **pg_pool** (`needs pg_pool`; not in `index.js`) | sync/DLQ batch |

## Hot path → gateway

No production **exported** handler used `pg_pool` before this change; no new SECURITY DEFINER RPCs were required for cutover. Future raw SQL in hot paths must add gateway RPCs + RLS suite coverage.

## Boot guard

- `isProductionBootRequiresDatabaseUrl()` → `false` (`src/db/pg_pool.js`).
- `getPgPool()` remains lazy; production first use requires `DATABASE_URL` or `PROD_RDS_*`; connect timeout default **5s** (`PG_POOL_CONNECT_MS` override allowed).

## Gateway service key (backend only)

| Check | Status |
|-------|--------|
| Constant-time compare | `services/api-gateway/src/security.js` → `secureCompare` / `timingSafeEqual` |
| Service key vs user JWT | JWT (contains `.`) is not accepted as service key via `apikey`; Bearer verifies Firebase |
| Client bundle | `PROD_GATEWAY_SERVICE_KEY` forbidden in `generate_flutter_dart_defines.js`; grep test `gateway_service_key_client_bundle.test.js` |
| Anon on privileged routes | Gateway tests: anon `apikey` → 401 on `admin_users`; user JWT → 404 on `serviceRoleOnlyTables` |
| ALB / WAF | `infra/aws/alb.tf` + SG on 443; **no AWS WAF resource** in repo (gap — operator may attach WAF separately) |