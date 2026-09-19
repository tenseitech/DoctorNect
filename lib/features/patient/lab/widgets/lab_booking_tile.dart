import '../../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/patient_lab_booking_filters.dart';
import '../../../../core/theme/app_typography.dart';

class LabBookingTile extends StatelessWidget {
  const LabBookingTile({
    super.key,
    required this.booking,
    required this.onTap,
    this.showDivider = false,
  });

  final LabBookingRecord booking;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final upcoming = PatientLabBookingFilters.isUpcoming(booking);
    final status = _statusStyle(booking);
    final day = DateFormat('dd').format(booking.dateTime);
    final month = DateFormat('MMM').format(booking.dateTime).toUpperCase();
    final labName = booking.labName?.trim().isNotEmpty == true ? booking.labName!.trim() : 'Lab';
    final patientName = booking.patientName.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: upcoming
                      ? AppColors.labPurple.withValues(alpha: 0.28)
                      : AppColors.borderOf(context),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: upcoming
                              ? [AppColors.labPurple, AppColors.labPurple.withValues(alpha: 0.78)]
                              : [status.color.withValues(alpha: 0.85), status.color],
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            day,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineSmall,
                              fontWeight: FontWeight.w800,
                              color: AppColors.surfaceOf(context),
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            month,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.surfaceOf(context).withValues(alpha: 0.92),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  booking.displayTestName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.bodyMedium,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _StatusChip(label: status.label, color: status.color),
                            ],
                          ),
                          const SizedBox(height: 3),
                          if (patientName.isNotEmpty)
                            Text(
                              patientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelMedium,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                          if (booking.allTestNames.length > 1) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${booking.allTestNames.length} tests booked',
                              style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.labPurple),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            labName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: AppColors.textSecondaryOf(context).withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  booking.slotLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textSecondaryOf(context).withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider) const SizedBox(height: 10),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

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
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

({String label, Color color}) _statusStyle(LabBookingRecord booking) {
  if (booking.hasReport) {
    return (label: 'Report ready', color: const Color(0xFF16A34A));
  }
  return switch (booking.status.toLowerCase()) {
      'requested' => (label: 'Pending', color: const Color(0xFFEA580C)),
      'confirmed' => (label: 'Confirmed', color: AppColors.labPurple),
      'processing' => (label: 'Processing', color: const Color(0xFF2563EB)),
      'completed' => (label: 'Completed', color: const Color(0xFF16A34A)),
      'declined' => (label: 'Declined', color: const Color(0xFFDC2626)),
      'cancelled' => (label: 'Cancelled', color: const Color(0xFFDC2626)),
      _ => (label: 'Booked', color: AppColors.textSecondary),
    };
}
