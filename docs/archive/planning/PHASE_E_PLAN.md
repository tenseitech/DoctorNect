# Phase E Plan: Clean Hardening & Firebase-Supabase Architecture Alignment

**Project:** DoctorNect Pre-Launch Hardening  
**Architecture Invariants:**
- **Primary Auth Provider:** **Firebase Authentication** remains the sole identity provider. Supabase Auth is NOT used; RLS evaluates `(auth.jwt()->>'sub')` matching Firebase UIDs.
- **Transactional Communications:** MSG91 SMS and email dispatch remain inside **Cloud Functions** routed through the existing static IP proxy.
- **Cache & Throttling Layer:** OTP challenges, rate limiting, and abuse limits are stored in **Redis with TTL**.
- **Object Storage:** AWS S3 buckets remain **100% private** with access restricted to CloudFront Origin Access Control (OAC) and presigned download URLs.
- **Role & Claims Authority:** Cloud Functions manages Firebase Custom Claims via Firebase Admin SDK; profile data resides in Supabase PostgreSQL `public.users`.
- **Payment Gateway:** Razorpay orders, payments, and webhooks persist to Supabase PostgreSQL with `UNIQUE` event IDs and HMAC-SHA256 signature verification.

---

## 1. Architectural Architecture & Module Mapping

| Category | Component | Current Location | Corrected Architecture Target |
|:---|:---|:---|:---|
| **Auth & Identity** | Client Authentication | Firebase Auth SDK | **Firebase Auth** (unchanged). Tokens verified in Supabase using Firebase JWT secret/JWKS. |
| **RLS Auth Check** | Policy Identity Token | `auth.uid()` | `(auth.jwt()->>'sub')` matching `users.id` / `users.firebase_uid`. |
| **Role Claims** | `profile_claims` | `profile_claims/{uid}` Firestore | Cloud Function `syncUserClaimsOnProfileWrite` sets Firebase Auth Custom Claims directly via Admin SDK; role mirrors to `public.users.role`. |
| **Super Admin Access** | Admin Role Check | Firestore `super_admins` | Supabase `public.super_admins` table checked via `is_super_admin(auth.jwt()->>'sub')`. |
| **OTP Challenges** | 6-Digit Codes & Expiry | Firestore `otp_challenges` | **Redis** key `otp:challenge:{phone}` with `EX 600` (10-min TTL). |
| **Rate Limiting** | OTP Request & Verify Throttles | Firestore `otp_rate_limits` | **Redis** keys `otp:rate:send:{phone}` and `otp:rate:fail:{phone}` with atomic `INCR` + `EXPIRE`. |
| **Abuse Limits** | IP & Account Throttles | Firestore `abuse_rate_limits` | **Redis** keys `abuse:ip:{ip}` and `abuse:user:{uid}` with dynamic window sliding. |
| **SMS & Email** | MSG91 Gateway | Cloud Functions proxy | **Cloud Functions** via existing proxy/static IP (no Supabase Edge). |
| **Support Tickets** | Issues & Threads | Firestore `support_tickets` | Supabase `public.support_tickets` + `public.support_ticket_messages` (RLS `(auth.jwt()->>'sub')`). |
| **In-App Feed** | User Notification Center | In-app Firestore listener | Supabase `public.in_app_notifications` with Postgres change subscriptions. |
| **Mail Queue** | Outbound Email Dispatch | Firestore `mail_queue` | Supabase `public.mail_queue` with Cloud Functions poller/webhook via MSG91 proxy. |
| **Security Audit** | Security Events | Firestore `security_events` | Supabase `public.security_audit_events` (insert-only via service role). |
| **Razorpay Payments** | Orders & Webhooks | Firestore `razorpayPayments` | Supabase `public.razorpay_orders`, `public.razorpay_payments`, `public.razorpay_webhook_events`. |
| **Promoted Ads** | Doctor/Clinic Banners | Firestore `promotedAds` | Supabase `public.promoted_ads` + Private S3 `ad-banners/` via CloudFront OAC. |
| **Private Vault** | KYC, Reports, Avatars | Firebase Storage | AWS S3 Private Buckets with presigned upload/download URLs and Supabase `storage_audit_logs`. |

---

## 2. Phase E Detailed Implementation Sub-Phases

### Sub-Phase E.1: Auth-Critical Hardening (Redis, Claims, Super Admins, Account Deletion)

#### 1. OTP & Rate Limits to Redis
- Replace all Firestore reads/writes in `backend/functions/registration_otp.js` with Redis commands:
  - Challenge: `SET otp:challenge:${phone} ${hash} EX 600`
  - Send Rate Limit: `INCR otp:send:${phone}` $\rightarrow$ if 1st, `EXPIRE 600`. Max 3 per 10 min.
  - Fail Rate Limit: `INCR otp:fail:${phone}` $\rightarrow$ if 1st, `EXPIRE 3600`. Max 5 failed attempts.
  - Session Token: `SET otp:session:${sessionId} ${phone} EX 900`.
- Zero database bloat: ephemeral challenge records never touch PostgreSQL.

#### 2. Profile Claims & Super Admins
- `syncUserClaimsOnProfileWrite`: When `public.users` role is updated, a Database Webhook notifies Cloud Functions to call `admin.auth().setCustomUserClaims(uid, { role, profileId })`.
- `public.super_admins`: Table storing allowed super admin UIDs with RLS checking:
  ```sql
  CREATE OR REPLACE FUNCTION public.is_super_admin(check_uid TEXT)
  RETURNS BOOLEAN
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM public.super_admins WHERE user_uid = check_uid
    );
  END;
  $$;
  ```

#### 3. Complete `deleteMyAccount` Cascade
- Updated `deleteMyAccount` Cloud Function atomically deletes:
  1. All PostgreSQL rows across all tables linked to `user_id` / `profile_id`.
  2. All AWS S3 objects under prefixes `avatars/${uid}/`, `health-records/${uid}/`, `prescriptions/${uid}/`, etc.
  3. Firebase Authentication user account via `admin.auth().deleteUser(uid)`.

---

### Sub-Phase E.2: Support Tickets, In-App Notifications, Mail Queue, Security Events

#### 1. Support Tickets Schema & RLS
```sql
CREATE TYPE support_ticket_status AS ENUM ('open', 'in_progress', 'resolved', 'closed');
CREATE TYPE support_ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');

CREATE TABLE public.support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_uid TEXT NOT NULL, -- Firebase UID
    subject TEXT NOT NULL CHECK (char_length(trim(subject)) >= 3),
    category TEXT NOT NULL CHECK (char_length(trim(category)) >= 2),
    status support_ticket_status NOT NULL DEFAULT 'open',
    priority support_ticket_priority NOT NULL DEFAULT 'medium',
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ
);

CREATE TABLE public.support_ticket_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
    sender_uid TEXT NOT NULL, -- Firebase UID
    sender_role TEXT NOT NULL CHECK (sender_role IN ('patient', 'doctor', 'lab', 'medicalStore', 'ambulance', 'super_admin')),
    message TEXT NOT NULL CHECK (char_length(trim(message)) > 0),
    attachment_s3_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_ticket_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY support_tickets_select ON public.support_tickets
    FOR SELECT TO authenticated
    USING (user_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub'));

CREATE POLICY support_tickets_insert ON public.support_tickets
    FOR INSERT TO authenticated
    WITH CHECK (user_uid = (auth.jwt()->>'sub'));

CREATE POLICY support_messages_select ON public.support_ticket_messages
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.support_tickets t
            WHERE t.id = support_ticket_messages.ticket_id
            AND (t.user_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub'))
        )
    );

CREATE POLICY support_messages_insert ON public.support_ticket_messages
    FOR INSERT TO authenticated
    WITH CHECK (
        sender_uid = (auth.jwt()->>'sub') AND
        EXISTS (
            SELECT 1 FROM public.support_tickets t
            WHERE t.id = support_ticket_messages.ticket_id
            AND (t.user_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub'))
        )
    );
```

#### 2. In-App Notifications Feed
```sql
CREATE TABLE public.in_app_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_uid TEXT NOT NULL, -- Firebase UID
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT NOT NULL,
    action_url TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_read BOOLEAN NOT NULL DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.in_app_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY in_app_notifications_owner ON public.in_app_notifications
    FOR ALL TO authenticated
    USING (user_uid = (auth.jwt()->>'sub'))
    WITH CHECK (user_uid = (auth.jwt()->>'sub'));
```

#### 3. Mail Queue & MSG91 Proxy Dispatcher
- Table: `public.mail_queue` (`id UUID PRIMARY KEY`, `to_email TEXT`, `subject TEXT`, `template_id TEXT`, `variables JSONB`, `status TEXT`, `error TEXT`, `created_at TIMESTAMPTZ`).
- Cloud Functions poller or database webhook triggers dispatch through existing MSG91 proxy. Zero Supabase Edge Function dependency.

#### 4. Security Audit Events
```sql
CREATE TABLE public.security_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    actor_uid TEXT,
    ip_address TEXT,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.security_audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY security_audit_events_admin_select ON public.security_audit_events
    FOR SELECT TO authenticated
    USING (public.is_super_admin(auth.jwt()->>'sub'));
```

---

### Sub-Phase E.3: Razorpay Monetization & Promoted Ads

#### 1. Razorpay Orders, Payments & Webhooks
```sql
CREATE TABLE public.razorpay_orders (
    order_id TEXT PRIMARY KEY, -- e.g. order_EKfWjp82aTFCbA
    user_uid TEXT NOT NULL,
    ad_id UUID,
    amount_paise BIGINT NOT NULL CHECK (amount_paise > 0),
    currency TEXT NOT NULL DEFAULT 'INR',
    receipt TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'created',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.razorpay_payments (
    payment_id TEXT PRIMARY KEY, -- e.g. pay_29QQoUBcxNqdf0
    order_id TEXT NOT NULL REFERENCES public.razorpay_orders(order_id),
    signature TEXT NOT NULL,
    amount_paise BIGINT NOT NULL,
    status TEXT NOT NULL,
    method TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.razorpay_webhook_events (
    event_id TEXT PRIMARY KEY, -- Unique Razorpay webhook delivery ID
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.razorpay_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.razorpay_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.razorpay_webhook_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY razorpay_orders_owner ON public.razorpay_orders
    FOR SELECT TO authenticated
    USING (user_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub'));

CREATE POLICY razorpay_payments_owner ON public.razorpay_payments
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.razorpay_orders o
            WHERE o.order_id = razorpay_payments.order_id
            AND (o.user_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub'))
        )
    );
```

#### 2. Promoted Ads
```sql
CREATE TYPE ad_status AS ENUM ('draft', 'pending_review', 'approved', 'rejected', 'active', 'expired', 'paused');

CREATE TABLE public.promoted_ads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    advertiser_uid TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    target_url TEXT NOT NULL,
    banner_s3_key TEXT NOT NULL,
    status ad_status NOT NULL DEFAULT 'draft',
    tier TEXT NOT NULL DEFAULT 'standard',
    start_date DATE NOT NULL,
    end_date DATE NOT NULL CHECK (end_date >= start_date),
    impressions INT NOT NULL DEFAULT 0,
    clicks INT NOT NULL DEFAULT 0,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.promoted_ads ENABLE ROW LEVEL SECURITY;

-- Public can read approved active ads
CREATE POLICY promoted_ads_public_select ON public.promoted_ads
    FOR SELECT TO authenticated
    USING (status = 'active' OR advertiser_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub'));

CREATE POLICY promoted_ads_advertiser_write ON public.promoted_ads
    FOR INSERT TO authenticated
    WITH CHECK (advertiser_uid = (auth.jwt()->>'sub'));
```

---

### Sub-Phase E.4: Complete Private S3 Storage Migration

All file storage strictly uses private AWS S3 buckets:
- **Banner Images & KYC Docs:** Private S3 bucket `s3://${AWS_S3_BUCKET_NAME}/ad-banners/` accessed via CloudFront OAC with signed URLs or presigned S3 URLs.
- **Avatars & Lab Reports:** `avatars/` and `lab-reports/` generated via presigned PUT/GET URLs from `S3StorageService`.
- **Zero Public Buckets:** S3 Block Public Access is 100% enforced.

---

## 3. Backward Compatibility & Gating Invariant

Every Phase E client repository and API path remains behind `DoctorPatientCutoverFlag.isEnabled` until final Stage 2 cutover approval. Legacy Firestore routes remain active as fallback until staging verification is complete.
