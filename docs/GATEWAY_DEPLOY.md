# Deploy the production gateway (auth-gateway + PostgREST on AWS ECS) and the production S3 bucket

The Cloud Functions in production talk to the AWS RDS database **only** through this gateway
(`PROD_GATEWAY_URL=https://api.doctornect.com`). Until the gateway answers on that address, do
**not** deploy the Functions with `APP_ENV=production`: every real-user database call would fail.
Do not "fix" that by pointing production at the staging Supabase project or by weakening
`check:boot-env`.

## Where things stand (AWS read-only check, 2026-11-26 afternoon)

| Piece | State |
|---|---|
| ALB + HTTPS listener (443, TLS 1.3 policy) with the ACM certificate for `api.doctornect.com` | **done** (certificate issued, in use) |
| Target group (HTTP 3000, health check `/healthz`) attached to the ALB | **done** |
| ECR repositories + images (`doctornect-auth-gateway`, `doctornect-postgrest` with the RDS CA) | **done** (pushed, tag = git SHA) |
| ECS cluster + service | exists, **desired count 0** |
| Task definition | revision 2 still uses `:latest` + the stock PostgREST image; the next apply switches to the pushed images |
| Secrets Manager: rds_credentials, postgrest_jwt_secret, gateway_service_key, demo-routing, gateway-firebase-admin | exist, **all 5 have no value yet** |
| DNS `api.doctornect.com` | **no record** |
| RDS `doctornect-prod` | available, private, deletion protection on; migration ledger not readable from here (needs the tunnel) |
| Bastion for the SSM tunnel | `doctornect-bastion` is running |

## What is left, shortest path (in this order)

1. **Tunnel tools**: install the Session Manager plugin
   (`https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe`).
   Use an AWS profile that may call `ssm:StartSession`, `rds:CreateDBSnapshot` and
   `rds:DescribeDBSnapshots` (the `doctornect-terraform` user may not).
2. **Snapshot RDS first** (safety net, ~10 min):
   ```powershell
   aws rds create-db-snapshot --db-instance-identifier doctornect-prod --db-snapshot-identifier doctornect-prod-pre-migrate-20261126 --region ap-south-1
   aws rds wait db-snapshot-available --db-snapshot-identifier doctornect-prod-pre-migrate-20261126 --region ap-south-1
   ```
3. **Open the tunnel** (terminal 1, keep it open). `.env` must have `PROD_RDS_HOST` (real endpoint),
   `PROD_RDS_CONNECT_HOST=127.0.0.1`, `PROD_RDS_PORT=5433`:
   ```powershell
   $ep = (aws rds describe-db-instances --db-instance-identifier doctornect-prod --region ap-south-1 --query "DBInstances[0].Endpoint.Address" --output text)
   $bastion = (aws ec2 describe-instances --region ap-south-1 --filters "Name=tag:Name,Values=doctornect-bastion" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
   aws ssm start-session --region ap-south-1 --target $bastion --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "host=$ep,portNumber=5432,localPortNumber=5433"
   ```
4. **Migrations on RDS** (terminal 2, repo root). Dry run first, read the "Pending migration files"
   list (expected: the seven 20261124000001 ... 20261125000004 files, the same ones staging got), then apply:
   ```powershell
   $h = (node -e "const {getHostFingerprint}=require('./scripts/lib/env_guard');const {getEnv}=require('./scripts/lib/env_loader');console.log(getHostFingerprint(getEnv('PROD_RDS_HOST')))")
   node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data --confirm=$h --confirm-db=doctornect
   node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm=$h --confirm-db=doctornect
   psql "postgresql://<admin-user>@127.0.0.1:5433/doctornect?sslmode=require" -v ON_ERROR_STOP=1 -f db/rds_bootstrap/04_rds_runtime_grants.sql
   ```
   Success: "Applied this run: 7" (or the number the dry run listed) and psql ends without ERROR.
5. **Password for `authenticator`** (same tunnel): `psql "postgresql://<admin-user>@127.0.0.1:5433/doctornect?sslmode=require"`,
   then `\password authenticator` (hidden input). Keep it for step 7.
6. **Firebase key for the gateway**: Google Cloud console > IAM > Service accounts (project
   medibond-45fad) > create `gateway-revocation`, role **Firebase Authentication Viewer** only >
   Keys > Add key > JSON.
7. **Gateway secrets** (asks for the step-5 password and the staging JWT secret; generates the rest,
   also stores `PROD_GATEWAY_SERVICE_KEY` in Firebase):
   ```powershell
   powershell -ExecutionPolicy Bypass -File infra/aws/set_gateway_secrets.ps1 -FirebaseKeyFile "C:\path\key.json"
   ```
   Delete the JSON file afterwards.
8. **Start the gateway**: in `infra/aws/terraform.tfvars` set `ecs_desired_count = 1`, then
   `terraform plan -out=tfplan` (expect: task definition replaced, service updated, 2 IAM resources
   for the demo/ prefix created, 0 other destroys) and `terraform apply tfplan`.
   Success: target group shows 1 **healthy** target.
9. **DNS**: CNAME `api` -> `doctornect-production-alb-...elb.amazonaws.com` (`terraform output -raw alb_dns_name`).
   Success: `curl.exe -s -o NUL -w "%{http_code}" https://api.doctornect.com/healthz` prints `200`.
10. **Functions settings**: `.env` `S3_BUCKET_PRODUCTION=` (`terraform output -raw s3_production_bucket`),
    empty `S3_BUCKET=`; IAM user `doctornect-functions-s3-production` > Create access key; then
    ```powershell
    powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1
    powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1 -Only AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY -PromptAll -Replace
    ```
11. **Gate + deploy**: `powershell -ExecutionPolicy Bypass -File scripts/env/predeploy_gate.ps1`
    (stops at the first failing gate; deploys only when all pass, then confirms the new code is live).

The detailed explanation of each step follows.

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
