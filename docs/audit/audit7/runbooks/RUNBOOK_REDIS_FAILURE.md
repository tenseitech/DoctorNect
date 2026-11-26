# RUNBOOK — Redis failure

**Symptoms:** `/readyz` shows `redis.ok: false` when Redis URL configured; elevated 429 or rate-limit errors.

**Severity:** SEV-2 when Redis is required for rate limiting in production.

## Triage

1. **SAFE DIAGNOSTIC:** `/readyz` dependencies.redis.
2. Confirm `RATE_LIMIT_REDIS_URL` / gateway config (**OPERATOR ACTION**).

## Behavior

- Gateway may fail-closed or use in-memory limiter per `rate_limit_factory` — inspect code path for environment.

## Recovery

- Restore Redis cluster / ElastiCache (**OPERATOR ACTION**).
- Temporary: ops may clear Redis URL only if policy allows degraded in-memory mode — **document risk**.

## Verification

`/readyz` redis ok; rate limit integration tests pass in CI.