import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/patient_appointment_models.dart';
import '../../utils/doctor_display_name.dart';
import 'appointment_card_shared.dart';

class CancelledAppointmentCard extends StatelessWidget {
  const CancelledAppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
    required this.onBookAgain,
    this.flat = false,
    this.showDivider = false,
  });

  final PatientAppointment appointment;
  final VoidCallback onTap;
  final VoidCallback onBookAgain;
  final bool flat;
  final bool showDivider;

  static const _cancelledBadgeBg = Color(0xFFFEF2F2);
  static const _cancelledBadgeText = Color(0xFFEF4444);
  static const _cancelledBadgeBorder = Color(0xFFFECACA);

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final reason = a.cancellationReason?.trim();

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
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd MMM yyyy · hh:mm a').format(a.dateTime),
                    style: appointmentCardDateStyle(),
                  ),
                  if (reason != null && reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      reason,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondaryOf(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _cancelledBadgeBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _cancelledBadgeBorder),
              ),
              child: Text(
                'Cancelled',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cancelledBadgeText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: onBookAgain,
            style: compactTealOutlinedButtonStyle(),
            child: const Text('Book Again'),
          ),
        ),
      ],
    );

    return AppointmentCardWrapper(
      onTap: onTap,
      flat: flat,
      showDivider: showDivider,
      child: content,
    );
  }
}
