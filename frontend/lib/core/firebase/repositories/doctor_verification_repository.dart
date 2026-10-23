import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../../auth/demo_auth_config.dart';
import '../../config/doctor_patient_cutover_flag.dart';
import '../../supabase/repositories/supabase_doctor_repository.dart';
import 'doctor_account_repository.dart';

/// Real-time doctor admin-approval status for the verification gate.
class DoctorVerificationRepository {
  DoctorVerificationRepository._();

  static final DoctorVerificationRepository instance =
      DoctorVerificationRepository._();

  @visibleForTesting
  static Stream<bool> Function(String doctorId)? debugWatchVerifiedOverride;

  @visibleForTesting
  static void debugReset() {
    debugWatchVerifiedOverride = null;
  }

  /// Parses Firestore `verified` field (bool or string) for gate routing.
  @visibleForTesting
  static bool parseVerifiedFromDoctorData(Map<String, dynamic>? data) {
    if (data == null) return false;
    final mobile = data['mobile'] as String? ?? data['phone'] as String?;
    if (DemoAuthConfig.isDemoDoctorPhone(mobile)) return true;
    final docId = data['doctorId'] as String? ?? data['id'] as String?;
    if (DemoAuthConfig.isDemoDoctorPhone(docId) ||
        DemoAuthConfig.isDemoDoctorId(docId)) {
      return true;
    }
    final verified = data['verified'];
    if (verified == true) return true;
    if (verified is String && verified.toLowerCase() == 'true') return true;
    if (data['verificationStatus'] == 'verified' ||
        data['status'] == 'approved') {
      return true;
    }
    return false;
  }

  Stream<bool> watchVerified(String doctorId) {
    if (debugWatchVerifiedOverride != null) {
      return debugWatchVerifiedOverride!(doctorId);
    }

    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabaseDoctorRepository.instance
          .watchDoctor(doctorId)
          .map(parseVerifiedFromDoctorData);
    }

    if (DemoAuthConfig.isDemoDoctorPhone(doctorId) ||
        DemoAuthConfig.isDemoDoctorId(doctorId)) {
      return Stream<bool>.value(true);
    }

    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) {
      return Stream<bool>.value(false);
    }

    return FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return false;
      return parseVerifiedFromDoctorData(snap.data());
    });
  }

  Future<bool> fetchVerified(String doctorId, {bool preferCache = false}) {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabaseDoctorRepository.instance.isDoctorVerified(doctorId);
    }
    if (DemoAuthConfig.isDemoDoctorPhone(doctorId) ||
        DemoAuthConfig.isDemoDoctorId(doctorId)) {
      return Future<bool>.value(true);
    }
    return DoctorAccountRepository.instance.isVerified(
      doctorId,
      preferCache: preferCache,
    );
  }
}
