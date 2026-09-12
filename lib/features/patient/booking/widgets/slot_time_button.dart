import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/booking_models.dart';

/// Time slot: available (teal), shared (amber, 1–2 booked), full/past (gray disabled).
class SlotTimeButton extends StatelessWidget {
  const SlotTimeButton({
    super.key,
    required this.label,
    required this.selected,
    required this.booked,
    this.bookingCount = 0,
    this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final bool booked;
  final int bookingCount;
  final VoidCallback? onTap;
  /// Tighter full-width layout for native phone grids.
  final bool compact;

  bool get _shared => !booked && bookingCount > 0;

  @override
  Widget build(BuildContext context) {
    final bg = booked
        ? AppColors.cardBgOf(context)
        : selected
            ? AppColors.patientTeal
            : Colors.transparent;
    final fg = booked
        ? AppColors.textSecondaryOf(context)
        : selected
            ? AppColors.white
            : _shared
                ? const Color(0xFFB45309)
                : AppColors.patientTeal;
    final border = booked
        ? AppColors.borderOf(context)
        : selected
            ? AppColors.patientTeal
            : _shared
                ? const Color(0xFFF59E0B)
                : AppColors.patientTeal;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: booked ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: compact ? double.infinity : null,
          constraints: compact
              ? BoxConstraints(minHeight: _shared && !selected ? 48 : 40)
              : null,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: selected ? 0 : 1.5),
          ),
          child: Column(
            mainAxisAlignment:
                compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: compact ? TextAlign.center : null,
                style: GoogleFonts.inter(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (_shared && !selected) ...[
                const SizedBox(height: 2),
                Text(
                  compact
                      ? '$bookingCount/$kMaxPatientsPerTimeSlot'
                      : '$bookingCount/$kMaxPatientsPerTimeSlot booked',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: compact ? TextAlign.center : null,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFB45309),
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
