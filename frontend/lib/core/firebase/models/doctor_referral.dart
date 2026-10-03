class DoctorReferral {
  const DoctorReferral({
    required this.referralId,
    required this.fromDoctorId,
    required this.fromDoctorName,
    required this.toDoctorId,
    required this.toDoctorName,
    required this.toSpecialization,
    required this.patientId,
    required this.patientName,
    required this.patientAge,
    required this.createdAt,
    this.appointmentId,
    this.reason,
    this.status = 'sent',
  });

  final String referralId;
  final String fromDoctorId;
  final String fromDoctorName;
  final String toDoctorId;
  final String toDoctorName;
  final String toSpecialization;
  final String patientId;
  final String patientName;
  final int patientAge;
  final String? appointmentId;
  final String? reason;
  final String status;
  final DateTime createdAt;
}
