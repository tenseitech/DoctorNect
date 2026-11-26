# Performance follow-up recommendations (Audit 5)

**Audit 5 follow-up (2026-11-26)** implemented keyset pagination for appointments, health records, prescriptions, medical directory, and in-app notifications; moved ICD-10 raw file to test fixtures. **Audit 4 remains ON HOLD.**

## Client (Flutter) — remaining

- Roll `selectColumns` to `supabase_lab_repository.dart`, `supabase_pharmacy_repository.dart`, `supabase_ambulance_repository.dart`.
- Keyset `DataPage` for lab/pharmacy/ambulance list endpoints still using fixed `.limit(100|150|500)`.
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