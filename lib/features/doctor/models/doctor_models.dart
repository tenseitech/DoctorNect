import 'package:flutter/material.dart';

enum VerificationStatus { verified, pending }

enum AppointmentType { newVisit, followUp, returning }

enum AppointmentStatus {
  pendingRequest,
  confirmed,
  inProgress,
  completed,
  cancelled,
  noShow,
  waiting,
}

enum AppointmentListTab { today, upcoming, pending, completed, cancelled }

class DoctorProfile {
  const DoctorProfile({
    required this.name,
    required this.verificationStatus,
  });

  final String name;
  final VerificationStatus verificationStatus;
}

class DoctorStats {
  const DoctorStats({
    required this.todaysAppointments,
    required this.pending,
    required this.completed,
  });

  final int todaysAppointments;
  final int pending;
  final int completed;
}

class PatientReport {
  const PatientReport({
    required this.id,
    required this.name,
    required this.fileType,
  });

  final String id;
  final String name;
  final String fileType;
}

class PastVisit {
  const PastVisit({
    required this.date,
    required this.diagnosis,
    required this.notes,
  });

  final DateTime date;
  final String diagnosis;
  final String notes;
}

class PatientVitals {
  const PatientVitals({
    required this.bloodPressure,
    required this.pulse,
    required this.temperature,
    required this.weight,
  });

  final String bloodPressure;
  final String pulse;
  final String temperature;
  final String weight;
}

class Appointment {
  const Appointment({
    required this.id,
    required this.tokenNumber,
    required this.patientName,
    required this.age,
    required this.gender,
    required this.timeSlot,
    required this.appointmentDate,
    required this.type,
    required this.status,
    this.isToday = true,
    this.contactNumber,
    this.chiefComplaints = const [],
    this.symptoms = const [],
    this.reports = const [],
    this.pastVisits = const [],
    this.lastVitals,
    this.bookedByName,
    this.patientRelation,
    this.slotShareReason,
  });

  final String id;
  final int tokenNumber;
  final String patientName;
  final int age;
  final String gender;
  final String timeSlot;
  final DateTime appointmentDate;
  final AppointmentType type;
  final AppointmentStatus status;
  final bool isToday;
  final String? contactNumber;
  final List<String> chiefComplaints;
  final List<String> symptoms;

  String? get reasonForVisit =>
      chiefComplaints.isEmpty ? null : chiefComplaints.join(', ');
  final List<PatientReport> reports;
  final List<PastVisit> pastVisits;
  final PatientVitals? lastVitals;

  /// Account holder who booked on behalf of this patient (family member bookings only).
  final String? bookedByName;

  /// Relation to the account holder, e.g. Wife, Brother, Son.
  final String? patientRelation;

  /// Why patient shares this time slot with others (Emergency / custom).
  final String? slotShareReason;

  bool get isSharedSlotEmergency =>
      slotShareReason?.trim().toLowerCase() == 'emergency';

  bool get isUpcoming =>
      appointmentDate.isAfter(DateTime.now()) &&
      (status == AppointmentStatus.confirmed ||
          status == AppointmentStatus.inProgress);

  Appointment copyWith({
    AppointmentStatus? status,
    List<String>? symptoms,
    List<String>? chiefComplaints,
  }) {
    return Appointment(
      id: id,
      tokenNumber: tokenNumber,
      patientName: patientName,
      age: age,
      gender: gender,
      timeSlot: timeSlot,
      appointmentDate: appointmentDate,
      type: type,
      status: status ?? this.status,
      isToday: isToday,
      contactNumber: contactNumber,
      chiefComplaints: chiefComplaints ?? this.chiefComplaints,
      symptoms: symptoms ?? this.symptoms,
      reports: reports,
      pastVisits: pastVisits,
      lastVitals: lastVitals,
      bookedByName: bookedByName,
      patientRelation: patientRelation,
      slotShareReason: slotShareReason,
    );
  }
}

class QuickActionItem {
  const QuickActionItem({
    required this.label,
    required this.icon,
    this.routeName,
  });

  final String label;
  final IconData icon;
  final String? routeName;
}
