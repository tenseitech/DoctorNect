import '../../auth/demo_auth_config.dart';
import '../../supabase/supabase_bootstrap.dart';

class DoctorDeactivationStatus {
  const DoctorDeactivationStatus({
    required this.deactivated,
    required this.canReactivate,
    this.reactivateBefore,
  });

  final bool deactivated;
  final bool canReactivate;
  final DateTime? reactivateBefore;
}

class DoctorAccountRepository {
  DoctorAccountRepository._();

  static final DoctorAccountRepository instance = DoctorAccountRepository._();

  bool _isTruthy(dynamic value) {
    if (value == true) return true;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  Future<DoctorDeactivationStatus> fetchDeactivationStatus(
    String doctorId, {
    bool preferCache = false,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      return const DoctorDeactivationStatus(
        deactivated: false,
        canReactivate: false,
      );
    }
    try {
      final res = await SupabaseBootstrap.client
          .from('doctors')
          .select('deactivated, reactivate_before, verified')
          .eq('doctor_id', doctorId)
          .maybeSingle();
      if (res == null) {
        return const DoctorDeactivationStatus(
          deactivated: false,
          canReactivate: false,
        );
      }
      final deactivated = _isTruthy(res['deactivated']);
      final reactivateBefore = res['reactivate_before'] != null
          ? DateTime.tryParse(res['reactivate_before'] as String)
          : null;
      var effectiveDeactivated = deactivated;
      if (!effectiveDeactivated &&
          reactivateBefore != null &&
          !_isTruthy(res['verified']) &&
          DateTime.now().isBefore(reactivateBefore)) {
        effectiveDeactivated = true;
      }
      if (!effectiveDeactivated) {
        return const DoctorDeactivationStatus(
          deactivated: false,
          canReactivate: false,
        );
      }
      final canReactivate = reactivateBefore != null &&
          DateTime.now().isBefore(reactivateBefore);
      return DoctorDeactivationStatus(
        deactivated: true,
        canReactivate: canReactivate,
        reactivateBefore: reactivateBefore,
      );
    } catch (_) {
      return const DoctorDeactivationStatus(
        deactivated: false,
        canReactivate: false,
      );
    }
  }

  Future<bool> isDeactivated(
    String doctorId, {
    bool preferCache = false,
  }) async {
    final status = await fetchDeactivationStatus(
      doctorId,
      preferCache: preferCache,
    );
    return status.deactivated;
  }

  Future<bool> isVerified(String doctorId, {bool preferCache = false}) async {
    if (DemoAuthConfig.isDemoAllowed &&
        (DemoAuthConfig.isDemoDoctorPhone(doctorId) ||
            DemoAuthConfig.isDemoDoctorId(doctorId))) {
      return true;
    }
    if (!SupabaseBootstrap.isReady) return false;
    try {
      final res = await SupabaseBootstrap.client
          .from('doctors')
          .select('verified, deactivated, mobile, verification_status, status')
          .eq('doctor_id', doctorId)
          .maybeSingle();
      if (res == null) return false;
      final mobile = res['mobile'] as String?;
      if (DemoAuthConfig.isDemoAllowed &&
          DemoAuthConfig.isDemoDoctorPhone(mobile)) {
        return true;
      }
      if (res['verification_status'] == 'verified' ||
          res['status'] == 'approved') {
        return true;
      }
      final verified = _isTruthy(res['verified']);
      final deactivated = _isTruthy(res['deactivated']);
      return verified && !deactivated;
    } catch (_) {
      return false;
    }
  }

  Future<void> deactivate({
    required String doctorId,
    required String ownerUid,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      throw StateError('Supabase is not available.');
    }
    await SupabaseBootstrap.client.rpc('deactivate_provider_profile');
  }

  Future<void> reactivate({
    required String doctorId,
    required String ownerUid,
  }) async {
    final status = await fetchDeactivationStatus(doctorId);
    if (!status.deactivated) return;
    if (!status.canReactivate) {
      throw StateError('Reactivation window has expired.');
    }
    if (!SupabaseBootstrap.isReady) {
      throw StateError('Supabase is not available.');
    }
    await SupabaseBootstrap.client.rpc('reactivate_provider_profile');
  }
}
