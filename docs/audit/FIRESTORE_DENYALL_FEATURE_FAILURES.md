# Release build vs deny-all Firestore (client SDK paths)

| Module | Feature | File | Firestore collection | Effect under deny-all |
|--------|---------|------|----------------------|------------------------|
| doctor | Appointment inbox / accept / cancel | `shared_appointments_store.dart` | `appointments` | Read/write denied — schedule UI empty or errors |
| doctor | Submit / edit prescriptions | `clinical_prescription_store.dart` | `prescriptions`, lines | Denied if not on Supabase repo path |
| doctor | In-app notification mark read | `in_app_notification_service.dart` | `in_app_notifications` | Inbox merge/read fails |
| doctor | Community medicine/diagnosis pickers | `community_*_repository.dart` | `community_*` | Suggestions fail |
| doctor | Connected labs/pharmacy (legacy store) | `lab_connection_store.dart`, `doctor_connected_*` | `lab_connections`, `pharmacy_connections` | Denied when Firestore-backed |
| patient | Book appointment (legacy path) | `booking_flow_screen.dart`, helpers | `appointments` | Booking persist fails if not callable/Supabase |
| patient | Lab booking list (legacy store) | `patient_lab_booking_store.dart` | `lab_bookings` | List stale/fails |
| patient | Favorites / registered doctors | `patient_favorites_store.dart`, `registered_doctors_store.dart` | varies | Denied reads |
| patient | In-app notifications | `in_app_notification_service.dart` | `in_app_notifications` | Same as doctor |
| pharmacy | Prescription queue | `pharmacy_prescription_store.dart` | `prescriptions`, `pharmacy_deliveries` | Denied if Firestore path active |
| pharmacy | Store registry / connections | `medical_store_registry.dart`, `pharmacy_connection_store.dart` | `medical_stores`, `pharmacy_connections` | Denied |
| lab | Dashboard tabs / registry (legacy) | `lab_dashboard_tabs.dart`, `lab_registry.dart` | `labs`, `lab_bookings` | Denied on Firestore reads |
| lab | Report upload | `lab_report_upload_sheet.dart` | — | **OK** — Supabase + S3 primary |
| ambulance | Booking / driver home / broadcasts | `ambulance_repository.dart`, screens | `ambulances`, `ambulance_requests`, `ambulance_broadcasts` | **Fails** — primary Firestore |
| ambulance | Profile / availability | `ambulance_profile_screen.dart`, toggles | `ambulances`, `private/settings` | Denied |
| all | Profile completion (legacy entry) | `profile_completion_service.dart` | `users`, role tables | Onboarding flags fail |

When `DoctorPatientCutoverFlag` + Supabase repos are wired, doctor/patient/pharmacy/lab **core** flows avoid Firestore; ambulance and notification merge paths remain the highest-risk gaps.
