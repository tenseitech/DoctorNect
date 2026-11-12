# S3 orphans when confirmUpload fails

## Idempotent confirm

`confirmS3UploadHandler` re-validates via HeadObject and re-applies the same metadata to Postgres or Firestore. Calling it N times after a successful PUT does not create duplicate objects or rotate keys.

## If confirm fails after client retries

1. **Client (implemented):** `S3StorageService.uploadBytes` catches `StorageException(code: confirm-failed)` and best-effort `deleteObject(objectKey)` via presigned delete API.
2. **Server (validation failures):** invalid HEAD/size/type triggers `DeleteObjectCommand` in the handler.
3. **Lifecycle (recommended ops):** bucket rule on `lab_reports/`, `health_records/` prefix — abort incomplete multipart uploads after 7d; optional tag-based expiry for keys never referenced in `lab_bookings.report_storage_key` (requires nightly janitor comparing DB).

No automatic server retry queue exists today; re-call `confirmS3Upload` with the same `objectKey` once network/auth is healthy.
