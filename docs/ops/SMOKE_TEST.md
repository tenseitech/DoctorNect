# DoctorNect Production Launch Smoke Test Plan

> **Scope:** 5 Active Launch Modules (Patient, Doctor, Pharmacy, Lab, Ambulance)  
> **Environment:** Launch Mode (`ENABLE_SUPABASE=1`, `use_supabase_db_doctor_patient=true`)  
> **Storage Mode:** Firebase Storage (`use_s3_storage=false`)  
> **Objective:** Empirically validate end-to-end functionality across all 5 modules before public release.

---

## Go / No-Go Decision Rule

> [!IMPORTANT]
> **Zero-Tolerance Launch Policy:**
> If ANY step in this smoke test fails due to database errors, permission denials, or custom claim race conditions that cannot be immediately resolved, **ABORT the Supabase cutover** and execute the **Firestore Fallback**:
> 1. Set Remote Config `use_supabase_db_doctor_patient=false`.
> 2. Build the app without `-Launch` flag (`./scripts/release_build.ps1`).
> 3. Launch with the 100% verified native Firestore engine, and address PostgreSQL issues post-launch.

---

## Pre-Test Setup
1. Device / Emulator running release build built with `-Launch` (`ENABLE_SUPABASE=1`).
2. Firebase Remote Config published with:
   - `use_supabase_db_doctor_patient = true`
   - `use_s3_storage = false`
3. Third-Party Auth enabled in Supabase Dashboard (`rnltknemwnjrjxthtull`).

---

## Test Execution Steps

### 1. Patient OTP Signup & Session Verification
- **Action:** Open app, select "Patient", enter mobile number, verify OTP.
- **Expected Result:**
  - Login succeeds and navigates to Patient Home.
  - JWT minted with custom claim `role: "authenticated"` verified via `getIdToken(true)`.
  - Patient record created in `public.users` and `public.patients`.
- **What a Failure Looks Like:**
  - Screen displays: `"Your account session is initializing security claims. Please sign in again or refresh."` or hangs indefinitely.
  - *Root Cause:* Third-Party Auth disabled in Supabase Dashboard, or `completeMobileOtpLogin` failed to set custom claims.

### 2. Patient Books Appointment
- **Action:** Select verified doctor, choose tomorrow's date and a morning slot, click "Confirm Booking".
- **Expected Result:**
  - Booking confirmed dialog appears with token number.
  - Row created in `public.appointments` with status `pending` or `confirmed`.
  - Advisory lock in `book_appointment_atomic` prevents duplicate slot allocation.
- **What a Failure Looks Like:**
  - Booking fails with "Slot unavailable" or PostgREST error 403 / 42501 (RLS violation).
  - *Root Cause:* RLS policy on `public.appointments` denying insert, or doctor schedule not initialized in PostgreSQL.

### 3. Doctor Calendar Visibility
- **Action:** Log in as the booked Doctor, open "Appointments" tab.
- **Expected Result:**
  - The newly booked appointment appears in the doctor's calendar list with patient name and time slot.
- **What a Failure Looks Like:**
  - Empty calendar list (`[]`), despite successful booking.
  - *Root Cause:* RLS policy evaluating `(auth.jwt() ->> 'sub')` does not match the doctor's authenticated Firebase UID.

### 4. Doctor Writes Prescription
- **Action:** Doctor opens the appointment, clicks "Write Prescription", adds 2 medicines (e.g., Paracetamol, Amoxicillin), dosage instructions, and clicks "Save Prescription".
- **Expected Result:**
  - Prescription saved confirmation appears.
  - Rows created in `public.prescriptions` and `public.prescription_medicines`.
  - Patient can see the prescription under "My Prescriptions".
- **What a Failure Looks Like:**
  - Error: "Failed to create prescription" or foreign key violation on appointment ID.
  - *Root Cause:* `create_prescription_atomic` RPC failure or missing RLS insert permission on `prescription_medicines`.

### 5. Pharmacy Receives & Fulfills Delivery
- **Action:** Log in as Pharmacy provider, open "Incoming Orders / Deliveries" tab.
- **Expected Result:**
  - The patient prescription appears as a fulfillment request.
  - Pharmacy clicks "Accept & Dispatch", order status updates to `out_for_delivery`.
  - Row in `public.pharmacy_deliveries` updates status via `update_pharmacy_delivery_status`.
- **What a Failure Looks Like:**
  - Deliveries list is empty (`[]`).
  - *Root Cause:* Missing pharmacy assignment query or RLS policy restriction on `pharmacy_deliveries`.

### 6. Lab Booking & Report Upload
- **Action:**
  1. Patient selects "Book Diagnostic Test", chooses "Complete Blood Count", selects Lab provider, confirms.
  2. Log in as Lab provider, open "Pending Tests", select booking, upload sample report PDF (via test file).
- **Expected Result:**
  - Lab booking saved in `public.lab_bookings`.
  - Report file uploaded successfully to storage.
  - Status transitions to `completed`.
- **What a Failure Looks Like:**
  - File upload fails with network/security exception, or report metadata not saved.
  - *Root Cause:* Storage security rules rejecting upload or lab not authorized on booking record.

### 7. Patient Views Lab Report
- **Action:** Log in as Patient, navigate to "Health Records" > "Lab Reports", tap on the completed report.
- **Expected Result:**
  - Report PDF renders in document viewer or downloads successfully.
- **What a Failure Looks Like:**
  - "Access Denied" or download URL returns 403 Forbidden.
  - *Root Cause:* Storage access rule does not recognize patient as the subject of the lab report.

### 8. Patient SOS Emergency Broadcast
- **Action:** Patient taps the red "SOS Emergency" button on home screen, confirms location.
- **Expected Result:**
  - Emergency SOS screen shows "Broadcasting to nearby ambulances...".
  - Row created in `public.ambulance_broadcasts` with GPS coordinates.
- **What a Failure Looks Like:**
  - "Failed to broadcast emergency request" or timeout.
  - *Root Cause:* `AmbulanceRepository.broadcastAmbulanceRequest` cutover routing failure or missing insert permission on `ambulance_broadcasts`.

### 9. Ambulance Driver Acceptance & GPS Tracking
- **Action:**
  1. Log in as Ambulance driver, observe incoming emergency alert.
  2. Tap "Accept Emergency", verify patient location.
  3. Start trip, simulate moving coordinates.
- **Expected Result:**
  - Driver status changes to `en_route`.
  - Patient screen transitions from searching to "Ambulance on the way", displaying live driver location.
- **What a Failure Looks Like:**
  - Emergency alert never appears on driver device, or location updates fail to stream.
  - *Root Cause:* Realtime subscription failure or RLS blocking driver from updating location.

---

## Smoke Test Summary Scorecard

| Module | Test Step | Status (Pass/Fail) | Verified Evidence |
|:---|:---|:---:|:---|
| **Patient** | OTP Signup & Claims | [ ] | Verified `getIdToken(true)` in `firebase_auth_service.dart:340` |
| **Patient** | Book Appointment | [ ] | Verified `book_appointment_atomic` in migration 20260926000001 |
| **Doctor** | Calendar View | [ ] | Verified RLS on `public.appointments` (`doctor_id = auth.jwt()->>'sub'`) |
| **Doctor** | Write Prescription | [ ] | Verified `create_prescription_atomic` in migration 20261022000001 |
| **Pharmacy** | Fulfill Delivery | [ ] | Verified `SupabasePharmacyRepository` delivery methods |
| **Lab** | Book & Upload Report | [ ] | Verified `SupabaseLabRepository` and storage rules |
| **Lab/Patient** | View Lab Report | [ ] | Verified storage download gate |
| **Ambulance** | Emergency SOS Broadcast | [ ] | Verified `AmbulanceRepository.broadcastAmbulanceRequest` |
| **Ambulance** | Driver Accept & GPS | [ ] | Verified `SupabaseAmbulanceRepository` and GPS streaming |

**Final Recommendation:**
- If all 9 steps **PASS**: **PROCEED WITH LAUNCH (Supabase Mode)**.
- If any step **FAILS**: **EXECUTE FALLBACK (Firestore Mode)** immediately.
