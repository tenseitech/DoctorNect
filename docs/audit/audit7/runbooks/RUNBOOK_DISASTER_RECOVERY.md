# RUNBOOK — Disaster recovery (summary)

Full plan: `../AUDIT_7_DISASTER_RECOVERY_PLAN.md`.

## Activation criteria

- Regional outage, catastrophic DB loss, or prolonged SEV-1 > RTO.

## Steps

1. Declare DR incident; assign IC.
2. Assess last good backup (RPO).
3. Provision recovery environment (**OPERATOR ACTION**).
4. Restore DB from snapshot / logical backup.
5. Restore gateway + Functions config from git + secrets store.
6. DNS cutover when validation passes.
7. Post-recovery monitoring 24h.

## Commands

All production recovery commands are **OPERATOR ACTION** — not automated from this repository.

## Test cadence

Quarterly staging DR drill recommended — status **NOT VERIFIED**.