import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/profile_completion_service.dart';
import '../core/enums/user_type.dart';
import '../core/session/ambulance_session.dart';
import '../core/theme/app_colors.dart';
import '../features/ambulance/ambulance_profile_screen.dart';
import '../features/doctor/profile/doctor_profile_screen.dart';
import '../features/lab/screens/lab_profile_screen.dart';
import '../features/pharmacy/screens/store_profile_screen.dart';
import '../core/theme/app_typography.dart';

/// Shown when a non-patient user tries to access role data before completing profile.
class CompleteProfilePrompt extends StatelessWidget {
  const CompleteProfilePrompt({
    super.key,
    required this.role,
    this.verificationPending = false,
  });

  final UserType role;
  final bool verificationPending;

  Future<void> _openProfile(BuildContext context) async {
    switch (role) {
      case UserType.doctor:
        await DoctorProfileScreen.open(context);
      case UserType.medicalStore:
        if (context.mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const StoreProfileScreen()),
          );
        }
      case UserType.lab:
        if (context.mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const LabProfileScreen()),
          );
        }
      case UserType.ambulance:
        if (context.mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => AmbulanceProfileScreen(
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
    final accent = switch (role) {
      UserType.doctor => AppColors.doctorBlue,
      UserType.medicalStore => AppColors.pharmacyGreen,
      UserType.lab => const Color(0xFF8B5CF6),
      UserType.ambulance => const Color(0xFFDC2626),
      _ => AppColors.doctorBlue,
    };

    final title = verificationPending
        ? 'Profile under review'
        : 'Complete your profile to continue';
    final message = verificationPending
        ? 'Your profile has been submitted. An administrator will review and approve your account. You can browse the app, but live data will appear after approval.'
        : 'Fill in your full profile details to access appointments, orders, and other live data in your dashboard.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                verificationPending
                    ? Icons.hourglass_top_rounded
                    : Icons.person_add_alt_1_outlined,
                size: 56,
                color: accent.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineMedium,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  height: 1.5,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              if (!verificationPending) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _openProfile(context),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('Complete profile'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Gates data-heavy tab content behind profile completion (and optional verification).
class ProfileDataGate extends StatelessWidget {
  const ProfileDataGate({
    super.key,
    required this.role,
    required this.child,
    this.isProfileTab = false,
    this.verificationPending = false,
  });

  final UserType role;
  final Widget child;
  final bool isProfileTab;
  final bool verificationPending;

  @override
  Widget build(BuildContext context) {
    if (isProfileTab) return child;

    return ListenableBuilder(
      listenable: ProfileCompletionService.instance,
      builder: (context, _) {
        if (ProfileCompletionService.instance.isComplete) {
          if (verificationPending) {
            return CompleteProfilePrompt(
              role: role,
              verificationPending: true,
            );
          }
          return child;
        }
        return CompleteProfilePrompt(role: role);
      },
    );
  }
}
