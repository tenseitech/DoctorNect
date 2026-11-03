# `.env.bak-before-guard-fix` — deployed source exposure (read-only)

**No secret values.** Variable **names** only. **Do not run mutating `gcloud` or delete bucket objects by hand.**

---

## Facts (operator attestation)

| Item | Detail |
|------|--------|
| **File** | `backend/functions/.env.bak-before-guard-fix` (local scratch backup; see `docs/ops/CLEANUP_MANIFEST.md`) |
| **Exposure** | Present inside **deployed Cloud Functions Gen2 source zip** objects for **14** functions (each function has its own object under the regional sources bucket) |
| **Bucket** | `gcf-v2-sources-658118593597-asia-south1` |
| **Bucket IAM (legacy)** | Access limited to project **Owner / Editor / Viewer** legacy roles (no broad public read) |
| **Remediation** | **Redeploy each affected function** from a tree that excludes the file (`firebase.json` `functions.ignore`: `**/.env*`, `**/*.bak*`, …). Each redeploy **overwrites** that function’s zip object at its per-function path. **Do not** delete zip objects manually (risk of broken deploy state / race with Firebase). |

### Fourteen functions (source zips contained the backup path)

Operator zip inventory — Gen2 function names:

1. `sendUserRegistrationOtp`  
2. `verifyUserRegistrationOtp`  
3. `lookupMobileRegistration`  
4. `finalizePatientOtpVerification`  
5. `resetUserPasswordWithOtp`  
6. `resetAmbulanceDriverPin`  
7. `completeMobileOtpLogin`  
8. `completeAmbulanceMobileOtpLogin`  
9. `getS3UploadUrl`  
10. `getS3DownloadUrl`  
11. `getS3DownloadUrls`  
12. `deleteS3Object`  
13. `deleteMyAccount`  
14. `createRazorpayOrder`  

Re-verify with the read-only listing loop below before relying on this list for compliance evidence.

### Variable **names** set in the backup file (no values)

The backup was a copy of deploy-time `backend/functions/.env` taken before production OTP guard work. Key names present (non-comment), aligned with contemporary functions `.env` inventory:

`ACCOUNT_APPROVAL_ADMIN_EMAILS`, `AMBULANCE_HTTP_ALLOWED_ORIGINS`, `AWS_REGION`, `BACKFILL_ADMIN_EMAILS`, `ENABLE_SUPABASE_SYNC`, `ENFORCE_ABUSE_APP_CHECK`, `ENFORCE_AMBULANCE_HTTP_APP_CHECK`, `ENFORCE_OTP_APP_CHECK`, `MSG91_AUTH_KEY`, `MSG91_EMAIL_DOMAIN`, `MSG91_FROM_EMAIL`, `MSG91_PROXY_URL`, `MSG91_SENDER_ID`, `MSG91_TEMPLATE_ID`, `MSG91_TEMPLATE_ID_LOGIN`, `MSG91_TEMPLATE_ID_PASSWORD_RESET`, `MSG91_TEMPLATE_ID_REGISTRATION`, `OTP_REDIS_MIRROR`, `OTP_TEST_MODE`, `RATE_LIMIT_BACKEND`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `REDIS_HOST`, `REDIS_PASSWORD`, `REDIS_PORT`, `REDIS_TLS`, `REVIEW_ACCESS_UNTIL`, `REVIEW_FIXED_OTP`, `REVIEW_TEST_NUMBERS`, `S3_BUCKET`, `S3_URL_CACHE`, `SUPABASE_ANON_KEY`, `SUPABASE_JWKS_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_URL`, `USE_S3_STORAGE`, `USE_SUPABASE_DB_DOCTOR_PATIENT`

Treat any name in this list as **potentially exposed** in historical zips until that function’s source object is replaced by a clean redeploy. Rotate credentials per `ROTATION_RUNBOOK.md` if exposure window matters for your threat model.

---

## Read-only: confirm zip contains backup path

Replace function name; **list/read only**:

```powershell
$project = "658118593597"
$region = "asia-south1"
$fn = "sendUserRegistrationOtp"
# Object layout varies by generation; list prefix first:
gsutil ls "gs://gcf-v2-sources-${project}-${region}/**" 2>$null | Select-String $fn
```

Download to temp and list archive paths **without printing file contents**:

```powershell
# After locating object URI from ls:
gsutil cp "gs://gcf-v2-sources-.../..." "$env:TEMP\fn-source.zip"
tar -tf "$env:TEMP\fn-source.zip" 2>$null | Select-String "\.env\.bak-before-guard-fix"
```

---

## Read-only: Artifact Registry `gcf-artifacts` images (dates)

Built container images may still exist after source zip overwrite. **List only** (judge whether layers might predate ignore fix):

```powershell
gcloud artifacts docker images list `
  asia-south1-docker.pkg.dev/medibond-45fad/gcf-artifacts `
  --include-tags `
  --format="table(package,version,createTime,updateTime)" `
  --limit=200
```

Filter by function / revision tag in console or add `--filter` on package path once you know the image name pattern for a given export.

**Agent constraint:** do not execute these commands from automated audit passes if project policy forbids `gcloud`; operator runs locally with read-only IAM.

---

## Related

- `docs/audit/ENV_BACKUP_COMMIT_PROPOSAL.md` — move local backup out of repo  
- `docs/audit/FIREBASE_IGNORE_PROPOSAL.md` — ignore rules now in `firebase.json`  
- `docs/audit/PLAIN_VS_SECRET_OVERLAP.md` — post-redeploy env hygiene  
