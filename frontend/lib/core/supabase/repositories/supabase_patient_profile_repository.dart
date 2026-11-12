import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/patient/records/models/health_record_models.dart';
import '../supabase_bootstrap.dart';
import '../supabase_stream_table.dart';

/// Supabase Repository for Patient Profile and Clinical Care Links.
/// Replaces Firestore `patients/{patientId}` and `patient_doctor_links`.
class SupabasePatientProfileRepository {
  SupabasePatientProfileRepository._();

  static final SupabasePatientProfileRepository instance =
      SupabasePatientProfileRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  static final RegExp _registeredPatientId = RegExp(
    r'^p\d+$',
    caseSensitive: false,
  );
  static final RegExp _walkInPatientId = RegExp(
    r'^wi\d+$',
    caseSensitive: false,
  );

  static bool isRegisteredPatientId(String? patientId) =>
      patientId != null &&
      patientId.isNotEmpty &&
      _registeredPatientId.hasMatch(patientId);

  static bool isWalkInPatientId(String? patientId) =>
      patientId != null &&
      patientId.isNotEmpty &&
      _walkInPatientId.hasMatch(patientId);

  bool checkIsRegisteredPatientId(String? patientId) =>
      isRegisteredPatientId(patientId);
  bool checkIsWalkInPatientId(String? patientId) =>
      isWalkInPatientId(patientId);

  static bool sharesRecordsWithDoctors(Map<String, dynamic>? patientData) {
    if (patientData == null) return false;
    return patientData['share_records_with_doctors'] as bool? ??
        patientData['shareRecordsWithDoctors'] as bool? ??
        true;
  }

  Future<bool> mayDoctorViewSharedPatientRecords(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!isRegisteredPatientId(patientId)) return false;
    return isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    );
  }

  Future<bool> isPatientSharingClinicalDataWithDoctors(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!isRegisteredPatientId(patientId)) return true;
    final data = await fetchPatientDocument(
      patientId,
      preferCache: preferCache,
    );
    if (data == null) return false;
    return sharesRecordsWithDoctors(data);
  }

  Future<Map<String, dynamic>?> fetchPatientDocument(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return null;

    try {
      final res = await _client
          .from('patients')
          .select()
          .eq('patient_id', patientId)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Real-time stream of a patient's document via Supabase Realtime `.stream()`.
  /// Uses a single `.eq('patient_id', patientId)` filter on primary key `patient_id`.
  Stream<Map<String, dynamic>?> watchPatientDocument(String patientId) {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const Stream.empty();
    }

    if (SupabaseBootstrap.isProduction) {
      return streamTable(
        table: 'patients',
        primaryKey: ['patient_id'],
        filterColumn: 'patient_id',
        filterValue: patientId,
      ).map((rows) {
        if (rows.isEmpty) return null;
        return rows.first;
      });
    }

    return _client
        .from('patients')
        .stream(primaryKey: ['patient_id'])
        .eq('patient_id', patientId)
        .map((rows) {
          if (rows.isEmpty) return null;
          return rows.first;
        });
  }

  Future<bool> ensureDoctorPatientLink({
    required String patientId,
    required String doctorId,
    required String source,
    String? fromDoctorId,
    String? referralId,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) {
      return false;
    }
    if (!isRegisteredPatientId(patientId)) return false;

    final payload = <String, dynamic>{
      'patient_id': patientId,
      'doctor_id': doctorId,
      'source': source,
      if (fromDoctorId != null && fromDoctorId.isNotEmpty)
        'from_doctor_id': fromDoctorId,
      if (referralId != null && referralId.isNotEmpty)
        'referral_id': referralId,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      await _client.from('patient_doctor_links').upsert(
        payload,
        onConflict: 'patient_id, doctor_id',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> grantDoctorCareTeamAccess({
    required String patientId,
    required String doctorId,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) {
      return false;
    }
    if (isWalkInPatientId(patientId)) return false;
    if (!isRegisteredPatientId(patientId)) return false;

    try {
      final currentDoc = await fetchPatientDocument(patientId);
      final currentTeam = (currentDoc?['care_team_doctor_ids'] as List<dynamic>? ??
              const [])
          .map((e) => e.toString())
          .toSet();

      if (!currentTeam.contains(doctorId)) {
        currentTeam.add(doctorId);
        await _client.from('patients').update({
          'care_team_doctor_ids': currentTeam.toList(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('patient_id', patientId);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> savePatientDocument(
    String patientId,
    Map<String, dynamic> data,
  ) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return;

    final payload = <String, dynamic>{
      'patient_id': patientId,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (data.containsKey('name')) payload['name'] = data['name'];
    if (data.containsKey('mobile')) payload['mobile'] = data['mobile'];
    if (data.containsKey('email')) payload['email'] = data['email'];
    if (data.containsKey('shareRecordsWithDoctors')) {
      payload['share_records_with_doctors'] = data['shareRecordsWithDoctors'];
    }
    if (data.containsKey('profileCompleted')) {
      payload['profile_completed'] = data['profileCompleted'];
    }

    await _client.from('patients').upsert(payload, onConflict: 'patient_id');
  }

  Future<List<HealthRecord>> fetchHealthRecords(String patientId) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];

    try {
      final res = await _client
          .from('health_records')
          .select()
          .eq('patient_id', patientId)
          .order('date', ascending: false)
          .limit(50);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map((row) {
        final storageStatus = row['file_storage'] as String?;
        return HealthRecord(
          id: row['record_id'] as String? ?? '',
          title: row['title'] as String? ?? 'Record',
          type: _parseRecordType(row['type'] as String?),
          date: row['date'] != null
              ? DateTime.tryParse(row['date'].toString()) ?? DateTime.now()
              : DateTime.now(),
          source: _parseSource(row['source'] as String?),
          fileName: row['file_name'] as String? ?? '',
          doctorName: row['doctor_name'] as String?,
          labName: row['lab_name'] as String?,
          isImage: row['is_image'] as bool? ?? false,
          notes: row['notes'] as String?,
          sharedWithDoctors: row['shared_with_doctors'] as bool? ?? false,
          fileStorage: storageStatus != null
              ? (HealthRecordFileStorage.values.where((e) => e.name == storageStatus).firstOrNull ??
                  HealthRecordFileStorage.none)
              : HealthRecordFileStorage.none,
          storageUrl: row['storage_url'] as String?,
          storageKey: row['storage_key'] as String?,
          storageProvider: row['storage_provider'] as String?,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  HealthRecordType _parseRecordType(String? val) {
    if (val == null) return HealthRecordType.other;
    try {
      return HealthRecordType.values.byName(val);
    } catch (_) {
      return HealthRecordType.other;
    }
  }

  RecordSource _parseSource(String? val) {
    if (val == null) return RecordSource.selfUploaded;
    try {
      return RecordSource.values.byName(val);
    } catch (_) {
      return RecordSource.selfUploaded;
    }
  }
}
