# Gateway client allowlist diff (auto-generated)

Generated from allowlist completeness scanner.

## Client Dart tables missing from gateway (feature break risk)

_None — all client-referenced tables are allowlisted._

## Client RPCs missing from gateway

_None._

## clientDirectAllowedTables not referenced in Dart (defense-in-depth exposure)

_None — every direct-allowed table appears in Dart or is embed-only._

## Allowlisted RPCs unused in client/backend scan

_None._

## Summary counts

| Metric | Count |
|--------|------:|
| Dart-discovered tables | 43 |
| Dart-discovered RPCs | 14 |
| clientDirectAllowedTables | 43 |
| Missing from allowlist (tables) | 0 |
| Extra direct allowlist (unreferenced) | 0 |
