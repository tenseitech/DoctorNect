# Doctor App — Full Audit Report
Generated: 2026-06-08

Stack: Flutter (Dart) client + Firebase/Firestore backend. The "backend" for each module is Firestore collections + `firestore.rules` + `firestore.indexes.json`. Findings below were verified against source files; line numbers reference the current workspace.

Severity legend: **Critical** = crashes / data loss / broken core flow / security hole. **Warning** = wrong behavior but does not crash. **Note** = improvement suggestion.

---

## 1. Doctor Module

### Critical Issues
- [ ] Profile edits never persist to Firestore — file: `lib/features/doctor/profile/sections/personal_info_section.dart` line: 58 (also `clinic_info_section.dart:72`, `professional_details_section.dart:44`, `consultation_settings_section.dart:31`, `notification_prefs_section.dart:28`, `edit_profile_section.dart:40`) — Every "Save" handler only mutates `DoctorProfileStore.instance.profile` in memory and shows a toast; there is no `doctors/{doctorId}` write. Edits are lost on restart and never reach patient search.
- [ ] Home "Add Prescription" uses a fake `patientId` — file: `lib/features/doctor/home/doctor_home_screen.dart` line: 135 — `_openPrescriptionWithSearch` hardcodes `patientId: 'fallback_${picked.id}'` (the investigations path at line 167 correctly uses `record?.patientId`). Prescriptions are written with a fake id, so rules (`prescriptions` read requires `patientId == myPatientId()`) prevent the patient from ever reading them.
- [ ] Reviews list never loaded from Firestore — file: `lib/features/doctor/profile/sections/reviews_section.dart` line: 18 (store init `doctor_profile_store.dart:80`) — UI reads `profile.reviews`, which is initialized empty and never populated from `ReviewRepository.fetchForDoctor` on login/prefetch, so the reviews list is always empty despite data existing.
- [ ] Doctor review replies are not saved — file: `lib/features/doctor/profile/sections/reviews_section.dart` line: 42 — "Post Reply" only does `setState(() => review.doctorReply = ...)` and shows "Reply posted". No Firestore update is made even though rules (`firestore.rules:240-242`) allow updating `doctorReply`; replies vanish on navigation.

### Warnings
- [ ] Synthetic `PAT-{hash}` patient IDs break patient access — file: `lib/features/doctor/clinical/models/clinical_models.dart` line: 149 — When `patient.patientId` is null, prescriptions/lab orders/referrals use a hash-derived `PAT-######` id that never matches a real patient's `myPatientId()`, so patients never see the records even though the doctor UI reports success.
- [ ] Doctor pharmacy delivery history not loaded after restart — file: `lib/core/firebase/repositories/pharmacy_firestore_repository.dart` line: 67 — Repository exposes `fetchDeliveriesForPatient`/`fetchDeliveriesForStore` only; there is no `fetchDeliveriesForDoctor` and doctor prefetch never hydrates `PharmacyPrescriptionStore`, so "Prescriptions Sent" shows only in-session sends.
- [ ] KYC upload files collected but never submitted — file: `lib/features/auth/doctor_registration_screen.dart` line: 157 — Registration validates certificate/ID file picks but the `roleData` sent to Firebase contains no document URLs/paths, so admin verification has nothing to review.
- [ ] Date of birth cannot be edited — file: `lib/features/doctor/profile/sections/personal_info_section.dart` line: 39 — `_pickDob()` returns immediately when `_dob != null`; profile defaults DOB to `1990-01-01`, so the picker never opens and DOB cannot be corrected.
- [ ] Account reactivation auto-sets `verified: true` — file: `lib/core/firebase/repositories/doctor_account_repository.dart` line: 133 — `reactivate()` sets `verified: true`, bypassing the admin KYC gate (registration sets `verified: false`); a self-reactivated doctor becomes searchable as verified without re-approval.
- [ ] Firestore writes fail silently for prescriptions/lab orders — file: `lib/features/doctor/clinical/data/clinical_prescription_store.dart` line: 92 (also `lib/features/doctor/clinical/data/lab_order_store.dart:32`) — `save()/add()` update local state and call Firestore via `unawaited(...)` with no `.catchError`; permission/network failures leave the UI showing "saved" while Firestore has no record.
- [ ] Dead cross-module call to in-memory mock — file: `lib/features/doctor/clinical/prescription/write_prescription_screen.dart` line: 242 — After the real Firestore save, the flow also calls `PatientProfileMock.syncPrescriptionFromDraft`, which only updates an in-memory map (`patient_profile_mock.dart:209`); it gives misleading "patient notified" UX with no guaranteed patient visibility.
- [ ] `loadFromFirestore` omits most editable profile fields — file: `lib/features/doctor/profile/data/doctor_profile_store.dart` line: 122 — Fields that exist on the doctor doc (clinic address, consultation settings, notification prefs, awards) are not mapped into `DoctorProfileData`, so the profile UI shows defaults/stale values after re-login.
- [ ] Lab order success UI overstates patient delivery — file: `lib/features/doctor/clinical/lab/lab_test_order_screen.dart` line: 346 — Success sheet shows "Patient notified", but for walk-ins (`wi...`) / synthetic ids the patient app cannot read `lab_orders` from Firestore; the notification is local/in-app only.

### Notes / Suggestions
- [ ] Empty catch swallows availability fetch errors — file: `lib/features/doctor/clinical/prescription/prescription_header_helper.dart` line: 52 — `loadConsultationTimings` silently falls back to defaults; offline/permission failures are invisible and the PDF may show wrong clinic hours.
- [ ] Cache short-circuit prevents refresh — file: `lib/features/doctor/clinical/data/clinical_prescription_store.dart` line: 157 — `if (preferCache && _hasPatientRecords(patientId)) return;` skips re-fetching from Firestore when any local record exists, risking stale data.
- [ ] `ReferralRepository` is write-only — file: `lib/core/firebase/repositories/referral_repository.dart` line: 13 — Referrals are saved but never fetched; the receiving doctor has no inbound-referral screen even though rules allow `toDoctorId` updates.
- [ ] Dead `ReferralStore` with hardcoded specialists — file: `lib/features/doctor/clinical/data/referral_store.dart` line: 18 — Hardcoded "Ramesh/Suresh" entries; the store is never referenced (real referrals use `RegisteredDoctorsStore` + Firestore).
- [ ] Walk-in IDs excluded from demographics fetch — file: `lib/features/doctor/patients/data/doctor_patients_service.dart` line: 158 — `_isFirestorePatientId` only matches `^p\d+$`, so walk-in `wi...` ids skip `fetchPatientDocument` and show placeholder demographics.
- [ ] No missing Firestore indexes found for current doctor queries — file: `firestore.indexes.json` — Appointment/prescription/pharmacy/medical_directory/lab_order queries match deployed indexes; issues are wrong field values and missing persistence, not index gaps.

---

## 2. Patient Module

### Critical Issues
- [ ] Lab slot-availability query violates Firestore rules — file: `lib/core/firebase/repositories/lab_booking_repository.dart` line: 45 — `bookedSlotLabelsForDate` queries `lab_bookings` with only a `dateTime` range and no `patientId` filter, but rules allow patient reads only when `resource.data.patientId == myPatientId()` (`firestore.rules:265`). The query is rejected at runtime, slot loading silently returns empty, and patients can double-book taken slots.
- [ ] Appointment `dateTime` ignores the selected slot time — file: `lib/core/data/shared_appointments_store.dart` line: 414 — `addBooking` builds `dateTime` from the calendar date only (`date.hour > 0 ? date.hour : 10`) and never parses `slotLabel` (e.g. "04:30 PM"). Stored appointments have the wrong timestamp, so cards and reminder scheduling fire at the wrong time.
- [ ] "Booking Confirmed" shown even when Firestore persist fails — file: `lib/core/data/shared_appointments_store.dart` line: 219 — `_persist` catches all `AppointmentRepository.save` failures and only `debugPrint`s them; `addBooking` always succeeds in memory, so `booking_flow_screen.dart:553` shows the confirmed screen and emits notifications even though the write failed (data loss across devices/reinstall).
- [ ] Lab booking proceeds without auth/patient guard or error handling — file: `lib/features/patient/lab/lab_booking_flow_screen.dart` line: 102 — `_confirm` calls `LabBookingRepository.save` with `PatientSession.loggedInPatientId` (may be empty), has no try/catch, no loading state, and always navigates to the confirmed screen; an empty `patientId` violates create rules and exceptions are unhandled.

### Warnings
- [ ] Family members added during booking are not persisted — file: `lib/features/patient/booking/booking_flow_screen.dart` line: 359 — The sheet adds a `FamilyMember` to local state only; unlike `AddFamilyMemberProfileScreen` it never calls `FamilyMemberRepository.saveMember`, so booking-time members are lost on restart.
- [ ] Records skip Firestore when local mock cache is non-empty — file: `lib/features/patient/records/patient_records_screen.dart` line: 55 — `_loadRecords` returns early when `HealthRecordsMock.records()` is non-empty, never reconciling with Firestore; records added on another device never appear.
- [ ] Record delete removes from UI even if Firestore delete fails — file: `lib/features/patient/records/patient_records_screen.dart` line: 214 — Delete calls Firestore + local file delete with no try/catch, then unconditionally calls `HealthRecordsMock.removeRecord`; a failed backend delete still removes it from the UI while it remains in `health_records`.
- [ ] Health-record fetch failures silently return empty — file: `lib/core/firebase/repositories/patient_profile_repository.dart` line: 36 — `fetchHealthRecords` wraps the whole pipeline in `catch (_) { return const []; }`; permission/network errors and bad enum values (`HealthRecordType.values.byName`) all surface as "no records" with no error state.
- [ ] `BuildContext` used after `await` without `mounted` — file: `lib/features/patient/records/add_record_screen.dart` line: 121 — After `await _fileBytes(picked)`, `ScaffoldMessenger.of(context)` is used without a `mounted` check; can throw if the widget was disposed.
- [ ] Appointment cancel not awaited; success shown before persist — file: `lib/features/patient/appointments/patient_appointments_screen.dart` line: 94 — `cancelByPatient` is async but invoked without `await`; the snackbar and tab switch happen immediately while the Firestore update may still fail (errors are swallowed in `_persist`).
- [ ] Prescription opener may open the wrong prescription — file: `lib/features/patient/appointments/patient_prescription_opener.dart` line: 90 — When no appointment-linked or diagnosis-matched draft is found, `_matchDraft` returns `drafts.first`, so opening from a completed appointment can show another doctor's Rx.
- [ ] Doctor-ordered lab tests have no patient-side UI — file: `lib/core/firebase/repositories/lab_order_repository.dart` (only `fetchForDoctor`) — Doctors create `lab_orders` that rules let patients read (`firestore.rules:301`) and a `notifyLabOrderSent` exists, but the patient module has no repository call or screen to list them; doctor->patient lab flow is broken in the UI.
- [ ] Slot collision check is per-patient only — file: `lib/core/firebase/repositories/lab_booking_repository.dart` line: 64 — Even if the rules query were fixed, `availableSlotsForPeriod` would only exclude the current patient's bookings, not global slot capacity.
- [ ] `setState` after `await` without `mounted` in DOB picker — file: `lib/features/auth/patient_registration_screen.dart` line: 53 — `_pickDob` awaits `showDatePicker` then calls `setState` without a `mounted` check.
- [ ] Appointment merge never removes stale records — file: `lib/core/data/shared_appointments_store.dart` line: 187 — `mergeFromFirestore` upserts remote records but never removes local entries deleted server-side, so cancelled/deleted appointments can linger in the list.
- [ ] `PatientAppointment` model omits `slotLabel` — file: `lib/features/patient/appointments/models/patient_appointment_models.dart` line: 3 — `slotLabel` is not mapped through, so cards display only `dateTime` (which is itself wrong per the Critical finding) and never show the chosen slot.
- [ ] Help & Support issue form is a stub — file: `lib/features/patient/profile/support/help_support_screen.dart` line: 29 — `_submitIssue` validates then shows a success snackbar only; nothing is sent to Firestore/email/ticketing and the screenshot is discarded.
- [ ] Completed appointment "Report" download is a stub — file: `lib/features/patient/appointments/widgets/completed_appointment_card.dart` line: 92 — The button shows "Downloading report..." with no fetch, navigation, or Firestore read.
- [ ] Lab report screen actions are stubs — file: `lib/features/patient/lab/lab_report_screen.dart` line: 22 — Download, Share, and "Send to doctor" each show a placeholder snackbar with no implementation.
- [ ] Hardcoded phlebotomist in lab notifications — file: `lib/core/notifications/patient_notification_scheduler.dart` line: 119 — `_checkLabCollection`/`_checkPhlebotomistOnWay` emit notifications with hardcoded "Ravi Kumar" / "+91 99887 76655" instead of data from `lab_bookings`.
- [ ] Vaccination reminder hardcoded — file: `lib/core/notifications/patient_notification_scheduler.dart` line: 170 — `_checkVaccinationDue` always notifies for "Influenza" in 7 days, unrelated to the patient's actual vaccination records.
- [ ] "Connected doctors" share sheet lists all searchable doctors — file: `lib/features/patient/records/patient_records_screen.dart` line: 186 — The share sheet lists `RegisteredDoctorsStore.instance.searchableDoctors.take(10)`, but sharing is a single `sharedWithDoctors` boolean; misleading UX vs. the actual access model.

### Notes / Suggestions
- [ ] "Add to Calendar" buttons are no-ops — file: `lib/features/patient/booking/widgets/booking_confirmed_view.dart` line: 119 (also `lib/features/patient/lab/lab_booking_confirmed_screen.dart:65`) — Buttons show a snackbar or `onPressed: () {}` with no calendar integration.
- [ ] About screen legal/rating links are stubs — file: `lib/features/patient/profile/about/about_screen.dart` line: 44 — Terms/privacy/rate-app actions show placeholder snackbars; no URLs opened.
- [ ] Record-preview download only confirms local save — file: `lib/features/patient/records/record_preview_screen.dart` line: 94 — Shows "File is saved on this device"; no export/share.
- [ ] Storage uploads are no-ops — file: `lib/features/patient/records/data/health_record_file_store.dart` line: 118 — Files stay device-local; `storageUrl`/`photoUrl` stay null, so records are not viewable on other devices.
- [ ] Missing `lab_bookings` composite index — file: `firestore.indexes.json` — No `lab_bookings` index (e.g. `patientId` + `dateTime`); needed once the slot query is made rules-compliant.
- [ ] Heavy reliance on in-memory mock stores — files: `patient_profile_mock.dart`, `health_records_mock.dart` — Profile/records/notifications read from mock hybrids, making Firestore the secondary source and increasing stale-data risk.
- [ ] Referral notification uses wrong trigger enum — file: `lib/core/notifications/patient_notification_emitter.dart` line: 137 — Uses `PatientNotificationTrigger.bookingConfirmed` instead of a dedicated referral trigger.
- [ ] Patient<->lab booking integration is one-way — files: `lab_home_screen.dart` -> `lab_booking_flow_screen.dart` -> `LabBookingRepository` — Bookings are written but there is no read path to list past lab bookings or sync with lab fulfillment.

---

## 3. Pharmacy Module
(Pharmacy = the medical-store role, `UserType.medicalStore`.)

### Critical Issues
- [ ] No real-time / periodic delivery sync for the store — file: `lib/features/pharmacy/screens/store_dashboard_screen.dart` line: 38 — The prescriptions tab reads only from in-memory `PharmacyPrescriptionStore`; deliveries are fetched once at login with no `snapshots()` listener and no pull-to-refresh, so a prescription sent while the store app is open is invisible until restart.
- [ ] Doctor delivery history never loaded from Firestore — file: `lib/core/firebase/firestore_data_prefetch.dart` line: 34 — Doctor prefetch loads pharmacy connections but not deliveries, and `PharmacyFirestoreRepository` has no `fetchDeliveriesForDoctor`; doctor pharmacy UI reads local memory only and status is lost after restart.
- [ ] Medicine availability / substitute state not persisted — file: `lib/features/pharmacy/data/pharmacy_prescription_store.dart` line: 158 (and `pharmacy_firestore_repository.dart:56`) — `updateMedicineLine()` updates local `medicineLines` only and never writes to Firestore; after refresh or on another device all lines revert to `pending` and OOS/substitute choices are lost.
- [ ] `patientId` mismatch breaks patient pharmacy status — file: `lib/core/firebase/repositories/pharmacy_firestore_repository.dart` line: 43 — Deliveries are written with `delivery.draft.patientId` (which falls back to `PAT-{hash}`/`fallback_{appointmentId}`), but the patient queries with the real `PatientSession.loggedInPatientId`, so patient pharmacy chips stay empty.
- [ ] `sendToStores` silently drops deliveries — file: `lib/features/pharmacy/data/pharmacy_prescription_store.dart` line: 94 — If `MedicalStoreRegistry.findById(storeId)` returns null (prefetch race, 60-store cap, fresh login) the loop `continue`s with no error, yet the doctor UI reports success, so some stores never receive the prescription.
- [ ] Profile screen force-unwrap can crash after login — file: `lib/features/pharmacy/screens/store_profile_screen.dart` line: 16 — `MedicalStoreRegistry.findById(MedicalStoreSession.loggedInStoreId)!` throws if the registry isn't populated yet; session is set immediately at login but registry fill is async, so opening Profile early null-check-crashes.

### Warnings
- [ ] Self-registration sets `verified: true` with no admin gate — file: `lib/features/auth/medical_store_registration_screen.dart` line: 90 — Every new store is written verified; `MedicalStoreRepository.isStoreVerified()` exists but is never called.
- [ ] `fetchVerifiedStores` does not filter verified — file: `lib/core/firebase/repositories/medical_store_repository.dart` line: 24 — The query has no `.where('verified', isEqualTo: true)`, so unverified stores appear in doctor/pharmacy search despite the method name.
- [ ] Doctor pharmacy notifications only fire on same device — file: `lib/features/pharmacy/data/pharmacy_prescription_store.dart` line: 141 — `markViewed`/`updateMedicineLine`/`markDispensed` call `InAppNotificationService.addDoctor` only when `d.doctorId == DoctorSession.loggedInDoctorId`, with no `in_app_notifications` write for the doctor's uid; other sessions/devices are never notified.
- [ ] Pharmacy notifications are in-memory only — file: `lib/features/pharmacy/data/pharmacy_notification_store.dart` line: 25 — `addStore()` inserts into a local list only and writes nothing to `in_app_notifications`, so all pharmacy alerts are lost on restart.
- [ ] Incomplete prescription round-trip mapping — file: `lib/core/firebase/mappers/prescription_firestore_mapper.dart` line: 24 — `fromMap` does not restore `age`/`gender` (age defaults to 0), investigations (always empty after reload), medicine `id` (new auto-ids), `frequency`, or `quantity`; the store detail UI shows wrong age/empty investigations and line-matching can fail after reload.
- [ ] State mutated during `build` on dashboard — file: `lib/features/pharmacy/screens/store_dashboard_screen.dart` line: 56 — `_selectedDoctorId` is assigned inside the `ListenableBuilder` builder without `setState`, violating Flutter's build contract.
- [ ] Pending-connection listener detached on the default tab — file: `lib/features/pharmacy/medical_store_shell.dart` line: 54 — `attachPendingConnections` runs only on tabs 1/2; tab 0 (Prescriptions, the default) calls `detachPendingConnections`, so incoming connection requests don't merge in real time on the main screen.
- [ ] Firestore write failures silently swallowed — file: `lib/features/pharmacy/data/pharmacy_connection_store.dart` line: 25 (also `pharmacy_prescription_store.dart:111,154,215`) — `unawaited(save...)` with no `.catchError`; UI shows local success while the write may have failed.
- [ ] `firstWhere` without `orElse` can throw — file: `lib/features/pharmacy/screens/connect_doctors_screen.dart` line: 142 (also `doctor_connected_stores_screen.dart:240`) — If pending state changes between render and tap, `firstWhere` throws `StateError` and crashes the screen.
- [ ] `markDispensed` does not require availability to be set — file: `lib/features/pharmacy/screens/store_prescription_detail_screen.dart` line: 380 — A store can mark dispensed with all medicines still `pending`; status becomes `dispensed` (not partial), misleading doctor and patient.
- [ ] Store registry capped at 60 documents — file: `lib/core/firebase/repositories/medical_store_repository.dart` line: 30 — `limit(connectionsPage * 2)` (= 60); stores beyond that are invisible to search/send and cause "Medical store not found".
- [ ] No loading/error UI when prefetch fails — file: `lib/features/pharmacy/screens/store_dashboard_screen.dart` line: 49 — Prefetch errors are `debugPrint` only; the dashboard shows empty state with no spinner/error, masking permission or index failures.

### Notes / Suggestions
- [ ] `isStoreVerified` is dead code — file: `lib/core/firebase/repositories/medical_store_repository.dart` line: 14 — Defined but never referenced; the intended verification gate was never wired in.
- [ ] Doctor council registration numbers always empty — file: `lib/features/pharmacy/data/pharmacy_connection_store.dart` line: 22 — `councilNumbers` is a hardcoded empty map, so `ConnectDoctorsScreen` never shows registration numbers.
- [ ] Connect Doctors shows no initial results — file: `lib/features/pharmacy/screens/connect_doctors_screen.dart` line: 26 — `_results` starts empty and (unlike the doctor side) the pharmacy must tap Search before any doctors appear.
- [ ] Notification tap uses fragile substring match — file: `lib/features/pharmacy/screens/store_notifications_screen.dart` line: 57 — Navigation depends on `n.title.contains('prescription')` (case-sensitive); renamed titles won't navigate.
- [ ] Rules allow any signed-in user to read all `medical_stores` — file: `firestore.rules` line: 338 — No `verified == true` constraint on read (unlike doctors); unverified stores are fully readable.
- [ ] Field-name inconsistency across pharmacy collections — file: `firestore.rules` line: 352 — `pharmacy_connections` uses `medicalStoreId` while `pharmacy_deliveries` uses `storeId`; code matches today but any wrong-field query compiles and fails at runtime with permission errors.

---

## 4. Lab Module
Headline finding: the Lab operator role exists in routing/enums (`UserType.lab`, `LabShell`) but is **not implemented end-to-end** — backend rules, session, UI, and cross-role integrations are missing or one-sided.

### Critical Issues
- [ ] Lab user role is a stub — no real dashboard — file: `lib/features/lab/lab_shell.dart` line: 8 — `LabShell` is a placeholder ("Lab Dashboard Coming Soon"); there is no order inbox, booking queue, report upload, or profile screen for lab users.
- [ ] Lab registration is not implemented — file: `lib/features/auth/lab_login_screen.dart` line: 15 — The registration route is a static "Lab Registration Coming Soon" Scaffold; no lab registration screen exists.
- [ ] Firestore rules block creating `users` docs with role `lab` — file: `firestore.rules` line: 143 — `users/{uid}` create only permits `doctor`/`patient`/`medicalStore`, but the app writes `'lab'` (`user_repository.dart:41`), so lab email registration fails at profile creation.
- [ ] No security rules for the `labs/{labId}` collection — file: `firestore.rules` line: 468 — There is no `match /labs/...` block; the app defines `FirestorePaths.labs` and writes lab profile docs (`user_repository.dart:60`), but the default-deny rule blocks all reads/writes.
- [ ] No `isLab()` role in rules — lab users cannot access lab data — file: `firestore.rules` line: 64 — Rules define doctor/patient/store helpers but no lab role; `lab_orders` read/create is limited to doctors (+ patient read), so a signed-in lab user has no path to read orders directed at them.
- [ ] Doctor->Lab integration is broken — no lab-side consumer of `lab_orders` — file: `lib/core/firebase/repositories/lab_order_repository.dart` line: 26 — Only `fetchForDoctor` exists; there is no `fetchForLab`, screen, or stream that reads orders, so doctor-created orders are invisible to any lab operator.
- [ ] Patient->Lab integration is broken — labs never receive bookings — file: `lib/core/firebase/repositories/lab_booking_repository.dart` line: 25 — Bookings store `partnerLab` as a plain name string with no `labId` and no lab notification; `lab_bookings` rules allow only patient read/create/update, and no lab UI reads them.
- [ ] Slot-availability query violates Firestore rules — file: `lib/core/firebase/repositories/lab_booking_repository.dart` line: 45 — `bookedSlotLabelsForDate` queries all `lab_bookings` for a date range without a `patientId` filter; rules (`firestore.rules:265`) deny that list query, breaking slot loading in production. (Same root issue surfaces under Patient.)
- [ ] Booking confirmation shown when save silently no-ops — file: `lib/features/patient/lab/lab_booking_flow_screen.dart` line: 102 — `LabBookingRepository.save` returns early without throwing when Firebase isn't ready or draft fields are null; `_confirm()` always navigates to the confirmed screen, so users see "Booking Confirmed!" without a persisted booking.
- [ ] Schedule step can hang forever on Firestore errors — file: `lib/features/patient/lab/lab_booking_flow_screen.dart` line: 451 — `_loadSlots()` sets `_loading = true` then awaits the slot query with no try/catch; if it throws (permission/network), `_loading` never resets and the UI spins forever.

### Warnings
- [ ] Lab login sets no session state — file: `lib/core/firebase/firebase_auth_service.dart` line: 547 — `_applyProfile` for `UserType.lab` is an empty `break`; there is no `LabSession`, so even a provisioned lab account has no in-app profile id for queries.
- [ ] Lab OAuth / missing-profile login rejected — file: `lib/core/firebase/firebase_auth_service.dart` line: 647 — OAuth completion auto-provisions only patients; lab signs the user out, so lab OAuth cannot onboard.
- [ ] Lab credential cache not implemented — file: `lib/core/auth/app_credential_store.dart` line: 102 — `registerForRole` and `findEmailByMobile` no-op for `UserType.lab`.
- [ ] Lab data prefetch is a no-op — file: `lib/core/firebase/firestore_data_prefetch.dart` line: 114 — After lab login, prefetch does nothing (empty `break`).
- [ ] Doctor lab orders store only `labName`, not `labId` — file: `lib/core/firebase/models/doctor_lab_order.dart` line: 31 — Orders reference a display name only with no link to a `labs/{labId}` account, so routing an order to a specific lab is impossible.
- [ ] Synthetic/fallback `patientId` breaks patient access to orders — file: `lib/features/doctor/clinical/lab/lab_order_service.dart` line: 11 — When `patient.patientId` is missing, `PAT-######`/`fallback_*` ids are used that never match a real patient's `myPatientId()`.
- [ ] Success sheet misrepresents lab notification — file: `lib/features/doctor/clinical/lab/lab_test_order_screen.dart` line: 347 — Shows "Lab order saved" when a lab is selected, but `LabOrderService` only notifies the patient; no lab notification is emitted.
- [ ] Personal lab contacts (`medical_directory`) not used in order flow — file: `lib/features/doctor/clinical/lab/lab_test_order_screen.dart` line: 270 — The "Preferred lab" dropdown uses hardcoded `partnerLabs` from `lab_catalog`, not the doctor's saved directory entries; two disconnected lab-contact systems.
- [ ] `LabOrderStore.add` persists with no error handling — file: `lib/features/doctor/clinical/data/lab_order_store.dart` line: 28 — `unawaited(LabOrderRepository.instance.save(order))` swallows write failures while the UI shows success.
- [ ] Lab home catalog load has no error UI — file: `lib/features/patient/lab/lab_home_screen.dart` line: 64 — The `FutureBuilder` treats `!hasData` as loading only; on error it spins forever with no retry.
- [ ] "View Booking" pops to app root — file: `lib/features/patient/lab/lab_booking_confirmed_screen.dart` line: 75 — `Navigator.popUntil(..., isFirst)` returns to the shell root; there is no booking-detail/history screen.
- [ ] "Add to Calendar" is a dead button — file: `lib/features/patient/lab/lab_booking_confirmed_screen.dart` line: 66 — `onPressed: () {}`.
- [ ] Lab report screen is mock-only — file: `lib/features/patient/lab/lab_report_screen.dart` line: 63 — Placeholder "PDF viewer (mock)"; download/share/send only show snackbars.
- [ ] Lab collection reminders use hardcoded phlebotomist data — file: `lib/core/notifications/patient_notification_scheduler.dart` line: 120 — Fixed name/phone unrelated to any booking.
- [ ] Last lab booking stored in memory only — file: `lib/core/notifications/patient_activity_store.dart` line: 9 — `lastLabBooking` drives reminders but is lost on restart even if a Firestore booking exists.
- [ ] Lab booking uses mock profile data as primary source — file: `lib/features/patient/lab/lab_booking_flow_screen.dart` line: 45 — Patient name/age/address/family come from `PatientProfileMock`, risking stale/default values.
- [ ] Firestore screen-sync empty for lab role — file: `lib/core/firebase/firestore_screen_sync.dart` line: 26 — Lab gets `Stream.empty()`; no realtime listeners for orders/bookings.

### Notes / Suggestions
- [ ] `lab_catalog` read-only; app falls back to hardcoded labs — file: `lib/core/firebase/repositories/lab_catalog_repository.dart` line: 167 — If `lab_catalog/default` is missing, embedded Mumbai-area partner labs are used, not live lab accounts.
- [ ] Health packages booked as synthetic single tests — file: `lib/features/patient/lab/lab_home_screen.dart` line: 41 — Packages become a fake `LabTestItem`; the package id is stored as `testId`, not individual tests.
- [ ] Booking ID collision risk — file: `lib/features/patient/lab/lab_booking_flow_screen.dart` line: 104 — `'LAB${millis % 100000}'` can collide under rapid bookings.
- [ ] `lab_bookings` status hardcoded to `confirmed` — file: `lib/core/firebase/repositories/lab_booking_repository.dart` line: 39 — No pending/accepted/rejected lab workflow.
- [ ] No lab-related composite indexes declared — file: `firestore.indexes.json` — No entries for `lab_orders`/`lab_bookings`/`labs`; future filtered lab queries will need indexes.
- [ ] Invite-network "Lab" option is SMS-only pre-launch copy — file: `lib/features/doctor/network/invite_network_view.dart` line: 61 — No in-app lab onboarding.
- [ ] Empty catch blocks in catalog lookup — file: `lib/core/firebase/repositories/lab_catalog_repository.dart` line: 55 — `testById`/`fromMap` swallow parse errors and return null/defaults.

---

## 5. Ambulance Module
Flow traced: book (`ambulance_booking_screen` -> `broadcastAmbulanceRequest`) -> broadcast (`ambulance_broadcasts` + per-driver `ambulance_requests`) -> driver sync -> accept (transaction) -> complete -> rate. Drivers use username/PIN (not Firebase Auth).

### Critical Issues
- [ ] Wide-open Firestore rules on ambulance collections — file: `firestore.rules` line: 427 — `ambulances` allows `read/create/update: if true`; `ambulance_broadcasts` and `ambulance_requests` allow `update: if true`. Any client can read all driver profiles/PINs, forge accepts, cancel/complete trips, or rewrite ratings.
- [ ] PIN stored and compared in plaintext — file: `lib/features/ambulance/models/ambulance_models.dart` line: 184 (compare at `ambulance_login_screen.dart:103`) — Registration writes `pin` as a plain string and login compares `match.pin != pin` directly; combined with open read rules, all driver PINs are exposed and usable.
- [ ] Session restore bypasses PIN authentication — file: `lib/features/splash/splash_screen.dart` line: 30 (also `ambulance_session.dart:54`, `ambulance_shell_auto.dart:26`) — On restart the session is restored from SharedPreferences and navigates straight to the driver dashboard with no PIN re-entry; anyone with device access gets in.
- [ ] Availability can be changed without PIN (pre-login) — file: `lib/features/ambulance/ambulance_login_screen.dart` line: 322 — Typing a valid username renders `AmbulanceAvailabilityToggle`, which calls `updateAvailability` with no PIN check, letting an attacker flip drivers online/offline.
- [ ] Patient not notified when a driver accepts via Firestore — file: `lib/core/firebase/repositories/ambulance_repository.dart` line: 318 — `notifyBookingAcceptedForBooker` is only called from `AmbulanceStore.acceptBooking` (requires `isPending`), but the sync listener often marks the broadcast `accepted` first, so `acceptBroadcast` returns silently and patients away from the booking screen get no alert.
- [ ] Patient sync + 5-minute timeout stop when leaving the booking screen — file: `lib/features/ambulance/ambulance_booking_screen.dart` line: 127 — `dispose()` cancels the countdown and calls `stopPatientWatch()`/`stopPatientHistoryWatch()`; if the patient navigates away, acceptance/completion updates aren't synced, the auto-cancel timeout never fires, and pending broadcasts can stay open in Firestore indefinitely.

### Warnings
- [ ] No availability toggle after login — file: `lib/features/ambulance/widgets/ambulance_availability_toggle.dart` line: 9 — The toggle is only wired on the login screen; the post-login dashboard/profile show status read-only, so drivers must log out to go offline.
- [ ] Login skips anonymous sign-in before `linkDriverAuth` — file: `lib/features/ambulance/ambulance_login_screen.dart` line: 119 — Login never calls `AmbulanceAuthHelper.ensureSignedIn()`, so `linkDriverAuth` returns early when `currentUser` is null and `authUid` is never linked on the login path.
- [ ] Service area / `pickupArea` ignored when selecting drivers — file: `lib/core/firebase/repositories/ambulance_repository.dart` line: 111 — `pickupArea`/`serviceAreas` are written but `fetchAllOnlineDrivers()` only filters `available`; all online drivers worldwide receive every request.
- [ ] `expiresAt` written but never enforced — file: `lib/core/firebase/repositories/ambulance_repository.dart` line: 163 — Broadcasts store a 5-minute `expiresAt`, but no client or rule reads it; expiry relies solely on the booking-screen countdown (which stops on dispose).
- [ ] Doctor bookings don't start patient history sync — file: `lib/features/ambulance/ambulance_booking_screen.dart` line: 58 — `watchPatientHistory` runs only when `_isPatient`; doctor-booked trips aren't synced unless the doctor stays on the screen.
- [ ] Offline fallback hardcodes `bookedByRole: patient` — file: `lib/features/ambulance/data/ambulance_store.dart` line: 264 — When Firebase is unavailable, doctor bookings lose their role and notifications route to the patient inbox.
- [ ] `acceptBroadcast` can report failure after a successful accept — file: `lib/core/firebase/repositories/ambulance_repository.dart` line: 318 — If the local booking is missing due to sync lag, the method returns `false` even when the transaction succeeded, showing "Another ambulance already accepted" incorrectly.
- [ ] `ensureSignedIn` signs out patient/doctor sessions — file: `lib/core/firebase/ambulance_auth_helper.dart` line: 17 — Entering the driver flow calls `auth.signOut()` on any non-anonymous user; on a shared device this silently drops a logged-in patient/doctor's session.
- [ ] Availability update fails silently on Firestore error — file: `lib/core/firebase/repositories/ambulance_repository.dart` line: 533 — Local store is updated first and Firestore errors are only `debugPrint`'d, so other devices read stale `isAvailable`.
- [ ] Registration uniqueness check swallowed on fetch error — file: `lib/features/ambulance/ambulance_registration_screen.dart` line: 115 — An empty catch on the uniqueness pre-check lets registration proceed if the fetch fails, risking duplicate usernames.
- [ ] Rating API allows trips still in `accepted` state — file: `lib/features/ambulance/data/ambulance_store.dart` line: 380 (repo `ambulance_repository.dart:444`) — `rateBooking`/`rateBroadcast` allow rating when status is `accepted`; only the UI gates on `isCompleted`.
- [ ] Cancel shows no error when Firestore cancel fails — file: `lib/features/ambulance/ambulance_booking_screen.dart` line: 458 — The button only shows success when `ok && mounted`; on failure the user gets no feedback and the UI may still show a pending request.

### Notes / Suggestions
- [ ] Driver alert system is dead code on the Firestore path — file: `lib/features/ambulance/data/ambulance_store.dart` line: 90 — `_pushDriverAlert` is used only in offline/local helpers; `alertsFor`/`unreadAlertCount` are never referenced in UI.
- [ ] `_RequestCard.alreadyTaken` parameter is unused — file: `lib/features/ambulance/ambulance_driver_home_screen.dart` line: 587 — No caller passes `alreadyTaken: true`; the "Taken" badge is unreachable.
- [ ] Empty catch blocks hide persistence/auth failures — file: `lib/core/session/ambulance_session.dart` line: 39 (also `ambulance_login_screen.dart:62,117`) — Session persist/restore and saved-username writes swallow all exceptions.
- [ ] In-app notifications are in-memory only — file: `lib/core/notifications/in_app_notification_service.dart` line: 23 — Notifications live in a process-local list and are lost on restart; nothing is written to `in_app_notifications`.
- [ ] Session-restore stub not added to `AmbulanceStore` — file: `lib/features/ambulance/ambulance_shell_auto.dart` line: 44 — If the stored id is missing from Firestore, a minimal stub reaches the shell but isn't registered, so `acceptBroadcast` fails the `findAmbulance`/`available` check.
- [ ] Local ambulance registered even when Firestore save fails — file: `lib/core/firebase/repositories/ambulance_repository.dart` line: 37 — `registerAmbulance` registers locally before Firestore; on cloud failure it returns null but leaves a ghost local entry.
- [ ] Hardcoded demo IDs filtered from production lists — file: `lib/core/firebase/repositories/ambulance_repository.dart` line: 552 — `_isRegistered` excludes ids/usernames like `amb1`, `careplus`; real registrations reusing those names are silently excluded.
- [ ] Firestore indexes sufficient for current ambulance queries — file: `firestore.indexes.json` line: 149 — Composite indexes exist for `(broadcastId, driverId)` and `(broadcastId, status)`; no missing-index failure identified.

---

## 6. Cross-Module Issues

### Critical Issues
- [ ] Synthetic patient IDs break every doctor->patient hand-off — files: `lib/features/doctor/clinical/models/clinical_models.dart:149`, `lib/features/doctor/home/doctor_home_screen.dart:135`, `lib/features/doctor/clinical/lab/lab_order_service.dart:11`, `lib/core/firebase/repositories/pharmacy_firestore_repository.dart:43` — Prescriptions, lab orders, and pharmacy deliveries are written with `PAT-{hash}` / `fallback_{appointmentId}` ids when the real patient id is missing. Firestore rules tie patient reads to `myPatientId()`, so the **same root cause** silently breaks Doctor↔Patient (prescriptions), Doctor↔Lab (orders) and Doctor↔Pharmacy↔Patient (delivery status) cross-module flows. This is the single highest-leverage bug.
- [ ] Lab role unimplemented breaks Doctor↔Lab and Patient↔Lab — files: `lib/features/lab/lab_shell.dart:8`, `lib/core/firebase/repositories/lab_order_repository.dart:26`, `lib/core/firebase/repositories/lab_booking_repository.dart:25`, `firestore.rules:64` — Doctors write `lab_orders` and patients write `lab_bookings`, but there is no lab-side session, screen, repository read, or `isLab()` rule. Both cross-module pipelines are write-only and never reach a lab operator.
- [ ] `lab_bookings` slot query rejected by rules (Patient↔Lab) — file: `lib/core/firebase/repositories/lab_booking_repository.dart:45` vs `firestore.rules:265` — The cross-collection read patients depend on for slot availability is denied server-side, so collision detection silently fails and double-booking is possible.
- [ ] Patient↔Ambulance acceptance not delivered cross-device — files: `lib/core/firebase/repositories/ambulance_repository.dart:318`, `lib/features/ambulance/ambulance_booking_screen.dart:127` — When a driver accepts via the Firestore path, the patient's in-app notification is skipped and the patient's listener is torn down on screen dispose, so the booker is never reliably told a driver is coming.
- [ ] Cross-module notifications are in-memory only — files: `lib/core/notifications/in_app_notification_service.dart:23`, `lib/features/pharmacy/data/pharmacy_notification_store.dart:25` — Doctor/pharmacy/ambulance notifications are emitted to process-local lists and (for many flows) never written to `in_app_notifications`, so any cross-actor event raised while the recipient is offline/on another device is lost.

### Warnings
- [ ] Doctor↔Pharmacy delivery status not round-tripped — files: `lib/core/firebase/firestore_data_prefetch.dart:34`, `lib/features/pharmacy/data/pharmacy_prescription_store.dart:158` — Missing `fetchDeliveriesForDoctor` plus unpersisted per-medicine availability mean the doctor and patient never see the store's dispense/OOS updates after a restart.
- [ ] Doctor↔Doctor referrals are one-way — file: `lib/core/firebase/repositories/referral_repository.dart:13` — Referrals are written but there is no inbound-referral fetch or screen for the receiving doctor.
- [ ] Verification gates inconsistent across roles — files: `lib/features/auth/medical_store_registration_screen.dart:90`, `lib/core/firebase/repositories/doctor_account_repository.dart:133`, `firestore.rules:338` — Stores self-set `verified: true`, doctors can self-reactivate to `verified: true`, and store reads aren't verified-filtered, so the trust boundary that other modules rely on is not enforced.

---

## Summary Table

| Module     | Critical | Warnings | Notes |
|------------|----------|----------|-------|
| Doctor     | 4        | 9        | 6     |
| Patient    | 4        | 18       | 8     |
| Pharmacy   | 6        | 12       | 6     |
| Lab        | 10       | 17       | 7     |
| Ambulance  | 6        | 12       | 8     |
| Cross      | 5        | 3        | 0     |
| **Total**  | **35**   | **71**   | **35**|

---

## Top 3 Most Urgent Fixes

1. **Fix patient-ID resolution at every doctor write.** Stop generating `PAT-{hash}` / `fallback_{appointmentId}` ids (`clinical_models.dart:149`, `doctor_home_screen.dart:135`, `lab_order_service.dart:11`, `pharmacy_firestore_repository.dart:43`). Always resolve and write the real registered `patientId`, or block the write. This one change unblocks prescriptions, lab orders and pharmacy status across the Doctor↔Patient↔Pharmacy↔Lab boundaries.
2. **Lock down the ambulance backend and PINs.** Replace the `if true` rules on `ambulances` / `ambulance_broadcasts` / `ambulance_requests` (`firestore.rules:427`), hash PINs (`ambulance_models.dart:184`), and require PIN re-entry on session restore (`splash_screen.dart:30`). Today any client can read every driver PIN and forge accepts/cancels — a data-loss and safety risk on an emergency feature.
3. **Stop showing success when persistence failed.** Surface Firestore errors instead of swallowing them in `_persist` (`shared_appointments_store.dart:219`), `unawaited(...)` store writes (`clinical_prescription_store.dart:92`, `pharmacy_prescription_store.dart`), and the lab booking flow (`lab_booking_flow_screen.dart:102`). Users currently see "Booking/Prescription Confirmed" while no record reaches the backend.

---

### Methodology & caveats
- Audit covered both the Flutter client and the Firestore "backend" (rules + indexes). Findings were verified by reading source; representative critical claims (`doctor_home_screen.dart:135`, `user_repository.dart:41` vs rules, `lab_booking_repository.dart:45`, `shared_appointments_store.dart:414`, `clinical_models.dart:149`, `lab_shell.dart`) were spot-checked directly.
- Line numbers reflect the current workspace and may shift by a line or two with edits; file paths are authoritative.
- This is a static audit. Runtime confirmation (e.g. actual `FAILED_PRECONDITION`/permission errors) requires running against a live Firebase project with the deployed rules.
