class DoctorLabOrder {
  const DoctorLabOrder({
    required this.orderId,
    required this.doctorId,
    required this.doctorName,
    required this.patientId,
    required this.patientName,
    required this.patientAge,
    required this.testIds,
    required this.testNames,
    required this.createdAt,
    this.appointmentId,
    this.labId, // FIXED: store the target lab's id so the lab operator can query their worklist
    this.labName,
    this.indication,
    this.urgency = 'Routine',
    this.fastingRequired = false,
    this.homeCollection = false,
    this.source = 'investigations',
    this.status = 'ordered',
    this.reportFileName,
    this.reportStorageUrl,
    this.reportSubmittedAt,
  });

  final String orderId;
  final String doctorId;
  final String doctorName;
  final String patientId;
  final String patientName;
  final int patientAge;
  final String? appointmentId;
  final List<String> testIds;
  final List<String> testNames;
  final String? labId; // FIXED: registered lab id (when selected from verified labs / directory)
  final String? labName;
  final String? indication;
  final String urgency;
  final bool fastingRequired;
  final bool homeCollection;
  final String source;
  final String status;
  final DateTime createdAt;
  final String? reportFileName;
  final String? reportStorageUrl;
  final DateTime? reportSubmittedAt;

  bool get hasReport =>
      reportFileName != null &&
      reportFileName!.trim().isNotEmpty &&
      reportStorageUrl != null &&
      reportStorageUrl!.trim().isNotEmpty;
}
