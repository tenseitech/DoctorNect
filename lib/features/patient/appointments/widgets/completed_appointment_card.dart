import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/patient_appointment_models.dart';
import '../patient_prescription_opener.dart';
import '../../utils/doctor_display_name.dart';
import 'appointment_card_shared.dart';

class CompletedAppointmentCard extends StatelessWidget {
  const CompletedAppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
    required this.onBookAgain,
    required this.onWriteReview,
    this.onEditReview,
    this.flat = false,
    this.showDivider = false,
  });

  final PatientAppointment appointment;
  final VoidCallback onTap;
  final VoidCallback onBookAgain;
  final VoidCallback onWriteReview;
  final VoidCallback? onEditReview;
  final bool flat;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final doctorRating = appointmentDoctorRatingBadge(a.doctorId);

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
                ],
              ),
            ),
            if (doctorRating != null) ...[
              const SizedBox(width: 8),
              doctorRating,
            ],
          ],
        ),
        if (a.diagnosis != null) ...[
          const SizedBox(height: 10),
          Text(
            a.diagnosis!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
        ],
        if (a.hasPrescription || a.hasReport) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (a.hasPrescription)
                OutlinedButton.icon(
                  onPressed: () => PatientPrescriptionOpener.open(context, a),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                  label: const Text('Prescription'),
                  style: compactTealOutlinedButtonStyle(),
                ),
              if (a.hasReport)
                OutlinedButton.icon(
                  onPressed: () {
                    AppToast.info(context, 'Report download is not available yet.');
                  },
                  icon: const Icon(Icons.download_outlined, size: 14),
                  label: const Text('Report'),
                  style: compactTealOutlinedButtonStyle(),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: onBookAgain,
              style: compactTealOutlinedButtonStyle(),
              child: const Text('Book Again'),
            ),
            if (a.hasReview && a.reviewRating != null) ...[
              appointmentReviewStars(a.reviewRating!),
              if (a.canEditReview && onEditReview != null)
                TextButton(
                  onPressed: onEditReview,
                  style: compactGhostButtonStyle(),
                  child: const Text('Edit review'),
                ),
            ] else
              TextButton(
                onPressed: onWriteReview,
                style: compactGhostButtonStyle(),
                child: const Text('Rate Doctor'),
              ),
          ],
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
