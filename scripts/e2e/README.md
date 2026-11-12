# DoctorNect PostgREST & Auth Gateway End-to-End Test Suite

This suite verifies the complete production deployment path:
`Client Request -> API Gateway (Port 3000) -> PostgREST (Port 3001) -> PostgreSQL Database`

## Architecture & Pinned Binary

- **PostgREST Version**: `12.2.3`
- **Official Release Binary**: `.bin/postgrest.exe` (Windows x64) / `postgrest` (Linux x64)
- **Pinned Checksum (SHA-256)**: `01ee186e6e9904a1fb8183a51b5b6d2b6695720c29f65325f6fc678708360bb8`
- **Docker / ECS Container Image**: `postgrest/postgrest:v12.2.3`

## Verified Scenarios

1. **Anonymous Whitelist Read**: Verifies unauthenticated clients can safely read `/rest/v1/doctor_directory` returning `200 OK`.
2. **Authenticated Atomic Transaction**: Verifies authenticated patients can invoke atomic stored procedures (`/rest/v1/rpc/book_appointment_atomic`) with PostgREST minting validated JWT claims.
3. **Gateway RPC Shielding**: Verifies unallowed RPCs (e.g. `delete_my_account`) are intercepted and rejected at the gateway boundary with `404 Not Found`.
4. **Header Forgery Resistance**: Verifies attacker attempts to inject privileged role claims (`x-user-role: super_admin`, `x-app-role: admin`) via HTTP headers are ignored.
5. **Anonymous Query Clamping**: Verifies queries exceeding allowed page sizes (`?limit=5000`) are clamped to maximum allowed thresholds (`100` rows).
6. **Internal Schema Protection**: Verifies internal operational tables (`/rest/v1/doctor_directory_updates`, `system_config`) cannot be accessed directly by API callers.

## Running the E2E Suite

Prerequisites:
- PostgreSQL 17 running locally with database `replay_check` bootstrapped.
- `REPLAY_DB_URL` configured in environment.

Execution:
```bash
node scripts/e2e/postgrest_e2e_runner.js
```

