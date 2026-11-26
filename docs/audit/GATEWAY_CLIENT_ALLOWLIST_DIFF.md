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
| serviceRoleOnlyTables (backend; not in Dart) | 23 |

## serviceRoleOnlyTables (expected extra vs Dart)

- `abuse_rate_limits`
- `admin_audit_logs`
- `admin_users`
- `ambulance_locations`
- `ambulance_private_settings`
- `ambulance_trip_contacts`
- `doctor_education`
- `doctor_facilities`
- `doctor_invites`
- `doctor_private`
- `mail_queue`
- `notification_outbox`
- `otp_challenges`
- `patient_care_team`
- `pharmacy_doctor_invites`
- `provisioning_errors`
- `razorpay_orders`
- `razorpay_payments`
- `razorpay_webhook_events`
- `security_events`
- `storage_audit_logs`
- `super_admins`
- `sync_dead_letter_queue`
