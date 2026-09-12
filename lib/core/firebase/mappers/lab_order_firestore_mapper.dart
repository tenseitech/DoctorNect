import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/doctor_lab_order.dart';

abstract final class LabOrderFirestoreMapper {
  static Map<String, dynamic> toMap(DoctorLabOrder order) => {
        'orderId': order.orderId,
        'doctorId': order.doctorId,
        'doctorName': order.doctorName,
        'patientId': order.patientId,
        'patientName': order.patientName,
        'patientAge': order.patientAge,
        if (order.appointmentId != null) 'appointmentId': order.appointmentId,
        if (order.labId != null && order.labId!.isNotEmpty) 'labId': order.labId, // FIXED: persist labId for lab-operator queries
        'testIds': order.testIds,
        'testNames': order.testNames,
        if (order.labName != null && order.labName!.isNotEmpty) 'labName': order.labName,
        if (order.indication != null && order.indication!.isNotEmpty) 'indication': order.indication,
        'urgency': order.urgency,
        'fastingRequired': order.fastingRequired,
        'homeCollection': order.homeCollection,
        'source': order.source,
        'status': order.status,
        'createdAt': order.createdAt,
        if (order.reportFileName != null) 'reportFileName': order.reportFileName,
        if (order.reportStorageUrl != null) 'reportStorageUrl': order.reportStorageUrl,
        if (order.reportSubmittedAt != null) 'reportSubmittedAt': order.reportSubmittedAt,
      };

  static DoctorLabOrder? fromMap(Map<String, dynamic> data) {
    try {
      final testNames = (data['testNames'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      if (testNames.isEmpty) return null;

      final parsedDate = _parseDate(data['createdAt']);

      return DoctorLabOrder(
        orderId: data['orderId'] as String? ?? '',
        doctorId: data['doctorId'] as String? ?? '',
        doctorName: data['doctorName'] as String? ?? '',
        patientId: data['patientId'] as String? ?? '',
        patientName: data['patientName'] as String? ?? '',
        patientAge: (data['patientAge'] as num?)?.toInt() ?? 0,
        appointmentId: data['appointmentId'] as String?,
        labId: data['labId'] as String?, // FIXED: restore labId on reload
        testIds: (data['testIds'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        testNames: testNames,
        labName: data['labName'] as String?,
        indication: data['indication'] as String?,
        urgency: data['urgency'] as String? ?? 'Routine',
        fastingRequired: data['fastingRequired'] as bool? ?? false,
        homeCollection: data['homeCollection'] as bool? ?? false,
        source: data['source'] as String? ?? 'investigations',
        status: data['status'] as String? ?? 'ordered',
        createdAt: parsedDate,
        reportFileName: data['reportFileName'] as String?,
        reportStorageUrl: data['reportStorageUrl'] as String?,
        reportSubmittedAt: _optionalParseDate(data['reportSubmittedAt']),
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _optionalParseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static DateTime _parseDate(dynamic value) {
    return _optionalParseDate(value) ?? DateTime.now();
  }
}
