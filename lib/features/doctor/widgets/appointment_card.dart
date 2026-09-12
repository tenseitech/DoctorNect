import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../appointments/appointment_utils.dart';
import '../appointments/widgets/appointment_action_buttons.dart';
import '../appointments/widgets/appointment_symptoms_section.dart';
import '../models/doctor_models.dart';
import 'doctor_ui_widgets.dart';

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    this.compact = false,
    this.onAccept,
    this.onDecline,
    this.onStart,
    this.onCancel,
    this.onView,
  });

  final Appointment appointment;
  final bool compact;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PatientAvatar(
                name: appointment.patientName,
                gender: appointment.gender,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${appointment.age} yrs Â· ${AppConstants.patientGenderLabel(appointment.gender)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 13, color: AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${DateFormat('dd MMM yyyy').format(appointment.appointmentDate)} Â· ${appointment.timeSlot}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(
                    label: AppointmentStatusStyle.label(appointment.status),
                    color: AppointmentStatusStyle.color(appointment.status),
                  ),
                  if (appointment.bookedByName != null &&
                      appointment.bookedByName!.trim().isNotEmpty &&
                      appointment.bookedByName!.trim().toLowerCase() !=
                          appointment.patientName.trim().toLowerCase()) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Booked by ${appointment.bookedByName}${appointment.patientRelation != null && appointment.patientRelation!.trim().isNotEmpty && appointment.patientRelation!.trim().toLowerCase() != 'self' ? ' (${appointment.patientRelation})' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  ],
                  if (appointment.slotShareReason != null &&
                      appointment.slotShareReason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SharedSlotBadge(slotShareReason: appointment.slotShareReason),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge(
                label: appointment.type == AppointmentType.newVisit ? 'New' : 'Follow-up',
                color: appointment.type == AppointmentType.newVisit
                    ? AppColors.doctorBlue
                    : const Color(0xFF7C3AED),
              ),
            ],
          ),
          if (appointment.reasonForVisit != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 14, color: AppColors.textSecondaryOf(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Reason: ${appointment.reasonForVisit}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (appointment.symptoms.isNotEmpty) ...[
            const SizedBox(height: 8),
            SymptomChipsPreview(symptoms: appointment.symptoms),
          ],
          if (!compact &&
              (onAccept != null ||
                  onDecline != null ||
                  onStart != null ||
                  onCancel != null ||
                  onView != null)) ...[
            const SizedBox(height: 12),
            AppointmentActionButtons(
              appointment: appointment,
              compact: true,
              onAccept: onAccept,
              onDecline: onDecline,
              onStart: onStart,
              onCancel: onCancel,
              onView: onView,
            ),
          ],
        ],
      ),
    );
  }
}