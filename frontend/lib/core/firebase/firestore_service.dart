import '../config/firestore_forbidden_guard.dart';
import 'repositories/ambulance_repository.dart';
import 'repositories/appointment_repository.dart';
import 'repositories/doctor_account_repository.dart';
import 'repositories/doctor_availability_repository.dart';
import 'repositories/doctor_directory_repository.dart';
import 'repositories/doctor_profile_detail_repository.dart';
import 'repositories/doctor_profile_repository.dart';
import 'repositories/doctor_verification_repository.dart';
import 'repositories/family_member_repository.dart';
import 'repositories/in_app_notification_repository.dart';
import 'repositories/lab_booking_repository.dart';
import 'repositories/lab_catalog_repository.dart';
import 'repositories/lab_connection_repository.dart';
import 'repositories/lab_order_repository.dart';
import 'repositories/lab_repository.dart';
import 'repositories/medical_directory_repository.dart';
import 'repositories/medical_store_repository.dart';
import 'repositories/medicine_suggestion_repository.dart';
import 'repositories/patient_account_repository.dart';
import 'repositories/patient_profile_repository.dart';
import 'repositories/pharmacy_firestore_repository.dart';
import 'repositories/prescription_repository.dart';
import 'repositories/referral_repository.dart';
import 'repositories/review_repository.dart';
import 'repositories/role_account_repository.dart';
import 'repositories/user_repository.dart';

export 'repositories/ambulance_repository.dart';
export 'repositories/appointment_repository.dart';
export 'repositories/doctor_account_repository.dart';
export 'repositories/doctor_availability_repository.dart';
export 'repositories/doctor_directory_repository.dart';
export 'repositories/doctor_profile_detail_repository.dart';
export 'repositories/doctor_profile_repository.dart';
export 'repositories/doctor_verification_repository.dart';
export 'repositories/family_member_repository.dart';
export 'repositories/in_app_notification_repository.dart';
export 'repositories/lab_booking_repository.dart';
export 'repositories/lab_catalog_repository.dart';
export 'repositories/lab_connection_repository.dart';
export 'repositories/lab_order_repository.dart';
export 'repositories/lab_repository.dart';
export 'repositories/medical_directory_repository.dart';
export 'repositories/medical_store_repository.dart';
export 'repositories/medicine_suggestion_repository.dart';
export 'repositories/patient_account_repository.dart';
export 'repositories/patient_profile_repository.dart';
export 'repositories/pharmacy_firestore_repository.dart';
export 'repositories/prescription_repository.dart';
export 'repositories/referral_repository.dart';
export 'repositories/review_repository.dart';
export 'repositories/role_account_repository.dart';
export 'repositories/user_repository.dart';

/// Central composition gateway for Firestore repositories.
class FirestoreService {
  FirestoreService._();

  static final FirestoreService _singleton = FirestoreService._();

  static FirestoreService get instance {
    FirestoreForbiddenGuard.assertNotForbidden('FirestoreService');
    return _singleton;
  }

  T _repo<T>(T Function() factory, String label) {
    FirestoreForbiddenGuard.assertNotForbidden('FirestoreService.$label');
    return factory();
  }

  AmbulanceRepository get ambulance =>
      _repo(() => AmbulanceRepository.instance, 'ambulance');
  AppointmentRepository get appointment =>
      _repo(() => AppointmentRepository.instance, 'appointment');
  DoctorAccountRepository get doctorAccount =>
      _repo(() => DoctorAccountRepository.instance, 'doctorAccount');
  DoctorAvailabilityRepository get doctorAvailability => _repo(
      () => DoctorAvailabilityRepository.instance, 'doctorAvailability');
  DoctorDirectoryRepository get doctorDirectory =>
      _repo(() => DoctorDirectoryRepository.instance, 'doctorDirectory');
  DoctorProfileDetailRepository get doctorProfileDetail => _repo(
      () => DoctorProfileDetailRepository.instance, 'doctorProfileDetail');
  DoctorProfileRepository get doctorProfile =>
      _repo(() => DoctorProfileRepository.instance, 'doctorProfile');
  DoctorVerificationRepository get doctorVerification => _repo(
      () => DoctorVerificationRepository.instance, 'doctorVerification');
  FamilyMemberRepository get familyMember =>
      _repo(() => FamilyMemberRepository.instance, 'familyMember');
  InAppNotificationRepository get notification =>
      _repo(() => InAppNotificationRepository.instance, 'notification');
  InAppNotificationRepository get inAppNotification =>
      _repo(() => InAppNotificationRepository.instance, 'inAppNotification');
  LabBookingRepository get labBooking =>
      _repo(() => LabBookingRepository.instance, 'labBooking');
  LabCatalogRepository get labCatalog =>
      _repo(() => LabCatalogRepository.instance, 'labCatalog');
  LabConnectionRepository get labConnection =>
      _repo(() => LabConnectionRepository.instance, 'labConnection');
  LabOrderRepository get labOrder =>
      _repo(() => LabOrderRepository.instance, 'labOrder');
  LabRepository get lab => _repo(() => LabRepository.instance, 'lab');
  MedicalDirectoryRepository get medicalDirectory =>
      _repo(() => MedicalDirectoryRepository.instance, 'medicalDirectory');
  MedicalStoreRepository get medicalStore =>
      _repo(() => MedicalStoreRepository.instance, 'medicalStore');
  MedicineSuggestionRepository get medicineSuggestion => _repo(
      () => MedicineSuggestionRepository.instance, 'medicineSuggestion');
  PatientAccountRepository get patientAccount =>
      _repo(() => PatientAccountRepository.instance, 'patientAccount');
  PatientProfileRepository get patientProfile =>
      _repo(() => PatientProfileRepository.instance, 'patientProfile');
  PharmacyFirestoreRepository get pharmacyFirestore => _repo(
      () => PharmacyFirestoreRepository.instance, 'pharmacyFirestore');
  PrescriptionRepository get prescription =>
      _repo(() => PrescriptionRepository.instance, 'prescription');
  ReferralRepository get referral =>
      _repo(() => ReferralRepository.instance, 'referral');
  ReviewRepository get review =>
      _repo(() => ReviewRepository.instance, 'review');
  RoleAccountRepository get roleAccount =>
      _repo(() => RoleAccountRepository.instance, 'roleAccount');
  UserRepository get user => _repo(() => UserRepository.instance, 'user');
}
