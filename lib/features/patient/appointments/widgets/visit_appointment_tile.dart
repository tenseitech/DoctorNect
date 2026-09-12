import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../utils/doctor_display_name.dart';
import '../models/patient_appointment_models.dart';

class VisitAppointmentTile extends StatefulWidget {
  const VisitAppointmentTile({
    super.key,
    required this.appointment,
    required this.onTap,
    this.showDivider = false,
  });

  final PatientAppointment appointment;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  State<VisitAppointmentTile> createState() => _VisitAppointmentTileState();
}

class _VisitAppointmentTileState extends State<VisitAppointmentTile> {
  Timer? _timer;
  late String _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = widget.appointment.countdownLabel;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final next = widget.appointment.countdownLabel;
      if (next != _countdown) setState(() => _countdown = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final status = _statusStyle(a);
    final isUpcoming = a.cancellationReason == null && a.isUpcoming;
    final day = DateFormat('dd').format(a.dateTime);
    final month = DateFormat('MMM').format(a.dateTime).toUpperCase();
    final time = a.slotLabel != null && a.slotLabel!.trim().isNotEmpty
        ? a.slotLabel!
        : DateFormat('hh:mm a').format(a.dateTime);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.surfaceOf(context),
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DateBadge(
                    day: day,
                    month: month,
                    highlight: isUpcoming,
                    color: status.color,
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
                                formatDoctorDisplayName(a.doctorName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _StatusChip(label: status.label, color: status.color),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          a.specialization,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 14,
                              color: AppColors.textSecondaryOf(context).withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                time,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                              ),
                            ),
                          ],
                        ),
                        if (isUpcoming) ...[
                          const SizedBox(height: 4),
                          Text(
                            _countdown,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF117554),
                            ),
                          ),
                        ],
                        if (a.cancellationReason != null &&
                            a.cancellationReason!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            a.cancellationReason!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
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
              ),
            ),
          ),
        ),
        if (widget.showDivider) Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
      ],
    );
  }

  ({String label, Color color}) _statusStyle(PatientAppointment appointment) {
    if (appointment.cancellationReason != null) {
      return (label: 'Cancelled', color: const Color(0xFFDC2626));
    }
    if (appointment.status == PatientBookingStatus.confirmed) {
      if (appointment.isUpcoming) {
        return (label: 'Upcoming', color: const Color(0xFFEA580C));
      }
      return (label: 'Completed', color: const Color(0xFF16A34A));
    }
    return (label: 'Pending', color: AppColors.textSecondaryOf(context));
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({
    required this.day,
    required this.month,
    required this.highlight,
    required this.color,
  });

  final String day;
  final String month;
  final bool highlight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 52,
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF0F766E) : color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: GoogleFonts.inter(
              fontSize: 16,
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
