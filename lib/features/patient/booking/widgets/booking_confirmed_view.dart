import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/notifications/app_toast.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/booking_models.dart';
import 'patient_booking_confirmed_base.dart';
import '../../../../core/theme/app_typography.dart';

class BookingConfirmedView extends StatelessWidget {
  const BookingConfirmedView({
    super.key,
    required this.booking,
    required this.onView,
    required this.onBookAnother,
  });

  final ConfirmedBooking booking;
  final VoidCallback onView;
  final VoidCallback onBookAnother;

  @override
  Widget build(BuildContext context) {
    final pending = booking.awaitingDoctorApproval;
    final accent = pending ? const Color(0xFFEA580C) : const Color(0xFF16A34A);

    return PatientBookingConfirmedBase(
      isPending: pending,
      title: pending ? 'Request Sent!' : 'Appointment Confirmed!',
      idLabel: pending
          ? 'The doctor will accept or decline your request.'
          : 'Appointment ID: ${booking.appointmentId}',
      primaryAccent: accent,
      primaryActionLabel: pending ? 'Back to Home' : 'View Appointment',
      onPrimaryAction: onView,
      secondaryActionLabel: 'Book Another',
      onSecondaryAction: onBookAnother,
      onCalendarAction: () => AppToast.info(context, 'Added to calendar'),
      mainDetails: Column(
        children: [
          Text(
            'Dr. ${booking.doctorName}',
            style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w600),
          ),
          Text(
            '${DateFormat('EEE, dd MMM yyyy').format(booking.date)} Â· ${booking.slotLabel}',
            style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
          ),
          if (!pending) ...[
            const SizedBox(height: 16),
            Text(
              '#${booking.tokenNumber}',
              style: GoogleFonts.inter(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: AppColors.patientTeal,
              ),
            ),
            Text('Token Number', style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context))),
          ],
          if (booking.clinicAddress != null && booking.clinicAddress!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              booking.clinicAddress!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }
}