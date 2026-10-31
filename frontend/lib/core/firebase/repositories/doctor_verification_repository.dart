import 'package:flutter/foundation.dart';

import '../../auth/demo_auth_config.dart';
import '../../supabase/repositories/supabase_doctor_repository.dart';

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

  /// Parses `verified` field (bool or string) for gate routing.
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
    return SupabaseDoctorRepository.instance
        .watchDoctor(doctorId)
        .map(parseVerifiedFromDoctorData);
  }

  Future<bool> fetchVerified(String doctorId, {bool preferCache = false}) {
    return SupabaseDoctorRepository.instance.isDoctorVerified(doctorId);
  }
}
