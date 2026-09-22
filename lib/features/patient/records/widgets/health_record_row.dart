import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/health_record_models.dart';
import '../utils/record_type_style.dart';
import '../../../../core/theme/app_typography.dart';

class HealthRecordRow extends StatelessWidget {
  const HealthRecordRow({
    super.key,
    required this.record,
    required this.onTap,
    this.showDivider = false,
    this.accentColor,
  });

  final HealthRecord record;
  final VoidCallback onTap;
  final bool showDivider;
  final Color? accentColor;

  Color get _accent {
    if (accentColor != null) return accentColor!;
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

  String? get _statusChipLabel {
    final status = record.labReportStatus;
    if (status == null) return null;
    return switch (status) {
      LabReportStatusKind.reportReady => 'Report ready',
      LabReportStatusKind.processing => 'Processing',
      LabReportStatusKind.confirmed => 'Confirmed',
      LabReportStatusKind.awaitingLab => 'Awaiting lab',
      LabReportStatusKind.completedPendingReport => 'Report pending',
      LabReportStatusKind.declined => 'Declined',
      LabReportStatusKind.cancelled => 'Cancelled',
      LabReportStatusKind.orderedByDoctor => 'Ordered by doctor',
    };
  }

  Color? get _statusChipColor {
    final status = record.labReportStatus;
    if (status == null) return null;
    return switch (status) {
      LabReportStatusKind.reportReady => AppColors.pharmacyGreen,
      LabReportStatusKind.processing => Colors.orange,
      LabReportStatusKind.confirmed => AppColors.labPurple,
      LabReportStatusKind.awaitingLab => AppColors.doctorBlue,
      LabReportStatusKind.completedPendingReport => const Color(0xFFD97706),
      LabReportStatusKind.declined => AppColors.error,
      LabReportStatusKind.cancelled => AppColors.textSecondary,
      LabReportStatusKind.orderedByDoctor => AppColors.patientTeal,
    };
  }

  Widget _buildMetaRow(BuildContext context, String year, Color accent) {
    final compact = ResponsiveLayout.isCompact(context);
    final statusLabel = _statusChipLabel;
    final statusColor = _statusChipColor;

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _SourceChip(label: _chipLabel, color: accent),
              Text(
                year,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
          if (statusLabel != null && statusColor != null) ...[
            const SizedBox(height: 6),
            _SourceChip(label: statusLabel, color: statusColor),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SourceChip(label: _chipLabel, color: accent),
        if (statusLabel != null && statusColor != null)
          _SourceChip(label: statusLabel, color: statusColor),
        Text(
          year,
          style: GoogleFonts.inter(
              fontSize: AppTypography.labelSmall,
              color: AppColors.textSecondaryOf(context)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final day = DateFormat('dd').format(record.date);
    final month = DateFormat('MMM').format(record.date).toUpperCase();
    final year = DateFormat('yyyy').format(record.date);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.surfaceOf(context),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RecordDateBadge(day: day, month: month, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyLarge,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _provider,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildMetaRow(context, year, accent),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textSecondaryOf(context)
                        .withValues(alpha: 0.75),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
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
      width: 52,
      height: 58,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: GoogleFonts.inter(
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            month,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.92),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Groups records by calendar month (newest months first).
List<(String monthLabel, List<HealthRecord> records)> groupHealthRecordsByMonth(
  List<HealthRecord> records,
) {
  final order = <String>[];
  final groups = <String, List<HealthRecord>>{};

  for (final record in records) {
    final key = DateFormat('MMMM yyyy').format(record.date);
    groups.putIfAbsent(key, () => []).add(record);
    if (!order.contains(key)) order.add(key);
  }

  return [for (final month in order) (month, groups[month]!)];
}

class HealthRecordMonthHeader extends StatelessWidget {
  const HealthRecordMonthHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cardBgOf(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: AppTypography.labelMedium,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondaryOf(context),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
