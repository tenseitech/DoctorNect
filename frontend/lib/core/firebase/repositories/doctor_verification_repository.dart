import 'package:flutter/foundation.dart';

import '../../auth/demo_auth_config.dart';
import '../../supabase/repositories/supabase_doctor_repository.dart';
import '../../supabase/supabase_bootstrap.dart';

/// Real-time doctor admin-approval status for the verification gate.
class DoctorVerificationRepository {
  DoctorVerificationRepository._();

  static final DoctorVerificationRepository instance =
      DoctorVerificationRepository._();

  static Stream<bool> Function(String doctorId)? _debugWatchVerifiedOverride;

  @visibleForTesting
  static Stream<bool> Function(String doctorId)? get debugWatchVerifiedOverride =>
      _debugWatchVerifiedOverride;

  @visibleForTesting
  static set debugWatchVerifiedOverride(
    Stream<bool> Function(String doctorId)? value,
  ) {
    assert(() {
      if (value != null && kReleaseMode) {
        throw AssertionError(
          'debugWatchVerifiedOverride must not be set in release mode',
        );
      }
      return true;
    }());
    _debugWatchVerifiedOverride = value;
  }

  /// Test-only: treat runtime as release (ignores [debugWatchVerifiedOverride]).
  @visibleForTesting
  static bool debugForceReleaseMode = false;

  @visibleForTesting
  static void debugReset() {
    _debugWatchVerifiedOverride = null;
    debugForceReleaseMode = false;
  }

  static bool get _effectiveReleaseMode =>
      kReleaseMode || debugForceReleaseMode;

  /// Parses `verified` field (bool or string) for gate routing.
  @visibleForTesting
  static bool parseVerifiedFromDoctorData(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (DemoAuthConfig.isDemoAllowed) {
      final mobile = data['mobile'] as String? ?? data['phone'] as String?;
      if (DemoAuthConfig.isDemoDoctorPhone(mobile)) return true;
      final docId = data['doctorId'] as String? ?? data['id'] as String?;
      if (DemoAuthConfig.isDemoDoctorPhone(docId) ||
          DemoAuthConfig.isDemoDoctorId(docId)) {
        return true;
      }
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
    if (!_effectiveReleaseMode) {
      final override = _debugWatchVerifiedOverride;
      if (override != null) {
        return override(doctorId);
      }
    }
    if (doctorId.isEmpty || !SupabaseBootstrap.isReady) {
      return Stream.value(false);
    }
    return SupabaseDoctorRepository.instance
        .watchDoctor(doctorId)
        .map(parseVerifiedFromDoctorData);
  }

  Future<bool> fetchVerified(String doctorId, {bool preferCache = false}) {
    return SupabaseDoctorRepository.instance.isDoctorVerified(doctorId);
  }
}
