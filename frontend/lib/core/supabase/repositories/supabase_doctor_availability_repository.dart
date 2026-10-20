import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/patient/booking/models/booking_models.dart';
import '../../data/shared_appointments_store.dart';
import '../../firebase/models/doctor_availability.dart';
import '../supabase_bootstrap.dart';

/// Supabase Repository for Doctor Availability & Booking Slot Computation.
/// Replaces Firestore `doctor_availability/{doctorId}`.
class SupabaseDoctorAvailabilityRepository {
  SupabaseDoctorAvailabilityRepository._();

  static final SupabaseDoctorAvailabilityRepository instance =
      SupabaseDoctorAvailabilityRepository._();

  static final _timeFormat = DateFormat('hh:mm a');

  static String normalizeTimeLabel(String label) {
    try {
      final parsed = _timeFormat.parse(label.trim());
      return _timeFormat.format(parsed);
    } catch (_) {
      return label.trim().toLowerCase();
    }
  }

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<DoctorAvailability?> fetch(
    String doctorId, {
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return null;

    try {
      final res = await _client
          .from('doctor_availability')
          .select()
          .eq('doctor_id', doctorId)
          .maybeSingle();

      if (res == null) return null;

      final blockedRes = await _client
          .from('doctor_blocked_dates')
          .select('blocked_date')
          .eq('doctor_id', doctorId);

      final blockedDates = <DateTime>{};
      for (final item in (blockedRes as List)) {
        final dStr = item['blocked_date'] as String?;
        if (dStr != null) {
          final dt = DateTime.tryParse(dStr);
          if (dt != null) {
            blockedDates.add(DateTime(dt.year, dt.month, dt.day));
          }
        }
      }

      final workingDaysList = (res['working_days'] as List<dynamic>? ??
              const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'])
          .map((e) => e.toString())
          .toList();

      return DoctorAvailability(
        workingDays: workingDaysList,
        morningStart: res['morning_start'] as String? ?? '09:00 AM',
        morningEnd: res['morning_end'] as String? ?? '01:00 PM',
        eveningEnabled: res['evening_enabled'] as bool? ?? true,
        eveningStart: res['evening_start'] as String? ?? '04:00 PM',
        eveningEnd: res['evening_end'] as String? ?? '08:00 PM',
        slotDurationMins: (res['slot_duration_mins'] as num?)?.toInt() ?? 15,
        maxPatientsPerDay: (res['max_patients_per_day'] as num?)?.toInt() ?? 20,
        breakEnabled: res['break_enabled'] as bool? ?? false,
        breakStart: res['break_start'] as String? ?? '01:00 PM',
        breakEnd: res['break_end'] as String? ?? '02:00 PM',
        blockedDates: blockedDates,
        leaveStart: res['leave_start'] != null
            ? DateTime.tryParse(res['leave_start'].toString())
            : null,
        leaveEnd: res['leave_end'] != null
            ? DateTime.tryParse(res['leave_end'].toString())
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String doctorId, DoctorAvailability schedule) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return;

    final payload = {
      'doctor_id': doctorId,
      'working_days': schedule.workingDays,
      'morning_start': schedule.morningStart,
      'morning_end': schedule.morningEnd,
      'evening_enabled': schedule.eveningEnabled,
      'evening_start': schedule.eveningStart,
      'evening_end': schedule.eveningEnd,
      'slot_duration_mins': schedule.slotDurationMins,
      'max_patients_per_day': schedule.maxPatientsPerDay,
      'break_enabled': schedule.breakEnabled,
      'break_start': schedule.breakStart,
      'break_end': schedule.breakEnd,
      if (schedule.leaveStart != null)
        'leave_start': schedule.leaveStart!.toIso8601String(),
      if (schedule.leaveEnd != null)
        'leave_end': schedule.leaveEnd!.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _client.from('doctor_availability').upsert(payload, onConflict: 'doctor_id');

    // Sync blocked dates
    await _client.from('doctor_blocked_dates').delete().eq('doctor_id', doctorId);
    if (schedule.blockedDates.isNotEmpty) {
      final insertRows = schedule.blockedDates.map((d) => {
        'doctor_id': doctorId,
        'blocked_date': DateFormat('yyyy-MM-dd').format(d),
      }).toList();
      await _client.from('doctor_blocked_dates').insert(insertRows);
    }
  }

  List<DateTime> nextBookableDays({int count = 7}) {
    final now = DateTime.now();
    return List.generate(
      count,
      (i) => DateTime(now.year, now.month, now.day + i),
    );
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
    } catch (_) {
      schedule = null;
    }
    schedule ??= DoctorAvailability.defaults();

    final dayName = DateFormat('EEE').format(date);
    if (!schedule.workingDays.contains(dayName)) return const [];

    final dateOnly = DateTime(date.year, date.month, date.day);
    if (schedule.blockedDates.contains(dateOnly)) return const [];

    if (schedule.leaveStart != null && schedule.leaveEnd != null) {
      final lStart = DateTime(
        schedule.leaveStart!.year,
        schedule.leaveStart!.month,
        schedule.leaveStart!.day,
      );
      final lEnd = DateTime(
        schedule.leaveEnd!.year,
        schedule.leaveEnd!.month,
        schedule.leaveEnd!.day,
      );
      if (!dateOnly.isBefore(lStart) && !dateOnly.isAfter(lEnd)) {
        return const [];
      }
    }

    final booked = existingAppointments ??
        SharedAppointmentsStore.instance.records.where((r) {
          return r.doctorId == doctorId &&
              !r.isCancelled &&
              _sameDay(r.dateTime, dateOnly);
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
      day: dateOnly,
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
        day: dateOnly,
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

      current = slotEnd;
    }
  }

  DateTime _parseTime(DateTime day, String label) {
    try {
      final parsed = _timeFormat.parse(label.trim());
      return DateTime(
        day.year,
        day.month,
        day.day,
        parsed.hour,
        parsed.minute,
      );
    } catch (_) {
      return DateTime(day.year, day.month, day.day, 9, 0);
    }
  }

  String _periodFor(DateTime dt) {
    if (dt.hour < 12) return 'Morning';
    if (dt.hour < 17) return 'Afternoon';
    return 'Evening';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
