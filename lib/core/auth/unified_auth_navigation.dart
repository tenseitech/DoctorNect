import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../enums/user_type.dart';
import '../firebase/firebase_auth_service.dart';
import '../validators/form_validators.dart';
import '../../features/auth/account_under_review_screen.dart';
import '../../features/auth/patient_registration_screen.dart';
import '../../features/auth/doctor_registration_screen.dart';
import '../../features/auth/medical_store_registration_screen.dart';
import '../../features/auth/lab_registration_screen.dart';
import '../../features/ambulance/ambulance_registration_screen.dart';
import '../../features/dashboard/dashboard_shell.dart';

/// Post-OTP navigation for the unified mobile auth flow.
abstract final class UnifiedAuthNavigation {
  /// Routes to the role-specific profile-completion / registration form after OTP verify (register path).
  static void openRegistrationForm(
    BuildContext context, {
    required UserType role,
    required String mobileDigits,
  }) {
    final mobile = FormValidators.formatFullPhone('+91', mobileDigits);
    final screen = switch (role) {
      UserType.patient =>
        PatientRegistrationScreen(preVerifiedMobile: mobileDigits),
      UserType.doctor => DoctorRegistrationScreen(preVerifiedMobile: mobile),
      UserType.medicalStore =>
        MedicalStoreRegistrationScreen(preVerifiedMobile: mobile),
      UserType.lab => LabRegistrationScreen(preVerifiedMobile: mobile),
      UserType.ambulance =>
        AmbulanceRegistrationScreen(preVerifiedMobile: mobile),
      _ => PatientRegistrationScreen(preVerifiedMobile: mobileDigits),
    };
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  /// Handles Firebase-auth login result (doctor / patient / pharmacy / lab).
  static Future<void> handleSignInResult(
    BuildContext context, {
    required UserType role,
    required AuthSignInResult result,
  }) async {
    if (result.cancelled) return;

    if (result.pendingReview) {
      await FirebaseAuthService.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountUnderReviewScreen()),
        (_) => false,
      );
      return;
    }

    if (result.canReactivateAccount && role == UserType.doctor) {
      await _offerReactivation(context, role, result.reactivateBefore);
      return;
    }

    if (!result.success) {
      if (result.message != null && result.message!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message!),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    TextInput.finishAutofillContext(shouldSave: true);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => DashboardShell(userType: role)),
      (_) => false,
    );
  }

  static Future<void> _offerReactivation(
    BuildContext context,
    UserType role,
    DateTime? reactivateBefore,
  ) async {
    final deadline = reactivateBefore != null
        ? DateFormat('d MMM yyyy').format(reactivateBefore)
        : '30 days';

    final shouldReactivate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Account deactivated'),
        content: Text(
          'Your profile is hidden from patients. Reactivate before $deadline to restore access.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseAuthService.instance.signOut();
              if (ctx.mounted) Navigator.pop(ctx, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivate account'),
          ),
        ],
      ),
    );

    if (!context.mounted || shouldReactivate != true) return;

    final result = await FirebaseAuthService.instance.reactivateDoctorAccount();
    if (!context.mounted) return;
    if (result.success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => DashboardShell(userType: role)),
        (_) => false,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'Could not reactivate account'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
