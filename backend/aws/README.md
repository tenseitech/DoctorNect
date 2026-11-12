# AWS S3 Storage Configuration & Deployment Guide

This directory contains AWS IAM and S3 configuration templates for DoctorNect's media and health record storage.

---

## 1. Environment Placeholders

Before applying the JSON templates to AWS, replace the following placeholders with your environment-specific values:

| Placeholder | Description | Example Value |
|---|---|---|
| `${S3_BUCKET}` | AWS S3 bucket name | `doctornect-staging` or `doctornect-prod` |
| `${ALLOWED_ORIGIN_PROD}` | Primary web domain | `https://doctornect.com` |
| `${ALLOWED_ORIGIN_APP}` | Application web domain | `https://app.doctornect.com` |
| `${ALLOWED_ORIGIN_LOCAL_1}` | Local development origin | `http://localhost:3000` |
| `${ALLOWED_ORIGIN_LOCAL_2}` | Local staging/mobile web origin | `http://localhost:5000` |

---

## 2. Encryption Architecture (SSE-S3 AES-256)

All objects uploaded to DoctorNect S3 buckets are encrypted at rest using server-side encryption with Amazon S3 managed keys (**SSE-S3 AES-256**).

### Why "Deny Missing SSE Header" Was Removed
- Since January 5, 2023, Amazon S3 automatically applies SSE-S3 encryption as default to all bucket objects without any client configuration.
- Client uploads using presigned PUT URLs should **not** be required to supply `x-amz-server-side-encryption: AES256` HTTP headers, as missing or mismatched client headers would needlessly reject valid client uploads while default encryption is already enforced at the bucket level.
- `s3_bucket_policy.json` enforces TLS via `EnforceTLSRequestsOnly` (`aws:SecureTransport: "false"`), guaranteeing that all data in transit is encrypted.

---

## 3. Deployment Commands (AWS CLI)

Run these commands using the AWS CLI configured with administrator or storage-admin credentials:

### Step 1: Create S3 Bucket (if not already created)
```bash
export BUCKET_NAME="doctornect-prod"
export AWS_REGION="ap-south-1"

aws s3api create-bucket \
  --bucket "${BUCKET_NAME}" \
  --region "${AWS_REGION}" \
  --create-bucket-configuration LocationConstraint="${AWS_REGION}"
```

### Step 2: Enable Bucket Default SSE-S3 Encryption
```bash
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'
```

### Step 3: Block Public Access
```bash
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'
```

### Step 4: Apply CORS Policy
Substitute placeholders and apply `cors.json`:
```bash
sed -e "s|\${ALLOWED_ORIGIN_PROD}|https://doctornect.com|g" \
    -e "s|\${ALLOWED_ORIGIN_APP}|https://app.doctornect.com|g" \
    -e "s|\${ALLOWED_ORIGIN_LOCAL_1}|http://localhost:3000|g" \
    -e "s|\${ALLOWED_ORIGIN_LOCAL_2}|http://localhost:5000|g" \
    backend/aws/cors.json > /tmp/cors_resolved.json

aws s3api put-bucket-cors \
  --bucket "${BUCKET_NAME}" \
  --cors-configuration file:///tmp/cors_resolved.json
```

### Step 5: Apply Bucket Policy (Enforce TLS)
Substitute `${S3_BUCKET}` and apply `s3_bucket_policy.json`:
```bash
sed -e "s|\${S3_BUCKET}|${BUCKET_NAME}|g" \
    backend/aws/s3_bucket_policy.json > /tmp/bucket_policy_resolved.json

aws s3api put-bucket-policy \
  --bucket "${BUCKET_NAME}" \
  --policy file:///tmp/bucket_policy_resolved.json
```

### Step 6: Create Backend IAM Service Account Policy
Substitute `${S3_BUCKET}` in `iam_policy.json` and attach to Cloud Functions IAM role:
```bash
sed -e "s|\${S3_BUCKET}|${BUCKET_NAME}|g" \
    backend/aws/iam_policy.json > /tmp/iam_policy_resolved.json

aws iam create-policy \
  --policy-name DoctorNectS3AccessPolicy \
  --policy-document file:///tmp/iam_policy_resolved.json
```
