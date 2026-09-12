enum HealthRecordType {
  prescription,
  labReport,
  imaging,
  discharge,
  vaccination,
  other,
}

enum RecordSource { practo, selfUploaded, doctorSent, labSent }

enum GlucoseReadingType { fasting, postPrandial, random }

/// Where the uploaded file bytes live.
enum HealthRecordFileStorage { none, local, firebase }

/// Lab test report pipeline status for Medical Record list badges.
enum LabReportStatusKind {
  reportReady,
  processing,
  confirmed,
  awaitingLab,
  completedPendingReport,
  declined,
  cancelled,
  orderedByDoctor,
}

class HealthRecord {
  HealthRecord({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    required this.source,
    required this.fileName,
    this.doctorName,
    this.labName,
    this.isImage = false,
    this.notes,
    this.sharedWithDoctors = false,
    this.fileStorage = HealthRecordFileStorage.none,
    this.storageUrl,
    this.prescriptionId,
    this.labOrderId,
    this.labBookingId,
    this.labReportStatus,
  });

  final String id;
  final String title;
  final HealthRecordType type;
  final DateTime date;
  final RecordSource source;
  final String fileName;
  final String? doctorName;
  final String? labName;
  final bool isImage;
  final String? notes;
  final bool sharedWithDoctors;

  /// `local` = saved on this device; `firebase` = [storageUrl] when Storage is enabled.
  final HealthRecordFileStorage fileStorage;
  final String? storageUrl;

  /// Set when [source] is [RecordSource.doctorSent] — links to Firestore clinical data.
  final String? prescriptionId;
  final String? labOrderId;
  final String? labBookingId;

  /// Set for patient/doctor lab test rows in the Medical Record Tests tab.
  final LabReportStatusKind? labReportStatus;

  bool get isSharedMedicalRecord =>
      source == RecordSource.doctorSent || source == RecordSource.labSent;

  bool get isDoctorSent => source == RecordSource.doctorSent;

  bool get isLabTestRecord => labOrderId != null || labBookingId != null;

  /// Who booked the lab test for this patient — patient self-booking vs doctor order.
  String? get labBookedByLabel {
    if (labOrderId != null) {
      final name = doctorName?.trim();
      if (name != null && name.isNotEmpty) {
        return 'Booked by ${name.startsWith('Dr.') ? name : 'Dr. $name'}';
      }
      return 'Booked by doctor';
    }
    if (labBookingId != null) {
      return 'Booked by patient';
    }
    return null;
  }

  bool get hasUploadedFile =>
      fileStorage == HealthRecordFileStorage.local ||
      fileStorage == HealthRecordFileStorage.firebase;
}

class VitalsLog {
  VitalsLog({
    required this.id,
    required this.dateTime,
    this.systolic,
    this.diastolic,
    this.pulse,
    this.glucose,
    this.glucoseType,
    this.weightKg,
    this.heightCm,
    this.temperatureF,
    this.spo2,
    this.steps,
    this.sleepHours,
    this.notes,
  });

  final String id;
  final DateTime dateTime;
  final int? systolic;
  final int? diastolic;
  final int? pulse;
  final double? glucose;
  final GlucoseReadingType? glucoseType;
  final double? weightKg;
  final double? heightCm;
  final double? temperatureF;
  final int? spo2;
  final int? steps;
  final double? sleepHours;
  final String? notes;

  double? get bmi {
    if (weightKg == null || heightCm == null || heightCm! <= 0) return null;
    final h = heightCm! / 100;
    return weightKg! / (h * h);
  }
}
