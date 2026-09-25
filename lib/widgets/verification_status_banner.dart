import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/verification_lifecycle.dart';
import '../core/enums/user_type.dart';

export '../core/auth/verification_lifecycle.dart';
export '../core/enums/user_type.dart';
import '../core/firebase/firestore_paths.dart';
import '../core/session/ambulance_session.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../features/ambulance/ambulance_profile_screen.dart';
import '../features/doctor/profile/doctor_profile_screen.dart';
import '../features/lab/screens/lab_profile_screen.dart';
import '../features/pharmacy/screens/store_profile_screen.dart';

/// Prominent banner displayed on role home screens for progressive profile completion
/// and real-time verification lifecycle monitoring.
class VerificationStatusBanner extends StatelessWidget {
  const VerificationStatusBanner({
    super.key,
    required this.role,
    this.stage,
    this.rejectionReason,
    this.onTapAction,
  });

  final UserType role;
  final VerificationStage? stage;
  final String? rejectionReason;
  final VoidCallback? onTapAction;

  Future<void> _defaultOpenProfile(BuildContext context) async {
    if (onTapAction != null) {
      onTapAction!();
      return;
    }
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
    if (stage != null) {
      return _buildContent(context, stage!, rejectionReason);
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!.data();
        if (data == null) return const SizedBox.shrink();

        final verified = data['verified'] == true;
        if (verified) return const SizedBox.shrink();

        final statusStr = data['verificationStatus'] as String? ??
            data['status'] as String? ??
            'registered';
        final resolvedStage = VerificationStage.fromString(statusStr);
        final reason = data['rejectionReason'] as String?;

        return _buildContent(context, resolvedStage, reason);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    VerificationStage currentStage,
    String? reason,
  ) {
    if (currentStage.isVerified) {
      return const SizedBox.shrink();
    }

    final (
      Color bg,
      Color border,
      Color accent,
      IconData icon,
      String title,
      String description,
      String? buttonLabel,
    ) = switch (currentStage) {
      VerificationStage.submittedForVerification => (
          const Color(0xFFEFF6FF),
          const Color(0xFFBFDBFE),
          const Color(0xFF2563EB),
          Icons.hourglass_top_rounded,
          'Profile Under Review',
          'Your profile and documents have been submitted to Super Admin for verification. You can explore the app while your account is being reviewed.',
          null,
        ),
      VerificationStage.revisionRequested => (
          const Color(0xFFFFFBEB),
          const Color(0xFFFDE68A),
          const Color(0xFFD97706),
          Icons.warning_amber_rounded,
          'Revisions Requested by Super Admin',
          (reason != null && reason.trim().isNotEmpty)
              ? 'Reason: "$reason". Please update your profile with the requested information and resubmit.'
              : 'Super Admin requested updates to your profile. Please make the corrections and resubmit.',
          'Update & Resubmit',
        ),
      VerificationStage.rejected => (
          const Color(0xFFFEF2F2),
          const Color(0xFFFECACA),
          const Color(0xFFDC2626),
          Icons.cancel_outlined,
          'Verification Rejected',
          (reason != null && reason.trim().isNotEmpty)
              ? 'Reason: "$reason". Please update your credentials or contact support.'
              : 'Your verification was not approved. Please review your submitted details.',
          'Review Profile',
        ),
      _ => (
          const Color(0xFFF0FDF4),
          const Color(0xFFBBF7D0),
          const Color(0xFF16A34A),
          Icons.assignment_late_outlined,
          'Action Required: Complete Your Profile',
          'Fill in required registration documents & credentials to get verified by Super Admin and unlock live appointments and operations.',
          'Complete Profile',
        ),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.titleSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: AppColors.textSecondaryOf(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (buttonLabel != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _defaultOpenProfile(context),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
