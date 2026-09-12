import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import 'doctor_account_repository.dart';

/// Real-time doctor admin-approval status for the verification gate.
class DoctorVerificationRepository {
  DoctorVerificationRepository._();

  static final DoctorVerificationRepository instance = DoctorVerificationRepository._();

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
    final verified = data['verified'];
    if (verified == true) return true;
    if (verified is String && verified.toLowerCase() == 'true') return true;
    return false;
  }

  Stream<bool> watchVerified(String doctorId) {
    if (debugWatchVerifiedOverride != null) {
      return debugWatchVerifiedOverride!(doctorId);
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
    return DoctorAccountRepository.instance.isVerified(
      doctorId,
      preferCache: preferCache,
    );
  }
}
