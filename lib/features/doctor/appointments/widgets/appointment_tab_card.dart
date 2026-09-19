import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/doctor_models.dart';
import '../appointment_utils.dart';
import '../../widgets/doctor_ui_widgets.dart';
import 'appointment_action_buttons.dart';
import 'appointment_symptoms_section.dart';
import '../../../../core/theme/app_typography.dart';

class AppointmentTabCard extends StatelessWidget {
  const AppointmentTabCard({
    super.key,
    required this.appointment,
    required this.onTap,
    required this.onAccept,
    required this.onDecline,
    required this.onStart,
    required this.onView,
    required this.onCancel,
    required this.onReschedule,
  });

  final Appointment appointment;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onStart;
  final VoidCallback onView;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final statusColor = AppointmentStatusStyle.color(appointment.status);
    final isUpcoming =
        AppointmentStatusStyle.isUpcomingActionable(appointment.status);
    final symptoms = appointment.symptoms.isNotEmpty
        ? appointment.symptoms
        : (SharedAppointmentsStore.instance
                .findRecordById(appointment.id)
                ?.symptoms ??
            const []);
    final wide = !ResponsiveLayout.isCompact(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(appointment.id),
        enabled: !wide,
        endActionPane: isUpcoming
            ? ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.38,
                children: [
                  SlidableAction(
                    onPressed: (_) => onReschedule(),
                    backgroundColor: AppColors.doctorBlue,
                    foregroundColor: AppColors.white,
                    icon: AppIcons.reschedule,
                    label: 'Reschedule',
                    borderRadius:
                        BorderRadius.circular(AppConstants.inputRadius),
                  ),
                  SlidableAction(
                    onPressed: (_) => onCancel(),
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: AppColors.white,
                    icon: Icons.close,
                    label: 'Cancel',
                    borderRadius:
                        BorderRadius.circular(AppConstants.inputRadius),
                  ),
                ],
              )
            : null,
        child: Material(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              padding: EdgeInsets.all(wide ? 16 : 12),
              child: wide
                  ? _WideLayout(
                      appointment: appointment,
                      statusColor: statusColor,
                      symptoms: symptoms,
                      onAccept: onAccept,
                      onDecline: onDecline,
                      onStart: onStart,
                      onCancel: onCancel,
                      onView: onView,
                      onReschedule: onReschedule,
                      isUpcoming: isUpcoming,
                    )
                  : _CompactLayout(
                      appointment: appointment,
                      statusColor: statusColor,
                      symptoms: symptoms,
                      onAccept: onAccept,
                      onDecline: onDecline,
                      onStart: onStart,
                      onCancel: onCancel,
                      onView: onView,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.appointment,
    required this.statusColor,
    required this.symptoms,
    required this.onAccept,
    required this.onDecline,
    required this.onStart,
    required this.onCancel,
    required this.onView,
    required this.onReschedule,
    required this.isUpcoming,
  });

  final Appointment appointment;
  final Color statusColor;
  final List<String> symptoms;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onView;
  final VoidCallback onReschedule;
  final bool isUpcoming;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _TokenBadge(number: appointment.tokenNumber, wide: true),
        const SizedBox(width: 16),
        Expanded(
          child: _AppointmentDetails(
            appointment: appointment,
            symptoms: symptoms,
            showStatus: false,
          ),
        ),
        const SizedBox(width: 20),
        Container(
          width: 1,
          height: 72,
          color: AppColors.borderOf(context),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 168,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: StatusBadge(
                  label: AppointmentStatusStyle.label(appointment.status),
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: AppointmentActionButtons(
                  appointment: appointment,
                  onAccept: onAccept,
                  onDecline: onDecline,
                  onStart: onStart,
                  onCancel: onCancel,
                  onView: onView,
                ),
              ),
              if (isUpcoming) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onReschedule,
                    icon: const Icon(AppIcons.reschedule, size: 16),
                    label: const Text('Reschedule'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.appointment,
    required this.statusColor,
    required this.symptoms,
    required this.onAccept,
    required this.onDecline,
    required this.onStart,
    required this.onCancel,
    required this.onView,
  });

  final Appointment appointment;
  final Color statusColor;
  final List<String> symptoms;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TokenBadge(number: appointment.tokenNumber, wide: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AppointmentDetails(
                appointment: appointment,
                symptoms: symptoms,
                showStatus: true,
                statusColor: statusColor,
              ),
              const SizedBox(height: 10),
              AppointmentActionButtons(
                appointment: appointment,
                onAccept: onAccept,
                onDecline: onDecline,
                onStart: onStart,
                onCancel: onCancel,
                onView: onView,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppointmentDetails extends StatelessWidget {
  const _AppointmentDetails({
    required this.appointment,
    required this.symptoms,
    required this.showStatus,
    this.statusColor,
  });

  final Appointment appointment;
  final List<String> symptoms;
  final bool showStatus;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final typeLabel = AppointmentStatusStyle.typeLabel(appointment.type);
    final typeColor = appointment.type == AppointmentType.newVisit
        ? AppColors.doctorBlue
        : const Color(0xFF7C3AED);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                appointment.patientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            if (showStatus && statusColor != null) ...[
              const SizedBox(width: 8),
              StatusBadge(
                label: AppointmentStatusStyle.label(appointment.status),
                color: statusColor!,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${appointment.age} yrs · ${AppConstants.patientGenderLabel(appointment.gender)} · $typeLabel',
          style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 4),
        Text(
          '${DateFormat('dd MMM yyyy').format(appointment.appointmentDate)} · ${appointment.timeSlot}',
          style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context)),
        ),
        if (appointment.bookedByName != null &&
            appointment.bookedByName!.trim().isNotEmpty &&
            appointment.bookedByName!.trim().toLowerCase() !=
                appointment.patientName.trim().toLowerCase()) ...[
          const SizedBox(height: 6),
          Text(
            'Booked by ${appointment.bookedByName}${appointment.patientRelation != null && appointment.patientRelation!.trim().isNotEmpty && appointment.patientRelation!.trim().toLowerCase() != 'self' ? ' (${appointment.patientRelation})' : ''}',
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w500,
              color: typeColor,
            ),
          ),
        ],
        if (appointment.slotShareReason != null &&
            appointment.slotShareReason!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          SharedSlotBadge(slotShareReason: appointment.slotShareReason),
        ],
        if (appointment.reasonForVisit != null) ...[
          const SizedBox(height: 6),
          Text(
            'Reason: ${appointment.reasonForVisit}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context)),
          ),
        ],
        if (symptoms.isNotEmpty) ...[
          const SizedBox(height: 8),
          SymptomChipsPreview(symptoms: symptoms),
        ],
      ],
    );
  }
}

class _TokenBadge extends StatelessWidget {
  const _TokenBadge({required this.number, required this.wide});

  final int number;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final size = wide ? 48.0 : 40.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.doctorBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.25)),
      ),
      child: Text(
        '#$number',
        style: GoogleFonts.inter(
          fontSize: wide ? 15 : 14,
          fontWeight: FontWeight.w800,
          color: AppColors.doctorBlue,
        ),
      ),
    );
  }
}
