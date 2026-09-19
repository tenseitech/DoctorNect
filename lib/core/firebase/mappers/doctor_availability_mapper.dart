import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/doctor_availability.dart';

abstract final class DoctorScheduleAvailabilityMapper {
  static Map<String, dynamic> toMap(
      String doctorId, DoctorScheduleAvailability schedule) {
    return {
      'doctorId': doctorId,
      'workingDays': schedule.workingDays,
      'morningStart': schedule.morningStart,
      'morningEnd': schedule.morningEnd,
      'eveningEnabled': schedule.eveningEnabled,
      'eveningStart': schedule.eveningStart,
      'eveningEnd': schedule.eveningEnd,
      'slotDurationMins': schedule.slotDurationMins,
      'maxPatientsPerDay': schedule.maxPatientsPerDay,
      'breakEnabled': schedule.breakEnabled,
      'breakStart': schedule.breakStart,
      'breakEnd': schedule.breakEnd,
      'blockedDates': schedule.blockedDates
          .map((d) => Timestamp.fromDate(DateTime(d.year, d.month, d.day)))
          .toList(),
      if (schedule.leaveStart != null)
        'leaveStart': Timestamp.fromDate(schedule.leaveStart!),
      if (schedule.leaveEnd != null)
        'leaveEnd': Timestamp.fromDate(schedule.leaveEnd!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DoctorScheduleAvailability? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      final blocked = <DateTime>{};
      for (final item in data['blockedDates'] as List<dynamic>? ?? const []) {
        if (item is Timestamp) {
          final d = item.toDate();
          blocked.add(DateTime(d.year, d.month, d.day));
        }
      }

      return DoctorScheduleAvailability(
        workingDays: (data['workingDays'] as List<dynamic>? ??
                const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'])
            .cast<String>(),
        morningStart: data['morningStart'] as String? ?? '09:00 AM',
        morningEnd: data['morningEnd'] as String? ?? '01:00 PM',
        eveningEnabled: data['eveningEnabled'] as bool? ?? true,
        eveningStart: data['eveningStart'] as String? ?? '04:00 PM',
        eveningEnd: data['eveningEnd'] as String? ?? '08:00 PM',
        slotDurationMins: (data['slotDurationMins'] as num?)?.toInt() ?? 15,
        maxPatientsPerDay: (data['maxPatientsPerDay'] as num?)?.toInt() ?? 20,
        breakEnabled: data['breakEnabled'] as bool? ?? false,
        breakStart: data['breakStart'] as String? ?? '01:00 PM',
        breakEnd: data['breakEnd'] as String? ?? '02:00 PM',
        blockedDates: blocked,
        leaveStart: (data['leaveStart'] as Timestamp?)?.toDate(),
        leaveEnd: (data['leaveEnd'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return null;
    }
  }
}

typedef DoctorAvailabilityMapper = DoctorScheduleAvailabilityMapper;
