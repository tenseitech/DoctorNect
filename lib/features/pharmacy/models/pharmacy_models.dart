import '../../doctor/clinical/models/clinical_models.dart';

enum ConnectionStatus { pending, active, rejected, removed }

enum ConnectionRequester { store, doctor }

enum PharmacyDeliveryStatus { sent, viewed, partiallyDispensed, dispensed }

enum MedicineAvailability { pending, available, outOfStock, substituted }

class MedicalStoreProfile {
  MedicalStoreProfile({
    required this.id,
    required this.storeName,
    required this.ownerName,
    required this.address,
    required this.drugLicenseNumber,
    required this.phone,
    required this.email,
    this.gstNumber,
    this.city = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.country = '',
    this.state = '',
    this.pincode = '',
  });

  final String id;
  final String storeName;
  final String ownerName;
  final String address;
  final String drugLicenseNumber;
  final String phone;
  final String email;
  final String? gstNumber;
  final String city;
  final String addressLine1;
  final String addressLine2;
  final String country;
  final String state;
  final String pincode;

  MedicalStoreProfile copyWith({
    String? storeName,
    String? ownerName,
    String? address,
    String? drugLicenseNumber,
    String? phone,
    String? email,
    String? gstNumber,
    bool clearGstNumber = false,
    String? city,
    String? addressLine1,
    String? addressLine2,
    String? country,
    String? state,
    String? pincode,
  }) {
    return MedicalStoreProfile(
      id: id,
      storeName: storeName ?? this.storeName,
      ownerName: ownerName ?? this.ownerName,
      address: address ?? this.address,
      drugLicenseNumber: drugLicenseNumber ?? this.drugLicenseNumber,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gstNumber: clearGstNumber ? null : (gstNumber ?? this.gstNumber),
      city: city ?? this.city,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      country: country ?? this.country,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
    );
  }
}

class PharmacyConnection {
  PharmacyConnection({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.medicalStoreId,
    required this.storeName,
    required this.status,
    required this.requestedAt,
    required this.requestedBy,
    this.respondedAt,
  });

  final String id;
  final String doctorId;
  final String doctorName;
  final String medicalStoreId;
  final String storeName;
  ConnectionStatus status;
  final DateTime requestedAt;
  final ConnectionRequester requestedBy;
  DateTime? respondedAt;
}

class MedicineDispenseLine {
  MedicineDispenseLine({
    required this.medicineEntryId,
    required this.medicineName,
    required this.dosageLabel,
    required this.form,
    required this.quantity,
    required this.frequencyLabel,
    required this.durationLabel,
    this.specialInstructions = '',
    this.availability = MedicineAvailability.pending,
    this.substituteName = '',
  });

  final String medicineEntryId;
  final String medicineName;
  final String dosageLabel;
  final String form;
  final String quantity;
  final String frequencyLabel;
  final String durationLabel;
  final String specialInstructions;
  MedicineAvailability availability;
  String substituteName;
}

class PharmacyPrescriptionDelivery {
  PharmacyPrescriptionDelivery({
    required this.id,
    required this.prescriptionId,
    required this.doctorId,
    required this.doctorName,
    required this.storeId,
    required this.storeName,
    required this.draft,
    required this.sentAt,
    this.status = PharmacyDeliveryStatus.sent,
    this.viewedAt,
    this.dispensedAt,
    this.dispensingNotes = '',
    required this.medicineLines,
  });

  final String id;
  final String prescriptionId;
  final String doctorId;
  final String doctorName;
  final String storeId;
  final String storeName;
  final PrescriptionDraft draft;
  PharmacyDeliveryStatus status;
  final DateTime sentAt;
  DateTime? viewedAt;
  DateTime? dispensedAt;
  String dispensingNotes;
  final List<MedicineDispenseLine> medicineLines;

  static List<MedicineDispenseLine> linesFromDraft(PrescriptionDraft draft) {
    return draft.validMedicines.map((m) {
      final dur =
          '${m.durationAmount}${m.durationAmount.isNotEmpty ? ' ${m.durationUnit}' : ''}'
              .trim();
      return MedicineDispenseLine(
        medicineEntryId: m.id,
        medicineName: m.name,
        dosageLabel: m.dosageLabel,
        form: m.form,
        quantity: m.quantity,
        frequencyLabel: m.frequencyLabel,
        durationLabel: dur,
        specialInstructions: m.specialInstructions,
      );
    }).toList();
  }
}

class PharmacyNotification {
  PharmacyNotification({
    required this.id,
    required this.userId,
    required this.userRole,
    required this.title,
    required this.message,
    required this.createdAt,
    this.referenceId,
    this.isRead = false,
  });

  final String id;
  final String userId;
  final String userRole;
  final String title;
  final String message;
  final DateTime createdAt;
  final String? referenceId;
  bool isRead;
}
