import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../booking/widgets/patient_booking_confirmed_base.dart';
import '../widgets/patient_app_shell.dart';
import 'models/lab_models.dart';
import 'patient_lab_bookings_screen.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';
import '../../../core/theme/app_typography.dart';

class LabBookingConfirmedScreen extends StatelessWidget {
  const LabBookingConfirmedScreen({super.key, required this.booking});

  final ConfirmedLabBooking booking;

  void _viewBooking(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PatientLabBookingsScreen()),
    );
  }

  void _goToHome(BuildContext context) {
    final shell = context.findAncestorWidgetOfExactType<PatientAppShell>();
    Navigator.of(context).popUntil((route) => route.isFirst);
    shell?.onDestinationSelected(0);
  }

  @override
  Widget build(BuildContext context) {
    final pending = booking.awaitingLabApproval;
    final accent = pending ? AppColors.labPurple : const Color(0xFF16A34A);

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      body: LabPageBody(
        centerVertically: true,
        child: PatientBookingConfirmedBase(
          centerCard: true,
          isPending: pending,
          title: pending ? 'Request sent!' : 'Booking Confirmed!',
          idLabel: 'Booking ID: ${booking.bookingId}',
          headerIcon: pending ? Icons.hourglass_top : Icons.check_circle,
          subMessage: pending
              ? (booking.labName != null
                  ? 'Waiting for ${booking.labName} to accept your request. You will be notified when the lab responds.'
                  : 'Waiting for the lab to accept your request. You will be notified when the lab responds.')
              : null,
          primaryAccent: accent,
          primaryActionLabel: 'View Bookings',
          onPrimaryAction: () => _viewBooking(context),
          secondaryActionLabel: 'Back to Home',
          onSecondaryAction: () => _goToHome(context),
          mainDetails: Column(
            children: [
              Text(
                booking.testName,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (booking.isHomeCollection) ...[
                Text(
                  'Phlebotomist will arrive:',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('EEE, dd MMM yyyy').format(booking.date)} Â· ${booking.slotLabel}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, color: AppColors.labPurple),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  booking.address,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                ),
              ] else ...[
                Text(
                  'Visit lab for sample collection:',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('EEE, dd MMM yyyy').format(booking.date)} Â· ${booking.slotLabel}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, color: AppColors.labPurple),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  booking.address,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
