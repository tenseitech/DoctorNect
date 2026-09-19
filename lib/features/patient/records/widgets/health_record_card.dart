import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/health_record_models.dart';
import '../utils/record_type_style.dart';
import '../../../../core/theme/app_typography.dart';

class HealthRecordCard extends StatelessWidget {
  const HealthRecordCard({
    super.key,
    required this.record,
    required this.onTap,
    this.onShare,
    this.onDelete,
    this.embedded = false,
    this.flat = false,
    this.showDivider = false,
  });

  final HealthRecord record;
  final VoidCallback onTap;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final bool embedded;
  final bool flat;
  final bool showDivider;

  IconData get _icon {
    if (record.labBookingId != null) return Icons.bloodtype_outlined;
    if (record.prescriptionId != null) return AppIcons.prescription;
    if (record.labOrderId != null) return Icons.science_outlined;
    return RecordTypeStyle.forType(record.type).icon;
  }

  Color get _iconColor {
    if (record.labBookingId != null) return const Color(0xFFDC2626);
    if (record.prescriptionId != null) return AppColors.doctorBlue;
    if (record.labOrderId != null) return AppColors.patientTeal;
    return RecordTypeStyle.forType(record.type).color;
  }

  String get _provider => record.doctorName ?? record.labName ?? '—';

  String get _sourceLabel => switch (record.source) {
        RecordSource.practo => 'Practo',
        RecordSource.doctorSent => 'From doctor',
        RecordSource.labSent => 'From lab',
        RecordSource.selfUploaded => 'Self-uploaded',
      };

  String get _chipLabel => record.labBookedByLabel ?? _sourceLabel;

  Color get _sourceColor => switch (record.source) {
        RecordSource.practo => AppColors.patientTeal,
        RecordSource.doctorSent => AppColors.doctorBlue,
        RecordSource.labSent => const Color(0xFFDC2626),
        RecordSource.selfUploaded => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    if (flat || embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: AppColors.surfaceOf(context),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: _buildFlatRow(context),
              ),
            ),
          ),
          if (showDivider)
            Divider(
                height: 1, thickness: 1, color: AppColors.borderOf(context)),
        ],
      );
    }

    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: _buildCardContent(context),
        ),
      ),
    );
  }

  Widget _buildFlatRow(BuildContext context) {
    final day = DateFormat('dd').format(record.date);
    final month = DateFormat('MMM').format(record.date).toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RecordDateBadge(day: day, month: month, color: _iconColor),
        const SizedBox(width: 12),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(_icon, color: _iconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                _provider,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _sourceColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _chipLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _sourceColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: AppColors.textSecondaryOf(context).withValues(alpha: 0.75),
        ),
      ],
    );
  }

  Widget _buildCardContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, color: _iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _provider,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy').format(record.date),
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  if (record.notes != null && record.notes!.trim().isNotEmpty)
                    Text(
                      record.notes!,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _sourceColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _chipLabel,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _sourceColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(onPressed: onTap, child: const Text('View')),
            if (onShare != null)
              TextButton(onPressed: onShare, child: const Text('Share')),
            if (onDelete != null)
              TextButton(
                onPressed: onDelete,
                child: Text('Delete',
                    style: GoogleFonts.inter(color: AppColors.error)),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecordDateBadge extends StatelessWidget {
  const _RecordDateBadge({
    required this.day,
    required this.month,
    required this.color,
  });

  final String day;
  final String month;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 54,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: GoogleFonts.inter(
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            month,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.85),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
