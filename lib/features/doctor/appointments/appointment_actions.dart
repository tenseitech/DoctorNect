import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/data/shared_appointments_store.dart';
import '../../../core/firebase/firebase_error_messages.dart';
import '../../../core/notifications/patient_notification_emitter.dart';
import '../../../core/session/doctor_session.dart';
import '../models/doctor_models.dart';
import 'widgets/reschedule_modal.dart';

abstract final class DoctorAppointmentActions {
  static void reschedule(
    BuildContext context, {
    required Appointment appointment,
    VoidCallback? onComplete,
  }) {
    RescheduleModal.show(
      context,
      appointment: appointment,
      onConfirm: (newDate, newSlot, reason, notifyPatient) async {
        final oldLabel =
            '${DateFormat('dd MMM').format(appointment.appointmentDate)} · ${appointment.timeSlot}';
        final newLabel = '${DateFormat('dd MMM').format(newDate)} · $newSlot';

        try {
          await SharedAppointmentsStore.instance.rescheduleByDoctor(
            recordId: appointment.id,
            newDate: newDate,
            newSlotLabel: newSlot,
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                describeUserFacingError(e, fallback: "Couldn't reschedule this appointment. Please check your connection and try again."),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        if (notifyPatient) {
          PatientNotificationEmitter.notifyDoctorRescheduled(
            doctorName: DoctorSession.loggedInDoctorName,
            oldDateTime: oldLabel,
            newDateTime: newLabel,
          );
        }

        onComplete?.call();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notifyPatient
                  ? 'Appointment rescheduled & patient notified'
                  : 'Appointment rescheduled',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  static void cancel(
    BuildContext context, {
    required Appointment appointment,
    String reason = 'Cancelled by doctor — clinic unavailable',
    VoidCallback? onComplete,
    bool popAfter = false,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel appointment?'),
        content: Text('Cancel ${appointment.patientName}\'s appointment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await SharedAppointmentsStore.instance.cancelByDoctor(
                  appointment.id,
                  reason: reason,
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      describeUserFacingError(e, fallback: "Couldn't cancel this appointment. Please check your connection and try again."),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              PatientNotificationEmitter.notifyDoctorCancelled(
                doctorName: DoctorSession.loggedInDoctorName,
                reason: reason,
              );
              onComplete?.call();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Appointment cancelled & patient notified'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              if (popAfter) Navigator.pop(context);
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }
}
