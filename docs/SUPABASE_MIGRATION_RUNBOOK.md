# DoctorNect: Firebase → Supabase Migration & Cutover Runbook

This runbook provides the operational manual for executing the backend migration of **DoctorNect** from Firebase to Supabase without downtime, data loss, or disruption to live Google Play Store users.

---

## 1. Prerequisites & Environment Setup

### Required Tools
- Node.js (v18+)
- Supabase CLI (`npm install -g supabase` or `npx supabase`)
- Firebase CLI (`npm install -g firebase-tools`)
- Flutter SDK (Dart 3.2+)

### Environment Variables for Migration Scripts
Copy `.env.migration.example` to `.env.migration` (which is gitignored) and fill in credentials:
```bash
cp .env.migration.example .env.migration
```
> [!IMPORTANT]
> **Zero Plaintext Credentials Policy:**
> All migration and rollback scripts (`migrate_firestore_to_supabase.js`, `reverse_sync_supabase_to_firestore.js`, `test_rls_policies.js`) automatically load credentials from `.env.migration` via `scripts/load_env.js`.
> **NEVER pass connection strings inline in CLI commands or PowerShell `$env:` one-liners**, as this permanently exposes credentials in terminal transcripts and shell history.
```

---

## 2. Phase 1 & 3: Database & RLS Migration

All SQL migration scripts are located in `supabase/migrations/`:
1. `20260923000001_doctornect_schema.sql` (Full normalized relational DDL + IPD forward hooks)
2. `20260923000002_doctornect_rls.sql` (Security Definer helper functions & 33 RLS policy blocks)
3. `20260923000003_doctornect_cron.sql` (Automated pg_cron maintenance jobs)

### Execution via Supabase CLI
```bash
# Link your local project to Supabase cloud
supabase link --project-ref <your-project-ref>

# Push migrations to production database
supabase db push
```

*Alternatively, execute the contents of each `.sql` file in sequence directly inside the Supabase Studio SQL Editor.*

---

## 3. Phase 4: Edge Functions Deployment

Deploy the two core serverless Edge Functions to Supabase:

### 1. Set Function Secrets
```bash
# Egress Proxy & SMS Gateway Secrets
supabase secrets set \
  MSG91_PROXY_URL="https://msg91-proxy-658118593597.asia-south1.run.app/otp" \
  PROXY_SECRET="<proxy-secret-from-gcp-secret-manager>" \
  MSG91_TEMPLATE_ID_REGISTRATION="6a82fb0c248c482651029d14" \
  MSG91_TEMPLATE_ID_LOGIN="6a82f82114fa5616e7034772" \
  MSG91_TEMPLATE_ID_PASSWORD_RESET="6a82fabaaaba9478cd046022" \
  MSG91_SENDER_ID="DRNECT" \
  RAZORPAY_KEY_ID="<your-razorpay-key-id>" \
  RAZORPAY_KEY_SECRET="<your-razorpay-key-secret>" \
  RAZORPAY_WEBHOOK_SECRET="<your-razorpay-webhook-secret>"
```

> [!NOTE]
> **Egress Proxy Architecture & IP Tracking:**
> The `auth-otp` function routes outbound OTP dispatch through the `msg91-proxy` Cloud Run service attached to `msg91-connector` and Cloud NAT (`msg91-nat`), guaranteeing static outbound IP `35.200.245.73`. During initial verification, MSG91 accepted requests from this new IP without pre-registration, indicating MSG91 IP allowlisting is currently relaxed on the production Auth Key. The proxy is retained as a permanent defense-in-depth barrier so any future IP policy enforcement by MSG91 will not disrupt service.

### 2. Deploy Functions
```bash
# Deploy auth-otp (handles public pre-flight and MSG91 verification)
supabase functions deploy auth-otp --no-verify-jwt

# Deploy razorpay-payments (handles order creation, verification, and webhooks)
supabase functions deploy razorpay-payments --no-verify-jwt
```

---

## 4. Phase 5: Baseline Data Migration (T-7 Days)

Run the automated data migration script to copy historical data from Firestore into PostgreSQL.

### Step 1: Install Script Dependencies
```bash
cd scripts
npm install
cd ..
```

### Step 2: Run Dry-Run Simulation
```bash
node scripts/migrate_firestore_to_supabase.js --dry-run
```
*Review the output audit table to ensure zero schema errors and verify document counts match.*

### Step 3: Run Baseline Live Migration
```bash
node scripts/migrate_firestore_to_supabase.js --live
```

### Step 4: Verify Live Demo Accounts
Run these verification queries in Supabase SQL editor:
```sql
-- 1. Verify 5 Google Play review demo accounts exist and are verified
SELECT uid, role, mobile, verified, display_name 
FROM users 
WHERE mobile IN ('7058809803', '7666892394', '9359503874', '9409858233', '9307583929');

-- 2. Verify Doctor profile is approved
SELECT doctor_id, name, specialization, verified 
FROM doctors 
WHERE mobile = '7666892394';

-- 3. Verify Ambulance private settings and PIN hash
SELECT ambulance_id, pin_hash 
FROM ambulance_private_settings 
WHERE ambulance_id = '9307583929';
```

---

## 5. Phase 7: Live Cutover Window (Sunday 01:00 AM – 04:00 AM IST)

### Pre-Cutover Standing Prerequisites
- [ ] **Firebase CLI Authentication**: Ensure `npx firebase-tools projects:list` succeeds without error. Re-authenticate in advance via `firebase login --reauth`.
- [ ] **Traffic Isolation Mechanism**: Legacy Flutter clients (v1.0.x) do not contain a Remote Config `maintenance_mode` listener in code. Traffic isolation is enforced strictly at the database layer via Firestore Security Rules (read-only during freeze; restored upon completion/rollback).

### Cutover Execution Checklist

| Time (IST) | Action | Command / Procedure |
|---|---|---|
| **01:00 AM** | Standing Auth & Env Verification | Confirm `firebase projects:list` and Supabase DB connection |
| **01:15 AM** | Freeze Firestore Writes | Deploy read-only rules: `firebase deploy --only firestore:rules` |
| **01:20 AM** | Execute Final Delta Migration | `node scripts/migrate_firestore_to_supabase.js --live --since="<baseline_timestamp>"` |
| **02:00 AM** | Data Parity Check | Run count parity queries between Firestore & Postgres |
| **02:30 AM** | Release Supabase App Build | Promote Flutter v1.1.0 to Production on Google Play Console (Staged Rollout) |
| **03:00 AM** | Live Smoke Test 5 Roles | Test all 5 demo accounts (`000000` OTP) on real devices |
| **03:45 AM** | Finalize Cutover | Deploy final Firestore rules / monitor live Postgres metrics |

---

## 6. Emergency 3-to-4 Minute Rollback Plan (Verified Protocol)

If a critical blocker is encountered during cutover, execute the rollback immediately. Total verified execution time is **~3 to 4 minutes** (contingent on Firebase CLI standing authentication pre-condition).

### Rollback Execution Steps:

1. **Freeze Supabase Client Writes (T+0 min, Duration: < 1s):**
   - Instantly revoke all write permissions from public client roles (`anon` and `authenticated`) to prevent new records from entering Supabase while or after reverse-sync runs:
   ```sql
   -- Execute in Supabase Studio SQL Editor or via psql:
   REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
   ```
   *(To undo/re-enable writes if rollback is cancelled:)*
   ```sql
   GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
   ```

2. **Halt Google Play Rollout (T+1 min, Duration: ~1-2 min):**
   - **Manual step (cannot be automated):**
   - Navigate to **Google Play Console** -> **Release** -> **Production** -> Click **Halt Rollout**.
   - Halting stops new devices from downloading v1.1.0 (Supabase build).

3. **Execute Reverse Sync (T+2 min, Duration: ~3-5s, Verified: 1.34s):**
   - Synchronize any records created in Supabase during the live window back into Firestore (`appointments`, `prescriptions` + line items, `reviews`, and `users`):
   ```bash
   node scripts/reverse_sync_supabase_to_firestore.js --live --since="<cutover_start_time>"
   ```
   *Note: For testing without touching live collections, use the `--collection-prefix="test_rollback_"` flag:*
   ```bash
   node scripts/reverse_sync_supabase_to_firestore.js --live --collection-prefix="test_rollback_"
   ```

4. **Restore Firestore Security Rules (T+3 min, Duration: ~20-30s):**
   - Restore original production Firestore security rules to allow legacy app clients to resume writes:
   ```bash
   firebase deploy --only firestore:rules
   ```
   > [!IMPORTANT]
   > **Standing Pre-Condition:** Firebase CLI must already be authenticated beforehand (`npx firebase-tools projects:list`). Never leave CLI login to the moment of emergency.

5. **Legacy Client Traffic Resumption & Isolation (T+4 min):**
   - **Traffic Isolation Reality (Option A):** Because legacy Flutter clients (v1.0.x) do not implement Firebase Remote Config or an app-level `maintenance_mode` flag, write isolation relies 100% on Firestore Security Rules. As soon as production rules are restored in Step 4, all legacy Flutter clients immediately resume normal read/write operations without requiring an app update or maintenance flag flip.
   *(Long-term defense-in-depth: An app-level `maintenance_mode` Remote Config banner can be implemented in future client versions, but is not currently present in v1.0.x).*

### Rollback Timeline Breakdown (Verified vs. Documented)

| Step | Action | Type | Duration |
|---|---|---|---|
| **Step 1** | Freeze Supabase Writes | Automated SQL | **< 1s** (Tested: 48ms) |
| **Step 2** | Halt Google Play Rollout | Manual Web Console | **~1-2 min** |
| **Step 3** | Supabase → Firestore Reverse Sync | Automated Script | **~3-5s** (Tested: 1.34s) |
| **Step 4** | Restore Firestore Rules | Automated CLI | **~20-30s** |
| **Step 5** | Legacy Client Resumption | Immediate (via Rules) | **0s** (Instant) |
| **TOTAL** | **Full Emergency Rollback** | | **~3 to 4 minutes** |
