import 'package:firebase_auth/firebase_auth.dart';

import '../auth/app_credential_store.dart';
import '../data/shared_appointments_store.dart';
import '../notifications/in_app_notification_service.dart';
import '../../features/ambulance/data/ambulance_store.dart';
import '../../features/doctor/clinical/data/clinical_prescription_store.dart';
import '../../features/doctor/patients/data/doctor_patients_service.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/lab/data/lab_connection_store.dart';
import '../../features/lab/data/lab_notification_store.dart';
import '../../features/lab/data/lab_worklist_store.dart';
import '../../features/patient/data/patient_favorites_store.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';
import '../../features/patient/records/data/patient_lab_booking_store.dart';
import '../../features/pharmacy/data/pharmacy_connection_store.dart';
import '../../features/pharmacy/data/pharmacy_notification_store.dart';
import '../../features/pharmacy/data/pharmacy_prescription_store.dart';
import 'ambulance_session.dart';

/// Single unified session manager for all user types and global sign-out cleanup.
abstract final class AppSession {
  // Doctor session state
  static String doctorId = '';
  static String doctorName = '';
  static String get activeDoctorId =>
      doctorId.isNotEmpty ? doctorId : (FirebaseAuth.instance.currentUser?.uid ?? '');

  // Patient session state
  static String patientId = '';
  static String patientName = '';
  static String patientKey = '';

  // Lab session state
  static String labId = '';
  static String labName = '';

  // Medical Store session state
  static String storeId = '';
  static String storeName = '';

  // Super Admin session state
  static String adminId = '';
  static String adminName = '';
  static String adminEmail = '';
  static String get activeAdminId =>
      adminId.isNotEmpty ? adminId : (FirebaseAuth.instance.currentUser?.uid ?? '');

  static void setDoctor({required String id, required String name}) {
    doctorId = id;
    doctorName = name;
  }

  static void setPatient({required String id, required String name}) {
    patientId = id;
    patientName = name;
    patientKey = name.trim().toLowerCase();
  }

  static void setLab({required String id, required String name}) {
    labId = id;
    labName = name;
  }

  static void setStore({required String id, required String name}) {
    storeId = id;
    storeName = name;
  }

  static void setSuperAdmin({required String id, required String name, String email = ''}) {
    adminId = id;
    adminName = name;
    adminEmail = email;
  }

  static void clear() {
    doctorId = '';
    doctorName = '';
    patientId = '';
    patientName = '';
    patientKey = '';
    labId = '';
    labName = '';
    storeId = '';
    storeName = '';
    adminId = '';
    adminName = '';
    adminEmail = '';
    AmbulanceSession.clear();
    DoctorProfileStore.instance.reset();
    PatientProfileMock.reset();
    SharedAppointmentsStore.instance.clearForSignOut();
    ClinicalPrescriptionStore.instance.clear();
    DoctorPatientsService.clearCache();
    PharmacyConnectionStore.instance.clear();
    LabConnectionStore.instance.clear();
    LabWorklistStore.instance.clear();
    PharmacyPrescriptionStore.instance.clear();
    PatientFavoritesStore.instance.clear();
    PatientLabBookingStore.instance.clear();
    AmbulanceStore.instance.clear();
    PharmacyNotificationStore.instance.clear();
    LabNotificationStore.instance.clear();
    InAppNotificationService.instance.clearAllNotifications();
    AppCredentialStore.clearAll();
  }
}
