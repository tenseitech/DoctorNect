import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/doctor/clinical/models/clinical_models.dart';
import '../../firebase/firestore_query_limits.dart';
import '../../firebase/models/firestore_page.dart';
import '../mappers/prescription_supabase_mapper.dart';
import '../supabase_bootstrap.dart';
import 'supabase_patient_profile_repository.dart';

/// Supabase Repository for Prescriptions.
/// Persists across normalized relational tables:
/// - `prescriptions`
/// - `prescription_medicines`
/// - `prescription_investigations`
/// - `prescription_referrals`
class SupabasePrescriptionRepository {
  SupabasePrescriptionRepository._();

  static final SupabasePrescriptionRepository instance =
      SupabasePrescriptionRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  static const String _selectQuery =
      '*, prescription_medicines(*), prescription_investigations(*), prescription_referrals(*)';

  /// Saves a prescription draft and its normalized child entities atomically.
  Future<void> save(
    PrescriptionDraft draft,
    String doctorId, {
    bool isNewRecord = false,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      throw StateError('Supabase is not available.');
    }
    if (doctorId.trim().isEmpty) {
      throw StateError('Doctor session is missing. Sign in again.');
    }

    final resolvedDoctorId =
        draft.doctorId.isNotEmpty ? draft.doctorId : doctorId;
    final patientId = draft.patientId;
    if (patientId.trim().isEmpty) {
      throw StateError('Patient ID is required to save prescription.');
    }

    final prescriptionRow = <String, dynamic>{
      'prescription_id': draft.prescriptionId,
      'doctor_id': resolvedDoctorId,
      'patient_id': patientId,
      if (draft.patient.appointmentId != null &&
          draft.patient.appointmentId!.isNotEmpty)
        'appointment_id': draft.patient.appointmentId,
      'doctor_name': draft.doctorName,
      'doctor_specialization': draft.doctorSpecialization,
      'doctor_qualifications': draft.doctorQualifications,
      'doctor_reg_number': draft.doctorRegNumber,
      'clinic_name': draft.clinicName,
      'clinic_address': draft.clinicAddress,
      'doctor_phone': draft.doctorPhone,
      'patient_name': draft.patient.patientName,
      'patient_age': draft.patient.age,
      if (draft.patient.gender != null) 'patient_gender': draft.patient.gender,
      'prescription_date': draft.prescriptionDate.toIso8601String(),
      'diagnosis_type': draft.diagnosisType,
      'primary_diagnosis': draft.primaryDiagnosis,
      'secondary_diagnosis': draft.secondaryDiagnosis,
      'chief_complaint': draft.chiefComplaint,
      'symptoms': draft.symptoms,
      'symptom_duration': draft.symptomDuration,
      'past_history': draft.pastHistory,
      'allergies': draft.allergies,
      'general_examination': draft.generalExamination,
      'blood_pressure': draft.vitals.bloodPressure,
      'temperature': draft.vitals.temperature,
      'pulse': draft.vitals.pulse,
      'spo2': draft.vitals.spo2,
      'weight_kg': draft.vitals.weightKg,
      'height_cm': draft.vitals.heightCm,
      'respiratory_rate': draft.vitals.respiratoryRate,
      'diet_advice': draft.dietAdvice,
      'activity_restrictions': draft.activityRestrictions,
      'lifestyle_advice': draft.lifestyleAdvice,
      'general_advice': draft.generalAdvice,
      'follow_up_note': draft.followUpNote,
      if (draft.nextVisit != null)
        'next_visit': draft.nextVisit!.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Child collections packaged for atomic single-transaction persistence
    prescriptionRow['medicines'] = draft.validMedicines.map((m) {
      return <String, dynamic>{
        'medicine_entry_id':
            m.id.isNotEmpty ? m.id : '${draft.prescriptionId}_${m.name.hashCode}',
        'name': m.name,
        'dosage': m.dosageLabel,
        'form': m.form,
        'frequency': m.frequencyLabel,
        'quantity': m.quantity,
        'duration': '${m.durationAmount} ${m.durationUnit}'.trim(),
        'instructions': m.instructions,
        'special_instructions': m.specialInstructions,
        'is_sos': m.isSos,
        'substitute_allowed': m.substituteAllowed,
      };
    }).toList();

    prescriptionRow['investigations'] = draft.investigations
        .where((i) => i.name.trim().isNotEmpty)
        .map((inv) => <String, dynamic>{
              'name': inv.name,
              'type': inv.type.name,
              'group_name': inv.group,
              'notes': inv.notes,
            })
        .toList();

    prescriptionRow['referrals'] = draft.referrals
        .where((r) => r.doctorId.isNotEmpty)
        .map((ref) => <String, dynamic>{
              'to_doctor_id': ref.doctorId,
              'to_doctor_name': ref.doctorName,
              'specialty': ref.specialization,
              'notes': ref.reason,
            })
        .toList();

    // 1. Single atomic database transaction via PostgreSQL RPC
    await _client.rpc(
      'create_prescription_atomic',
      params: {'payload': prescriptionRow},
    );
  }

  /// One-time fetch for a doctor's prescriptions with relational child entries.
  Future<FirestorePage<PrescriptionDraft>> fetchForDoctor(
    String doctorId, {
    dynamic startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }

    try {
      final res = await _client
          .from('prescriptions')
          .select(_selectQuery)
          .eq('doctor_id', doctorId)
          .order('prescription_date', ascending: false)
          .limit(limit);

      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(PrescriptionSupabaseMapper.fromRow)
          .whereType<PrescriptionDraft>()
          .toList();

      return FirestorePage(
        items: items,
        hasMore: rows.length == limit,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SupabasePrescriptionRepository] fetchForDoctor failed: $e\n$st');
      }
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  /// One-time fetch for a patient's prescriptions.
  Future<FirestorePage<PrescriptionDraft>> fetchForPatient(
    String patientId, {
    dynamic startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }

    try {
      final res = await _client
          .from('prescriptions')
          .select(_selectQuery)
          .eq('patient_id', patientId)
          .order('prescription_date', ascending: false)
          .limit(limit);

      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(PrescriptionSupabaseMapper.fromRow)
          .whereType<PrescriptionDraft>()
          .toList();

      return FirestorePage(
        items: items,
        hasMore: rows.length == limit,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabasePrescriptionRepository] fetchForPatient failed: $e\n$st');
      }
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  /// Doctor-facing fetch — checks consent/sharing first.
  Future<FirestorePage<PrescriptionDraft>> fetchForPatientForDoctor(
    String patientId, {
    dynamic startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    final isSharing = await SupabasePatientProfileRepository.instance
        .isPatientSharingClinicalDataWithDoctors(patientId);
    if (!isSharing) {
      return const FirestorePage(items: [], hasMore: false);
    }
    return fetchForPatient(
      patientId,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  /// Doctor-scoped fetch for one specific patient.
  Future<FirestorePage<PrescriptionDraft>> fetchForDoctorAndPatient(
    String doctorId,
    String patientId, {
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty || patientId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }

    try {
      final res = await _client
          .from('prescriptions')
          .select(_selectQuery)
          .eq('doctor_id', doctorId)
          .eq('patient_id', patientId)
          .order('prescription_date', ascending: false)
          .limit(limit);

      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(PrescriptionSupabaseMapper.fromRow)
          .whereType<PrescriptionDraft>()
          .toList();

      return FirestorePage(
        items: items,
        hasMore: rows.length == limit,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabasePrescriptionRepository] fetchForDoctorAndPatient failed: $e\n$st');
      }
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  /// Doctor-facing fetch for one patient — checks consent/sharing first.
  Future<FirestorePage<PrescriptionDraft>> fetchForDoctorAndPatientForDoctor(
    String doctorId,
    String patientId, {
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    final isSharing = await SupabasePatientProfileRepository.instance
        .isPatientSharingClinicalDataWithDoctors(patientId);
    if (!isSharing) {
      return const FirestorePage(items: [], hasMore: false);
    }
    return fetchForDoctorAndPatient(
      doctorId,
      patientId,
      limit: limit,
      preferCache: preferCache,
    );
  }

  /// Realtime stream for patient prescriptions.
  /// CONVERSION RULE: Single .eq filter -> uses Supabase `.stream()`.
  Stream<List<PrescriptionDraft>> watchForPatient(String patientId) {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const Stream.empty();
    }

    late final StreamController<List<PrescriptionDraft>> controller;
    RealtimeChannel? channel;

    controller = StreamController<List<PrescriptionDraft>>.broadcast(
      onListen: () async {
        final initial = await fetchForPatient(patientId);
        if (!controller.isClosed) {
          controller.add(initial.items);
        }

        channel = _client.channel('public:prescriptions:patient:$patientId')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'prescriptions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'patient_id',
              value: patientId,
            ),
            callback: (payload) async {
              final updated = await fetchForPatient(patientId);
              if (!controller.isClosed) {
                controller.add(updated.items);
              }
            },
          )
          ..subscribe();
      },
      onCancel: () async {
        if (channel != null) {
          await _client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }
}
