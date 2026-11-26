# RUNBOOK — Gateway outage

**Symptoms:** App API failures, `/readyz` non-200, spike in client network errors.

**Detection:** Synthetic probe on `/readyz`; log filter `service=doctornect-auth-gateway` + 5xx.

**Severity:** SEV-1 if all users affected.

## Triage

1. **SAFE DIAGNOSTIC:** `curl -sS https://<gateway-host>/livez` — expect 200.
2. **SAFE DIAGNOSTIC:** `curl -sS https://<gateway-host>/readyz` — inspect `dependencies.postgrest` and `redis`.
3. Check recent deploy / ECS task events (**OPERATOR ACTION**).

## Logs

- Gateway stdout: `event=api_request`, `request_id` for correlation.
- PostgREST upstream unreachable → 503/502 patterns.

## Recovery

- Restart gateway tasks if liveness fails (**OPERATOR ACTION**).
- If PostgREST down → `RUNBOOK_DATABASE_OUTAGE.md`.
- If Redis required and down → `RUNBOOK_REDIS_FAILURE.md`.

## Verification

`/readyz` 200; sample authenticated REST call succeeds.

## Escalation

SEV-1 > 15m → incident commander + on-call.