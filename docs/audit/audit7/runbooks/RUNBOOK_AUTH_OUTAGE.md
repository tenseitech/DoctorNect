# RUNBOOK — Authentication outage

**Symptoms:** Login/OTP failures; spike in `auth.failure` logs; Firebase Auth dashboard errors.

**Severity:** SEV-1.

## Triage

1. Firebase Status; MSG91/Razorpay if OTP/payment coupled.
2. Search logs `category=auth`.
3. Verify App Check / API keys not expired (**OPERATOR ACTION**).

## Recovery

- Roll back auth-related Functions deploy.
- Rotate compromised keys if security incident.

## Verification

Staging login E2E with test account (**NON-PRODUCTION TEST**).