# Open issues (from archived security audits)

Consolidated from `docs/archive/verification/SECURITY_AUDIT_2026-10-06.md` and `SECURITY_AUDIT_v2.md`. **Status** reflects audit date unless a later spine doc says fixed. Verification spine: [reports/DOCTORNECT_FINAL_AUDIT.md](reports/DOCTORNECT_FINAL_AUDIT.md), [ops/ARCHITECTURE_CUTOVER_REPORT.md](ops/ARCHITECTURE_CUTOVER_REPORT.md).

| ID | Title | Severity | Status | Source |
|----|--------|----------|--------|--------|
| SEC-05 | Unvetted doctor auto-approval on `completeMobileOtpLogin` | Critical | Open — verify in current `registration_otp.js` | SECURITY_AUDIT v1/v2 |
| SEC-12 | Appointment update rules allow sensitive field tampering | High | Open — rules may have changed; re-verify Firestore rules | SECURITY_AUDIT v1/v2 |
| SEC-13 | Public doctor PII readable without auth | Medium | Partial — Postgres cutover reduces Firestore exposure; confirm RLS/public views | SECURITY_AUDIT v1/v2 |
| SEC-15 | Hosting CSP omitted S3 origins for web | High | Open if web S3 enabled | SECURITY_AUDIT v1 |
| SEC-18 | Bulk deploy could enable undeployed Supabase sync triggers | High | Open — confirm `index.js` exports vs deployed set | SECURITY_AUDIT v1 |
| SEC-22 | `deleteMyAccount` Supabase Postgres erasure gap | High | Partial — Supabase paths added; confirm all tables | SECURITY_AUDIT v2 |
| SEC-23 | Client-side appointment create bypasses slot capacity | High | Open — Firestore rules vs callable-only booking | SECURITY_AUDIT v2 |
| SEC-09 | Ambulance mobile OTP reinstall / `authUid` linkage | Medium | Verify current ambulance OTP login path | SECURITY_AUDIT v2 |
| GAP-01 | 18 Supabase Firestore sync triggers exported but not deployed | High | Open — architecture is Postgres-primary; triggers may be dead code | SECURITY_AUDIT v2 |
| GAP-02 | Orphan deployed function `ssrmedibond45fad` (us-central1) | Medium | Unknown — confirm traffic / decommission | SECURITY_AUDIT v2 |
| GAP-03 | `razorpayWebhook` not deployed while code exists | High | Unknown — confirm production deploy list | SECURITY_AUDIT v2 |
| OPS-01 | MSG91 portal spend cap not documented as configured | Low | Unknown | SECURITY_AUDIT v2 |
| OPS-02 | `app_config/demo_accounts` in production Firestore | Medium | Unknown | SECURITY_AUDIT v2 |
| OPS-03 | Orphan callables `sendOtp` / `verifyOtp` | Medium | CTRL-04 claims retired — confirm live | SECURITY_AUDIT v2 |

Do not treat this list as a pentest sign-off; re-validate against current code and deployment after `gcloud auth login`.
