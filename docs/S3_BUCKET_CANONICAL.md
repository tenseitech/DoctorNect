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
- **Resolver:** `backend/functions/src/config/s3_bucket.js` → `getS3BucketName()`
- **Legacy fallback:** `S3_BUCKET_NAME`, `AWS_S3_VAULT_BUCKET` read **only** inside helper until **2026-06-30** (TODO).

## Same bucket when `S3_BUCKET` is set in deploy env?

| Consumer | Resolves to same bucket as `getS3BucketName()`? |
|----------|--------------------------------------------------|
| `s3_storage.js` | **yes** |
| `delete_my_account.js` | **yes** (previously **no** — used different string default) |

When `S3_BUCKET` is unset, all callers share the same helper fallback chain (including legacy names until TODO removal).
