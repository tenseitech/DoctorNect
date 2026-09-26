import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/verification_lifecycle.dart';
import '../core/enums/user_type.dart';

export '../core/auth/verification_lifecycle.dart';
export '../core/enums/user_type.dart';
import '../core/firebase/firestore_paths.dart';
import '../core/notifications/app_toast.dart';
import '../core/session/ambulance_session.dart';
import '../core/session/doctor_session.dart';
import '../core/session/lab_session.dart';
import '../core/session/medical_store_session.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Card embedded in professional profile screens showing current verification progress,
/// checklist requirements, rejection/revision reasons, and the "Submit for Verification" action.
class VerificationSubmissionCard extends StatefulWidget {
  const VerificationSubmissionCard({
    super.key,
    required this.role,
  });

  final UserType role;

  @override
  State<VerificationSubmissionCard> createState() =>
      _VerificationSubmissionCardState();
}

class _VerificationSubmissionCardState
    extends State<VerificationSubmissionCard> {
  bool _submitting = false;

  String? _resolveProfileId() {
    return switch (widget.role) {
      UserType.doctor => DoctorSession.loggedInDoctorId,
      UserType.medicalStore => MedicalStoreSession.loggedInStoreId,
      UserType.lab => LabSession.loggedInLabId,
      UserType.ambulance => AmbulanceSession.loggedInAmbulanceId,
      _ => null,
    };
  }

  Future<void> _submitForVerification(
    BuildContext context,
    String uid,
    String? profileId,
  ) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final userRef =
          FirebaseFirestore.instance.collection(FirestorePaths.users).doc(uid);

      batch.set(
        userRef,
        {
          'verificationStatus': 'submitted_for_verification',
          'status': 'pending_review',
          'submittedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final roleCol = switch (widget.role) {
        UserType.doctor => FirestorePaths.doctors,
        UserType.medicalStore => FirestorePaths.medicalStores,
        UserType.lab => FirestorePaths.labs,
        UserType.ambulance => FirestorePaths.ambulances,
        _ => null,
      };

      if (roleCol != null && profileId != null && profileId.isNotEmpty) {
        final roleRef =
            FirebaseFirestore.instance.collection(roleCol).doc(profileId);
        batch.set(
          roleRef,
          {
            'verificationStatus': 'submitted_for_verification',
            'status': 'pending_review',
            'submittedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      if (!context.mounted) return;
      AppToast.info(
        context,
        'Profile submitted for Super Admin verification!',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(
        context,
        'Failed to submit for verification. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const SizedBox.shrink();
    }

    final profileId = _resolveProfileId();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!.data() ?? {};
        final isVerified = data['verified'] == true;
        final statusStr = data['verificationStatus'] as String? ??
            data['status'] as String? ??
            'registered';
        final stage = isVerified
            ? VerificationStage.verified
            : VerificationStage.fromString(statusStr);
        final reason = data['rejectionReason'] as String?;

        return _buildCard(context, uid, profileId, stage, reason);
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    String uid,
    String? profileId,
    VerificationStage stage,
    String? reason,
  ) {
    final accent = switch (widget.role) {
      UserType.doctor => AppColors.doctorBlue,
      UserType.medicalStore => AppColors.pharmacyGreen,
      UserType.lab => AppColors.labPurple,
      UserType.ambulance => const Color(0xFFDC2626),
      _ => AppColors.doctorBlue,
    };

    final requirements =
        VerificationRequirementsConfig.requirementsForRole(widget.role);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  stage.isVerified
                      ? Icons.verified_rounded
                      : (stage.isPending
                          ? Icons.hourglass_top_rounded
                          : Icons.shield_outlined),
                  color: stage.isVerified ? const Color(0xFF16A34A) : accent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Super Admin Verification',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.titleMedium,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: stage.isVerified
                        ? const Color(0xFFDCFCE7)
                        : (stage.isPending
                            ? const Color(0xFFDBEAFE)
                            : (stage.isRevisionRequested
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFF1F5F9))),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    stage.displayLabel,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: stage.isVerified
                          ? const Color(0xFF15803D)
                          : (stage.isPending
                              ? const Color(0xFF1D4ED8)
                              : (stage.isRevisionRequested
                                  ? const Color(0xFFB45309)
                                  : AppColors.textSecondaryOf(context))),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stage.isVerified) ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF16A34A), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your professional account is verified. All operational features are active.',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (stage.isPending) ...[
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          color: Color(0xFF2563EB), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your profile has been submitted and is currently being reviewed by Super Admin. You will receive an update once approved.',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  if (stage.isRevisionRequested && reason != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Revision requested by Super Admin:',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reason,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: const Color(0xFF78350F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    'Required for Verification:',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.titleSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in requirements) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.isDocument
                                ? Icons.file_present_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 16,
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.bodySmall,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                                Text(
                                  item.description,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelSmall,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => _submitForVerification(
                                context,
                                uid,
                                profileId,
                              ),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        stage.isRevisionRequested
                            ? 'Resubmit for Verification'
                            : 'Submit for Verification',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        textStyle: GoogleFonts.inter(
                          fontSize: AppTypography.labelLarge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
