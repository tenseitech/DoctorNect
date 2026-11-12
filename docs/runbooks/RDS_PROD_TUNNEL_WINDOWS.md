# Windows: RDS access via SSM or SSH (private subnet)

Use when RDS **`Publicly accessible = No`**.

## Prerequisites

| Item | Action |
|------|--------|
| AWS CLI v2 | `aws --version` |
| Session Manager plugin | [Install for Windows](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) |
| IAM | `ssm:StartSession` on bastion instance; RDS security group ingress **5432** from **bastion SG** and **gateway/ECS SG** only — never `0.0.0.0/0` |
| CA bundle | `infra/aws/README_CA_BUNDLE.md` → `global-bundle.pem` |
| Repo root `.env` | `PROD_RDS_HOST` = real endpoint; `PROD_RDS_CONNECT_HOST=127.0.0.1`; **`PROD_RDS_PORT=5433` (required — no default 5432)** |

## Option A — SSM port forward (recommended)

**Terminal 1** (keep open):

```powershell
$RdsEndpoint = "<PASTE_RDS_ENDPOINT_HERE>"
$InstanceId  = "<bastion-or-ssm-managed-ec2-instance-id>"
$LocalPort   = 5433

aws ssm start-session `
  --target $InstanceId `
  --document-name AWS-StartPortForwardingSessionToRemoteHost `
  --parameters "host=$RdsEndpoint,portNumber=5432,localPortNumber=$LocalPort"
```

**Terminal 2** (project root, after filling `repo root `.env``):

```powershell
cd c:\Users\khije\Downloads\DoctorNect\doctor
# Fingerprint for guards (no secret):
node -e "const {getHostFingerprint}=require('./scripts/lib/env_guard');const {getEnv}=require('./scripts/lib/env_loader');console.log(getHostFingerprint(getEnv('PROD_RDS_HOST')));"

node scripts/db/db_connectivity_smoke.js --env=production --mode=postgres
node scripts/db/rds_readiness_probe.js --target=production --confirm=<paste-prod-rds-host-exactly>
```

TLS: `pg` uses `PROD_RDS_SSL_SERVERNAME` / `PROD_RDS_HOST` as **servername** while TCP goes to `127.0.0.1:5433`.

## Option B — SSH tunnel via bastion

```powershell
ssh -i C:\path\to\bastion-key.pem -N `
  -L 5433:<PASTE_RDS_ENDPOINT_HERE>:5432 `
  ec2-user@<bastion-public-ip-or-dns>
```

Same `repo root `.env`` tunnel vars as Option A.

## Diagnose failures

| Symptom | Likely cause | Manual fix |
|---------|----------------|------------|
| `ETIMEDOUT` / `ECONNREFUSED` on `127.0.0.1` | Tunnel not running or wrong local port | Start SSM/SSH session; match `PROD_RDS_PORT` |
| `timeout` to RDS hostname (no tunnel) | Laptop cannot reach private RDS | Use tunnel; do not enable public RDS |
| `certificate verify failed` | Wrong TLS servername | Set `PROD_RDS_SSL_SERVERNAME` = real `*.rds.amazonaws.com` host |
| `ENOENT` CA bundle | Missing PEM | Download per `infra/aws/README_CA_BUNDLE.md` |
| `28P01` password auth | Wrong user/password | Reset in Secrets Manager / RDS master |
| `no pg_hba.conf entry` | SG or wrong VPC | RDS SG allow 5432 from bastion ENI |

## Production migrate / bootstrap guards

Add RDS host fingerprint (8 chars) to `docs/audit/allowed_host_hashes.txt` after first connect:

```powershell
node -e "const c=require('crypto');const h=require('./scripts/lib/env_loader').getEnv('PROD_RDS_HOST');console.log(c.createHash('sha256').update(h.trim().toLowerCase()).digest('hex').slice(0,8).toUpperCase());"
```

Execute migrations (operator confirms each step):

```powershell
node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data --confirm=<PROD_RDS_HOST>
# After review:
node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm=<PROD_RDS_HOST>
```
