class DoctorMedicalDirectoryEntry {
  const DoctorMedicalDirectoryEntry({
    required this.entryId,
    required this.doctorId,
    required this.name,
    required this.type,
    required this.phone,
    required this.createdAt,
    this.updatedAt,
  });

  final String entryId;
  final String doctorId;
  final String name;
  final String type;
  final String phone;
  final DateTime createdAt;
  final DateTime? updatedAt;
}
