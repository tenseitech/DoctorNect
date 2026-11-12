# Razorpay Webhook Integration Guide

This guide details the technical behavior, security model, and configuration requirements for the `razorpayWebhook` Cloud Function (`asia-south1`) handling promoted ad payment activations.

---

## 1. Webhook Endpoint Configuration

Configure the webhook in the **Razorpay Dashboard** under **Settings → Webhooks**:

- **Webhook URL:** `https://razorpaywebhook-lgq6nrfroa-el.a.run.app`  
  *(Deployed Gen 2 Cloud Function URL for `razorpayWebhook` in region `asia-south1`)*
- **Secret:** Must match the secret stored in Google Cloud Secret Manager (`RAZORPAY_WEBHOOK_SECRET`).
- **Active Events (Select only these two):**
  - `payment.captured`
  - `order.paid`
- **Alert Email:** Configure an operations email to receive webhook delivery failure notices.

---

## 2. Signature Verification Details

The webhook verifies incoming requests before parsing or executing any business logic:

1. **Signature Header:** Reads `x-razorpay-signature` header. If missing or non-string, returns `400 Bad Request`.
2. **Secret Resolution:** Resolves from Google Cloud Secret Manager (`razorpayWebhookSecret.value()`) with fallback to `process.env.RAZORPAY_WEBHOOK_SECRET`. If unset, returns `503 Service Unavailable`.
3. **Raw Body Buffer:** Uses `req.rawBody` buffer directly. Refuses to verify re-serialized strings to prevent JSON whitespace / key-order discrepancies. If missing, returns `400 Bad Request`.
4. **HMAC Calculation:** Computes `HMAC-SHA256` of `req.rawBody` using the webhook secret:
   ```js
   crypto.createHmac('sha256', webhookSecret).update(rawBodyBuffer).digest('hex')
   ```
5. **Constant-Time Comparison:** Evaluates buffer lengths and executes `crypto.timingSafeEqual(expected, received)` in constant time to prevent timing attacks. On mismatch, returns `400 Bad Request`.

---

## 3. Unhandled Events & Idempotency

### Unhandled Event Behavior
When Razorpay sends an event with a **valid signature** but an **unhandled event type** (anything other than `payment.captured` or `order.paid`):
- The function logs: `[razorpayWebhook] Ignored non-handled event type: <eventType>`.
- The function responds with **`HTTP 200 OK`**:
  ```json
  { "status": "ignored", "event": "<eventType>" }
  ```
- **Rationale:** A 200 response acknowledges delivery and stops Razorpay from retrying unhandled notifications indefinitely.

### Idempotency & Retry Safety
When Razorpay retries delivery of the same event or payment (e.g., due to downstream network timeouts):
1. **Event-Level Deduplication (`razorpayWebhookEvents/{eventId}`):**
   - The event ID is read from the `x-razorpay-event-id` header.
   - If `razorpayWebhookEvents/{eventId}` already exists with matching `paymentId` and `adId`, the transaction immediately exits cleanly with:
     ```json
     { "success": true, "idempotent": true, "adId": "<adId>" }
     ```
2. **Payment Ledger Deduplication (`razorpayPayments/{paymentId}`):**
   - Before modifying any promoted ad, the function inspects `razorpayPayments/{paymentId}`.
   - If the payment ledger already exists for the same ad and the ad is in a valid paid state (`pending_approval`, `active`, or `rejected`) with `ad.razorpayPaymentId === paymentId`, the retry succeeds idempotently without duplicate billing or status overwrites.
   - If the payment was already claimed by a *different* ad, the request is permanently rejected with `HTTP 200` (`{ status: "rejected", reason: "payment_already_used" }`).
3. **Ad State Transition:**
   - On first successful verification, the ad transitions atomically from `pending_payment` to `pending_approval`, and `paymentStatus` is set to `verified`.

---

## 4. Complete HTTP Status Code Matrix

| Condition / Failure Mode | HTTP Status | Response Body | Razorpay Behavior |
|:---|:---:|:---|:---|
| **Invalid HTTP Method** (not `POST`) | `405 Method Not Allowed` | `{"error": {"message": "Method Not Allowed. POST required."}}` | Fails / does not retry |
| **Missing `x-razorpay-signature` Header** | `400 Bad Request` | `'Missing webhook signature.'` | Fails / does not retry |
| **Missing Raw Request Body (`req.rawBody`)** | `400 Bad Request` | `'Missing raw request body.'` | Fails / does not retry |
| **Signature Mismatch** (tampered or wrong secret) | `400 Bad Request` | `'Invalid webhook signature.'` | Fails / does not retry |
| **Malformed JSON Payload** | `400 Bad Request` | `'Invalid JSON payload.'` | Fails / does not retry |
| **Secret Missing in Environment / Secret Manager** | `503 Service Unavailable` | `{"error": {"message": "Webhook secret not configured."}}` | Razorpay retries |
| **Valid Signature, Non-handled Event** | `200 OK` | `{"status": "ignored", "event": "<event>"}` | Acknowledged, no retry |
| **Order Notes Missing** (`adId`, `providerUid`, `durationHours`) | `200 OK` | `{"status": "rejected", "reason": "order_notes_missing"}` | Acknowledged, no retry |
| **Missing Payment or Order ID** | `200 OK` | `{"status": "rejected", "reason": "missing_identifiers"}` | Acknowledged, no retry |
| **Currency Mismatch** (not `INR`) | `200 OK` | `{"status": "rejected", "reason": "currency_mismatch"}` | Acknowledged, no retry |
| **Amount Mismatch Against Pricing Table** | `200 OK` | `{"status": "rejected", "reason": "amount_mismatch"}` | Acknowledged, no retry |
| **Promoted Ad Not Found in Firestore** | `200 OK` | `{"status": "rejected", "reason": "ad_not_found"}` | Acknowledged, no retry |
| **Order ID Mismatch on Ad Document** | `200 OK` | `{"status": "rejected", "reason": "order_id_mismatch"}` | Acknowledged, no retry |
| **Payment ID Already Claimed by Another Ad** | `200 OK` | `{"status": "rejected", "reason": "payment_already_used"}` | Acknowledged, no retry |
| **Business Logic Precondition Failed** | `200 OK` | `{"status": "rejected", "reason": "<errorCode>"}` | Acknowledged, no retry |
| **Transient Database / Firestore Error** | `500 Internal Server Error` | `'Internal Server Error'` | Razorpay retries with backoff |
| **Successful Activation (First Time)** | `200 OK` | `{"success": true, "idempotent": false, "adId": "<adId>"}` | Success |
| **Successful Activation (Idempotent Retry)** | `200 OK` | `{"success": true, "idempotent": true, "adId": "<adId>"}` | Success |
