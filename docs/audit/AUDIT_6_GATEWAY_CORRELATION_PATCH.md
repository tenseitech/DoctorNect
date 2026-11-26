# Audit 6 — Gateway request correlation

**Status:** **Integrated** in `services/api-gateway/src/server.js` and `proxy.js` (Audit 6 final pass).

- `resolveRequestId` per request; invalid inbound IDs replaced.
- `x-request-id` on JSON responses, OPTIONS, and proxied PostgREST responses.
- `emitAuditLog({ requestId })` for JSON and completed proxy requests.
- CORS allows/exposes `x-request-id`.

Audit 4 `/livez` and `/readyz` behavior in the same file was **preserved**, not reverted.