# RUNBOOK — Realtime failure

**Symptoms:** Live lists stale; no websocket updates; token errors in debug logs.

**Severity:** SEV-3 (degraded UX; polling may partially compensate per Audit 5/6).

## Triage

1. Client: Supabase realtime status.
2. Verify Firebase `idToken` → gateway JWT path.
3. Network/firewall blocking websocket.

## Recovery

- App resume triggers debounced `setAuth` (Audit 6).
- User re-login if token invalid.

## Verification

Staging: open appointment list on two clients; observe update within SLA (manual).