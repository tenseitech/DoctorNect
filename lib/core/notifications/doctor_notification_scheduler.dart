import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../features/doctor/models/doctor_models.dart';
import '../data/shared_appointments_store.dart';
import '../session/doctor_session.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import 'doctor_notification_emitter.dart';
import 'in_app_notification_service.dart';

/// Time-based doctor alerts for features that exist in the doctor app (in-clinic only).
class DoctorNotificationScheduler {
  DoctorNotificationScheduler._();

  static final instance = DoctorNotificationScheduler._();

  Timer? _timer;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_running) return;
      _tick();
      _timer = Timer.periodic(const Duration(minutes: 3), (_) => _tick());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  List<Appointment> get _todayAppointments {
    final store = SharedAppointmentsStore.instance;
    final doctorId = DoctorSession.loggedInDoctorId;
    return [
      ...store.todayQueueForDoctor(doctorId),
      ...store.doctorAppointments(doctorId).where((a) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final d = DateTime(a.appointmentDate.year, a.appointmentDate.month,
            a.appointmentDate.day);
        return d == today && a.status == AppointmentStatus.confirmed;
      }),
    ];
  }

  List<Appointment> get _tomorrowAppointments =>
      SharedAppointmentsStore.instance
          .tomorrowForDoctor(DoctorSession.loggedInDoctorId);

  void _tick() {
    final now = DateTime.now();
    _checkTomorrowReminder(now);
    _checkTodayMorningReminder(now);
    _checkNextPatientReminders(now);
    _checkNoShowAlerts(now);
    _checkSlotsFillingUp(now);
  }

  void _checkTomorrowReminder(DateTime now) {
    if (now.hour != 20) return;
    final tomorrow = _tomorrowAppointments;
    if (tomorrow.isEmpty) return;
    final lines = tomorrow
        .map((a) => '${a.patientName} · ${a.timeSlot} · ${_typeLabel(a.type)}')
        .join('\n');
    DoctorNotificationEmitter.notifyTomorrowSummary(
      summary: '${tomorrow.length} appointment(s) tomorrow:\n$lines',
    );
  }

  void _checkTodayMorningReminder(DateTime now) {
    if (now.hour != 7 || now.minute > 5) return;
    final today = _todayAppointments
        .where((a) => a.status != AppointmentStatus.cancelled)
        .toList();
    if (today.isEmpty) return;
    final lines =
        today.map((a) => '${a.timeSlot} · ${a.patientName}').join('\n');
    DoctorNotificationEmitter.notifyTodaySchedule(
      summary: '${today.length} appointment(s) today:\n$lines',
    );
  }

  void _checkNextPatientReminders(DateTime now) {
    for (final a in _todayAppointments) {
      if (a.status == AppointmentStatus.cancelled ||
          a.status == AppointmentStatus.completed) {
        continue;
      }
      final diff = a.appointmentDate.difference(now);
      if (diff.inMinutes >= 14 && diff.inMinutes <= 16) {
        DoctorNotificationEmitter.notifyNextPatient(
          patientName: a.patientName,
          reason:
              a.type == AppointmentType.newVisit ? 'New visit' : 'Follow-up',
          appointmentId: a.id,
          appointmentTime: a.appointmentDate,
        );
      }
    }
  }

  void _checkNoShowAlerts(DateTime now) {
    for (final a in _todayAppointments) {
      if (a.status != AppointmentStatus.waiting &&
          a.status != AppointmentStatus.confirmed) {
        continue;
      }
      final afterStart = now.difference(a.appointmentDate);
      if (afterStart.inMinutes >= 10 && afterStart.inMinutes <= 12) {
        InAppNotificationService.instance.addDoctor(
          DoctorNotificationEmitter.patientNoShowAlert(
            patientName: a.patientName,
            slotLabel: a.timeSlot,
            appointmentId: a.id,
          ),
        );
      }
    }
  }

  void _checkSlotsFillingUp(DateTime now) {
    final booked = _todayAppointments.length;
    final max = DoctorProfileStore.instance.profile.maxPatientsPerDay;
    if (max == 0) return;
    final pct = ((booked / max) * 100).round();
    if (pct >= 80) {
      DoctorNotificationEmitter.notifySlotsFillingUp(percentBooked: pct);
    }
  }

  String _typeLabel(AppointmentType t) =>
      t == AppointmentType.newVisit ? 'New' : 'Follow-up';

  void runStartupChecks() {
    final today = _todayAppointments;
    if (today.isEmpty) return;
    final lines = today
        .take(4)
        .map((a) => '${a.timeSlot} · ${a.patientName}')
        .join(' · ');
    DoctorNotificationEmitter.notifyTodaySchedule(
      summary: 'You have ${today.length} appointment(s) today. Next: $lines',
    );
  }
}
