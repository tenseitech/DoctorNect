# Performance follow-up recommendations (Audit 5)

Non-blocking items deferred from Audit 5 remediation. **Audit 4 remains ON HOLD** for database migration work.

## Client (Flutter)

- Roll `selectColumns` / narrow projections to `supabase_lab_repository.dart`, `supabase_appointment_repository.dart`, `supabase_ambulance_repository.dart`.
- Introduce cursor-based `DataPage` for lists currently using fixed `.limit(100|200|500)` (PERF-02).
- Profile startup with DevTools; defer non-critical service init after first frame.

## Gateway

- Evaluate short-lived JWKS key cache (must not weaken revocation checks).
- Wire ECS health checks to `/readyz` only after Audit 4 gateway deploy is authorized.

## Backend Functions

- Audit `cross_role_sync.js` batch sizes under load (static review only in Audit 5).
- Monitor `PG_POOL_MAX` vs Firebase max instances.

## Infrastructure (documentation only)

- Confirm RDS `max_connections` vs `docs/audit/AUDIT_4_CONNECTION_BUDGET.md` before scaling ECS tasks.
- Enable `wire_gateway_rate_limit_redis_secret` in production (Audit 4 DB-05 operator action).