import '../../../../core/validators/form_validators.dart';

int _globalEntryIdCounter = 0;

class PatientClinicalContext {
  const PatientClinicalContext({
    required this.patientName,
    required this.age,
    this.gender,
    this.weightKg,
    this.patientId,
    this.appointmentId,
  });

  final String patientName;
  final int age;
  final String? gender;
  final double? weightKg;
  final String? patientId;
  final String? appointmentId;
}

class PrescriptionVitals {
  String bloodPressure = '';
  String temperature = '';
  String pulse = '';
  String spo2 = '';
  String weightKg = '';
  String heightCm = '';
  String respiratoryRate = '';
}

class MedicineEntry {
  MedicineEntry({String? id}) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${_globalEntryIdCounter++}';

  final String id;
  String name = '';
  String dosageAmount = '';
  String dosageUnit = 'mg';
  String form = 'Tablet';
  bool morning = false;
  bool afternoon = false;
  bool night = false;
  String customFrequency = '';
  bool useCustomFrequency = false;
  String instructions = '';
  String durationAmount = '';
  String durationUnit = 'Days';
  String quantity = '';
  String specialInstructions = '';
  bool isSos = false;
  bool substituteAllowed = true;

  String get frequencyLabel {
    if (useCustomFrequency && customFrequency.trim().isNotEmpty) {
      return customFrequency.trim();
    }
    final m = morning ? 1 : 0;
    final a = afternoon ? 1 : 0;
    final n = night ? 1 : 0;
    if (m + a + n == 0) return 'As directed';
    return '$m-$a-$n';
  }

  String get dosageLabel {
    if (dosageAmount.isEmpty) return '';
    return '$dosageAmount $dosageUnit';
  }

  String get durationLabel {
    final amount = durationAmount.trim();
    final unit = durationUnit.trim();
    if (amount.isEmpty && unit.isEmpty) return '';
    if (amount.isEmpty) return unit;
    if (unit.isEmpty) return amount;
    if (amount.toLowerCase() == unit.toLowerCase()) return amount;
    return '$amount $unit';
  }

  void recalculateQuantity() {
    if (useCustomFrequency) return;
    final days = int.tryParse(durationAmount) ?? 0;
    if (days <= 0) return;
    final perDay = (morning ? 1 : 0) + (afternoon ? 1 : 0) + (night ? 1 : 0);
    if (perDay == 0) return;
    quantity = '${perDay * days}';
  }
}

enum InvestigationType { lab, radiology, custom }

class InvestigationEntry {
  InvestigationEntry({
    String? id,
    required this.type,
    required this.name,
    this.group = '',
    this.notes = '',
    this.catalogId,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${_globalEntryIdCounter++}';

  final String id;
  final String? catalogId;
  InvestigationType type;
  String name;
  String group;
  String notes;

  String get categoryLabel {
    switch (type) {
      case InvestigationType.lab:
        return 'Lab';
      case InvestigationType.radiology:
        return 'Radiology';
      case InvestigationType.custom:
        return 'Custom';
    }
  }

  /// Backward compatibility — older preview code reads `category`.
  String get category => categoryLabel;
}

class ReferralEntry {
  ReferralEntry({
    required this.doctorId,
    required this.doctorName,
    required this.specialization,
    this.reason = '',
    this.sent = false,
  });

  final String doctorId;
  final String doctorName;
  final String specialization;
  String reason;
  bool sent;

  String get displayTitle => 'Dr. $doctorName ($specialization)';
}

class PrescriptionDraft {
  PrescriptionDraft({
    required this.patient,
    String? prescriptionId,
    DateTime? prescriptionDate,
  })  : prescriptionId = prescriptionId ?? _newPrescriptionId(),
        prescriptionDate = prescriptionDate ?? DateTime.now();

  final PatientClinicalContext patient;
  final String prescriptionId;
  final DateTime prescriptionDate;

  // Doctor/clinic snapshot — saved at write-time so patients can see
  // who issued the prescription regardless of their session context.
  String doctorId = '';
  String doctorName = '';
  String doctorSpecialization = '';
  String doctorQualifications = '';
  String doctorRegNumber = '';
  String clinicName = '';
  String clinicAddress = '';
  String doctorPhone = '';

  final PrescriptionVitals vitals = PrescriptionVitals();
  String chiefComplaint = '';
  String diagnosisType = 'Provisional';
  String primaryDiagnosis = '';
  String secondaryDiagnosis = '';
  String symptoms = '';
  String symptomDuration = '';
  String pastHistory = '';
  String allergies = '';
  String generalExamination = '';
  List<MedicineEntry> medicines = [];
  List<InvestigationEntry> investigations = [];
  List<String> bodyParts = [];
  Map<String, String> bodyPartNotes = {};
  String dietAdvice = '';
  String activityRestrictions = '';
  String lifestyleAdvice = '';
  String generalAdvice = '';
  DateTime? nextVisit;
  String followUpNote = '';
  DateTime? validityDate;
  bool enableReminders = true;
  bool sendToPharmacy = false;
  List<ReferralEntry> referrals = [];

  static String _newPrescriptionId() {
    final now = DateTime.now();
    return 'RX-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch % 100000}';
  }

  String get patientId => patient.patientId ?? ''; // FIXED: never fabricate a PAT-{hash} id; empty means unresolved so callers block the write

  bool get hasResolvedPatientId =>
      patient.patientId != null && patient.patientId!.trim().isNotEmpty; // FIXED: callers must check before persisting/sending

  List<MedicineEntry> get validMedicines =>
      medicines.where((m) => m.name.trim().isNotEmpty).toList();

  List<InvestigationEntry> get validInvestigations =>
      investigations.where((i) => i.name.trim().isNotEmpty).toList();

  /// Lab test names listed on the prescription (for lab routing on send).
  List<String> get labTestNames => validInvestigations
      .where(
        (e) =>
            e.type == InvestigationType.lab ||
            (e.type == InvestigationType.custom && e.group == 'lab'),
      )
      .map((e) => e.name.trim())
      .where((n) => n.isNotEmpty)
      .toList();

  /// Pharmacy receives dispensing context + medicines only.
  PrescriptionDraft copyForPharmacy() {
    final d = copy();
    d.investigations.clear();
    d.bodyParts.clear();
    d.bodyPartNotes.clear();
    d.dietAdvice = '';
    d.activityRestrictions = '';
    d.lifestyleAdvice = '';
    d.generalAdvice = '';
    d.followUpNote = '';
    d.nextVisit = null;
    d.validityDate = null;
    return d;
  }

  String? validateForSubmit() {
    if (primaryDiagnosis.trim().isEmpty) {
      return FormValidators.primaryDiagnosis(primaryDiagnosis);
    }
    if (validMedicines.isEmpty) return 'Add at least one medicine';
    return null;
  }

  PrescriptionDraft copy() {
    final d = PrescriptionDraft(
      patient: patient,
      prescriptionId: prescriptionId,
      prescriptionDate: prescriptionDate,
    );
    d.vitals.bloodPressure = vitals.bloodPressure;
    d.vitals.temperature = vitals.temperature;
    d.vitals.pulse = vitals.pulse;
    d.vitals.spo2 = vitals.spo2;
    d.vitals.weightKg = vitals.weightKg;
    d.vitals.heightCm = vitals.heightCm;
    d.vitals.respiratoryRate = vitals.respiratoryRate;
    d.chiefComplaint = chiefComplaint;
    d.diagnosisType = diagnosisType;
    d.primaryDiagnosis = primaryDiagnosis;
    d.secondaryDiagnosis = secondaryDiagnosis;
    d.symptoms = symptoms;
    d.symptomDuration = symptomDuration;
    d.pastHistory = pastHistory;
    d.allergies = allergies;
    d.generalExamination = generalExamination;
    d.medicines = medicines.map((m) {
      final e = MedicineEntry(id: m.id);
      e.name = m.name;
      e.dosageAmount = m.dosageAmount;
      e.dosageUnit = m.dosageUnit;
      e.form = m.form;
      e.morning = m.morning;
      e.afternoon = m.afternoon;
      e.night = m.night;
      e.customFrequency = m.customFrequency;
      e.useCustomFrequency = m.useCustomFrequency;
      e.instructions = m.instructions;
      e.durationAmount = m.durationAmount;
      e.durationUnit = m.durationUnit;
      e.quantity = m.quantity;
      e.specialInstructions = m.specialInstructions;
      e.isSos = m.isSos;
      e.substituteAllowed = m.substituteAllowed;
      return e;
    }).toList();
    d.investigations = investigations
        .map(
          (i) => InvestigationEntry(
            id: i.id,
            type: i.type,
            name: i.name,
            group: i.group,
            notes: i.notes,
            catalogId: i.catalogId,
          ),
        )
        .toList();
    d.doctorId = doctorId;
    d.doctorName = doctorName;
    d.doctorSpecialization = doctorSpecialization;
    d.doctorQualifications = doctorQualifications;
    d.doctorRegNumber = doctorRegNumber;
    d.clinicName = clinicName;
    d.clinicAddress = clinicAddress;
    d.doctorPhone = doctorPhone;
    d.bodyParts = List<String>.from(bodyParts);
    d.bodyPartNotes = Map<String, String>.from(bodyPartNotes);
    d.dietAdvice = dietAdvice;
    d.activityRestrictions = activityRestrictions;
    d.lifestyleAdvice = lifestyleAdvice;
    d.generalAdvice = generalAdvice;
    d.nextVisit = nextVisit;
    d.followUpNote = followUpNote;
    d.validityDate = validityDate;
    d.enableReminders = enableReminders;
    d.sendToPharmacy = sendToPharmacy;
    d.referrals = referrals
        .map(
          (r) => ReferralEntry(
            doctorId: r.doctorId,
            doctorName: r.doctorName,
            specialization: r.specialization,
            reason: r.reason,
            sent: r.sent,
          ),
        )
        .toList();
    return d;
  }
}

class AllergyTag {
  AllergyTag({required this.name, required this.severity});

  final String name;
  final String severity;
}

class LabTestItem {
  const LabTestItem({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;
  final String category;
}
