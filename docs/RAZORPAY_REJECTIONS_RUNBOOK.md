# Razorpay Webhook Rejections Runbook

This runbook covers operator workflows for auditing, reconciling, and refunding payments rejected by the `razorpayWebhook` Cloud Function in `asia-south1`.

---

## 1. Overview of Dead-Letter Rejections

When `razorpayWebhook` receives a cryptographically verified webhook event from Razorpay (`payment.captured` or `order.paid`) that cannot be processed due to a permanent logical inconsistency, it writes a durable dead-letter document to the Firestore collection:

```
/razorpayWebhookRejections/{docId}
```

- **Document ID (`docId`):** The `x-razorpay-event-id` header if provided by Razorpay; otherwise `${paymentId}_${reason}`.
- **Fields:**
  - `eventId` (`string|null`): Razorpay event ID (`evt_...`).
  - `paymentId` (`string|null`): Razorpay payment ID (`pay_...`).
  - `orderId` (`string|null`): Razorpay order ID (`order_...`).
  - `adId` (`string|null`): Promoted ad document ID from order notes.
  - `reason` (`string`): Rejection classification code (see table below).
  - `amountPaise` (`number|null`): Transaction amount in paise (divide by 100 for INR).
  - `currency` (`string|null`): Currency code (e.g., `'INR'`).
  - `createdAt` (`Timestamp`): Server timestamp when the rejection first occurred (never overwritten on replay).
  - `lastSeenAt` (`Timestamp`): Server timestamp of the latest delivery attempt.
  - `attempts` (`number`): Count of delivery attempts received for this rejection (incremented on replay).
- **Data Protection:** Contains strictly non-sensitive operational identifiers. **No user names, phone numbers, email addresses, or cardholder credentials are stored.**

---

## 2. Which Rejections Mean Money Was Taken?

> [!IMPORTANT]
> Because `razorpayWebhook` processes `payment.captured` and `order.paid` events, **in almost every rejection scenario, money has already been deducted from the provider's payment method, but their ad was NOT activated.**

| Rejection Reason | Financial Impact | Cause & Root Diagnosis | Operator Action |
|:---|:---:|:---|:---|
| `amount_mismatch` | **Money Taken** | Amount paid in paise does not match duration rate in `AD_PRICING_TABLE`. | Refund payment via Razorpay Dashboard. |
| `order_notes_missing` | **Money Taken** | Order created without `adId`, `providerUid`, or `durationHours` notes. | Refund payment or manually link ad. |
| `missing_identifiers` | **Money Taken** | Razorpay payload lacked `paymentId` or `orderId`. | Inspect Razorpay logs and refund if charged. |
| `currency_mismatch` | **Money Taken** | Payment captured in currency other than `INR`. | Refund payment via Razorpay Dashboard. |
| `ad_not_found` | **Money Taken** | The `adId` referenced in order notes does not exist in Firestore. | Refund payment or restore deleted ad. |
| `order_id_mismatch` | **Money Taken** | Ad exists, but its `razorpayOrderId` was superseded by a newer order. | Refund older order via Razorpay Dashboard. |
| `payment_already_used` | **Money Taken** | Payment ID was already claimed by another promoted ad document. | Possible double-spend or collision: investigate and refund duplicate. |
| `failed-precondition` | **Money Taken** | Ad was not in `pending_payment` state (e.g. already expired/active). | Verify ad status; refund if duplicate charge. |

---

## 3. How to Query Rejections

### Option A: Firebase Console
1. Open the [Firebase Console](https://console.firebase.google.com/project/medibond-45fad/firestore).
2. Navigate to **Firestore Database → Data → `razorpayWebhookRejections`**.
3. Sort or filter by `createdAt` (Descending) or filter by `reason`.

### Option B: Node.js Admin SDK / CLI Script
Run an Admin query from a secure environment:
```javascript
const admin = require('firebase-admin');
const db = admin.firestore();

async function getRecentRejections(limit = 50) {
  const snap = await db.collection('razorpayWebhookRejections')
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();

  return snap.docs.map(doc => ({
    id: doc.id,
    ...doc.data(),
    createdAt: doc.data().createdAt?.toDate()?.toISOString(),
  }));
}
```

---

## 4. How to Refund from the Razorpay Dashboard

When an ad payment is rejected, issue a refund directly through the Razorpay Merchant Portal:

1. Log into the [Razorpay Dashboard](https://dashboard.razorpay.com/).
2. In the left navigation, go to **Transactions → Payments**.
3. Search for the payment using the **`paymentId`** (`pay_...`) recorded in the `razorpayWebhookRejections` document.
4. Verify that the payment status is **Captured** and matches the amount recorded.
5. In the top right corner of the payment details card, click **Issue Refund**.
6. Select **Full Refund** (or enter the full amount in INR).
7. (Optional) In the refund notes, enter:
   `DoctorNect Promoted Ad Activation Rejected - Reason: <reason> (Ad ID: <adId>)`
8. Click **Confirm Refund**.
9. Notify the provider via support or have them recreate their ad booking in the app.

---

## 5. Log-Based Alert Policy (`gcloud` CLI Reference)

To automatically notify operations when a webhook is rejected, create a log-based metric and alerting policy in Google Cloud Monitoring.

> [!NOTE]
> The following commands are provided as text-only reference for operator configuration. Do not run automated deployment scripts.

### Step 1: Create a Log-Based Metric
Filter for structured rejection logs emitted by `promoted_ads.js`:
```bash
gcloud logging metrics create razorpay_webhook_rejections_metric \
  --project=medibond-45fad \
  --description="Counts rejected Razorpay promoted ad webhook payments" \
  --log-filter='resource.type="cloud_function"
resource.labels.function_name="razorpayWebhook"
jsonPayload.action="razorpay.webhook_rejected"
jsonPayload.securityEvent=true'
```

### Step 2: Define Alert Policy JSON (`rejection-alert-policy.json`)
```json
{
  "displayName": "Razorpay Webhook Payment Rejection Alert",
  "documentation": {
    "content": "A Razorpay webhook payment was rejected due to an invalid order or pricing mismatch. Inspect firestore collection razorpayWebhookRejections and issue customer refund if captured.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Razorpay Webhook Rejection Count > 0",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/razorpay_webhook_rejections_metric\" AND resource.type=\"cloud_function\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "60s",
        "trigger": {
          "count": 1
        },
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
```

### Step 3: Create the Alert Policy
```bash
gcloud alpha monitoring policies create \
  --project=medibond-45fad \
  --policy-from-file="rejection-alert-policy.json"
```
