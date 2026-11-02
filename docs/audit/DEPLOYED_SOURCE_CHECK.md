# Deployed Cloud Functions source verification (read-only)

Use this to confirm production **`verifyUserRegistrationOtp`**, **`completeMobileOtpLogin`**, **`sendUserRegistrationOtp`**, and **`lookupMobileRegistration`** match git commit **`9883f00`** (Oct 24 functions tip per `DEPLOY_HASH_COHORT.md`).

**Do not paste secret values.** Bucket/object names and hashes only.

---

## 1. Resolve storage location per function

Replace `<PROJECT>`, `<REGION>`, and function names as needed (Gen2 callables on Cloud Run).

```powershell
$project = "<FIREBASE_PROJECT_ID>"
$region = "asia-south1"
$fn = "verifyUserRegistrationOtp"

gcloud functions describe $fn `
  --gen2 `
  --region=$region `
  --project=$project `
  --format="yaml(buildConfig.source.storageSource.bucket,buildConfig.source.storageSource.object)"
```

Repeat for:

- `completeMobileOtpLogin`
- `sendUserRegistrationOtp`
- `lookupMobileRegistration`

Record **bucket** and **object** names only (no download URLs with tokens in shared logs).

---

## 2. Download and extract source archive

```powershell
$bucket = "<BUCKET_FROM_DESCRIBE>"
$object = "<OBJECT_FROM_DESCRIBE>"
$dest = "$env:TEMP\doctornect-fn-source.zip"

gcloud storage cp "gs://$bucket/$object" $dest --project=$project
Expand-Archive -Path $dest -DestinationPath "$env:TEMP\doctornect-fn-source" -Force
```

Locate extracted paths (layout varies by build):

- `backend/functions/registration_otp.js`
- `backend/functions/index.js`

---

## 3. Hash and compare to git

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor

git hash-object --no-filters (git show 9883f00:backend/functions/registration_otp.js | Out-String | Set-Content -Path "$env:TEMP\reg9883.js" -Encoding utf8; git hash-object --no-filters "$env:TEMP\reg9883.js")

git hash-object --no-filters "$env:TEMP\doctornect-fn-source\...\registration_otp.js"
git hash-object --no-filters "$env:TEMP\doctornect-fn-source\...\index.js"
git hash-object --no-filters (git show 9883f00:backend/functions/index.js)
```

**Known reference blob (Oct 24 tip, local clone):**

| File | `9883f00` blob SHA |
|------|---------------------|
| `backend/functions/registration_otp.js` | `7805656b85bbb065f13ea446a2d5d5f461686b1c` |

---

## 4. Interpret results

| Outcome | Meaning |
|---------|---------|
| Deployed `registration_otp.js` hash **matches** `9883f00` | **Proxy confirmed** — hotfix base commit is correct for OTP modules. |
| **Mismatch** | Deployed from a **different commit** or **uncommitted** build-time edits. Diff deployed file vs `git show 9883f00:backend/functions/registration_otp.js` (names/lines only in notes). |
| `index.js` mismatch but `registration_otp.js` match | Callable wiring may differ; hotfix-only deploy of two functions still uses local `index.js` at deploy time — prefer deploying from **`..\doctor-hotfix`** tree with minimal `registration_otp.js` patch. |

---

## 5. Optional: revision metadata

```powershell
gcloud run services describe verifyuserregistrationotp `
  --region=$region `
  --project=$project `
  --format="value(status.latestReadyRevisionName,metadata.annotations)"
```

Compare revision create time to **2026-10-24T06:18Z** deploy window (operator calendar).
