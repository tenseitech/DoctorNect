# RUNBOOK — Storage failure

**Symptoms:** Upload/presign failures; S3 403/5xx in Functions logs.

**Severity:** SEV-2 for lab report / KYC workflows.

## Triage

1. Functions logs for `s3_storage` errors.
2. AWS S3 health / IAM role on task (**OPERATOR ACTION**).

## Recovery

- Fix IAM policy; rotate keys.
- Confirm path uses confirm idempotency (Audit 6).

## Verification

`s3_storage.test.js` relevant cases; staging presign+confirm with test object.