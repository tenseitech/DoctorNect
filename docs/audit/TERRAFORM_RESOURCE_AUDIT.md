# Terraform audit (`infra/aws`) — ECS gateway prep

Generated for console-created RDS/VPC. **No `aws_db_instance` / VPC / subnet resources** in this module.

## Uses existing infrastructure (variables + data)

| Input | Purpose |
|-------|---------|
| `vpc_id` | ALB, ECS, SGs |
| `public_subnet_ids` | Internet-facing ALB |
| `private_subnet_ids` | Fargate tasks (needs NAT for JWKS/Secrets/ECR) |
| `rds_endpoint`, `rds_port`, `rds_db_name` | Documentation / future wiring (PostgREST uses Secrets Manager URI) |
| `rds_security_group_id` | **Ingress rule** `rds_ingress_from_ecs` (5432 from ECS SG) |
| `rds_instance_identifier` | Optional `data.aws_db_instance.selected` (read-only verify) |
| `acm_certificate_arn` | HTTPS listener (cert must exist in ACM) |

## Creates new resources (expected plan)

| Resource | File |
|----------|------|
| `aws_db_parameter_group` (pg18 cron/ssl) | `rds.tf` |
| `aws_lb`, target group, HTTPS listener | `alb.tf` |
| `aws_security_group` ALB + ECS | `security_groups.tf` |
| `aws_security_group_rule` RDS←ECS | `security_groups.tf` |
| `aws_ecs_cluster`, task definition, service | `ecs.tf` |
| IAM execution role + Secrets Manager read policy | `ecs.tf` |
| Secrets Manager secret **containers** (no values in TF) | `secrets.tf` |
| CloudWatch log group + alarms | `cloudwatch.tf` |
| WAF Web ACL + ALB association | `waf.tf` |

## Must NOT appear in plan (RDS/VPC)

- `aws_db_instance`, `aws_vpc`, `aws_subnet`, `aws_nat_gateway`
- `aws_db_subnet_group` replace/destroy on existing RDS

**Attach parameter group manually or CLI** (`rds.tf` comments) — Terraform creates the group; associating it to your existing instance is a **modify**, not create instance.

## `terraform plan` status

| Step | Result |
|------|--------|
| `terraform validate` | **PASS** (see `terraform_validate_waf.txt`) |
| `terraform plan` | **NOT RUN** — needs valid AWS credentials + `terraform.tfvars` (from example). Agent attempt failed: PowerShell list-var quoting + no creds (`docs/audit/terraform_plan_attempt.txt`). Operator: `cd infra/aws && terraform init && terraform plan -out=tfplan` |

## Secret JSON shapes (AWS Secrets Manager — operator fills after apply)

**`doctornect/production/rds_credentials_*`**

```json
{
  "connection_string": "postgresql://authenticator:REPLACE_PASSWORD@REPLACE_RDS_HOST:5432/doctornect?sslmode=require"
}
```

**`doctornect/production/postgrest_jwt_secret_*`**

```json
{
  "jwt_secret": "REPLACE_MIN_32_CHARS"
}
```

Generate: `openssl rand -hex 32`

**`doctornect/production/gateway_service_key_*`**

```json
{
  "service_key": "REPLACE_MIN_32_CHARS"
}
```

Generate: `openssl rand -hex 32` (same value → Firebase `PROD_GATEWAY_SERVICE_KEY` + `SUPABASE_SERVICE_ROLE_KEY` secret)

**Not in Terraform (gateway env gaps):**

- `ANON_KEY` — PostgREST public role header; defaults in code if unset. Set `PROD_GATEWAY_ANON_KEY` on Functions client; optional future ECS env `ANON_KEY`.
- Firebase JWKS — no secret; gateway uses `FIREBASE_PROJECT_ID` + live Google JWKS.

## ACM / Route53 checklist

| Item | Terraform | Operator |
|------|-----------|----------|
| ACM cert for `api.doctornect.com` | Uses `acm_certificate_arn` var only | Request/validate cert in **ap-south-1** (ALB region) |
| Route53 alias to ALB | **Not in repo** | A/AAAA alias → `alb_dns_name` output |
| Public API DNS | **Not in repo** | Point `PROD_GATEWAY_URL` / client `SUPABASE_URL` at this host |

## PostgREST / JWT path

1. Internet → **Auth Gateway** (:3000) — Firebase JWT verify, allowlist, mint PostgREST JWT.
2. Gateway → **PostgREST** localhost :3001 in same task.
3. PostgREST → **RDS** as `authenticator` via `PGRST_DB_URI` (roles from `db/rds_bootstrap/01_roles_and_extensions.sql` + `04_rds_runtime_grants.sql`).
4. Clients **never** hit PostgREST directly on RDS.