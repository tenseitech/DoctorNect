import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/patient/records/models/health_record_models.dart';
import '../supabase_bootstrap.dart';
import 'supabase_patient_profile_repository.dart';

/// Supabase Repository for Patient Health Records (Clinical Vault).
/// Replaces Firestore `health_records/{recordId}` documents.
/// Stores S3 storage keys and metadata alongside clinical record attributes.
class SupabaseHealthRecordsRepository {
  SupabaseHealthRecordsRepository._();

  static final SupabaseHealthRecordsRepository instance =
      SupabaseHealthRecordsRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<List<HealthRecord>> fetchForPatient(String patientId) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];

    try {
      final res = await _client
          .from('health_records')
          .select()
          .eq('patient_id', patientId)
          .order('date', ascending: false)
          .limit(100);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map(_fromRow).whereType<HealthRecord>().toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseHealthRecordsRepository] fetchForPatient error: $e\n$st');
      }
      return const [];
    }
  }

  Future<List<HealthRecord>> fetchForDoctor(String patientId) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];

    final isSharing = await SupabasePatientProfileRepository.instance
        .isPatientSharingClinicalDataWithDoctors(patientId);
    if (!isSharing) return const [];

    try {
      final res = await _client
          .from('health_records')
          .select()
          .eq('patient_id', patientId)
          .order('date', ascending: false)
          .limit(100);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map(_fromRow).whereType<HealthRecord>().toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseHealthRecordsRepository] fetchForDoctor error: $e\n$st');
      }
      return const [];
    }
  }

  Future<void> save(
    HealthRecord record, {
    required String patientId,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return;

    final row = <String, dynamic>{
      'record_id': record.id,
      'patient_id': patientId,
      'title': record.title,
      'type': record.type.name,
      'date': record.date.toIso8601String(),
      'source': record.source.name,
      'file_name': record.fileName,
      if (record.doctorName != null) 'doctor_name': record.doctorName,
      if (record.labName != null) 'lab_name': record.labName,
      'is_image': record.isImage,
      if (record.notes != null) 'notes': record.notes,
      'shared_with_doctors': record.sharedWithDoctors,
      'file_storage': record.fileStorage.name,
      if (record.storageUrl != null) 'storage_url': record.storageUrl,
      if (record.storageKey != null) 'storage_key': record.storageKey,
      if (record.storageProvider != null)
        'storage_provider': record.storageProvider,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _client.from('health_records').upsert(row, onConflict: 'record_id');
  }

  Future<void> delete(
    String recordId, {
    required String patientId,
  }) async {
    if (!SupabaseBootstrap.isReady || recordId.isEmpty || patientId.isEmpty) {
      return;
    }

    await _client
        .from('health_records')
        .delete()
        .eq('record_id', recordId)
        .eq('patient_id', patientId);
  }

  /// Realtime stream for patient health records.
  /// CONVERSION RULE: Single .eq filter on patient_id -> uses Supabase `.stream()`.
  Stream<List<HealthRecord>> watchForPatient(String patientId) {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const Stream.empty();
    }

    return _client
        .from('health_records')
        .stream(primaryKey: ['record_id'])
        .eq('patient_id', patientId)
        .order('date', ascending: false)
        .map((rows) => rows.map(_fromRow).whereType<HealthRecord>().toList());
  }

  HealthRecord? _fromRow(Map<String, dynamic> row) {
    try {
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
            ? (HealthRecordFileStorage.values
                    .where((e) => e.name == storageStatus)
                    .firstOrNull ??
                HealthRecordFileStorage.none)
            : HealthRecordFileStorage.none,
        storageUrl: row['storage_url'] as String?,
        storageKey: row['storage_key'] as String?,
        storageProvider: row['storage_provider'] as String?,
      );
    } catch (_) {
      return null;
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
