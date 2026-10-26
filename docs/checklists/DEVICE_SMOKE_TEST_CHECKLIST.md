# DoctorNect Device Smoke Test Checklist
**Version:** 1.0 (Post-Migration Clean Verification)  
**Scope:** Doctor, Patient, Pharmacy, Lab, Ambulance  
**Pre-condition:** Firebase Cloud Functions deployed, Staging/Production Supabase active, `DoctorPatientCutoverFlag.isEnabled = true`.

---

## 1. Registration & Phone OTP Verification (5 User Roles)

Perform complete mobile registration flow on device for each role:
- [ ] **Role 1: Patient** (10-digit phone, enter received MSG91 OTP)
- [ ] **Role 2: Doctor** (10-digit phone, license details, enter OTP)
- [ ] **Role 3: Pharmacy / Medical Store** (10-digit phone, store name, enter OTP)
- [ ] **Role 4: Lab** (10-digit phone, lab name, enter OTP)
- [ ] **Role 5: Ambulance Driver** (10-digit phone, vehicle number, enter OTP)

### Expected Result
- Verification succeeds, custom token minted, user enters respective authenticated app shell.
- Firebase Auth custom claims contain:
  - `role`: `'authenticated'`
  - `app_role`: `'patient'` | `'doctor'` | `'pharmacy'` | `'lab'` | `'ambulance'`
  - `user_role`: matches `app_role`
  - `verified`: `false` (for providers) or `true` (for patients)

### Database & Redis Verification
- **Postgres Table:** `public.users`
  ```sql
  SELECT id, firebase_uid, phone, role, verified, created_at 
  FROM public.users 
  WHERE phone = '+91<TEST_PHONE>';
  ```
- **Redis Verification:** During OTP step, session exists with TTL in Redis:
  - Key: `otp:session:<SESSION_ID>` (TTL <= 900s)
  - Key: `ratelimit:otp_send:<IP_HASH>` and `ratelimit:otp_send:<PHONE_HASH>`

---

## 2. Patient Books Doctor Appointment

- [ ] Log in as Patient.
- [ ] Search for Doctor, select an available date and 15-minute slot.
- [ ] Complete booking.

### Expected Result
- Booking confirmation screen displays assigned Token Number (e.g., Token #1).
- Slot capacity remains <= 3 concurrent patients.
- Appointment appears under Patient's Upcoming Appointments and Doctor's Daily Schedule.

### Database Verification
- **Postgres Table:** `public.appointments`
  ```sql
  SELECT appointment_id, patient_id, doctor_id, date_time, slot_label, token_number, patient_status, doctor_status 
  FROM public.appointments 
  WHERE patient_id = '<PATIENT_PROFILE_ID>' 
  ORDER BY created_at DESC LIMIT 1;
  ```
  *Expected:* `patient_status = 'confirmed'`, `doctor_status = 'pendingRequest'|'confirmed'`.

---

## 3. Doctor Writes Prescription (S3 PDF Upload & Patient Access)

- [ ] Log in as Doctor. Open confirmed appointment.
- [ ] Tap "Write Prescription", select diagnosis (ICD-10) and medicines.
- [ ] Save & Generate Prescription PDF.
- [ ] Log in as Patient. Navigate to Prescriptions tab and tap to open the generated PDF.

### Expected Result
- Prescription PDF uploads to AWS S3 via presigned PUT URL.
- Metadata is confirmed and recorded in Supabase.
- Patient opens PDF directly from presigned GET URL without authentication failure.

### Database & S3 Storage Verification
- **Postgres Table:** `public.prescriptions`
  ```sql
  SELECT prescription_id, appointment_id, doctor_id, patient_id, pdf_s3_key, created_at 
  FROM public.prescriptions 
  WHERE appointment_id = '<APPOINTMENT_ID>';
  ```
- **S3 Bucket Object:**
  - Key: `prescriptions/<PRESCRIPTION_ID>.pdf` (File size > 0 bytes).

---

## 4. Pharmacy Order Status Lifecycle (Realtime Sync)

- [ ] Log in as Patient with an active prescription.
- [ ] Tap "Order Medicines" -> select linked Medical Store.
- [ ] Log in as Pharmacy. See incoming order in Realtime order stream.
- [ ] Progress order status: `Accepted` -> `Preparing` -> `Out for Delivery` -> `Delivered`.
- [ ] Verify Patient screen updates status in real-time without manual refresh.

### Expected Result
- State transitions execute via `update_pharmacy_delivery_status` RPC.
- **Realtime / Polling Behavior:**
  - *Staging (`APP_ENV=staging`):* Supabase Realtime WebSocket broadcasts status changes immediately to Patient UI.
  - *Production (`APP_ENV=production`):* `streamTable()` adaptive polling (~8s standard) with change detection re-fetches and updates Patient UI without manual refresh; skips redundant rebuilds if status has not changed.

### Database Verification
- **Postgres Table:** `public.pharmacy_orders` / `public.pharmacy_prescriptions`
  ```sql
  SELECT delivery_id, order_id, store_id, patient_id, status, updated_at 
  FROM public.pharmacy_prescriptions 
  WHERE patient_id = '<PATIENT_PROFILE_ID>' 
  ORDER BY updated_at DESC LIMIT 1;
  ```

---

## 5. Lab Booking & Report Upload

- [ ] Log in as Patient -> Book a Lab Test (e.g. Complete Blood Count).
- [ ] Log in as Lab -> Open incoming lab booking.
- [ ] Upload test report PDF.
- [ ] Log in as Patient -> Open Lab Bookings -> Download/View Lab Report.

### Expected Result
- Lab report PDF uploads to S3 -> confirmed -> linked to lab booking.
- Patient downloads and views report via presigned S3 GET URL.

### Database & S3 Verification
- **Postgres Table:** `public.lab_bookings` and `public.lab_reports`
  ```sql
  SELECT booking_id, lab_id, patient_id, test_name, status, report_s3_key 
  FROM public.lab_bookings 
  WHERE booking_id = '<BOOKING_ID>';
  ```
- **S3 Bucket Object:** `reports/labs/<BOOKING_ID>.pdf`.

---

## 6. Emergency Ambulance Dispatch & Live Tracking

- [ ] Log in as Patient -> Tap Emergency Ambulance -> Broadcast Request.
- [ ] Log in as Ambulance Driver -> Receive incoming broadcast alert.
- [ ] Driver taps "Accept Request".
- [ ] Driver streams GPS location updates while en route.
- [ ] Driver arrives and completes trip.

### Expected Result
- Broadcast accepted via `accept_ambulance_request` RPC (atomic row-lock, race-safe).
- Sibling pending requests automatically marked `taken`.
- Live location coordinates cached in Redis (`ambulance:location:<BROADCAST_ID>`) with 300s TTL.
- **Tracking Stream Behavior:**
  - *Staging (`APP_ENV=staging`):* Direct Supabase WebSocket stream.
  - *Production (`APP_ENV=production`):* `streamTable(isHighFrequency: true)` polls every ~3 seconds for active trips, delivering fresh coordinates without opening a persistent WebSocket.
- Patient map displays live ambulance movement.
- Completed via `complete_ambulance_trip` RPC (`status = 'completed'`).

### Database & Redis Verification
- **Postgres Table:** `public.ambulance_broadcasts`
  ```sql
  SELECT broadcast_id, patient_id, status, accepted_driver_id, accepted_at, updated_at 
  FROM public.ambulance_broadcasts 
  WHERE broadcast_id = '<BROADCAST_ID>';
  ```
- **Postgres Table:** `public.ambulance_requests`
  ```sql
  SELECT request_id, broadcast_id, driver_id, status 
  FROM public.ambulance_requests 
  WHERE broadcast_id = '<BROADCAST_ID>';
  ```
- **Redis Key:**
  - Key: `ambulance:location:<BROADCAST_ID>` (Type: String/JSON or Geo, TTL <= 300s).

---

## 7. Support Ticket Chat

- [ ] Log in as Patient -> Profile -> Help & Support.
- [ ] Create a new support ticket and send a message.
- [ ] Verify message sends and displays in conversation history.

### Database Verification
- **Postgres Table:** `public.support_tickets` & `public.support_ticket_messages`
  ```sql
  SELECT ticket_id, user_id, subject, status, created_at FROM public.support_tickets WHERE user_id = '<USER_ID>';
  SELECT message_id, ticket_id, sender_id, message_text, created_at FROM public.support_ticket_messages WHERE ticket_id = '<TICKET_ID>';
  ```

---

## 8. Profile Completion Modal

- [ ] Register new Doctor or Ambulance account.
- [ ] Navigate to Home/Profile. Verify Profile Completion prompt appears.
- [ ] Enter missing details (e.g., service areas, registration number).
- [ ] Save profile.

### Expected Result
- Details update directly in Supabase without error.
- Profile completeness reflects 100% and prompt dismisses.

### Database Verification
- **Postgres Table:** `public.doctors` / `public.ambulances` / `public.medical_stores` / `public.labs`
  ```sql
  SELECT profile_completed, verified FROM public.doctors WHERE owner_uid = '<AUTH_UID>';
  ```

---

## 9. Provider Verification Banner

- [ ] New provider accounts display `Under Verification` status banner.
- [ ] Admin approves account (sets `verified = true` via admin RPC or dashboard).
- [ ] Provider app refreshes: banner disappears, account status transitions to verified.

### Expected Result
- Verification status transitions cleanly without requiring Firestore writes.
