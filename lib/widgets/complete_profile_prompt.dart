import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/profile_completion_service.dart';
import '../core/auth/verification_lifecycle.dart';
import '../core/enums/user_type.dart';
import '../core/firebase/firestore_paths.dart';
import '../core/session/ambulance_session.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../features/ambulance/ambulance_profile_screen.dart';
import '../features/doctor/profile/doctor_profile_screen.dart';
import '../features/lab/screens/lab_profile_screen.dart';
import '../features/pharmacy/screens/store_profile_screen.dart';

/// Shown when a non-patient user tries to access role data before completing profile or verification.
class CompleteProfilePrompt extends StatelessWidget {
  const CompleteProfilePrompt({
    super.key,
    required this.role,
    this.verificationPending = false,
    this.stage,
    this.rejectionReason,
  });

  final UserType role;
  final bool verificationPending;
  final VerificationStage? stage;
  final String? rejectionReason;

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

    final effectiveStage = stage ??
        (verificationPending
            ? VerificationStage.submittedForVerification
            : VerificationStage.registered);

    final (
      IconData icon,
      String title,
      String message,
      String? buttonText,
    ) = switch (effectiveStage) {
      VerificationStage.submittedForVerification => (
          Icons.hourglass_top_rounded,
          'Profile under review',
          'Your profile has been submitted. An administrator will review and approve your account. You can browse the app, but live operational data will appear after approval.',
          null,
        ),
      VerificationStage.revisionRequested => (
          Icons.warning_amber_rounded,
          'Revisions Requested by Super Admin',
          rejectionReason != null && rejectionReason!.isNotEmpty
              ? 'Reason: "$rejectionReason". Please update your profile details and resubmit for approval.'
              : 'Super Admin requested updates to your submitted profile. Please review and make the necessary corrections.',
          'Update Profile & Resubmit',
        ),
      VerificationStage.rejected => (
          Icons.cancel_outlined,
          'Verification Rejected',
          rejectionReason != null && rejectionReason!.isNotEmpty
              ? 'Reason: "$rejectionReason". Please update your credentials or contact administrator support.'
              : 'Your verification was not approved. Please review your submitted details.',
          'Review Profile',
        ),
      _ => (
          Icons.person_add_alt_1_outlined,
          'Complete your profile to continue',
          'Fill in your full profile details and submit for verification to access appointments, orders, and live data in your dashboard.',
          'Complete profile',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
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
              if (buttonText != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _openProfile(context),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: Text(buttonText),
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

/// Gates data-heavy tab content behind profile completion and verification.
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
    if (isProfileTab || role.isPatient) return child;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (role.isAmbulance && AmbulanceSession.isLoggedIn) {
        // Ambulance might use session login; check ambulance store / doc
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
      return CompleteProfilePrompt(role: role);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          if (verificationPending) {
            return CompleteProfilePrompt(
              role: role,
              verificationPending: true,
            );
          }
          return child;
        }

        final data = snapshot.data!.data();
        if (data == null) return child;

        final isVerified = data['verified'] == true;
        if (isVerified) return child;

        final statusStr = data['verificationStatus'] as String? ??
            data['status'] as String? ??
            (verificationPending ? 'submitted_for_verification' : 'registered');
        final stage = VerificationStage.fromString(statusStr);
        final reason = data['rejectionReason'] as String?;

        return CompleteProfilePrompt(
          role: role,
          stage: stage,
          rejectionReason: reason,
          verificationPending: stage.isPending,
        );
      },
    );
  }
}
