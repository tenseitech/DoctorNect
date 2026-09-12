import 'package:flutter/material.dart';

import '../models/doctor_models.dart';

abstract final class AppointmentStatusStyle {
  static String label(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.pendingRequest => 'Request pending',
      AppointmentStatus.confirmed => 'Confirmed',
      AppointmentStatus.inProgress => 'In Progress',
      AppointmentStatus.completed => 'Completed',
      AppointmentStatus.cancelled => 'Cancelled',
      AppointmentStatus.noShow => 'No-Show',
      AppointmentStatus.waiting => 'Waiting',
    };
  }

  static Color color(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.pendingRequest => const Color(0xFFEA580C),
      AppointmentStatus.confirmed => const Color(0xFF2563EB),
      AppointmentStatus.inProgress => const Color(0xFFF59E0B),
      AppointmentStatus.completed => const Color(0xFF16A34A),
      AppointmentStatus.cancelled => const Color(0xFFDC2626),
      AppointmentStatus.noShow => const Color(0xFF64748B),
      AppointmentStatus.waiting => const Color(0xFFF59E0B),
    };
  }

  static String typeLabel(AppointmentType type) {
    return type == AppointmentType.newVisit ? 'New Patient' : 'Follow-up';
  }

  static bool isPendingRequest(AppointmentStatus status) {
    return status == AppointmentStatus.pendingRequest;
  }

  static bool isUpcomingActionable(AppointmentStatus status) {
    return status == AppointmentStatus.pendingRequest ||
        status == AppointmentStatus.confirmed ||
        status == AppointmentStatus.inProgress ||
        status == AppointmentStatus.waiting;
  }

  static bool canStartConsultation(Appointment appointment) {
    if (!appointment.isToday) return false;
    return appointment.status == AppointmentStatus.confirmed ||
        appointment.status == AppointmentStatus.waiting ||
        appointment.status == AppointmentStatus.inProgress;
  }
}

abstract final class AppointmentFilters {
  static List<Appointment> apply({
    required List<Appointment> source,
    required AppointmentListTab tab,
    DateTime? filterDate,
    AppointmentType? typeFilter,
    String searchQuery = '',
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var list = source.where((a) {
      final apptDay = DateTime(
        a.appointmentDate.year,
        a.appointmentDate.month,
        a.appointmentDate.day,
      );

      return switch (tab) {
        AppointmentListTab.today =>
          apptDay == today && a.status != AppointmentStatus.cancelled,
        AppointmentListTab.upcoming =>
          apptDay.isAfter(today) &&
              (a.status == AppointmentStatus.confirmed ||
                  a.status == AppointmentStatus.pendingRequest ||
                  a.status == AppointmentStatus.inProgress ||
                  a.status == AppointmentStatus.waiting),
        AppointmentListTab.pending =>
          a.status == AppointmentStatus.pendingRequest ||
              a.status == AppointmentStatus.waiting,
        AppointmentListTab.completed => a.status == AppointmentStatus.completed,
        AppointmentListTab.cancelled =>
          a.status == AppointmentStatus.cancelled ||
              a.status == AppointmentStatus.noShow,
      };
    }).toList();

    if (filterDate != null) {
      final day = DateTime(filterDate.year, filterDate.month, filterDate.day);
      list = list.where((a) {
        final apptDay = DateTime(
          a.appointmentDate.year,
          a.appointmentDate.month,
          a.appointmentDate.day,
        );
        return apptDay == day;
      }).toList();
    }

    if (typeFilter != null) {
      list = list.where((a) {
        if (typeFilter == AppointmentType.returning) {
          return a.type == AppointmentType.followUp;
        }
        return a.type == typeFilter;
      }).toList();
    }

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((a) => a.patientName.toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
    return list;
  }
}
