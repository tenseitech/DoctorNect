# Terraform remote state (S3 + native lockfile)

**Terraform >= 1.10** (`use_lockfile` on the S3 backend). DoctorNect operators: confirm with `terraform version`.

**Do not run `terraform init -migrate-state` until you approve** and the state bucket exists.

## 1) Create bucket (operator — ap-south-1)

```bash
aws s3api create-bucket \
  --bucket doctornect-terraform-state-<AWS_ACCOUNT_ID> \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

aws s3api put-bucket-versioning \
  --bucket doctornect-terraform-state-<AWS_ACCOUNT_ID> \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket doctornect-terraform-state-<AWS_ACCOUNT_ID> \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket doctornect-terraform-state-<AWS_ACCOUNT_ID> \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## 2) State locking (no DynamoDB)

With `use_lockfile = true`, Terraform writes a lock object next to state, e.g.  
`production/gateway/terraform.tfstate.tflock`.  
No DynamoDB table is required.

## 3) Enable backend in repo

`infra/aws/backend.tf` matches `backend.tf.example` (S3 + `use_lockfile`). **Do not run `terraform init` until the bucket exists and you confirm.**

1. While using local state for plans, temporarily rename `backend.tf` → `backend.tf.off` **or** init only after step 1.
2. `cd infra/aws && terraform init -migrate-state` (answer **yes** to copy existing local state).
3. Prefer committing `backend.tf.example` + this doc; keep the bucket name in sync with `backend.tf`.

## IAM for state

The Terraform operator needs on **`doctornect-terraform-state-<AWS_ACCOUNT_ID>`**:

| Scope | Actions |
|-------|---------|
| Bucket | `s3:ListBucket`, `s3:GetBucketVersioning`, `s3:GetEncryptionConfiguration` |
| Objects `/*` (state + `.tflock`) | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` |

Lock acquisition/release uses **PutObject** / **DeleteObject** (and **GetObject**) on the `*.tflock` key under the same prefix as `key` in `backend.tf`.

Attach **three** customer-managed policies to `doctornect-terraform` (each file &lt; 6 KB IAM quota):

- `docs/ops/IAM_TERRAFORM_OPERATOR.json` — AWS resources for `infra/aws`
- `docs/ops/IAM_TERRAFORM_OPERATOR_IAM.json` — `doctornect-production-*` IAM roles/policies + PassRole
- `docs/ops/IAM_TERRAFORM_OPERATOR_STATE.json` — Terraform S3 state bucket + lock objects