import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';
import '../../appointments/models/patient_appointment_models.dart';
import '../../booking/booking_flow_screen.dart';
import '../../../../core/theme/app_typography.dart';

class AppointmentsSection extends StatelessWidget {
  const AppointmentsSection({
    super.key,
    required this.onViewAll,
    required this.onFindDoctor,
  });

  final VoidCallback onViewAll;
  final VoidCallback onFindDoctor;

  static List<PatientAppointment> _homeAppointments(
      List<PatientAppointment> all) {
    final upcoming = all
        .where((a) => a.cancellationReason == null && a.isUpcoming)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final rest = all
        .where((a) => a.cancellationReason != null || !a.isUpcoming)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return [...upcoming, ...rest].take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SharedAppointmentsStore.instance,
      builder: (context, _) {
        final compact = ResponsiveLayout.isCompact(context);
        final appointments = _homeAppointments(
          SharedAppointmentsStore.instance.patientAppointments(),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, compact ? 12 : 20, 16, compact ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Appointments',
                            style: GoogleFonts.inter(
                              fontSize: compact ? 15 : 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your upcoming & recent visits',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: onViewAll,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.patientTeal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'View all',
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 14),
                if (appointments.isEmpty)
                  _EmptyAppointments(onFindDoctor: onFindDoctor)
                else
                  Column(
                    children: [
                      for (var i = 0; i < appointments.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _AppointmentCard(appointment: appointments[i]),
                      ],
                    ],
                  ),
              ],
            ),
          );
      },
    );
  }
}

class _EmptyAppointments extends StatelessWidget {
  const _EmptyAppointments({required this.onFindDoctor});

  final VoidCallback onFindDoctor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.patientTeal.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_outlined,
                color: AppColors.patientTeal, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            'No appointments yet',
            style: GoogleFonts.inter(
                fontSize: AppTypography.bodyLarge, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Book your first consultation to see upcoming visits here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.textSecondaryOf(context),
                height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onFindDoctor,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.patientTeal,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              'Find a doctor',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment});

  final PatientAppointment appointment;

  void _openDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailScreen(appointment: appointment),
      ),
    );
  }

  void _bookAgain(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(doctorId: appointment.doctorId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _appointmentStatusStyle(appointment);
    final isUpcoming =
        appointment.cancellationReason == null && appointment.isUpcoming;
    final day = DateFormat('dd').format(appointment.dateTime);
    final month = DateFormat('MMM').format(appointment.dateTime).toUpperCase();
    final time = DateFormat('hh:mm a').format(appointment.dateTime);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isUpcoming
                  ? AppColors.patientTeal.withValues(alpha: 0.28)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isUpcoming
                          ? const [Color(0xFF0D9488), Color(0xFF0369A1)]
                          : [
                              status.color.withValues(alpha: 0.85),
                              status.color
                            ],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isUpcoming ? AppColors.patientTeal : status.color)
                                .withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
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
                          color: AppColors.surfaceOf(context)
                              .withValues(alpha: 0.92),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
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
                              _formatDoctorName(appointment.doctorName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodyMedium,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _StatusChip(label: status.label, color: status.color),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        appointment.specialization,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              size: 14,
                              color: AppColors.textSecondaryOf(context)
                                  .withValues(alpha: 0.9)),
                          const SizedBox(width: 4),
                          Text(
                            time,
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.labelMedium,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                          if (isUpcoming) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                appointment.countdownLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelSmall,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.patientTeal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isUpcoming)
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondaryOf(context)
                        .withValues(alpha: 0.85),
                  )
                else
                  TextButton(
                    onPressed: () => _bookAgain(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.patientTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Book again',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
        style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

String _formatDoctorName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Dr. —';
  if (trimmed.toLowerCase().startsWith('dr.')) return trimmed;
  return 'Dr. $trimmed';
}

({String label, Color color}) _appointmentStatusStyle(
    PatientAppointment appointment) {
  if (appointment.cancellationReason != null) {
    return (label: 'Cancelled', color: const Color(0xFFDC2626));
  }
  if (appointment.status == PatientBookingStatus.confirmed) {
    if (appointment.isUpcoming) {
      return (label: 'Upcoming', color: const Color(0xFFEA580C));
    }
    return (label: 'Completed', color: const Color(0xFF16A34A));
  }
  return (label: 'Pending', color: AppColors.textSecondary);
}
