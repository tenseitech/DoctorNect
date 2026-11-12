# S3 bucket env — canonical `S3_BUCKET` (names only)

## Readers before consolidation

| Name | Location | Role |
|------|----------|------|
| `S3_BUCKET` | `s3_storage.js` (module const) | Presigned upload/download/delete; audit field writes |
| `S3_BUCKET_NAME` | `s3_storage.js` (fallback chain) | **Removed** — use helper |
| `AWS_S3_VAULT_BUCKET` | `s3_storage.js` (fallback chain) | **Removed** — use helper |
| `S3_BUCKET` | `delete_my_account.js` | User S3 prefix cleanup on account delete |
| `AWS_S3_VAULT_BUCKET` | `frontend/.../app_environment.dart` | **Removed** — getter was unused (no imports) |

## After consolidation

- **Canonical env name:** `S3_BUCKET`
- **Resolver:** `backend/functions/src/config/s3_bucket.js` → `getS3BucketName()` / lazy `resolveS3Bucket()`
- **Legacy aliases:** removed from helper (no `S3_BUCKET_NAME` / `AWS_S3_VAULT_BUCKET` reads). **Fail-fast** if `S3_BUCKET` is unset (`failed-precondition`).
- **Tests:** `test/setup_env.js` sets a dummy bucket when `.env` is absent.

## Historical default (removed)

| Location | Old default string | Matched real vault bucket? |
|----------|-------------------|----------------------------|
| `delete_my_account.js` | `doctornect` | **No** — presign path used a different hardcoded regional name |

## Deployed env (names only, sample 2026-10-31)

| Function | `S3_BUCKET` | `S3_BUCKET_NAME` | `AWS_S3_VAULT_BUCKET` |
|----------|-------------|------------------|------------------------|
| `getS3UploadUrl` | present | absent | absent |
| `deleteS3Object` | present | absent | absent |
| `deleteMyAccount` | present | present (legacy) | present (legacy) |

All three have **`S3_BUCKET`** — safe to deploy code that requires it only. Recommend dropping legacy alias keys on `deleteMyAccount` at next deploy (code ignores them).

## Same bucket when `S3_BUCKET` is set in deploy env?

| Consumer | Resolves to same bucket as `getS3BucketName()`? |
|----------|--------------------------------------------------|
| `s3_storage.js` | **yes** |
| `delete_my_account.js` | **yes** |
