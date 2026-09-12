import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/patient_appointment_models.dart';
import '../../utils/doctor_display_name.dart';
import 'appointment_card_shared.dart';

class UpcomingAppointmentCard extends StatefulWidget {
  const UpcomingAppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
    required this.onReschedule,
    required this.onCancel,
    this.flat = false,
    this.showDivider = false,
  });

  final PatientAppointment appointment;
  final VoidCallback onTap;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;
  final bool flat;
  final bool showDivider;

  @override
  State<UpcomingAppointmentCard> createState() => _UpcomingAppointmentCardState();
}

class _UpcomingAppointmentCardState extends State<UpcomingAppointmentCard> {
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
    final statusColor = a.status == PatientBookingStatus.confirmed
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    final statusLabel = a.status == PatientBookingStatus.confirmed ? 'Confirmed' : 'Pending';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            appointmentDoctorAvatar(a.doctorName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDoctorDisplayName(a.doctorName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appointmentCardDoctorNameStyle(),
                  ),
                  Text(
                    a.specialization,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.slotLabel != null && a.slotLabel!.trim().isNotEmpty
                        ? '${DateFormat('EEE, dd MMM yyyy').format(a.dateTime)} · ${a.slotLabel}'
                        : DateFormat('EEE, dd MMM yyyy · hh:mm a').format(a.dateTime),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.patientTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${a.tokenNumber}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.patientTeal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.local_hospital_outlined, size: 16, color: AppColors.patientTeal),
            const SizedBox(width: 4),
            Text(
              'In-Clinic',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.patientTeal,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ),
          ],
        ),
        if (a.clinicName != null) ...[
          const SizedBox(height: 8),
          Text(
            a.clinicName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          if (a.clinicAddress != null)
            Text(
              a.clinicAddress!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          _countdown,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.patientTeal),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onReschedule,
              style: compactTealOutlinedButtonStyle(),
              icon: const Icon(AppIcons.reschedule, size: 16),
              label: const Text('Reschedule'),
            ),
            TextButton(
              onPressed: widget.onCancel,
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );

    return AppointmentCardWrapper(
      onTap: widget.onTap,
      flat: widget.flat,
      showDivider: widget.showDivider,
      child: content,
    );
  }
}
