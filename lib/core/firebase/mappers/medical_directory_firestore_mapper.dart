import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/doctor_medical_directory_entry.dart';

abstract final class MedicalDirectoryFirestoreMapper {
  static Map<String, dynamic> toMap(DoctorMedicalDirectoryEntry entry) => {
        'entryId': entry.entryId,
        'doctorId': entry.doctorId,
        'name': entry.name,
        'type': entry.type,
        'phone': entry.phone,
        'createdAt': entry.createdAt,
        if (entry.updatedAt != null) 'updatedAt': entry.updatedAt,
      };

  static DoctorMedicalDirectoryEntry? fromMap(Map<String, dynamic> data) {
    try {
      return DoctorMedicalDirectoryEntry(
        entryId: data['entryId'] as String? ?? '',
        doctorId: data['doctorId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        type: data['type'] as String? ?? '',
        phone: data['phone'] as String? ?? '',
        createdAt: _parseDate(data['createdAt']),
        updatedAt: data['updatedAt'] == null ? null : _parseDate(data['updatedAt']),
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}
