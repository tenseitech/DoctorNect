# Legacy Firestore ↔ Supabase bridge removal plan

**Status:** Plan only — **do not delete** until staging/RDS cutover sign-off and `ENABLE_SUPABASE_SYNC=0` confirmed in all deploy envs.

**Goal:** Remove dual-write and reverse-sync code paths after `FIRESTORE_FORBIDDEN=1`, `notification_outbox` worker, and Auth Gateway + RDS are the sole production notification/data paths.

---

## Phase 0 — Preconditions (no deletions)

1. Confirm Supabase Dashboard has **no** database webhooks pointing at `sync-to-firestore` or `supabaseDatabaseWebhook`.
2. Confirm `ENABLE_SUPABASE_DATABASE_WEBHOOK=0` and `APP_ENV=production` on Functions (handler returns 503).
3. Confirm `ENABLE_SUPABASE_SYNC=0` in production materialized env.
4. Run `processNotificationOutboxScheduled` in staging with representative FCM traffic.

---

## Phase 1 — Stop deploying / invoking bridges (config only)

| Item | Action |
|------|--------|
| `ENABLE_SUPABASE_SYNC`, `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD` | Keep `0`; remove from production `.env.example` narrative after code delete |
| `ENABLE_SUPABASE_DATABASE_WEBHOOK` | Keep `0` in production |
| Supabase Edge `sync-to-firestore` | Do not deploy; remove dashboard webhooks |

---

## Phase 2 — Delete in dependency order

### Step 1 — Supabase Edge reverse bridge (no Cloud Functions deps)

| Delete | Notes |
|--------|--------|
| `backend/supabase/functions/sync-to-firestore/index.ts` | + `deno.json` if present |
| Docs/runbooks that only describe active reverse sync | Already marked legacy in `SYNC_ROLLOUT.md`, `PRE_CUTOVER_CHECKLIST.md` |

**Tests to remove with Step 1:**

- `backend/functions/test/sync_to_firestore.test.js`
- `backend/functions/test/sync_to_firestore_emulator.test.js`
- `backend/functions/test/sync_to_firestore_honest.test.js`
- Emulator targets in `backend/functions/package.json` (`test:sync-to-firestore-emulator`, references in `test:emulators`)

### Step 2 — Firestore `onDocumentWritten` slot trigger (unexported but still in tree)

| Delete / trim | Notes |
|---------------|--------|
| `reconcileAppointmentSlot` export + `onDocumentWritten` in `appointment_slots.js` | Keep Postgres callables `bookAppointment`, `rescheduleAppointment`, handlers |
| Comment block in `index.js` re slot reconciliation | Already notes Postgres-only |

**Tests to remove / shrink:**

- Firestore-only branches in `doctor_slots.test.js` (Firestore rate-limit fallback) — after guard confirms no prod path

### Step 3 — Forward sync module (`cross_role_sync.js`)

| Delete | Notes |
|--------|--------|
| `syncFirestoreUserToSupabase` and sibling `syncFirestore*ToSupabase` functions | Large file; may split DLQ helpers into `sync_dlq.js` first |
| `user_id_bridge.js` only if exclusively used by bridge + backfill (grep before delete) |

**Tests to remove with Step 3:**

- `backend/functions/test/user_identity_bridge.test.js`
- `backend/functions/test/supabase_sync_gate.test.js` (replace with “file absent” assertion or delete)
- Portions of `supabase_webhook_idempotency.test.js` that simulate `sync-to-firestore` loop (comments + mocks)

**Keep temporarily:**

- `sync_dead_letter_queue` table (Postgres) for audit/history until empty

### Step 4 — Feature flags (`sync_flags.js`)

| Delete / merge | Notes |
|----------------|--------|
| `isSupabaseSyncEnabled`, `ENABLE_SUPABASE_SYNC` readers | After Step 3 |
| Keep `isDoctorPatientSupabasePrimary()` if still used for Remote Config cutover | Move to `app_resources.js` or `sync_flags.js` slim file |

**Tests:**

- `backend/functions/test/supabase_sync_gate.test.js`
- Env parity references in `env_parity.test.js` (update, do not delete whole file)

### Step 5 — Legacy HTTPS webhook (`supabase_database_webhook.js`)

| Delete | When |
|--------|------|
| `exports.supabaseDatabaseWebhook` in `index.js` | After 30d with outbox-only notifications in staging + prod rehearsal |
| `supabase_database_webhook.js` | Same |
| `SUPABASE_WEBHOOK_SECRET` from deploy checklist | After handler removed |

**Tests to remove with Step 5:**

- `backend/functions/test/supabase_webhook_idempotency.test.js` (or keep minimal unit tests if shared helpers move to `notification_dispatch.js`)

---

## Phase 3 — Schema / client cleanup (later)

| Item | Action |
|------|--------|
| `sync_origin`, `synced_by` columns | Deprecate writes; optional migration to drop after parity audit |
| `sync_dead_letter_queue` | Archive then drop |
| Flutter `shared_appointments_store.dart` `_mirrorPatientCancelToSupabase` | Remove when client is Postgres-only |
| `frontend` Firestore appointment paths | Separate FIRESTORE_REMOVAL inventory |

---

## Verification after each step

```bash
# Workspace
npm run env:verify
node scripts/test/predeploy_secret_check.test.js
cd backend/functions && node --test test/supabase_sync_gate.test.js test/firestore_forbidden_runtime.test.js

# No bridge exports
node --test backend/functions/test/backend_audit_fixes.test.js
```

---

## Ownership

| Area | Owner action |
|------|----------------|
| Supabase Dashboard webhooks | Manual disable (not in git) |
| GCP Functions deploy | Redeploy after `index.js` export removals |
| RDS | No migration required for handler removal |
