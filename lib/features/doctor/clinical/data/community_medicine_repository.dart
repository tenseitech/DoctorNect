import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/firebase/firestore_paths.dart';
import '../../../../core/firebase/firestore_read_helper.dart';
import 'indian_medicines_database.dart';
import 'dosage_units.dart';

const kCommunityDosageUnits = kDosageUnits;

const kCommunityMedicineForms = [
  'Tablet',
  'Capsule',
  'Liquid',
  'Syrup',
  'Injection',
  'Syringe',
];

class CommunityMedicine {
  const CommunityMedicine({
    required this.id,
    required this.name,
    required this.dosageUnit,
    required this.form,
    required this.addedByDoctorId,
  });

  final String id;
  final String name;
  final String dosageUnit;
  final String form;
  final String addedByDoctorId;
}

class MedicineSearchSuggestion {
  const MedicineSearchSuggestion({
    required this.name,
    this.isCommunity = false,
    this.dosageUnit,
    this.form,
  });

  final String name;
  final bool isCommunity;
  final String? dosageUnit;
  final String? form;
}

/// Shared doctor-contributed medicines stored in Firestore `community_medicines`.
class CommunityMedicineRepository {
  CommunityMedicineRepository._();

  static final CommunityMedicineRepository instance =
      CommunityMedicineRepository._();

  static const _fetchLimit = 1000;

  final List<CommunityMedicine> _cache = [];

  List<CommunityMedicine> get cached => List.unmodifiable(_cache);

  Future<void> fetchAll() async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      final query = FirebaseFirestore.instance
          .collection(FirestorePaths.communityMedicines)
          .orderBy('name')
          .limit(_fetchLimit);
      final snap =
          await FirestoreReadHelper.getQuery(query: query, preferCache: true);

      _cache
        ..clear()
        ..addAll(snap.docs.map(_fromDoc));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CommunityMedicineRepository.fetchAll failed: $e\n$st');
      }
    }
  }

  CommunityMedicine? findByName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final m in _cache) {
      if (m.name.toLowerCase() == key) return m;
    }
    return null;
  }

  /// Prefix / contains search on the in-memory cache.
  List<CommunityMedicine> search(String query, {int limit = 8}) =>
      searchMedicines(query, limit: limit);

  List<CommunityMedicine> searchMedicines(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _cache.take(limit).toList();

    final results = <CommunityMedicine>[];
    for (final m in _cache) {
      final lower = m.name.toLowerCase();
      if (lower.startsWith(q) || lower.contains(q)) {
        results.add(m);
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  bool isKnownName(String name) {
    final q = name.trim();
    if (q.isEmpty) return true;

    if (findByName(q) != null) return true;

    final db = IndianMedicinesDatabase.instance;
    if (!db.isLoaded) return false;

    final s = db.search(q, limit: 1);
    if (s.isEmpty) return false;
    return s.first.trim().toLowerCase() == q.toLowerCase();
  }

  /// Indian DB first, then community cache; dedupe by name (case-insensitive).
  List<MedicineSearchSuggestion> searchMerged(String query, {int limit = 8}) {
    final seen = <String>{};
    final results = <MedicineSearchSuggestion>[];

    void addResult(MedicineSearchSuggestion item) {
      final key = item.name.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) return;
      results.add(item);
    }

    final db = IndianMedicinesDatabase.instance;
    if (db.isLoaded) {
      for (final name in db.search(query, limit: limit)) {
        addResult(MedicineSearchSuggestion(name: name));
        if (results.length >= limit) return results;
      }
    }

    for (final m in search(query, limit: limit)) {
      addResult(
        MedicineSearchSuggestion(
          name: m.name,
          isCommunity: true,
          dosageUnit: m.dosageUnit,
          form: m.form,
        ),
      );
      if (results.length >= limit) break;
    }

    return results;
  }

  Future<CommunityMedicine?> addMedicine({
    required String name,
    required String dosageUnit,
    required String form,
    required String doctorId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || doctorId.isEmpty) return null;

    final existing = findByName(trimmed);
    if (existing != null) return existing;

    if (!FirebaseBootstrap.isReady) {
      throw StateError('Internet is required to add a community medicine.');
    }

    final doc = await FirebaseFirestore.instance
        .collection(FirestorePaths.communityMedicines)
        .add({
      'name': trimmed,
      'nameLower': trimmed.toLowerCase(),
      'dosageUnit': dosageUnit,
      'form': form,
      'addedByDoctorId': doctorId,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final medicine = CommunityMedicine(
      id: doc.id,
      name: trimmed,
      dosageUnit: dosageUnit,
      form: form,
      addedByDoctorId: doctorId,
    );
    _cache.add(medicine);
    _cache.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return medicine;
  }

  static CommunityMedicine _fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return CommunityMedicine(
      id: doc.id,
      name: data['name'] as String? ?? '',
      dosageUnit: data['dosageUnit'] as String? ?? 'mg',
      form: data['form'] as String? ?? 'Tablet',
      addedByDoctorId: data['addedByDoctorId'] as String? ?? '',
    );
  }
}
