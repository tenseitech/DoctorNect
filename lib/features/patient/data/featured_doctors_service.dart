import 'package:flutter/material.dart';

import '../../../core/data/shared_appointments_store.dart';
import '../../doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import 'registered_doctors_store.dart';

enum FeaturedDoctorPeriod { day, week, month, year }

class FeaturedDoctorEntry {
  const FeaturedDoctorEntry({
    required this.period,
    required this.doctor,
    required this.consultationCount,
  });

  final FeaturedDoctorPeriod period;
  final DoctorListing doctor;
  final int consultationCount;

  String get title => switch (period) {
        FeaturedDoctorPeriod.day => 'Doctor of the Day',
        FeaturedDoctorPeriod.week => 'Doctor of the Week',
        FeaturedDoctorPeriod.month => 'Doctor of the Month',
        FeaturedDoctorPeriod.year => 'Doctor of the Year',
      };

  String get subtitle {
    if (consultationCount > 0) {
      return '$consultationCount consultation${consultationCount == 1 ? '' : 's'} in this period';
    }
    return 'Top rated on DoctorNect';
  }

  Color get accent => switch (period) {
        FeaturedDoctorPeriod.day => const Color(0xFF2563EB),
        FeaturedDoctorPeriod.week => const Color(0xFF6366F1),
        FeaturedDoctorPeriod.month => const Color(0xFFDB2777),
        FeaturedDoctorPeriod.year => const Color(0xFFCA8A04),
      };
}

abstract final class FeaturedDoctorsService {
  /// Returns the start date for the given period (used by stats service).
  static DateTime periodStartFor(FeaturedDoctorPeriod period) {
    return _periodStart(DateTime.now(), period);
  }

  static DateTime _periodStart(DateTime now, FeaturedDoctorPeriod period) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      FeaturedDoctorPeriod.day => today,
      FeaturedDoctorPeriod.week =>
        today.subtract(Duration(days: today.weekday - DateTime.monday)),
      FeaturedDoctorPeriod.month => DateTime(now.year, now.month),
      FeaturedDoctorPeriod.year => DateTime(now.year),
    };
  }

  static Map<String, int> _consultationCountsSince(DateTime start) {
    final counts = <String, int>{};
    for (final record in SharedAppointmentsStore.instance.records) {
      if (record.isCancelled) continue;
      if (record.dateTime.isBefore(start)) continue;
      if (!_countsAsConsultation(record.doctorStatus)) continue;
      counts[record.doctorId] = (counts[record.doctorId] ?? 0) + 1;
    }
    return counts;
  }

  static bool _countsAsConsultation(AppointmentStatus status) {
    return status == AppointmentStatus.confirmed ||
        status == AppointmentStatus.inProgress ||
        status == AppointmentStatus.completed ||
        status == AppointmentStatus.waiting;
  }

  static FeaturedDoctorEntry? featuredFor(FeaturedDoctorPeriod period) {
    var doctors = RegisteredDoctorsStore.instance.verifiedDoctors;
    if (doctors.isEmpty) {
      doctors = RegisteredDoctorsStore.instance.searchableDoctors;
    }
    if (doctors.isEmpty) return null;

    final now = DateTime.now();
    final start = _periodStart(now, period);
    final counts = _consultationCountsSince(start);

    DoctorListing? best;
    var bestScore = 0;

    for (final doctor in doctors) {
      final score = counts[doctor.id] ?? 0;
      if (score > bestScore) {
        bestScore = score;
        best = doctor;
        continue;
      }
      if (score == bestScore && score > 0 && best != null) {
        if (doctor.rating > best.rating ||
            (doctor.rating == best.rating &&
                doctor.reviewCount > best.reviewCount)) {
          best = doctor;
        }
      }
    }

    if (best == null || bestScore == 0) {
      best = _fallbackDoctor(doctors, period, now);
      bestScore = counts[best.id] ?? 0;
    }

    return FeaturedDoctorEntry(
      period: period,
      doctor: best,
      consultationCount: bestScore,
    );
  }

  static List<FeaturedDoctorEntry> allFeatured() {
    return FeaturedDoctorPeriod.values
        .map(featuredFor)
        .whereType<FeaturedDoctorEntry>()
        .toList();
  }

  static DoctorListing _fallbackDoctor(
    List<DoctorListing> doctors,
    FeaturedDoctorPeriod period,
    DateTime now,
  ) {
    final sorted = [...doctors]..sort((a, b) {
        final rating = b.rating.compareTo(a.rating);
        if (rating != 0) return rating;
        return b.reviewCount.compareTo(a.reviewCount);
      });

    final seed = now.year + now.month * 31 + now.day + period.index * 997;
    return sorted[seed % sorted.length];
  }
}
