import '../../../features/doctor/clinical/models/clinical_models.dart';

/// Maps Supabase PostgreSQL prescription rows (with nested relational child items)
/// to [PrescriptionDraft] domain models.
abstract final class PrescriptionSupabaseMapper {
  static PrescriptionDraft? fromRow(Map<String, dynamic> data) {
    try {
      final prescriptionId = data['prescription_id'] as String? ?? '';
      if (prescriptionId.isEmpty) return null;

      final patientId = data['patient_id'] as String?;
      final patientName = data['patient_name'] as String? ?? 'Patient';
      final patientAge = (data['patient_age'] as num?)?.toInt() ?? 0;
      final patientGender = data['patient_gender'] as String?;
      final appointmentId = data['appointment_id'] as String?;

      DateTime prescriptionDate = DateTime.now();
      if (data['prescription_date'] != null) {
        prescriptionDate =
            DateTime.tryParse(data['prescription_date'].toString()) ??
                DateTime.now();
      }

      final draft = PrescriptionDraft(
        patient: PatientClinicalContext(
          patientName: patientName,
          age: patientAge,
          gender: patientGender,
          patientId: patientId,
          appointmentId: appointmentId,
        ),
        prescriptionId: prescriptionId,
        prescriptionDate: prescriptionDate,
      );

      // Doctor / Clinic snapshot
      draft.doctorId = data['doctor_id'] as String? ?? '';
      draft.doctorName = data['doctor_name'] as String? ?? '';
      draft.doctorSpecialization =
          data['doctor_specialization'] as String? ?? '';
      draft.doctorQualifications =
          data['doctor_qualifications'] as String? ?? '';
      draft.doctorRegNumber = data['doctor_reg_number'] as String? ?? '';
      draft.clinicName = data['clinic_name'] as String? ?? '';
      draft.clinicAddress = data['clinic_address'] as String? ?? '';
      draft.doctorPhone = data['doctor_phone'] as String? ?? '';

      draft.chiefComplaint = data['chief_complaint'] as String? ?? '';
      draft.diagnosisType = data['diagnosis_type'] as String? ?? 'Provisional';
      draft.primaryDiagnosis = data['primary_diagnosis'] as String? ?? '';
      draft.secondaryDiagnosis = data['secondary_diagnosis'] as String? ?? '';
      draft.symptoms = data['symptoms'] as String? ?? '';
      draft.symptomDuration = data['symptom_duration'] as String? ?? '';
      draft.pastHistory = data['past_history'] as String? ?? '';
      draft.allergies = data['allergies'] as String? ?? '';
      draft.generalExamination = data['general_examination'] as String? ?? '';

      // Vitals
      draft.vitals.bloodPressure = data['blood_pressure'] as String? ?? '';
      draft.vitals.temperature = data['temperature'] as String? ?? '';
      draft.vitals.pulse = data['pulse'] as String? ?? '';
      draft.vitals.spo2 = data['spo2'] as String? ?? '';
      draft.vitals.weightKg = data['weight_kg'] as String? ?? '';
      draft.vitals.heightCm = data['height_cm'] as String? ?? '';
      draft.vitals.respiratoryRate =
          data['respiratory_rate'] as String? ?? '';

      // Advice & Follow up
      draft.dietAdvice = data['diet_advice'] as String? ?? '';
      draft.activityRestrictions =
          data['activity_restrictions'] as String? ?? '';
      draft.lifestyleAdvice = data['lifestyle_advice'] as String? ?? '';
      draft.generalAdvice = data['general_advice'] as String? ?? '';
      draft.followUpNote = data['follow_up_note'] as String? ?? '';

      if (data['next_visit'] != null) {
        draft.nextVisit =
            DateTime.tryParse(data['next_visit'].toString());
      }

      // 1. Medicines
      final rawMeds = data['prescription_medicines'] as List<dynamic>? ??
          data['medicines'] as List<dynamic>? ??
          const [];
      draft.medicines = rawMeds.map((raw) {
        final map = Map<String, dynamic>.from(raw as Map);
        final entry = MedicineEntry(
          id: (map['medicine_entry_id'] ?? map['id']) as String?,
        );
        entry.name = map['name'] as String? ?? '';
        _applyDosage(entry, map['dosage'] as String? ?? '');
        entry.form = map['form'] as String? ?? 'Tablet';
        entry.instructions = map['instructions'] as String? ?? '';
        entry.specialInstructions =
            (map['special_instructions'] ?? map['specialInstructions'])
                    as String? ??
                '';
        entry.isSos =
            (map['is_sos'] ?? map['isSos']) as bool? ?? false;
        entry.substituteAllowed =
            (map['substitute_allowed'] ?? map['substituteAllowed'])
                    as bool? ??
                true;
        _applyDuration(entry, map['duration'] as String? ?? '');
        entry.quantity = map['quantity'] as String? ?? '';
        _applyFrequency(entry, map['frequency'] as String? ?? '');
        return entry;
      }).toList();

      // 2. Investigations
      final rawInv =
          data['prescription_investigations'] as List<dynamic>? ??
              data['investigations'] as List<dynamic>? ??
              const [];
      draft.investigations = rawInv
          .map((raw) {
            final map = Map<String, dynamic>.from(raw as Map);
            final typeStr = map['type'] as String? ?? 'custom';
            InvestigationType invType;
            try {
              invType = InvestigationType.values.byName(typeStr);
            } catch (_) {
              invType = InvestigationType.custom;
            }
            return InvestigationEntry(
              type: invType,
              name: map['name'] as String? ?? '',
              group: (map['group_name'] ?? map['group']) as String? ?? '',
              notes: map['notes'] as String? ?? '',
            );
          })
          .where((i) => i.name.trim().isNotEmpty)
          .toList();

      // 3. Referrals
      final rawRef = data['prescription_referrals'] as List<dynamic>? ??
          data['referrals'] as List<dynamic>? ??
          const [];
      draft.referrals = rawRef
          .map((raw) {
            final map = Map<String, dynamic>.from(raw as Map);
            return ReferralEntry(
              doctorId: (map['to_doctor_id'] ?? map['doctorId']) as String? ?? '',
              doctorName: (map['doctor_name'] ?? map['doctorName']) as String? ?? '',
              specialization: map['specialization'] as String? ?? '',
              reason: map['reason'] as String? ?? '',
              sent: map['sent'] as bool? ?? false,
            );
          })
          .where((r) => r.doctorId.isNotEmpty)
          .toList();

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
        entry.durationUnit =
            single[0].toUpperCase() + single.substring(1).toLowerCase();
        return;
      }
      entry.durationAmount = single;
      return;
    }

    entry.durationAmount = parts.first;
    entry.durationUnit = parts.sublist(1).join(' ');
  }
}
