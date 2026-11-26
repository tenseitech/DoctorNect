import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase/firestore_query_limits.dart';
import '../../firebase/models/doctor_medical_directory_entry.dart';
import '../../firebase/models/firestore_page.dart';
import '../supabase_bootstrap.dart';
import '../supabase_keyset_pagination.dart';

/// PostgREST columns for directory list reads (PERF-04).
const String _medicalDirectoryListColumns =
    'entry_id,doctor_id,name,type,phone,created_at,updated_at';

/// Supabase repository for Doctor's Medical Directory.
/// Backed by `public.medical_directory` in PostgreSQL.
class SupabaseMedicalDirectoryRepository {
  SupabaseMedicalDirectoryRepository._();

  static final SupabaseMedicalDirectoryRepository instance =
      SupabaseMedicalDirectoryRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<void> save(DoctorMedicalDirectoryEntry entry) async {
    if (!SupabaseBootstrap.isReady) return;

    try {
      await _client.from('medical_directory').upsert({
        'entry_id': entry.entryId,
        'doctor_id': entry.doctorId,
        'name': entry.name,
        'type': entry.type,
        'phone': entry.phone,
        'created_at': entry.createdAt.toUtc().toIso8601String(),
        'updated_at': (entry.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseMedicalDirectoryRepository] save error: $e');
      }
      rethrow;
    }
  }

  Future<void> update(DoctorMedicalDirectoryEntry entry) async {
    if (!SupabaseBootstrap.isReady) return;

    try {
      await _client.from('medical_directory').update({
        'name': entry.name,
        'type': entry.type,
        'phone': entry.phone,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('entry_id', entry.entryId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseMedicalDirectoryRepository] update error: $e');
      }
      rethrow;
    }
  }

  Future<void> delete(String entryId) async {
    if (!SupabaseBootstrap.isReady || entryId.isEmpty) return;

    try {
      await _client.from('medical_directory').delete().eq('entry_id', entryId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseMedicalDirectoryRepository] delete error: $e');
      }
      rethrow;
    }
  }

  Future<FirestorePage<DoctorMedicalDirectoryEntry>> fetchForDoctor(
    String doctorId, {
    int limit = FirestoreQueryLimits.medicalDirectoryPage,
    String? startAfterCursor,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }

    try {
      var query = _client
          .from('medical_directory')
          .select(_medicalDirectoryListColumns)
          .eq('doctor_id', doctorId);

      final keyset = KeysetCursor.decode(startAfterCursor);
      if (keyset != null) {
        query = SupabaseKeysetPagination.applyAscendingPage(
          query,
          sortColumn: 'name',
          idColumn: 'entry_id',
          cursor: keyset,
        );
      }

      final res = await query
          .order('name', ascending: true)
          .order('entry_id', ascending: true)
          .limit(limit);

      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows.map(_entryFromRow).toList();

      String? nextCursor;
      if (rows.isNotEmpty && rows.length == limit) {
        nextCursor = KeysetCursor.fromRow(
          rows.last,
          sortColumn: 'name',
          idColumn: 'entry_id',
        )?.encode();
      }

      return FirestorePage(
        items: items,
        cursor: nextCursor,
        hasMore: rows.length == limit,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseMedicalDirectoryRepository] fetchForDoctor error: $e');
      }
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  DoctorMedicalDirectoryEntry _entryFromRow(Map<String, dynamic> row) {
    return DoctorMedicalDirectoryEntry(
      entryId: row['entry_id'] as String? ?? '',
      doctorId: row['doctor_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      type: row['type'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.tryParse(row['updated_at'].toString())
          : null,
    );
  }
}
