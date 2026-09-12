import '../../../features/doctor/clinical/models/clinical_models.dart';

abstract final class PrescriptionFirestoreMapper {
  static PrescriptionDraft? fromMap(Map<String, dynamic> data) {
    try {
      final prescriptionId = data['prescriptionId'] as String? ?? '';
      if (prescriptionId.isEmpty) return null;

      final draft = PrescriptionDraft(
        patient: PatientClinicalContext(
          patientName: data['patientName'] as String? ?? 'Patient',
          age: (data['patientAge'] as num?)?.toInt() ?? 0, // FIXED: restore real age instead of hardcoded 0
          gender: data['patientGender'] as String?, // FIXED: restore gender
          patientId: data['patientId'] as String?,
          appointmentId: data['appointmentId'] as String?,
        ),
        prescriptionId: prescriptionId,
        prescriptionDate: DateTime.tryParse(data['prescriptionDate'] as String? ?? '') ??
            DateTime.now(),
      );

      // Doctor/clinic snapshot (written since v2 of the schema).
      draft.doctorId = data['doctorId'] as String? ?? '';
      draft.doctorName = data['doctorName'] as String? ?? '';
      draft.doctorSpecialization = data['doctorSpecialization'] as String? ?? '';
      draft.doctorQualifications = data['doctorQualifications'] as String? ?? '';
      draft.doctorRegNumber = data['doctorRegNumber'] as String? ?? '';
      draft.clinicName = data['clinicName'] as String? ?? '';
      draft.clinicAddress = data['clinicAddress'] as String? ?? '';
      draft.doctorPhone = data['doctorPhone'] as String? ?? '';

      draft.chiefComplaint = data['chiefComplaint'] as String? ?? '';
      draft.diagnosisType = data['diagnosisType'] as String? ?? 'Provisional';
      draft.primaryDiagnosis = data['primaryDiagnosis'] as String? ?? '';
      draft.secondaryDiagnosis = data['secondaryDiagnosis'] as String? ?? '';
      draft.symptoms = data['symptoms'] as String? ?? '';
      draft.symptomDuration = data['symptomDuration'] as String? ?? '';
      draft.pastHistory = data['pastHistory'] as String? ?? '';
      draft.allergies = data['allergies'] as String? ?? '';
      draft.generalExamination = data['generalExamination'] as String? ?? '';

      final vitals = data['vitals'] as Map<String, dynamic>? ?? const {};
      draft.vitals.bloodPressure = vitals['bloodPressure'] as String? ?? '';
      draft.vitals.temperature = vitals['temperature'] as String? ?? '';
      draft.vitals.pulse = vitals['pulse'] as String? ?? '';
      draft.vitals.spo2 = vitals['spo2'] as String? ?? '';
      draft.vitals.weightKg = vitals['weightKg'] as String? ?? '';
      draft.vitals.heightCm = vitals['heightCm'] as String? ?? '';
      draft.vitals.respiratoryRate = vitals['respiratoryRate'] as String? ?? '';

      final medicines = data['medicines'] as List<dynamic>? ?? const [];
      draft.medicines = medicines.map((raw) {
        final map = Map<String, dynamic>.from(raw as Map);
        final entry = MedicineEntry(id: map['id'] as String?); // FIXED: restore medicine id so dispense lines match after reload
        entry.name = map['name'] as String? ?? '';
        _applyDosage(entry, map['dosage'] as String? ?? '');
        entry.form = map['form'] as String? ?? 'Tablet';
        entry.instructions = map['instructions'] as String? ?? '';
        entry.specialInstructions = map['specialInstructions'] as String? ?? '';
        entry.isSos = map['isSos'] as bool? ?? false;
        entry.substituteAllowed = map['substituteAllowed'] as bool? ?? true;
        _applyDuration(entry, map['duration'] as String? ?? '');
        entry.quantity = map['quantity'] as String? ?? '';
        _applyFrequency(entry, map['frequency'] as String? ?? '');
        return entry;
      }).toList();

      final investigations = data['investigations'] as List<dynamic>? ?? const []; // FIXED: restore investigations
      draft.investigations = investigations.map((raw) {
        final map = Map<String, dynamic>.from(raw as Map);
        return InvestigationEntry(
          type: InvestigationType.values.byName(map['type'] as String? ?? InvestigationType.custom.name),
          name: map['name'] as String? ?? '',
          group: map['group'] as String? ?? '',
          notes: map['notes'] as String? ?? '',
        );
      }).where((i) => i.name.trim().isNotEmpty).toList();

      final advice = data['advice'] as Map<String, dynamic>? ?? const {};
      draft.dietAdvice = advice['diet'] as String? ?? '';
      draft.activityRestrictions = advice['activity'] as String? ?? '';
      draft.lifestyleAdvice = advice['lifestyle'] as String? ?? '';
      draft.generalAdvice = advice['general'] as String? ?? '';
      draft.followUpNote = data['followUpNote'] as String? ?? '';

      final nextVisit = data['nextVisit'] as String?;
      if (nextVisit != null && nextVisit.isNotEmpty) {
        draft.nextVisit = DateTime.tryParse(nextVisit);
      }

      final referrals = data['referrals'] as List<dynamic>? ?? const [];
      draft.referrals = referrals.map((raw) {
        final map = Map<String, dynamic>.from(raw as Map);
        return ReferralEntry(
          doctorId: map['doctorId'] as String? ?? '',
          doctorName: map['doctorName'] as String? ?? '',
          specialization: map['specialization'] as String? ?? '',
          reason: map['reason'] as String? ?? '',
          sent: map['sent'] as bool? ?? false,
        );
      }).where((r) => r.doctorId.isNotEmpty).toList();

      return draft;
    } catch (_) {
      return null;
    }
  }

  static void _applyDosage(MedicineEntry entry, String dosage) {
    final parts = dosage.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return;
    entry.dosageAmount = parts.first;
    if (parts.length > 1) {
      entry.dosageUnit = parts.sublist(1).join(' ');
    }
  }

  static void _applyFrequency(MedicineEntry entry, String frequency) {
    final trimmed = frequency.trim();
    if (trimmed.isEmpty) return;

    final match = RegExp(r'^(\d)-(\d)-(\d)$').firstMatch(trimmed);
    if (match != null) {
      entry.useCustomFrequency = false;
      entry.customFrequency = '';
      entry.morning = match.group(1) != '0';
      entry.afternoon = match.group(2) != '0';
      entry.night = match.group(3) != '0';
      return;
    }

    entry.useCustomFrequency = true;
    entry.customFrequency = trimmed;
  }

  static void _applyDuration(MedicineEntry entry, String duration) {
    final trimmed = duration.trim();
    if (trimmed.isEmpty) return;

    const knownUnits = {'days', 'weeks', 'months'};
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final single = parts.first;
      if (knownUnits.contains(single.toLowerCase())) {
        entry.durationAmount = '';
        entry.durationUnit = single[0].toUpperCase() + single.substring(1).toLowerCase();
        return;
      }
      entry.durationAmount = single;
      return;
    }

    entry.durationAmount = parts.first;
    entry.durationUnit = parts.sublist(1).join(' ');
  }

  static Map<String, dynamic> toMap(PrescriptionDraft draft, String doctorId) {
    return {
      'prescriptionId': draft.prescriptionId,
      'doctorId': draft.doctorId.isNotEmpty ? draft.doctorId : doctorId,
      if (draft.doctorName.isNotEmpty) 'doctorName': draft.doctorName,
      if (draft.doctorSpecialization.isNotEmpty) 'doctorSpecialization': draft.doctorSpecialization,
      if (draft.doctorQualifications.isNotEmpty) 'doctorQualifications': draft.doctorQualifications,
      if (draft.doctorRegNumber.isNotEmpty) 'doctorRegNumber': draft.doctorRegNumber,
      if (draft.clinicName.isNotEmpty) 'clinicName': draft.clinicName,
      if (draft.clinicAddress.isNotEmpty) 'clinicAddress': draft.clinicAddress,
      if (draft.doctorPhone.isNotEmpty) 'doctorPhone': draft.doctorPhone,
      'patientId': draft.patientId,
      'patientName': draft.patient.patientName,
      'patientAge': draft.patient.age, // FIXED: persist age so it round-trips
      if (draft.patient.gender != null) 'patientGender': draft.patient.gender, // FIXED: persist gender
      if (draft.patient.appointmentId != null && draft.patient.appointmentId!.isNotEmpty)
        'appointmentId': draft.patient.appointmentId,
      'prescriptionDate': draft.prescriptionDate.toIso8601String(),
      'diagnosisType': draft.diagnosisType,
      'primaryDiagnosis': draft.primaryDiagnosis,
      'secondaryDiagnosis': draft.secondaryDiagnosis,
      'chiefComplaint': draft.chiefComplaint,
      'symptoms': draft.symptoms,
      'symptomDuration': draft.symptomDuration,
      'pastHistory': draft.pastHistory,
      'allergies': draft.allergies,
      'generalExamination': draft.generalExamination,
      'vitals': {
        'bloodPressure': draft.vitals.bloodPressure,
        'temperature': draft.vitals.temperature,
        'pulse': draft.vitals.pulse,
        'spo2': draft.vitals.spo2,
        'weightKg': draft.vitals.weightKg,
        'heightCm': draft.vitals.heightCm,
        'respiratoryRate': draft.vitals.respiratoryRate,
      },
      'medicines': draft.validMedicines
          .map(
            (m) => {
              'id': m.id, // FIXED: persist medicine id so pharmacy dispense lines match after reload
              'name': m.name,
              'dosage': m.dosageLabel,
              'form': m.form,
              'frequency': m.frequencyLabel,
              'quantity': m.quantity,
              'duration': '${m.durationAmount} ${m.durationUnit}'.trim(),
              'instructions': m.instructions,
              'specialInstructions': m.specialInstructions,
              'isSos': m.isSos,
              'substituteAllowed': m.substituteAllowed,
            },
          )
          .toList(),
      'investigations': draft.validInvestigations
          .map((i) => {
                'name': i.name,
                'type': i.type.name,
                if (i.group.isNotEmpty) 'group': i.group,
                'notes': i.notes,
              })
          .toList(),
      'advice': {
        'diet': draft.dietAdvice,
        'activity': draft.activityRestrictions,
        'lifestyle': draft.lifestyleAdvice,
        'general': draft.generalAdvice,
      },
      'followUpNote': draft.followUpNote,
      'nextVisit': draft.nextVisit?.toIso8601String(),
      if (draft.referrals.isNotEmpty)
        'referrals': draft.referrals
            .map(
              (r) => {
                'doctorId': r.doctorId,
                'doctorName': r.doctorName,
                'specialization': r.specialization,
                'reason': r.reason,
                'sent': r.sent,
              },
            )
            .toList(),
    };
  }
}
