# Manual check: one Razorpay TEST-mode promoted-ad payment

Why: the app now strips the `NFC` and `READ_BASIC_PHONE_STATE` permissions that the Razorpay SDK
adds (PROJECT_ANALYSIS.md D4). Checkout should not need them, but only a real payment run on a phone
proves it. Nothing in this repo has tested a payment end to end; do this once after installing a
build that contains the change.

Use TEST mode only. Demo accounts never get live keys (they get `RAZORPAY_TEST_KEY_*`, or the main
keys only when those are `rzp_test_...`), so the demo doctor is the safest account to use.

## Before you start

- Staging demo APK (version name ends in `-staging-demo`) installed with `adb install -r`, and the
  new Functions deployed (the old build does not log demo users in).
- In Firebase Secret Manager / env: `RAZORPAY_TEST_KEY_ID` and `RAZORPAY_TEST_KEY_SECRET` set to
  Razorpay **test** keys (Razorpay Dashboard > switch to Test Mode > Account & Settings > API Keys).
- Razorpay Dashboard in **Test Mode** open in a browser.

## Steps

1. Log in as the demo doctor: `9999900001`, OTP `000000`.
2. Open the promoted-ad (sponsored listing) screen, fill in a short test ad, choose a plan, tap Pay.
3. Razorpay Checkout opens. It must open without a permission prompt for NFC or phone state.
4. Pay with a Razorpay test method: UPI ID `success@razorpay`, or a test card from Razorpay's
   "Test card details" documentation page. Do not use a real card.
5. Wait for the app to return from Checkout.

## What success looks like

- App: a success message; the ad shows as waiting for approval (not live yet).
- Razorpay Dashboard (Test Mode) > Transactions > Payments: one payment, status **Captured**, the
  amount matches the plan price the app showed (server-side price, not a client value).
- Database (staging, read-only check): `promoted_ads` row for the doctor with `status =
  'pending_approval'` and `payment_status = 'verified'`; `razorpay_orders` row for the order with
  `status = 'paid'`; `razorpay_payments` has the payment once.
- Paying the same order again (back button, retry) must not create a second activation.

## What to check in the Functions logs (Cloud Logging, project medibond-45fad)

Filter on the function names `createRazorpayOrder`, `verifyRazorpayPayment`, `razorpayWebhook`.

- Expected: no `ERROR` entries for this payment.
- Must NOT appear: `[createRazorpayOrder] Razorpay order creation failed`,
  `[verifyRazorpayPayment] Error fetching payment/order from Razorpay`,
  `[razorpayWebhook] Invalid signature`, `amount_mismatch`, `currency_mismatch`,
  `order_id_mismatch`, `order_notes_missing`, `ad_not_found`, `RAZORPAY_WEBHOOK_SECRET is not configured`.
- Acceptable: `[createRazorpayOrder] Could not reuse existing order; creating new one.` (a retry).
- Logs never contain card numbers, UPI IDs or the key secret; if you see one, report it.

## If it fails

- Checkout does not open or closes immediately: take a screenshot and `adb logcat -d > logcat.txt`
  (look for `razorpay` / `SecurityException` lines). If a permission is the cause, revert the two
  `tools:node="remove"` lines in `frontend/android/app/src/main/AndroidManifest.xml`.
- Payment captured in Razorpay but the ad stays `pending_payment`: check `verifyRazorpayPayment`
  and `razorpayWebhook` logs (webhook URL and secret in the Razorpay Dashboard > Webhooks).
