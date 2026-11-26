# Audit 6 — RPC idempotency proposal (REL-04)

**Status:** **BLOCKED BY AUDIT 4 HOLD** for schema-dependent items. Client guards partially mitigate duplicate submits.

## Already idempotent (code / DB evidence)

| Operation | Mechanism | Evidence |
|-----------|-----------|----------|
| `book_appointment_atomic` | Natural key `p_appointment_id`; slot locks; duplicate patient errors | RLS harness idempotency conflict test |
| `create_prescription_atomic` | `prescription_id` in payload | RPC name + upsert semantics in SQL |
| S3 `confirmS3Upload` | Same `objectKey` safe replay | `s3_storage.test.js` |
| In-app notifications | Deterministic `notification_id` upsert | `in_app_notifications.js` |
| Razorpay webhook | Processed flag / idempotent capture | webhook tests |
| Lab order upsert | `onConflict: order_id` | `SupabaseLabRepository.saveOrder` |

## Client-side duplicate protection (Audit 6)

| Flow | Guard key | Scope |
|------|-----------|-------|
| Patient `bookAppointment` | `book_appointment:{appointmentId}` | Per-appointment concurrent calls |
| Doctor prescription `save` | `prescription_save:{prescriptionId}` | Per prescription |
| Lab `saveOrder` | `lab_order_save:{orderId}` | Per order |

**Limitation:** Guards are process-local (single Flutter isolate). Retries from another device or cold restart can still duplicate unless server idempotency exists.

## Proposed server idempotency (requires Audit 4 / migration — not applied)

### LAB-04 — `submit_lab_report` RPC 4th parameter

- **Risk:** Duplicate report keys on retry without idempotency key.
- **Proposal:** Add optional `p_idempotency_key` (UUID) stored in `lab_report_submissions` with unique index; return existing row on replay.
- **Migration:** Separate from `20261126000001_audit4_*` — new file only when hold clears.

### Generic RPC header pattern

- Accept `Idempotency-Key` at gateway for selected RPC proxy paths (store in Redis with TTL 24h) — **requires Redis wiring in production (Audit 4 ON HOLD).**

## Contract tests (static, no DB)

- `backend/functions/test/lab_report_rpc_migration_contract.test.js` (untracked) — keep out of Audit 6 commit if Audit 4 migration file not committed.

## Validation blocked

- Runtime replay of duplicate RPC calls against staging Postgres until operator applies migrations and hold is lifted.