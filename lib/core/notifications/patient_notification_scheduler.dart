import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/shared_appointments_store.dart';
import '../../features/patient/appointments/models/patient_appointment_models.dart';
import '../../features/patient/data/patient_mock_data.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';
import '../../features/patient/profile/models/patient_profile_models.dart';
import 'patient_activity_store.dart';
import 'patient_notification_emitter.dart';

/// Time-based patient alerts — only for features present in the patient app.
class PatientNotificationScheduler {
  PatientNotificationScheduler._();

  static final instance = PatientNotificationScheduler._();

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

  List<PatientAppointment> get _upcoming {
    final all = SharedAppointmentsStore.instance.patientAppointments();
    return all
        .where((a) =>
            a.cancellationReason == null &&
            a.dateTime.isAfter(DateTime.now().subtract(const Duration(minutes: 30))))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  void _tick() {
    final prefs = PatientProfileMock.notificationPrefs;
    if (!prefs.appointmentReminders) return;

    final now = DateTime.now();
    _checkTomorrow8Pm(now);
    _checkTwoHoursBefore(now);
    _checkThirtyMinBefore(now);
    _checkLabCollection(now);
    _checkPhlebotomistOnWay(now);
    _checkDailyWellness(now, prefs);
    _checkSundayVitals(now);
    _checkVaccinationDue(now);
  }

  void runStartupChecks() {
    if (!PatientProfileMock.notificationPrefs.healthTips) return;
    PatientNotificationEmitter.notifyHealthTip(
      tip: PatientMockData.healthTips.first.title,
    );
  }

  void _checkTomorrow8Pm(DateTime now) {
    if (now.hour != 20 || now.minute > 5) return;
    final tomorrow = _upcoming.where((a) {
      final d = a.dateTime;
      final t = DateTime.now().add(const Duration(days: 1));
      return d.year == t.year && d.month == t.month && d.day == t.day;
    });
    for (final a in tomorrow) {
      PatientNotificationEmitter.notifyReminderTomorrow(
        doctorName: a.doctorName,
        dateTimeLabel: DateFormat('dd MMM, hh:mm a').format(a.dateTime),
        location: a.clinicAddress ?? a.clinicName ?? 'Clinic',
      );
    }
  }

  void _checkTwoHoursBefore(DateTime now) {
    for (final a in _upcoming) {
      final diff = a.dateTime.difference(now);
      if (diff.inMinutes >= 115 && diff.inMinutes <= 125) {
        PatientNotificationEmitter.notifyReminderTwoHours(
          doctorName: a.doctorName,
          dateTimeLabel: DateFormat('dd MMM, hh:mm a').format(a.dateTime),
          clinicAddress: a.clinicAddress ?? 'See appointment for address',
        );
      }
    }
  }

  void _checkThirtyMinBefore(DateTime now) {
    for (final a in _upcoming) {
      final diff = a.dateTime.difference(now);
      if (diff.inMinutes >= 28 && diff.inMinutes <= 32) {
        PatientNotificationEmitter.notifyReminderThirtyMin(doctorName: a.doctorName);
      }
    }
  }

  void _checkLabCollection(DateTime now) {
    final booking = PatientActivityStore.instance.lastLabBooking;
    if (booking == null || !booking.isHomeCollection) return;
    final collection = DateTime(
      booking.date.year,
      booking.date.month,
      booking.date.day,
      _parseHour(booking.slotLabel),
    );
    final diff = collection.difference(now);
    if (diff.inMinutes >= 55 && diff.inMinutes <= 65) {
      PatientNotificationEmitter.notifyLabCollectionReminder(
        slotLabel: booking.slotLabel,
        // FIXED: don't fabricate a specific phlebotomist name/phone — the booking has none assigned yet.
        phlebotomistName: 'Your lab collection agent',
        contact: '',
      );
    }
  }

  void _checkPhlebotomistOnWay(DateTime now) {
    final booking = PatientActivityStore.instance.lastLabBooking;
    if (booking == null || !booking.isHomeCollection) return;
    final collection = DateTime(
      booking.date.year,
      booking.date.month,
      booking.date.day,
      _parseHour(booking.slotLabel),
    );
    final diff = collection.difference(now);
    if (diff.inMinutes >= 25 && diff.inMinutes <= 35) {
      PatientNotificationEmitter.notifyPhlebotomistOnTheWay(
        // FIXED: don't use hardcoded phlebotomist data — booking has no assigned agent yet.
        phlebotomistName: 'Your lab collection agent',
        eta: 'soon',
      );
    }
  }

  void _checkDailyWellness(DateTime now, NotificationPrefs prefs) {
    if (prefs.medicationReminders && prefs.medications.isNotEmpty) {
      for (final m in prefs.medications) {
        if (now.hour == 8 || now.hour == 20) {
          PatientNotificationEmitter.notifyMedicineReminder(
            medicineName: m.name,
            dosage: 'Scheduled dose',
            foodTiming: 'As prescribed',
          );
        }
      }
    }
    if (prefs.healthTips && now.hour == 8 && now.minute <= 5) {
      PatientNotificationEmitter.notifyHealthTip(
        tip: PatientMockData.healthTips.first.title,
      );
    }
  }

  void _checkSundayVitals(DateTime now) {
    if (now.weekday != DateTime.sunday || now.hour != 9 || now.minute > 5) return;
    PatientNotificationEmitter.notifyVitalsReminder();
  }

  void _checkVaccinationDue(DateTime now) {
    if (now.hour != 10) return;
    // FIXED: only notify when a real vaccination record has an upcoming due date — no hardcoded Influenza.
    final upcoming = PatientProfileMock.vaccinations
        .where((v) {
          final daysUntil = v.date.difference(now).inDays;
          return daysUntil >= 0 && daysUntil <= 7;
        })
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (upcoming.isEmpty) return;
    final next = upcoming.first;
    PatientNotificationEmitter.notifyVaccinationDue(
      vaccineName: next.name,
      dueDate: next.date,
    );
  }

  int _parseHour(String slot) {
    final match = RegExp(r'(\d{1,2})').firstMatch(slot);
    if (match == null) return 9;
    var h = int.parse(match.group(1)!);
    if (slot.toLowerCase().contains('pm') && h < 12) h += 12;
    return h;
  }
}
