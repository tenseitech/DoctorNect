import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/firebase/models/doctor_referral.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class ReferredPatientCard extends StatelessWidget {
  const ReferredPatientCard({
    super.key,
    required this.referral,
    this.incoming = false,
    this.onOpenConsult,
  });

  final DoctorReferral referral;
  final bool incoming;
  final VoidCallback? onOpenConsult;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('dd MMM yyyy, hh:mm a').format(referral.createdAt);

    final canConsult = incoming && onOpenConsult != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: InkWell(
          onTap: canConsult ? onOpenConsult : null,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(
              color: AppColors.isDark(context)
                  ? const Color(0xFF22C55E).withValues(alpha: 0.35)
                  : const Color(0xFF16A34A).withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.isDark(context)
                          ? const Color(0xFF22C55E).withValues(alpha: 0.16)
                          : const Color(0xFF16A34A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Referred',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.isDark(context)
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF16A34A),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                referral.patientName,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              _detailRow(context, 'Age', '${referral.patientAge} yrs'),
              if (referral.patientId.isNotEmpty)
                _detailRow(context, 'Patient ID', referral.patientId),
              _detailRow(
                context,
                incoming ? 'Referred by' : 'Referred to',
                incoming
                    ? 'Dr. ${referral.fromDoctorName}'
                    : 'Dr. ${referral.toDoctorName} (${referral.toSpecialization})',
              ),
              if (incoming)
                _detailRow(context, 'Specialization', referral.toSpecialization),
              if (referral.reason != null && referral.reason!.trim().isNotEmpty)
                _detailRow(context, 'Reason', referral.reason!.trim()),
              if (canConsult) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onOpenConsult,
                  icon: const Icon(Icons.medical_services_outlined, size: 18),
                  label: const Text('Open consult'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.doctorBlue,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodySmall,
            color: AppColors.textPrimaryOf(context),
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
