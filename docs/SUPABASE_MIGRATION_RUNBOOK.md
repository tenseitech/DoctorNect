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

### Cutover Execution Checklist

| Time (IST) | Action | Command / Procedure |
|---|---|---|
| **01:00 AM** | Enable Maintenance Banner | Set `maintenance_mode = true` in Remote Config |
| **01:15 AM** | Freeze Firestore Writes | Deploy read-only rules: `firebase deploy --only firestore:rules` |
| **01:20 AM** | Execute Final Delta Migration | `node scripts/migrate_firestore_to_supabase.js --live --since="<baseline_timestamp>"` |
| **02:00 AM** | Data Parity Check | Run count parity queries between Firestore & Postgres |
| **02:30 AM** | Release Supabase App Build | Promote Flutter v1.1.0 to Production on Google Play Console |
| **03:00 AM** | Live Smoke Test 5 Roles | Test all 5 demo accounts (`000000` OTP) on real devices |
| **03:45 AM** | Lift Maintenance Mode | Disable maintenance banner; monitor real-time queries |

---

## 6. Emergency 15-Minute Rollback Plan

If a critical blocker is encountered during cutover, execute the rollback immediately:

1. **Halt Google Play Rollout (T+2 min):**
   - In Google Play Console -> Release -> Production -> Click **Halt Rollout**.
2. **Execute Reverse Sync (T+7 min):**
   - Synchronize any records created in Supabase during the live window back into Firestore (`appointments`, `prescriptions` + line items, `reviews`, and `users`):
   ```bash
   node scripts/reverse_sync_supabase_to_firestore.js --live --since="<cutover_start_time>"
   ```
   *Note: For pre-cutover testing/validation without touching live Firestore collections, use the `--collection-prefix="test_rollback_"` flag:*
   ```bash
   node scripts/reverse_sync_supabase_to_firestore.js --live --collection-prefix="test_rollback_"
   ```
3. **Restore Firestore Rules (T+10 min):**
   - Restore original production rules:
   ```bash
   firebase deploy --only firestore:rules
   ```
4. **Deactivate Maintenance Mode (T+15 min):**
   - Turn off maintenance mode; legacy clients resume operation without disruption.
