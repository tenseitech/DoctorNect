# DoctorNect - project analysis (2026-11-26)

Branch `security/full-audit-fix`, nothing pushed. Admin module out of scope. Method: code reading,
manifest load of `backend/functions/index.js`, migrations replayed on scratch PG17 + PG18 (Docker),
schema/grant/RLS audits on the scratch DB, client-vs-backend name cross-check, read-only AWS CLI,
`npm audit`, `flutter analyze`, APK manifest dump. Previous rounds: SECURITY_AUDIT_REPORT.md (R1-R3).

## Executive summary

- One **Critical** release blocker: the five S3 callables the app uses for every upload/download are
  defined in `s3_storage.js` but **not exported from `index.js`**, so the next Functions deploy would
  remove them (and `confirmS3Upload` is already missing live: HTTP 404).
- **High**: a pre-OTP account-existence oracle (`lookupMobileRegistration`, unused by the app);
  `reschedule_appointment_atomic` writes 10:00 IST for every slot, can re-open cancelled or completed
  appointments and has no lock; MSG91 SMS calls have no timeout; CI is out of date (Flutter 3.47.5 vs
  3.50 required, no permissions block, unconfigured release APK artifact); demo ambulance anonymous
  session routes to RDS in production (design decision).
- The data layer is in good shape: 84 migrations replay on PG17 and PG18, the 7 newest are
  idempotent, 72 SQL checks pass, RLS coverage 0 issues on 66 tables, no anon grant surprises, every
  SECURITY DEFINER function pins `search_path`. Every table/RPC the app and the Functions use exists
  and is allowed by the gateway. `npm audit`: 0 in Functions and gateway.
- Release config is sound (minify + shrink, release signing, targetSdk 36, backups off, media
  permissions stripped). `flutter analyze`: 0 errors/warnings; all 337 infos are one deprecation.

## Inventory (short)

| Area | Facts |
|---|---|
| Cloud Functions | 46 exported in `index.js` (37 callable, 5 HTTPS, 4 scheduled), all `asia-south1`; every function binds `PROD_GATEWAY_SERVICE_KEY` + `DEMO_SUPABASE_SERVICE_ROLE_KEY` (cold-start routing assert); OTP send/verify also `OTP_HMAC_SECRET`, `REVIEW_FIXED_OTP`. HTTPS endpoints wrap `withApiSecurityHeaders` (admin excluded). |
| Gateway | `services/api-gateway`: client allowlist 47 tables / 14 RPCs, service-role allowlist 70 / 16, anon public allowlist 5; client routing hints rejected (400); demo numbers refused on RDS. |
| Schema (PG18 scratch) | 66 tables, 145 policies, 113 functions (22 SECURITY DEFINER callable by `authenticated`, 1 by `anon`: `doctor_directory_rows`, public profile fields only). |
| Client | Flutter 3.50.1, `medibond` 1.0.2+7, targetSdk 36, 28 callables used. |
| Infra | Terraform `infra/aws` (validate OK). AWS: ALB + HTTPS + ACM issued, TG `/healthz`, ECR images pushed; ECS desired 0; 5 gateway secrets empty; no DNS. |
| CI | `.github/workflows`: backend-functions-ci, build-apk, env-policy, flutter-ci, gateway_ci, supabase-keepalive. |

## Findings (priority order)

Status: open / fixed (commit) / needs decision / blocked (on you) / won't fix.

| ID | Sev | Area | Where | Problem | Impact | Fix | Effort | Fix risk | Status |
|---|---|---|---|---|---|---|---|---|---|
| C1 | Critical | Functions | `backend/functions/index.js` (no export), `s3_storage.js:1429-1453` | `getS3UploadUrl`, `getS3DownloadUrl(s)`, `deleteS3Object`, `confirmS3Upload` are not exported from `index.js` | Deploy deletes the live upload/download functions; `confirmS3Upload` already 404 live: no file upload can be confirmed | Re-export from `index.js`; test that every client callable is exported | S | Low | fixed |
| H1 | High | Security/OTP | `index.js` `lookupMobileRegistration`, `registration_otp.js:2962` | Unauthenticated (App Check only) callable returns `exists` + `role` for any number before OTP | Account enumeration: who uses the app and as which provider/patient | Answer with a constant, non-revealing result; delete the dead client path (`resolvePath`) | S | Low (app does not call it) | fixed (server; dead client path left, harmless) |
| H2 | High | Booking/SQL | `reschedule_appointment_atomic` (`20261119000004`) | Always 10:00 IST; capacity counted by label not time; no advisory lock; re-opens cancelled/completed; past dates allowed | Wrong appointment times (client then fails "slot/time mismatch"), over-booking race, revived cancelled visits | New migration: parse `hh:mm AM/PM`, same lock + capacity rule as booking, status and date guards; SQL test | M | Medium (RPC body only, same signature) | fixed (migration 20261126000001: apply on staging, then RDS) |
| H3 | High | Ambulance/plane | `completeAmbulanceMobileOtpLogin`, `ambulance_auth_helper.dart` | Ambulance session is anonymous; in production the demo ambulance's anon uid is not on the demo allowlist, so its callables route to RDS | Demo ambulance (Play review) broken after deploy; no real-user impact | See decision D1 | M-L | Medium | needs decision |
| H4 | High | Reliability | `registration_otp.js:1122-1208` `postMsg91OtpRequest` | No timeout on both MSG91 send paths (proxy and direct) | A slow MSG91 holds the OTP send until the 60 s function timeout; user stuck, cost | `req.setTimeout(8000)` like verify | S | Low | fixed |
| H5 | High | CI | `.github/workflows/*.yml` | Flutter 3.47.5 (project needs 3.50 for AGP 9), Node 20 vs engines 22, no `permissions:` (default token rights), `build-apk` uploads a release APK without Firebase/data-plane config, no SQL/boot-env/secret-scan jobs | CI red or misleading; broader token rights than needed | Pin versions, `permissions: contents: read`, debug-only artifact, add SQL tests + secret scan + check:boot-env (example env) | M | Low | open |
| M1 | Medium | Reliability | `src/db/client.js:92` | Gateway/Supabase client has no request timeout | Gateway outage: every DB call hangs until function timeout | `global.fetch` with `AbortSignal.timeout(15000)` | S | Low | fixed |
| M2 | Medium | DB perf | 28 FK columns without index (e.g. `appointments.booked_by_uid`, `patient_doctor_links.doctor_id`, `pharmacy_deliveries.doctor_id`, `ambulance_locations.driver_id`, `support_tickets.*`) | Seq scans on joins/deletes (account deletion, cascades) | Slow queries as data grows | Migration `CREATE INDEX IF NOT EXISTS` for all 28 | S | Low | fixed (migration 20261126000002) |
| M3 | Medium | Boot | `assert_app_env.js` `assertProductionCutoverBoot` | Completeness assert not called at cold start | Missing Redis/MSG91 config found at first use, not boot | Call it at cold start (check:boot-env already warns) | S | Medium (could stop boot) | needs decision (D2) |
| M4 | Medium | Lab | `lab_catalog_repository.dart:20` | Queries table `lab_catalog` (dropped); error swallowed | One failing request per lab screen load; catalog never server-driven | Read `lab_catalog_tests` or stop querying | S | Low | open |
| M5 | Medium | Privacy/logs | 10 `console.error(..., err)` sites | Whole error objects logged (PostgREST errors can echo row values) | PHI/PII in Cloud Logging | Log `code` + `message` only | S | Low | open |
| M6 | Medium | Supply/TLS | ~20 `scripts/**` with `rejectUnauthorized: false` (staging audits) | Unverified TLS to staging DB | MITM of a privileged connection | Use `scripts/lib/staging_pg_ssl.js` | M | Low | open |
| M7 | Medium | Docs | `MIGRATION_STATUS.md` | Says prod 77/77, head `20261119000005`, wrong branch | Misleads cutover steps (7 pending now) | Update | S | None | open |
| M8 | Medium | Legacy | 109 Flutter files / 7 backend files mention Firestore | Dead dual-path code, naming | Maintenance, accidental re-enable | Staged removal | L | Medium | needs decision (D3) |
| L1 | Low | DB | `storage_audit_logs.status` | No CHECK | Bad values possible | CHECK constraint (NOT VALID + validate) | S | Low | open |
| L2 | Low | Gateway | `services/api-gateway/src/config.js` | Allowlists name non-existent `lab_catalog`, `medicine_suggestions`, `admin_users`, `provisioning_errors`, `sync_dead_letter_queue`, `delete_my_account` | Stale surface | Remove dead names (test) | S | Low | open |
| L3 | Low | Client | `medicine_suggestion_repository.dart` | Inserts into dropped table; never called | Dead code | Remove | S | None | open |
| L4 | Low | Android | Razorpay SDK adds `NFC`, `READ_BASIC_PHONE_STATE` | Extra permissions in Data safety | Store listing questions | `tools:node="remove"` after a payment test | S | Medium (SDK) | needs decision (D4) |
| L5 | Low | Flutter | 337 `deprecated_member_use` (material.dart -> material_ui) | Deprecation only | Future break | Migrate when material_ui is stable for all plugins | L | Medium | needs decision (D5) |
| L6 | Low | Android | `gradle.properties` `android.builtInKotlin=false` + shim | Plugins still apply KGP | Blocks AGP built-in Kotlin | Remove when plugins update | S | - | blocked (upstream) |
| L7 | Low | CI | `supabase-keepalive.yml` | Duplicates Functions `supabaseKeepalive`, needs a repo secret | Extra secret surface | Keep as backup or delete | S | None | needs decision (D6) |
| L8 | Low | Secrets binding | all functions | `PROD_GATEWAY_SERVICE_KEY` bound everywhere | Functions without DB use still hold it | By design (cold-start routing assert + DB calls) | - | - | won't fix (documented) |

Verified OK (no change): per-role account deletion retention (doctor/pharmacy/lab/ambulance anonymised,
patient data kept; patient Auth deleted last), SUPER_ADMIN_EMAILS + claim, HTTP security headers,
gateway/client/table/RPC parity, release signing/minify/backup flags, Android permissions besides L4,
npm audit 0, RLS coverage 0 issues, anon grants 0 surprises.

## Fix order (dependencies)

C1 -> (deploy gate) ; H1, H4, M1, M5 independent ; H2 -> SQL test -> replay PG17/18 ; M2, L1 -> one
migration each after H2's number ; H5 after the SQL/test commands are final ; M4, L3 client ; L2 gateway ;
M6 scripts ; M7 docs last.

## Needs your decision

- **D1 Ambulance session (H3).** (a) Server-side: when `completeAmbulanceMobileOtpLogin` links a
  demo-number ambulance, record the anonymous uid as demo (signed custom claim `dn_plane=demo` set only
  from the fixed allowlist) and route by that claim in Functions + gateway. (b) Sign ambulance drivers
  in with the custom token the OTP step already mints (uid = account owner) and drop the anonymous
  requirement in the ambulance module. (c) Leave as is (demo ambulance broken in production).
  Recommendation: (b) long-term (one identity model), (a) only if (b) cannot ship before review.
- **D2 Cold-start completeness (M3).** Call `assertProductionCutoverBoot` at boot (fail fast) or keep
  it in `check:boot-env` only. Recommendation: call it after the first green deploy.
- **D3 Firestore legacy (M8).** Remove in stages (client gate + repositories, then backend legacy
  branches) or keep. Recommendation: staged removal, one module per PR.
- **D4 Razorpay permissions (L4).** Strip `NFC`/`READ_BASIC_PHONE_STATE` or keep. Recommendation:
  strip and run one test payment.
- **D5 material_ui (L5).** Migrate now or wait. Recommendation: wait for plugin support.
- **D6 GitHub keepalive (L7).** Keep or delete. Recommendation: delete (Functions keepalive exists).

## Blocked on your manual actions

Gateway secrets, ECS desired count 1 + apply, DNS CNAME, RDS snapshot + 7 migrations + runtime grants,
`authenticator` password, Functions secrets (`OTP_HMAC_SECRET`), production S3 settings, deploy via
`scripts/env/predeploy_gate.ps1` (docs/GATEWAY_DEPLOY.md, "What is left").
