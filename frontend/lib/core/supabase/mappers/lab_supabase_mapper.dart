import '../../firebase/models/doctor_lab_order.dart';
import '../../firebase/repositories/lab_booking_repository.dart';
import '../../../features/lab/models/lab_connection_models.dart';
import '../../../features/patient/lab/models/lab_models.dart';
import '../../../features/pharmacy/models/pharmacy_models.dart';

abstract final class LabSupabaseMapper {
  static PartnerLab partnerLabFromRow(Map<String, dynamic> row) {
    return PartnerLab(
      id: row['lab_id'] as String? ?? '',
      name: row['lab_name'] as String? ?? '',
      rating: (row['rating'] as num?)?.toDouble() ?? 0.0,
      area: row['city'] as String? ?? '',
    );
  }

  static LabBookingRecord? bookingFromRow(Map<String, dynamic> row) {
    try {
      final dateTimeRaw = row['date_time'] as String?;
      final createdAtRaw = row['created_at'] as String?;
      final dt = dateTimeRaw != null ? DateTime.parse(dateTimeRaw) : DateTime.now();

      final isHome = row['is_home_collection'] as bool? ?? false;
      final collType = isHome ? 'home' : 'walkIn';

      return LabBookingRecord(
        bookingId: row['booking_id'] as String? ?? '',
        labId: row['lab_id'] as String?,
        labName: row['lab_name'] as String?,
        patientId: row['patient_id'] as String? ?? '',
        patientName: row['patient_name'] as String? ?? '',
        testName: row['test_name'] as String? ?? 'Lab Test',
        dateTime: dt,
        slotLabel: row['slot_label'] as String? ?? '',
        collectionType: collType,
        address: row['collection_address'] as String? ?? '',
        status: row['status'] as String? ?? 'pending',
        reportStorageKey: row['report_s3_key'] as String?,
        reportFileName: row['report_file_name'] as String?,
        reportStorageUrl: row['report_storage_url'] as String?,
        createdAt: createdAtRaw != null ? DateTime.parse(createdAtRaw) : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> bookingToRow(LabBookingRecord record) {
    return {
      'booking_id': record.bookingId,
      if (record.labId != null) 'lab_id': record.labId,
      if (record.labName != null) 'lab_name': record.labName,
      'patient_id': record.patientId,
      'patient_name': record.patientName,
      'test_name': record.testName,
      'date_time': record.dateTime.toIso8601String(),
      'slot_label': record.slotLabel,
      'is_home_collection': record.collectionType.toLowerCase().contains('home'),
      'collection_address': record.address,
      'status': record.status,
      if (record.reportStorageKey != null)
        'report_s3_key': record.reportStorageKey,
    };
  }

  static DoctorLabOrder? orderFromRow(Map<String, dynamic> row) {
    try {
      final createdAtRaw = row['created_at'] as String?;
      final dt = createdAtRaw != null ? DateTime.parse(createdAtRaw) : DateTime.now();

      final testIdsRaw = (row['test_ids'] as List?)?.cast<String>() ?? const [];
      final testNamesRaw = (row['test_names'] as List?)?.cast<String>() ?? const [];

      return DoctorLabOrder(
        orderId: row['order_id'] as String? ?? '',
        doctorId: row['doctor_id'] as String? ?? '',
        doctorName: row['doctor_name'] as String? ?? '',
        patientId: row['patient_id'] as String? ?? '',
        patientName: row['patient_name'] as String? ?? '',
        patientAge: row['patient_age'] as int? ?? 0,
        labId: row['lab_id'] as String?,
        labName: row['lab_name'] as String?,
        testIds: testIdsRaw,
        testNames: testNamesRaw.isNotEmpty
            ? testNamesRaw
            : (row['test_name'] != null ? [row['test_name'] as String] : const []),
        indication: row['clinical_notes'] as String?,
        status: row['status'] as String? ?? 'prescribed',
        reportStorageKey: row['report_s3_key'] as String?,
        createdAt: dt,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> orderToRow(DoctorLabOrder order) {
    return {
      'order_id': order.orderId,
      'doctor_id': order.doctorId,
      'doctor_name': order.doctorName,
      'patient_id': order.patientId,
      'patient_name': order.patientName,
      'patient_age': order.patientAge,
      if (order.labId != null) 'lab_id': order.labId,
      if (order.labName != null) 'lab_name': order.labName,
      'clinical_notes': order.indication,
      'status': order.status,
      'test_ids': order.testIds,
      'test_names': order.testNames,
      if (order.reportStorageKey != null)
        'report_s3_key': order.reportStorageKey,
    };
  }

  static LabConnection? connectionFromRow(Map<String, dynamic> row) {
    try {
      final reqStr = row['requested_by'] as String? ?? 'doctor';
      final statusStr = row['status'] as String? ?? 'pending';

      LabConnectionRequester requester = reqStr == 'lab'
          ? LabConnectionRequester.lab
          : LabConnectionRequester.doctor;

      ConnectionStatus status;
      switch (statusStr) {
        case 'active':
          status = ConnectionStatus.active;
          break;
        case 'rejected':
          status = ConnectionStatus.rejected;
          break;
        case 'pending':
        default:
          status = ConnectionStatus.pending;
          break;
      }

      final reqAt = row['requested_at'] as String?;
      final respAt = row['responded_at'] as String?;

      return LabConnection(
        id: row['connection_id'] as String? ?? '',
        doctorId: row['doctor_id'] as String? ?? '',
        doctorName: row['doctor_name'] as String? ?? '',
        labId: row['lab_id'] as String? ?? '',
        labName: row['lab_name'] as String? ?? '',
        status: status,
        requestedAt: reqAt != null ? DateTime.parse(reqAt) : DateTime.now(),
        requestedBy: requester,
        respondedAt: respAt != null ? DateTime.parse(respAt) : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> connectionToRow(LabConnection connection) {
    return {
      'connection_id': connection.id,
      'doctor_id': connection.doctorId,
      'doctor_name': connection.doctorName,
      'lab_id': connection.labId,
      'lab_name': connection.labName,
      'status': connection.status.name,
      'requested_by': connection.requestedBy.name,
      'requested_at': connection.requestedAt.toIso8601String(),
      if (connection.respondedAt != null)
        'responded_at': connection.respondedAt!.toIso8601String(),
    };
  }
}
