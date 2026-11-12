import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../features/patient/records/models/health_record_models.dart';
import '../../supabase/repositories/supabase_health_records_repository.dart';
import '../../supabase/repositories/supabase_patient_profile_repository.dart';
import '../../supabase/supabase_bootstrap.dart';

class PatientProfileRepository {
  PatientProfileRepository._();

  static final PatientProfileRepository instance = PatientProfileRepository._();

  static final RegExp _registeredPatientId = RegExp(
    r'^p\d+$',
    caseSensitive: false,
  );
  static final RegExp _walkInPatientId = RegExp(
    r'^wi\d+$',
    caseSensitive: false,
  );

  static bool isRegisteredPatientId(String? patientId) =>
      patientId != null &&
      patientId.isNotEmpty &&
      _registeredPatientId.hasMatch(patientId);

  static bool isWalkInPatientId(String? patientId) =>
      patientId != null &&
      patientId.isNotEmpty &&
      _walkInPatientId.hasMatch(patientId);

  bool checkIsRegisteredPatientId(String? patientId) =>
      isRegisteredPatientId(patientId);
  bool checkIsWalkInPatientId(String? patientId) =>
      isWalkInPatientId(patientId);

  /// Patient opted in to share profile/health records with doctors (default true when unset).
  static bool sharesRecordsWithDoctors(Map<String, dynamic>? patientData) {
    if (patientData == null) return false;
    return patientData['shareRecordsWithDoctors'] as bool? ?? true;
  }

  /// Registered patients (`p*`) only — used for profile vault + health records.
  /// Walk-in ids have no persisted profile and cannot expose the vault.
  Future<bool> mayDoctorViewSharedPatientRecords(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!isRegisteredPatientId(patientId)) return false;
    return isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    );
  }

  /// Whether doctors may read this patient's clinical history (RX, labs, visit notes).
  /// Walk-in / synthetic ids have no sharing preference — appointment-scoped data stays visible.
  Future<bool> isPatientSharingClinicalDataWithDoctors(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!isRegisteredPatientId(patientId)) return true;
    final data = await fetchPatientDocument(
      patientId,
      preferCache: preferCache,
    );
    if (data == null) return false;
    return sharesRecordsWithDoctors(data);
  }

  Future<Map<String, dynamic>?> fetchPatientDocumentForDoctor(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!await mayDoctorViewSharedPatientRecords(
      patientId,
      preferCache: preferCache,
    )) {
      return null;
    }
    return fetchPatientDocument(patientId, preferCache: preferCache);
  }

  Future<List<HealthRecord>> fetchHealthRecordsForDoctor(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!await mayDoctorViewSharedPatientRecords(
      patientId,
      preferCache: preferCache,
    )) {
      return const [];
    }
    final records = await fetchHealthRecords(patientId);
    return records.where((record) => record.sharedWithDoctors).toList();
  }

  Future<Map<String, dynamic>?> fetchPatientDocument(
    String patientId, {
    bool preferCache = true,
  }) async {
    return SupabasePatientProfileRepository.instance
          .fetchPatientDocument(patientId);
  }

  /// Records a patient↔doctor relationship for rules-side care-team grant checks.
  /// Walk-in (`wi*`) patients have no registered profile and skip this path.
  Future<bool> ensureDoctorPatientLink({
    required String patientId,
    required String doctorId,
    required String source,
    String? fromDoctorId,
    String? referralId,
  }) async {
    return SupabasePatientProfileRepository.instance.ensureDoctorPatientLink(
        patientId: patientId,
        doctorId: doctorId,
        source: source,
        fromDoctorId: fromDoctorId,
        referralId: referralId,
      );
  }

  Future<bool> grantDoctorCareTeamAccess({
    required String patientId,
    required String doctorId,
  }) async {
    return SupabasePatientProfileRepository.instance
          .grantDoctorCareTeamAccess(
        patientId: patientId,
        doctorId: doctorId,
      );
  }

  Future<void> savePatientDocument(
    String patientId,
    Map<String, dynamic> data,
  ) async {
    return SupabasePatientProfileRepository.instance
          .savePatientDocument(patientId, data);
  }

  Future<List<HealthRecord>> fetchHealthRecords(String patientId) async {
    return SupabaseHealthRecordsRepository.instance
          .fetchForPatient(patientId);
  }

  Future<void> savePatientFcmToken(String patientId, String token) async {
    if (!SupabaseBootstrap.isReady || token.isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final platform = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : (defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'unknown'));
      await SupabaseBootstrap.client.from('user_devices').upsert({
        'user_id': uid,
        'platform': platform,
        'fcm_token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,platform');
    } catch (e) {
      if (kDebugMode) debugPrint('[savePatientFcmToken] Supabase error: $e');
    }
  }

  Future<void> clearPatientFcmToken(String patientId) async {
    if (!SupabaseBootstrap.isReady) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final platform = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : (defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'unknown'));
      await SupabaseBootstrap.client
          .from('user_devices')
          .delete()
          .match({'user_id': uid, 'platform': platform});
    } catch (e) {
      if (kDebugMode) debugPrint('[clearPatientFcmToken] Supabase error: $e');
    }
  }

  Future<void> saveHealthRecord(String patientId, HealthRecord record) async {
    return SupabaseHealthRecordsRepository.instance
          .save(record, patientId: patientId);
  }

  Future<void> deleteHealthRecord(String recordId) async {
    return SupabaseHealthRecordsRepository.instance
          .delete(recordId, patientId: '');
  }
}
