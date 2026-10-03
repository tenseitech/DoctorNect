import '../../features/doctor/models/doctor_models.dart';
import 'shared_appointments_store.dart';

/// Stats computed for a single doctor over a time period.
class DoctorPeriodStats {
  const DoctorPeriodStats({
    required this.patientsTreated,
    required this.consultationCount,
    required this.services,
  });

  /// Number of unique patients seen.
  final int patientsTreated;

  /// Total non-cancelled consultations.
  final int consultationCount;

  /// Service breakdown labels, e.g. ["Prescription", "Lab Report", "Follow-up"].
  final List<String> services;

  static const empty = DoctorPeriodStats(
    patientsTreated: 0,
    consultationCount: 0,
    services: [],
  );
}

/// Computes per-doctor statistics from the shared appointment store.
abstract final class DoctorPatientStatsService {
  static DoctorPeriodStats statsForDoctor(String doctorId, DateTime since) {
    final records = SharedAppointmentsStore.instance.records;

    final uniquePatients = <String>{};
    var consultations = 0;
    var prescriptions = 0;
    var labReports = 0;
    var followUps = 0;
    var newVisits = 0;
    final specializations = <String>{};

    for (final r in records) {
      if (r.doctorId != doctorId) continue;
      if (r.isCancelled) continue;
      if (r.dateTime.isBefore(since)) continue;
      if (!_countsAsConsultation(r.doctorStatus)) continue;

      consultations++;

      // Track unique patients by patientId first, fallback to name
      final patientKey = (r.patientId != null && r.patientId!.isNotEmpty)
          ? r.patientId!
          : r.patientName.trim().toLowerCase();
      if (patientKey.isNotEmpty) uniquePatients.add(patientKey);

      if (r.hasPrescription) prescriptions++;
      if (r.hasReport || r.labReports.isNotEmpty) labReports++;
      if (r.visitType == AppointmentType.followUp) followUps++;
      if (r.visitType == AppointmentType.newVisit) newVisits++;
      if (r.specialization.trim().isNotEmpty) {
        specializations.add(r.specialization.trim());
      }
    }

    final services = <String>[
      if (newVisits > 0) 'New Visit ($newVisits)',
      if (followUps > 0) 'Follow-up ($followUps)',
      if (prescriptions > 0) 'Prescription ($prescriptions)',
      if (labReports > 0) 'Lab Report ($labReports)',
    ];

    return DoctorPeriodStats(
      patientsTreated: uniquePatients.length,
      consultationCount: consultations,
      services: services,
    );
  }

  static bool _countsAsConsultation(AppointmentStatus status) {
    return status == AppointmentStatus.confirmed ||
        status == AppointmentStatus.inProgress ||
        status == AppointmentStatus.completed ||
        status == AppointmentStatus.waiting;
  }
}
