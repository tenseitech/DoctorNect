# Audit 7 — Incident response framework

## Severity

| Level | Definition | Examples |
|-------|------------|----------|
| SEV-1 | Total loss of critical path | Gateway down, DB unreachable for all users |
| SEV-2 | Major degradation | High 5xx, sync DLQ flood, auth mostly failing |
| SEV-3 | Limited impact | Single region, single role, elevated latency |
| SEV-4 | Minor | Cosmetic, non-production, single user |

## Process

1. **Detect** — alerts, probes, user reports, CI failure.
2. **Triage** — confirm blast radius; assign incident commander.
3. **Communicate** — status channel; no PHI in public updates.
4. **Mitigate** — runbooks under `runbooks/`.
5. **Recover** — verify health + key workflows (staging first).
6. **Close** — timeline, evidence, residual actions.
7. **Postmortem** — within 5 business days for SEV-1/2.

## Roles

- **IC:** coordinates comms and sequencing.
- **Ops:** gateway, Redis, infra.
- **App:** Functions, Flutter releases.
- **Data:** DB restore (operator only; Audit 4 hold for schema changes).