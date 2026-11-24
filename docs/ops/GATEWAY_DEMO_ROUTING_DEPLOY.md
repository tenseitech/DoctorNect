# Auth gateway — production demo routing (ECS)

The ECS task (`infra/aws/ecs.tf`) runs **auth-gateway** (port 3000) + **PostgREST → RDS** (port 3001) in one Fargate pod.

## Prerequisites

- Terraform state for `infra/aws` (VPC, ALB, ECS cluster).
- Supabase **staging** project used as the demo data plane (`DEMO_SUPABASE_URL`).
- Firebase demo Auth users (`rev_fb_*`) on `medibond-45fad`.

## Secret setup (operator)

**Order (all interactive; values never echoed). Run `-WhatIf` on each script first.**

| Step | Script | Targets |
|------|--------|---------|
| 1 | `.\scripts\ops\set_production_gateway_aws_secrets.ps1` | AWS `rds_credentials_*` → `connection_string`; AWS `postgrest_jwt_secret_*` → `jwt_secret` |
| 2 | `.\scripts\ops\set_demo_secrets.ps1` | Firebase `REVIEW_FIXED_OTP`, `DEMO_SUPABASE_SERVICE_ROLE_KEY`; AWS `doctornect/production/demo-routing`; root `.env` non-secret URLs only |
| 3 | `.\scripts\ops\rotate_gateway_service_key.ps1 -AwsSecretName doctornect/production/gateway_service_key_<suffix>` | AWS `gateway_service_key_*` + Firebase `PROD_GATEWAY_SERVICE_KEY` (**always last** — single source for gateway key) |

### Firebase Functions (`defineSecret`)

| Secret | Set by |
|--------|--------|
| `REVIEW_FIXED_OTP` | `set_demo_secrets.ps1` |
| `DEMO_SUPABASE_SERVICE_ROLE_KEY` | `set_demo_secrets.ps1` |
| `PROD_GATEWAY_SERVICE_KEY` | `rotate_gateway_service_key.ps1` only |

Never materialize these into `backend/functions/.env`.

### AWS Secrets Manager — `doctornect/production/demo-routing`

Must match Terraform `var.environment` (`production`, not `prod`). `set_demo_secrets.ps1` default is `production`.

| JSON key | Purpose |
|----------|---------|
| `DEMO_FIREBASE_UID_ALLOWLIST` | Demo Firebase UIDs |
| `DEMO_PGRST_URL` | Supabase PostgREST base (`…/rest/v1`) |
| `DEMO_PGRST_JWT_SECRET` | HS256 secret used to mint JWTs for demo PostgREST |

Gateway container env (non-secret):

- `APP_ENV=production`
- `DEMO_REAL_ROUTING_ENABLED=1`
- `DEMO_PGRST_JWT_AUD=authenticated`

## `DEMO_PGRST_JWT_SECRET` must match Supabase JWT verification

Demo upstream is **Supabase PostgREST**. The gateway mints HS256 JWTs with `DEMO_PGRST_JWT_SECRET`. PostgREST / Supabase must validate the same secret or you get **401 Unauthorized**.

### Legacy JWT secret (most projects)

Supabase Dashboard → **Project Settings** → **API** → **JWT Settings** → **JWT Secret** (Legacy). Use that string for:

- ECS `DEMO_PGRST_JWT_SECRET` (AWS secret)
- Not required in Cloud Functions env (gateway only)

### New asymmetric “JWT signing keys”

If the project shows **JWT signing keys** (ECC/RSA) instead of a single legacy secret:

1. PostgREST on Supabase Hosted already uses Supabase’s verifier — for **ECS demo upstream**, you still need the **legacy HS256 secret** if PostgREST is configured with `PGRST_JWT_SECRET` (this repo’s gateway minter is HS256-only).
2. In Dashboard → JWT Settings, check whether **“Reveal legacy JWT secret”** is available; use that for `DEMO_PGRST_JWT_SECRET`.
3. If legacy secret is disabled and only asymmetric keys exist, you must either:
   - rotate/enable a compatible HS256 secret for the demo PostgREST path, or
   - extend `services/api-gateway` to mint JWTs with the current signing key (out of scope for narrow rollout — open an infra task).

Symptom: demo UID calls return 401 from demo upstream; real UID path (RDS) still works.

## Staging audit SQL (local only)

Read-only checks: [STAGING_AUDIT_DATABASE.md](./STAGING_AUDIT_DATABASE.md).

## Health check

- `GET https://<gateway-host>/healthz` — `healthy` + PostgREST sub-check.

## Deploy (operator)

```bash
cd infra/aws
terraform plan -out=tfplan
terraform apply tfplan
```

Force new ECS deployment after image or secret changes.

## Post-deploy verify (read-only)

```bash
node scripts/audit/post_deploy_demo_routing_verify.js
node scripts/audit/verify_demo_login_chain_readonly.js
```

## Firebase Functions (narrow OTP)

```powershell
$env:NARROW_OTP_DEPLOY="1"
node scripts/env/materialize_functions_env.js
cd backend/functions; npm run bundle:verify
firebase deploy --only functions:sendUserRegistrationOtp,functions:verifyUserRegistrationOtp --project medibond-45fad
node ../scripts/env/cleanup_functions_env.js
```