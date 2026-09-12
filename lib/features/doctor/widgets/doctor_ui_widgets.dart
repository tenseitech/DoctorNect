import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../models/doctor_models.dart';

class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.status});

  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final verified = status == VerificationStatus.verified;
    final color = verified ? const Color(0xFF16A34A) : const Color(0xFFEA580C);
    final bg = color.withValues(alpha: 0.12);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              verified ? Icons.verified : Icons.hourglass_top,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              verified ? 'Verified' : 'Pending',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatMetricCard extends StatefulWidget {
  const StatMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
    this.shortLabel,
    this.valueFontSize,
  });

  final String label;
  final String? shortLabel;
  final String value;
  final Color accent;
  final VoidCallback onTap;
  final double? valueFontSize;

  @override
  State<StatMetricCard> createState() => _StatMetricCardState();
}

class _StatMetricCardState extends State<StatMetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.shortLabel ?? widget.label;
    final valueSize = widget.valueFontSize ?? 14.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withValues(alpha: 0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hovered ? widget.accent.withValues(alpha: 0.45) : AppColors.borderOf(context),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            splashColor: widget.accent.withValues(alpha: 0.12),
            highlightColor: widget.accent.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: valueSize * 1.25,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.value,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: valueSize,
                          fontWeight: FontWeight.w700,
                          color: widget.accent,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w500,
                        color: _hovered ? AppColors.textPrimaryOf(context) : AppColors.textSecondaryOf(context),
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows why a patient shares a time slot (Emergency / custom reason).
class SharedSlotBadge extends StatelessWidget {
  const SharedSlotBadge({
    super.key,
    required this.slotShareReason,
    this.compact = false,
  });

  final String? slotShareReason;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reason = slotShareReason?.trim();
    if (reason == null || reason.isEmpty) return const SizedBox.shrink();

    final isEmergency = reason.toLowerCase() == 'emergency';
    final color = isEmergency ? const Color(0xFFDC2626) : const Color(0xFFEA580C);
    final label = isEmergency
        ? (compact ? 'Emergency' : 'Emergency slot')
        : (compact && reason.length > 18 ? '${reason.substring(0, 16)}…' : reason);

    return StatusBadge(
      label: label,
      color: color,
      icon: isEmergency ? Icons.emergency : Icons.info_outline,
    );
  }
}

class PatientAvatar extends StatelessWidget {
  const PatientAvatar({
    super.key,
    required this.name,
    required this.gender,
  });

  final String name;
  final String gender;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = AppConstants.isFemalePatientGender(gender)
        ? const Color(0xFFDB2777)
        : AppColors.doctorBlue;

    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        initial,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
