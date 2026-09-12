import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/firebase/firestore_paths.dart';
import '../../../../core/firebase/firestore_read_helper.dart';
import 'icd10_diagnoses_database.dart';

class CommunityDiagnosis {
  const CommunityDiagnosis({
    required this.id,
    required this.text,
    required this.addedByDoctorId,
  });

  final String id;
  final String text;
  final String addedByDoctorId;
}

/// Doctor-contributed diagnoses stored in Firestore `community_diagnoses`.
class CommunityDiagnosisRepository {
  CommunityDiagnosisRepository._();

  static final CommunityDiagnosisRepository instance = CommunityDiagnosisRepository._();

  static const _fetchLimit = 1000;

  final List<CommunityDiagnosis> _cache = [];

  List<CommunityDiagnosis> get cached => List.unmodifiable(_cache);

  Future<void> fetchAll() async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      final query = FirebaseFirestore.instance
          .collection(FirestorePaths.communityDiagnoses)
          .orderBy('text')
          .limit(_fetchLimit);
      final snap = await FirestoreReadHelper.getQuery(query: query, preferCache: true);

      _cache
        ..clear()
        ..addAll(snap.docs.map(_fromDoc));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CommunityDiagnosisRepository.fetchAll failed: $e\n$st');
      }
    }
  }

  CommunityDiagnosis? findByText(String text) {
    final key = text.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final item in _cache) {
      if (item.text.toLowerCase() == key) return item;
    }
    return null;
  }

  bool isKnownDisplay(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (findByText(trimmed) != null) return true;
    return Icd10DiagnosesDatabase.instance.isKnownDisplay(trimmed);
  }

  List<String> search(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _cache.take(limit).map((e) => e.text).toList();

    final results = <String>[];
    for (final item in _cache) {
      final lower = item.text.toLowerCase();
      if (lower.contains(q)) {
        results.add(item.text);
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  /// ICD-10 bundled list first, then community cache; dedupe by text.
  List<String> searchMerged(String query, {int limit = 8}) {
    final seen = <String>{};
    final results = <String>[];

    void add(String value) {
      final key = value.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) return;
      results.add(value.trim());
    }

    for (final item in Icd10DiagnosesDatabase.instance.search(query, limit: limit)) {
      add(item);
      if (results.length >= limit) return results;
    }

    for (final item in search(query, limit: limit)) {
      add(item);
      if (results.length >= limit) return results;
    }

    return results;
  }

  Future<CommunityDiagnosis?> addDiagnosis({
    required String text,
    required String doctorId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || doctorId.isEmpty) return null;

    final existing = findByText(trimmed);
    if (existing != null) return existing;

    if (!FirebaseBootstrap.isReady) {
      throw StateError('Internet is required to save a custom diagnosis.');
    }

    final doc = await FirebaseFirestore.instance.collection(FirestorePaths.communityDiagnoses).add({
      'text': trimmed,
      'textLower': trimmed.toLowerCase(),
      'addedByDoctorId': doctorId,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final diagnosis = CommunityDiagnosis(
      id: doc.id,
      text: trimmed,
      addedByDoctorId: doctorId,
    );
    _cache.add(diagnosis);
    _cache.sort((a, b) => a.text.toLowerCase().compareTo(b.text.toLowerCase()));
    return diagnosis;
  }

  Future<void> persistCustomIfNeeded(String text, {required String doctorId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isKnownDisplay(trimmed) || doctorId.isEmpty) return;
    try {
      await addDiagnosis(text: trimmed, doctorId: doctorId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CommunityDiagnosisRepository.persistCustomIfNeeded failed: $e\n$st');
      }
    }
  }

  static CommunityDiagnosis _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return CommunityDiagnosis(
      id: doc.id,
      text: data['text'] as String? ?? '',
      addedByDoctorId: data['addedByDoctorId'] as String? ?? '',
    );
  }
}
