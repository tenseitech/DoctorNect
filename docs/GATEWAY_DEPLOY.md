# Deploy the production gateway (auth-gateway + PostgREST on AWS ECS) and the production S3 bucket

The Cloud Functions in production talk to the AWS RDS database **only** through this gateway
(`PROD_GATEWAY_URL=https://api.doctornect.com`). Until the gateway answers on that address, do
**not** deploy the Functions with `APP_ENV=production`: every real-user database call would fail.
Do not "fix" that by pointing production at the staging Supabase project or by weakening
`check:boot-env`.

## Where things stand (checked 2026-11-26)

| Piece | State |
|---|---|
| RDS (PostgreSQL 18, private, encrypted) | exists |
| ECS cluster, task definition, IAM roles, log group, security groups, ALB target group | exist (Terraform state of 2026-11-23) |
| Secrets Manager entries (rds_credentials, postgrest_jwt_secret, gateway_service_key, demo-routing) | exist, values not verifiable from here |
| ECS **service**, **ALB** + HTTPS listener, alarms | **not created** (they were only in a saved plan) |
| DNS `api.doctornect.com` | **no record** |
| ECR repositories in Terraform, PostgREST image with the RDS CA | **missing** (added now: `infra/aws/ecr.tf`, `services/postgrest`) |
| Gateway `ANON_KEY`, Firebase Admin credential, CORS, proxy hops in the task | **missing** (added now) |
| Separate production S3 bucket | **missing** (added now: `infra/aws/s3.tf`); staging and production use the same bucket today |

## What you need once

1. **AWS CLI v2**: download and run `https://awscli.amazonaws.com/AWSCLIV2.msi`. Then
   `aws configure` with an access key of an AWS admin user (region `ap-south-1`).
   Success: `aws sts get-caller-identity` shows your account number.
2. **Terraform**: `winget install Hashicorp.Terraform`. Success: `terraform version` shows 1.10 or newer.
3. **Docker Desktop** running. Success: `docker info` works.
4. You are logged in to Firebase: `firebase login`. Success: `firebase projects:list` shows `medibond-45fad`.

All commands below run in PowerShell from the repository folder unless a step says `cd`.

## Step 1. Check for ECR repositories that already exist

```powershell
aws ecr describe-repositories --region ap-south-1 --query "repositories[].repositoryName"
```

If the list contains `doctornect-auth-gateway` and/or `doctornect-postgrest`, tell Terraform about
them (otherwise skip):

```powershell
cd infra/aws
terraform init
terraform import aws_ecr_repository.auth_gateway doctornect-auth-gateway
terraform import aws_ecr_repository.postgrest doctornect-postgrest
```

## Step 2. Create the AWS pieces (service still at 0 tasks)

`infra/aws/terraform.tfvars` (git-ignored) already has the bucket names and `ecs_desired_count = 0`.

```powershell
cd infra/aws
terraform init
terraform plan -out tfplan
```

Read the plan summary. It should **create**: 2 ECR repositories + lifecycle policy, the ECS service,
the ALB + HTTPS listener, 2 alarms, the `gateway-firebase-admin` secret, the production S3 bucket
and its log bucket (+ public-access block, encryption, versioning, lifecycle, CORS, TLS-only policy,
logging), 2 IAM policies, 1 IAM user. It should **update** the task definition and the secrets
IAM policy. It must **not destroy** anything. If it wants to destroy something, stop and ask.

```powershell
terraform apply tfplan
```

Success: `terraform output` prints `alb_dns_name`, `ecr_auth_gateway_url`, `s3_production_bucket`.

## Step 3. Build and push the two images

```powershell
powershell -ExecutionPolicy Bypass -File infra/aws/build_push_images.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File infra/aws/build_push_images.ps1
```

Success: "Pushed both images and updated gateway_image / postgrest_image in terraform.tfvars."
The PostgREST image carries the AWS RDS CA bundle, so it can use `sslmode=verify-full`.

## Step 4. Firebase key for the gateway (token revocation check)

1. Open `https://console.cloud.google.com/iam-admin/serviceaccounts?project=medibond-45fad`.
2. **Create service account**, name `gateway-revocation`. Role: **Firebase Authentication Viewer**
   (nothing else). Done.
3. Open it > **Keys** > **Add key** > **Create new key** > **JSON**. A file downloads.

Keep the file only until step 6 finishes, then delete it.

## Step 5. Password for the RDS `authenticator` role

PostgREST logs in to RDS as `authenticator`. Through your usual RDS tunnel
(`docs/runbooks/RDS_PROD_TUNNEL_WINDOWS.md`), open psql as the admin user and run:

```
\password authenticator
```

Type a new long password twice (psql hides it and sends only a hash). Keep it for step 6.

## Step 6. Fill the gateway secrets (no copy-paste of generated values)

```powershell
powershell -ExecutionPolicy Bypass -File infra/aws/set_gateway_secrets.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File infra/aws/set_gateway_secrets.ps1 -FirebaseKeyFile "C:\path\to\downloaded-key.json"
```

It asks (hidden input) for the step-5 password and for the staging Supabase **JWT secret**
(Supabase dashboard > Project Settings > API > JWT secret). It generates the rest:
`service_key` (48 random bytes; also stored in Firebase as `PROD_GATEWAY_SERVICE_KEY`),
`anon_key`, `jwt_secret`. Nothing is printed. Delete the downloaded JSON file afterwards.

Secrets used (AWS Secrets Manager, prefix `doctornect/production/`):

| Secret | JSON keys |
|---|---|
| `gateway_service_key_*` | `service_key`, `anon_key` |
| `postgrest_jwt_secret_*` | `jwt_secret` |
| `rds_credentials_*` | `connection_string` = `postgres://authenticator:<pw>@<rds>:5432/doctornect?sslmode=verify-full&sslrootcert=/etc/ssl/rds/global-bundle.pem` |
| `demo-routing` | `DEMO_PGRST_URL`, `DEMO_PGRST_JWT_SECRET`, `DEMO_FIREBASE_UID_ALLOWLIST` |
| `gateway-firebase-admin` | `firebase_service_account_json` |

## Step 7. Start the gateway

Edit `infra/aws/terraform.tfvars`: `ecs_desired_count = 1`. Then:

```powershell
cd infra/aws
terraform plan -out tfplan
terraform apply tfplan
```

Success: AWS console > ECS > `doctornect-production-cluster` > service shows 1 running task, and
the target group shows the target **healthy** (a few minutes). If the task stops, open
CloudWatch > Log groups > the ECS log group: the first error line names the missing setting.

## Step 8. DNS

At the company that hosts the `doctornect.com` DNS, add a **CNAME** record:
`api` -> the value of `terraform output -raw alb_dns_name`. (Route 53: an **A / Alias** record to the
ALB instead.) The ACM certificate in `acm_certificate_arn` must cover `api.doctornect.com`.

Success (can take up to an hour):

```powershell
curl.exe -s -o NUL -w "%{http_code}" https://api.doctornect.com/healthz
```

prints `200`.

## Step 9. Production S3 bucket for the Functions

1. Put the bucket name in `.env`: `S3_BUCKET_PRODUCTION=` the value of
   `terraform output -raw s3_production_bucket`. Keep `S3_BUCKET_STAGING` as it is, and empty the
   legacy `S3_BUCKET=` line.
2. IAM console > Users > `doctornect-functions-s3-production` > **Security credentials** >
   **Create access key** (use case: application outside AWS). Then store it in Firebase (hidden
   prompts, nothing printed):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1 -Only AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY -PromptAll -Replace
   ```
3. The staging Functions' IAM user gets the staging-only policy:
   `terraform output -raw functions_s3_staging_policy_arn` > attach it to that user in the IAM
   console and remove its broader S3 policies.
4. Real-user files already in the staging bucket under `prod/`? Copy them once before switching:
   `aws s3 sync s3://<staging-bucket>/prod/ s3://<production-bucket>/prod/` (none expected before launch).

## Step 10. Functions secrets and final check

```powershell
powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1
npm run check:boot-env -- .env --target=functions --check-secret-manager
```

Success: `0 FAIL`. Only then deploy the Functions (`firebase deploy --only functions --project medibond-45fad`).

## Rollback

- Gateway: set `ecs_desired_count = 0` and apply (stops the tasks; nothing is deleted).
- The production bucket has `prevent_destroy`; Terraform cannot delete it by accident.
