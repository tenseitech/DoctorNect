import '../../../features/doctor/clinical/models/clinical_models.dart';
import '../../../features/pharmacy/models/pharmacy_models.dart';

abstract final class PharmacySupabaseMapper {
  static MedicalStoreProfile storeFromRow(Map<String, dynamic> row) {
    final meta = (row['metadata'] as Map<String, dynamic>?) ?? const {};
    return MedicalStoreProfile(
      id: row['store_id'] as String? ?? '',
      storeName: row['store_name'] as String? ?? '',
      ownerName: meta['owner_name'] as String? ?? '',
      address: row['address_line'] as String? ?? '',
      drugLicenseNumber: row['license_number'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      email: meta['email'] as String? ?? '',
      gstNumber: meta['gst_number'] as String?,
      city: row['city'] as String? ?? '',
      verified: row['verified'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> storeToRow(
    MedicalStoreProfile profile, {
    String? ownerUid,
  }) {
    return {
      'store_id': profile.id,
      if (ownerUid != null) 'owner_uid': ownerUid,
      'store_name': profile.storeName,
      'license_number': profile.drugLicenseNumber,
      'city': profile.city,
      'address_line': profile.address,
      'phone': profile.phone,
      'verified': profile.verified,
      'metadata': {
        'owner_name': profile.ownerName,
        'email': profile.email,
        if (profile.gstNumber != null) 'gst_number': profile.gstNumber,
      },
    };
  }

  static PharmacyPrescriptionDelivery? deliveryFromRow(
    Map<String, dynamic> row,
  ) {
    try {
      final deliveryId = row['delivery_id'] as String? ?? '';
      final sentAtRaw = row['sent_at'] as String?;
      final viewedAtRaw = row['viewed_at'] as String?;
      final dispensedAtRaw = row['dispensed_at'] as String?;
      final statusStr = row['status'] as String? ?? 'sent';

      PharmacyDeliveryStatus status;
      switch (statusStr.toLowerCase()) {
        case 'viewed':
          status = PharmacyDeliveryStatus.viewed;
          break;
        case 'partially_dispensed':
        case 'partiallydispensed':
          status = PharmacyDeliveryStatus.partiallyDispensed;
          break;
        case 'dispensed':
          status = PharmacyDeliveryStatus.dispensed;
          break;
        case 'sent':
        default:
          status = PharmacyDeliveryStatus.sent;
          break;
      }

      final medicinesRaw = (row['pharmacy_delivery_medicines'] as List?) ?? const [];
      final lines = medicinesRaw.map((m) {
        final map = m as Map<String, dynamic>;
        final availStr = map['availability'] as String? ?? 'pending';
        MedicineAvailability avail;
        switch (availStr) {
          case 'in_stock':
          case 'available':
            avail = MedicineAvailability.available;
            break;
          case 'out_of_stock':
            avail = MedicineAvailability.outOfStock;
            break;
          case 'partial':
          case 'substituted':
            avail = MedicineAvailability.substituted;
            break;
          default:
            avail = MedicineAvailability.pending;
        }

        return MedicineDispenseLine(
          medicineEntryId: map['medicine_entry_id'] as String? ?? '',
          medicineName: map['medicine_name'] as String? ?? '',
          dosageLabel: map['dosage_label'] as String? ?? '',
          form: map['form'] as String? ?? '',
          quantity: map['quantity'] as String? ?? '',
          frequencyLabel: map['frequency_label'] as String? ?? '',
          durationLabel: map['duration_label'] as String? ?? '',
          specialInstructions: map['special_instructions'] as String? ?? '',
          availability: avail,
          substituteName: map['substitute_name'] as String? ?? '',
        );
      }).toList();

      return PharmacyPrescriptionDelivery(
        id: deliveryId,
        prescriptionId: row['prescription_id'] as String? ?? '',
        doctorId: row['doctor_id'] as String? ?? '',
        doctorName: row['doctor_name'] as String? ?? '',
        storeId: row['store_id'] as String? ?? '',
        storeName: row['store_name'] as String? ?? '',
        draft: PrescriptionDraft(
          prescriptionId: row['prescription_id'] as String? ?? '',
          patient: PatientClinicalContext(
            patientId: row['patient_id'] as String? ?? '',
            patientName: row['patient_name'] as String? ?? '',
            age: 0,
            gender: '',
          ),
        ),
        sentAt: sentAtRaw != null ? DateTime.parse(sentAtRaw) : DateTime.now(),
        status: status,
        viewedAt: viewedAtRaw != null ? DateTime.parse(viewedAtRaw) : null,
        dispensedAt:
            dispensedAtRaw != null ? DateTime.parse(dispensedAtRaw) : null,
        dispensingNotes: row['dispensing_notes'] as String? ?? '',
        medicineLines: lines,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> deliveryToRow(
    PharmacyPrescriptionDelivery delivery,
  ) {
    return {
      'delivery_id': delivery.id,
      'prescription_id': delivery.prescriptionId,
      'doctor_id': delivery.doctorId,
      'doctor_name': delivery.doctorName,
      'store_id': delivery.storeId,
      'store_name': delivery.storeName,
      'patient_id': delivery.draft.patientId,
      'patient_name': delivery.draft.patient.patientName,
      'status': delivery.status.name,
      'sent_at': delivery.sentAt.toIso8601String(),
      'viewed_at': delivery.viewedAt?.toIso8601String(),
      'dispensed_at': delivery.dispensedAt?.toIso8601String(),
      'dispensing_notes': delivery.dispensingNotes,
    };
  }

  static PharmacyConnection? connectionFromRow(Map<String, dynamic> row) {
    try {
      final reqStr = row['requested_by'] as String? ?? 'doctor';
      final statusStr = row['status'] as String? ?? 'pending';

      ConnectionRequester requester = reqStr == 'store'
          ? ConnectionRequester.store
          : ConnectionRequester.doctor;

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

      return PharmacyConnection(
        id: row['connection_id'] as String? ?? '',
        doctorId: row['doctor_id'] as String? ?? '',
        doctorName: row['doctor_name'] as String? ?? '',
        medicalStoreId: row['store_id'] as String? ?? '',
        storeName: row['store_name'] as String? ?? '',
        status: status,
        requestedAt: reqAt != null ? DateTime.parse(reqAt) : DateTime.now(),
        requestedBy: requester,
        respondedAt: respAt != null ? DateTime.parse(respAt) : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> connectionToRow(PharmacyConnection connection) {
    return {
      'connection_id': connection.id,
      'doctor_id': connection.doctorId,
      'doctor_name': connection.doctorName,
      'store_id': connection.medicalStoreId,
      'store_name': connection.storeName,
      'status': connection.status.name,
      'requested_by': connection.requestedBy.name,
      'requested_at': connection.requestedAt.toIso8601String(),
      if (connection.respondedAt != null)
        'responded_at': connection.respondedAt!.toIso8601String(),
    };
  }
}
