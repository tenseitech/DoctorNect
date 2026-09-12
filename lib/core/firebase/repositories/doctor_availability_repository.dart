import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../features/patient/booking/models/booking_models.dart';
import '../../data/shared_appointments_store.dart';
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_read_helper.dart';
import '../mappers/doctor_availability_mapper.dart';
import '../models/doctor_availability.dart';

class DoctorAvailabilityRepository {
  DoctorAvailabilityRepository._();

  static final DoctorAvailabilityRepository instance = DoctorAvailabilityRepository._();

  static final _timeFormat = DateFormat('hh:mm a');

  Future<DoctorAvailability?> fetch(String doctorId, {bool preferCache = true}) async {
    if (!FirebaseBootstrap.isReady) return null;

    final snap = await FirestoreReadHelper.getDocument(
      reference: FirebaseFirestore.instance.collection(FirestorePaths.doctorAvailability).doc(doctorId),
      preferCache: preferCache,
    );
    if (!snap.exists) return null;
    return DoctorAvailabilityMapper.fromMap(snap.data());
  }

  Future<void> save(String doctorId, DoctorAvailability schedule) async {
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.doctorAvailability)
        .doc(doctorId)
        .set(DoctorAvailabilityMapper.toMap(doctorId, schedule));
  }

  List<DateTime> nextBookableDays({int count = 7}) {
    final now = DateTime.now();
    return List.generate(count, (i) => DateTime(now.year, now.month, now.day + i));
  }

  Future<List<TimeSlot>> slotsForDate({
    required String doctorId,
    required DateTime date,
    List<DoctorNectAppointmentRecord>? existingAppointments,
    DateTime? referenceTime,
  }) async {
    DoctorAvailability? schedule;
    try {
      schedule = await fetch(doctorId, preferCache: true);
    } catch (_) {}
    schedule ??= DoctorAvailability.defaults();
    final day = DateTime(date.year, date.month, date.day);
    final weekday = DateFormat('EEE').format(day);

    if (!schedule.workingDays.contains(weekday)) return const [];
    if (schedule.blockedDates.any((d) => _sameDay(d, day))) return const [];

    if (schedule.leaveStart != null && schedule.leaveEnd != null) {
      final start = DateTime(
        schedule.leaveStart!.year,
        schedule.leaveStart!.month,
        schedule.leaveStart!.day,
      );
      final end = DateTime(
        schedule.leaveEnd!.year,
        schedule.leaveEnd!.month,
        schedule.leaveEnd!.day,
      );
      if (!day.isBefore(start) && !day.isAfter(end)) return const [];
    }

    final booked = existingAppointments ??
        SharedAppointmentsStore.instance.records.where((r) {
          return r.doctorId == doctorId &&
              !r.isCancelled &&
              _sameDay(r.dateTime, day);
        }).toList();

    if (booked.length >= schedule.maxPatientsPerDay) return const [];

    final bookingCounts = <String, int>{};
    for (final r in booked) {
      final key = normalizeTimeLabel(r.slotLabel);
      bookingCounts[key] = (bookingCounts[key] ?? 0) + 1;
    }
    final slots = <TimeSlot>[];

    _appendRange(
      slots: slots,
      day: day,
      startLabel: schedule.morningStart,
      endLabel: schedule.morningEnd,
      durationMins: schedule.slotDurationMins,
      breakEnabled: schedule.breakEnabled,
      breakStart: schedule.breakStart,
      breakEnd: schedule.breakEnd,
      bookedCounts: bookingCounts,
      referenceTime: referenceTime,
    );

    if (schedule.eveningEnabled) {
      _appendRange(
        slots: slots,
        day: day,
        startLabel: schedule.eveningStart,
        endLabel: schedule.eveningEnd,
        durationMins: schedule.slotDurationMins,
        breakEnabled: schedule.breakEnabled,
        breakStart: schedule.breakStart,
        breakEnd: schedule.breakEnd,
        bookedCounts: bookingCounts,
        referenceTime: referenceTime,
      );
    }

    // Deduplicate slots by label in case morning/evening ranges overlap
    final uniqueSlots = <String, TimeSlot>{};
    for (final slot in slots) {
      uniqueSlots.putIfAbsent(slot.label, () => slot);
    }

    final resultList = uniqueSlots.values.toList();
    resultList.sort((a, b) {
      try {
        final timeA = _timeFormat.parse(a.label.trim());
        final timeB = _timeFormat.parse(b.label.trim());
        return timeA.compareTo(timeB);
      } catch (_) {
        return 0;
      }
    });

    return resultList;
  }

  void _appendRange({
    required List<TimeSlot> slots,
    required DateTime day,
    required String startLabel,
    required String endLabel,
    required int durationMins,
    required bool breakEnabled,
    required String breakStart,
    required String breakEnd,
    required Map<String, int> bookedCounts,
    DateTime? referenceTime,
  }) {
    var current = _parseTime(day, startLabel);
    final end = _parseTime(day, endLabel);
    final breakStartTime = breakEnabled ? _parseTime(day, breakStart) : null;
    final breakEndTime = breakEnabled ? _parseTime(day, breakEnd) : null;

    while (current.isBefore(end)) {
      final slotEnd = current.add(Duration(minutes: durationMins));
      if (slotEnd.isAfter(end)) break;

      final inBreak = breakStartTime != null &&
          breakEndTime != null &&
          current.isBefore(breakEndTime) &&
          slotEnd.isAfter(breakStartTime);

      if (!inBreak) {
        final label = _timeFormat.format(current);
        final normalized = normalizeTimeLabel(label);
        final isPast = isSlotTimeInPast(day, label, referenceTime);
        final bookingCount = bookedCounts[normalized] ?? 0;
        slots.add(
          TimeSlot(
            id: '${day.year}${day.month}${day.day}_$normalized',
            label: label,
            period: _periodFor(current),
            status: isPast || bookingCount >= kMaxPatientsPerTimeSlot
                ? SlotStatus.booked
                : SlotStatus.available,
            bookingCount: bookingCount,
          ),
        );
      }

      current = current.add(Duration(minutes: durationMins));
    }
  }

  DateTime _parseTime(DateTime day, String label) {
    final parsed = _timeFormat.parse(label.trim());
    return DateTime(day.year, day.month, day.day, parsed.hour, parsed.minute);
  }

  String _periodFor(DateTime time) {
    if (time.hour < 12) return 'Morning';
    if (time.hour < 17) return 'Afternoon';
    return 'Evening';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Why the doctor cannot be booked on [date], or null if the day is normally bookable.
  String? unavailabilityReason(DoctorAvailability schedule, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final weekday = DateFormat('EEE').format(day);

    if (schedule.blockedDates.any((d) => _sameDay(d, day))) {
      return 'Doctor is on holiday on ${DateFormat('dd MMM yyyy').format(day)}';
    }

    if (schedule.leaveStart != null && schedule.leaveEnd != null) {
      final start = DateTime(
        schedule.leaveStart!.year,
        schedule.leaveStart!.month,
        schedule.leaveStart!.day,
      );
      final end = DateTime(
        schedule.leaveEnd!.year,
        schedule.leaveEnd!.month,
        schedule.leaveEnd!.day,
      );
      if (!day.isBefore(start) && !day.isAfter(end)) {
        return 'Doctor is on leave on ${DateFormat('dd MMM yyyy').format(day)}';
      }
    }

    if (!schedule.workingDays.contains(weekday)) {
      return 'Doctor is not available on ${DateFormat('EEE').format(day)} (weekly off)';
    }

    return null;
  }

  bool isUnavailableDay(DoctorAvailability schedule, DateTime date) =>
      unavailabilityReason(schedule, date) != null;

  static String normalizeTimeLabel(String label) {
    try {
      final parsed = _sharedTimeFormat.parse(label.trim());
      return _sharedTimeFormat.format(parsed);
    } catch (_) {
      return label.trim().toLowerCase();
    }
  }

  static final DateFormat _sharedTimeFormat = DateFormat('hh:mm a');
}
