# Audit 7 — Backup & restore plan

## Evidence in repository (static)

| Asset | Backup mechanism (documented) | Location |
|-------|------------------------------|----------|
| Staging Postgres | Logical NDJSON export | `docs/ops/PROGRESS.md`, `backups/staging_logical_*` |
| Production RDS | AWS snapshots (operator) | `docs/runbooks/PRODUCTION_CUTOVER_RDS.md` |
| Application code | Git | GitHub |
| Infrastructure | Terraform in `infra/aws` | Versioned |
| Secrets | AWS Secrets Manager / env (not in git) | Operator |

## Policy (recommended)

| Data | Frequency | Retention | Encryption |
|------|-----------|-----------|------------|
| RDS production | Daily automated + pre-deploy manual | 7–35 days | At rest (AWS) |
| Staging logical | Weekly + pre-migration | 90 days | Filesystem + checksum manifest |
| S3 clinical | Versioning + lifecycle | Per compliance review | SSE |

## Restore procedure (operator)

1. Identify snapshot ID / backup manifest SHA (**OPERATOR ACTION**).
2. Restore to **isolated** instance — not production primary without approval.
3. Validate row counts vs manifest.
4. Point gateway to restored endpoint only in controlled cutover.

## Integrity verification

- SHA-256 manifests for logical exports (existing practice).
- Periodic **staging** restore drill quarterly — **NOT VERIFIED** this audit.

## OPS-10 checklist

- [ ] Last successful RDS snapshot timestamp recorded
- [ ] Manifest hash verified
- [ ] Staging restore drill completed
- [ ] Application smoke after restore
- [ ] RTO/RPO measured