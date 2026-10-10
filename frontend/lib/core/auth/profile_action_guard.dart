import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../session/ambulance_session.dart';
import '../session/doctor_session.dart';
import '../session/lab_session.dart';
import '../session/medical_store_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../../features/ambulance/ambulance_profile_screen.dart'
    deferred as amb_prof;
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/doctor/profile/doctor_profile_screen.dart'
    deferred as doc_prof;
import '../../features/lab/screens/lab_profile_screen.dart'
    deferred as lab_prof;
import '../../features/pharmacy/screens/store_profile_screen.dart'
    deferred as store_prof;
import 'demo_auth_config.dart';
import 'verification_lifecycle.dart';

/// Central guard for mutating operations across professional roles
/// (Doctor, Pharmacy, Diagnostic Lab, Ambulance).
///
/// In view-only mode, users can view all screens and tabs normally.
/// However, any action that creates or mutates data (e.g. adding patients,
/// writing prescriptions, dispensing orders, accepting trips, connecting partners)
/// is blocked until the profile is verified.
abstract final class ProfileActionGuard {
  /// Evaluates whether mutating actions are allowed for [role].
  ///
  /// Always allowed for Patients, Super Admins, verified accounts,
  /// and demo accounts.
  static bool isAllowed(UserType role) {
    if (role == UserType.patient || role == UserType.superAdmin) {
      return true;
    }

    // Demo doctor bypass
    if (role == UserType.doctor) {
      final docId = DoctorSession.loggedInDoctorId;
      final mobile = DoctorProfileStore.instance.profile.mobile;
      if (DemoAuthConfig.isDemoDoctorPhone(docId) ||
          docId.contains(DemoAuthConfig.demoDoctorPhone) ||
          DemoAuthConfig.isDemoDoctorPhone(mobile)) {
        return true;
      }
    }

    // Demo pharmacy bypass
    if (role == UserType.medicalStore) {
      final storeId = MedicalStoreSession.loggedInStoreId;
      if (DemoAuthConfig.isDemoPharmacyPhone(storeId) ||
          storeId.contains(DemoAuthConfig.demoPharmacyPhone)) {
        return true;
      }
    }

    // Demo lab bypass
    if (role == UserType.lab) {
      final labId = LabSession.loggedInLabId;
      if (DemoAuthConfig.isDemoLabPhone(labId) ||
          labId.contains(DemoAuthConfig.demoLabPhone)) {
        return true;
      }
    }

    // Demo ambulance bypass
    if (role == UserType.ambulance) {
      final ambId = AmbulanceSession.loggedInAmbulanceId;
      if (DemoAuthConfig.isDemoAmbulancePhone(ambId) ||
          ambId.contains(DemoAuthConfig.demoAmbulancePhone)) {
        return true;
      }
    }

    return RoleVerificationController.instance.isVerified(role);
  }

  /// Runs [onAllowed] if the profile is verified or in demo mode.
  /// Otherwise, intercepts the action and shows the Complete Profile / Verification popup.
  static Future<void> run(
    BuildContext context,
    UserType role,
    VoidCallback onAllowed,
  ) async {
    if (isAllowed(role)) {
      onAllowed();
      return;
    }
    await showPopup(context, role);
  }

  /// Displays the verification / complete profile modal popup.
  static Future<void> showPopup(BuildContext context, UserType role) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProfileVerificationDialog(role: role),
    );
  }

  /// Automatically displays the popup on first entry into the app
  /// when the profile is incomplete (dismissible, persisted so it doesn't show on every launch).
  static Future<void> showOnFirstEntryIfNeeded(
    BuildContext context,
    UserType role,
  ) async {
    if (isAllowed(role)) return;

    final stage = RoleVerificationController.instance.stageFor(role);
    if (!stage.isIncomplete && !stage.isRevisionRequested) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      var uid = '';
      if (FirebaseBootstrap.isReady) {
        try {
          uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        } catch (_) {}
      }
      final key = uid.isNotEmpty
          ? 'profile_prompt_shown_${role.name}_$uid'
          : 'profile_prompt_shown_${role.name}';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);
    } catch (_) {}

    if (!context.mounted) return;
    await showPopup(context, role);
  }
}

class _ProfileVerificationDialog extends StatelessWidget {
  const _ProfileVerificationDialog({required this.role});

  final UserType role;

  Color _accentColor(BuildContext context) {
    return switch (role) {
      UserType.doctor => AppColors.doctorBlue,
      UserType.medicalStore => AppColors.pharmacyGreen,
      UserType.lab => AppColors.labPurple,
      UserType.ambulance => const Color(0xFFDC2626),
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Future<void> _navigateToProfile(BuildContext context) async {
    switch (role) {
      case UserType.doctor:
        await doc_prof.loadLibrary();
        if (context.mounted) {
          await doc_prof.DoctorProfileScreen.open(context);
        }
      case UserType.medicalStore:
        await store_prof.loadLibrary();
        if (context.mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => store_prof.StoreProfileScreen()),
          );
        }
      case UserType.lab:
        await lab_prof.loadLibrary();
        if (context.mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => lab_prof.LabProfileScreen()),
          );
        }
      case UserType.ambulance:
        await amb_prof.loadLibrary();
        if (context.mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => amb_prof.AmbulanceProfileScreen(
                ambulanceId: AmbulanceSession.loggedInAmbulanceId,
              ),
            ),
          );
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = RoleVerificationController.instance.stageFor(role);
    final accent = _accentColor(context);
    final reason = RoleVerificationController.instance.rejectionReasonFor(role);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    if (stage == VerificationStage.submittedForVerification) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.surfaceOf(context),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 380, maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Profile Under Review',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondaryOf(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.hourglass_top_rounded,
                      size: 36,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Your profile and credentials have been submitted for verification and are currently being reviewed by Super Admin. You can view all information in the app, but creating or modifying data is paused until approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodyMedium,
                    color: AppColors.textSecondaryOf(context),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Understood',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = RoleVerificationController.instance.profileDataFor(role);
    final percentage = VerificationRequirementsConfig.completionPercentage(
      role,
      data,
    );
    final missing = VerificationRequirementsConfig.missingFields(role, data);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.surfaceOf(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 380, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stage.isRevisionRequested
                          ? 'Action Required'
                          : 'Complete Your Profile',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondaryOf(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: percentage / 100,
                        strokeWidth: 8,
                        backgroundColor: accent.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (stage.isRevisionRequested &&
                  reason != null &&
                  reason.trim().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revision Requested by Admin:',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reason,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.bodySmall,
                          color: const Color(0xFF78350F),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Text(
                  'Your profile is $percentage% complete. Please complete the required fields to verify your account and unlock actions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodyMedium,
                    color: AppColors.textSecondaryOf(context),
                    height: 1.4,
                  ),
                ),
              ],
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Missing Details (${missing.length}):',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    color: AppColors.cardBgOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: role == UserType.ambulance
                        ? Border.all(
                            color: AppColors.borderOf(context)
                                .withValues(alpha: 0.15),
                          )
                        : Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: missing.length,
                    separatorBuilder: (_, __) => const Divider(height: 6),
                    itemBuilder: (context, i) {
                      final item = missing[i];
                      return Row(
                        children: [
                          Icon(
                            item.isDocument
                                ? Icons.file_present_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: AppTypography.bodySmall,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.section,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: AppTypography.labelSmall,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _navigateToProfile(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Complete Profile',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondaryOf(context),
                ),
                child: Text(
                  'Later',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
