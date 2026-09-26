import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'supabase_bootstrap.dart';

/// Exception thrown when a Patient mutation is blocked by the maintenance gate.
class PatientMaintenanceException implements Exception {
  PatientMaintenanceException(
      [this.message = 'System maintenance in progress']);
  final String message;

  @override
  String toString() => 'PatientMaintenanceException: $message';
}

/// Central guard and error boundary for all Patient module mutations on Supabase.
abstract final class PatientWriteGuard {
  static bool _cachedMaintenanceActive = false;
  static DateTime? _lastCheckTime;
  static const Duration _cacheTtl = Duration(seconds: 30);

  @visibleForTesting
  static bool? debugMaintenanceOverride;

  @visibleForTesting
  static void resetForTesting() {
    _cachedMaintenanceActive = false;
    _lastCheckTime = null;
    debugMaintenanceOverride = null;
  }

  /// Checks the remote `system_config` table for the patient module status.
  static Future<bool> isMaintenanceActive({bool forceRefresh = false}) async {
    if (debugMaintenanceOverride != null) {
      return debugMaintenanceOverride!;
    }

    if (!forceRefresh &&
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheTtl) {
      return _cachedMaintenanceActive;
    }

    if (!SupabaseBootstrap.isReady) return false;

    try {
      final res = await SupabaseBootstrap.client
          .from('system_config')
          .select('config_value')
          .eq('config_key', 'patient_module_status')
          .maybeSingle();

      if (res != null && res['config_value'] != null) {
        final val = res['config_value'];
        if (val is Map) {
          final status = val['status']?.toString();
          final allowWrites = val['allow_writes'] == true;
          _cachedMaintenanceActive =
              (status == 'maintenance' || status == 'rollback' || !allowWrites);
        }
      } else {
        _cachedMaintenanceActive = false;
      }
      _lastCheckTime = DateTime.now();
    } catch (_) {
      // Network hiccup on config read shouldn't block user unless hard freeze hits
      _cachedMaintenanceActive = false;
    }

    return _cachedMaintenanceActive;
  }

  /// Runs a patient write operation with 2-layer defense:
  /// 1. Soft kill-switch preflight (`system_config`)
  /// 2. Hard freeze catch (`42501` permission denied safety net)
  static Future<T> run<T>({
    required BuildContext? context,
    required Future<T> Function() action,
  }) async {
    // 1. Primary path: Preflight soft check
    final inMaintenance = await isMaintenanceActive();
    if (inMaintenance) {
      if (context != null && context.mounted) {
        showMaintenanceSheet(context);
      }
      throw PatientMaintenanceException(
        'DoctorNect is undergoing scheduled database maintenance. Booking will resume shortly.',
      );
    }

    // 2. Safety-net path: Execute write and catch hard 42501 permission denied
    try {
      return await action();
    } on PostgrestException catch (e) {
      final isPermissionDenied = e.code == '42501' ||
          e.message.toLowerCase().contains('permission denied') ||
          e.message.toLowerCase().contains('insufficient_privilege');

      if (isPermissionDenied) {
        _cachedMaintenanceActive =
            true; // Cache the maintenance state immediately
        _lastCheckTime = DateTime.now();
        if (context != null && context.mounted) {
          showMaintenanceSheet(context);
        }
        throw PatientMaintenanceException(
          'Database write freeze active. System is in maintenance mode.',
        );
      }
      rethrow;
    }
  }

  /// Renders a friendly bottom sheet modal informing the patient of scheduled maintenance.
  static void showMaintenanceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.patientTeal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  size: 36,
                  color: AppColors.patientTeal,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Scheduled System Maintenance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'DoctorNect is currently undergoing a brief database maintenance update.\n\n'
                'Your medical records and existing appointments are completely safe. '
                'New bookings will resume shortly.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.patientTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Understand & Close'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      )),
    );
  }
}
