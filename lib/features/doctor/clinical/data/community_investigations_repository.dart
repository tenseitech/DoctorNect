import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/firebase/firestore_paths.dart';
import '../../../../core/firebase/firestore_read_helper.dart';
import 'medical_tests_catalog.dart';

class CommunityLabTest {
  const CommunityLabTest({
    required this.id,
    required this.name,
    required this.group,
    required this.addedByDoctorId,
  });

  final String id;
  final String name;
  final String group;
  final String addedByDoctorId;
}

class CommunityRadiologyTest {
  const CommunityRadiologyTest({
    required this.id,
    required this.name,
    required this.group,
    required this.addedByDoctorId,
  });

  final String id;
  final String name;
  final String group;
  final String addedByDoctorId;
}

class CommunityBodyPart {
  const CommunityBodyPart({
    required this.id,
    required this.name,
    required this.addedByDoctorId,
  });

  final String id;
  final String name;
  final String addedByDoctorId;
}

/// Doctor-contributed lab tests, radiology, and body parts in Firestore.
class CommunityInvestigationsRepository {
  CommunityInvestigationsRepository._();

  static final CommunityInvestigationsRepository instance =
      CommunityInvestigationsRepository._();

  static const _fetchLimit = 1000;

  final List<CommunityLabTest> _labCache = [];
  final List<CommunityRadiologyTest> _radiologyCache = [];
  final List<CommunityBodyPart> _bodyPartCache = [];

  List<CommunityLabTest> get labCached => List.unmodifiable(_labCache);
  List<CommunityRadiologyTest> get radiologyCached => List.unmodifiable(_radiologyCache);
  List<CommunityBodyPart> get bodyPartCached => List.unmodifiable(_bodyPartCache);

  Future<void> fetchAll() async {
    if (!FirebaseBootstrap.isReady) return;
    await Future.wait([
      _fetchLabTests(),
      _fetchRadiologyTests(),
      _fetchBodyParts(),
    ]);
  }

  Future<void> _fetchLabTests() async {
    try {
      final query = FirebaseFirestore.instance
          .collection(FirestorePaths.communityLabTests)
          .orderBy('name')
          .limit(_fetchLimit);
      final snap = await FirestoreReadHelper.getQuery(query: query, preferCache: true);
      _labCache
        ..clear()
        ..addAll(snap.docs.map(_labFromDoc));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CommunityInvestigationsRepository._fetchLabTests failed: $e\n$st');
      }
    }
  }

  Future<void> _fetchRadiologyTests() async {
    try {
      final query = FirebaseFirestore.instance
          .collection(FirestorePaths.communityRadiology)
          .orderBy('name')
          .limit(_fetchLimit);
      final snap = await FirestoreReadHelper.getQuery(query: query, preferCache: true);
      _radiologyCache
        ..clear()
        ..addAll(snap.docs.map(_radiologyFromDoc));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CommunityInvestigationsRepository._fetchRadiologyTests failed: $e\n$st');
      }
    }
  }

  Future<void> _fetchBodyParts() async {
    try {
      final query = FirebaseFirestore.instance
          .collection(FirestorePaths.communityBodyParts)
          .orderBy('name')
          .limit(_fetchLimit);
      final snap = await FirestoreReadHelper.getQuery(query: query, preferCache: true);
      _bodyPartCache
        ..clear()
        ..addAll(snap.docs.map(_bodyPartFromDoc));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CommunityInvestigationsRepository._fetchBodyParts failed: $e\n$st');
      }
    }
  }

  List<TestCatalogItem> mergedLabCatalog() {
    final seen = <String>{};
    final results = <TestCatalogItem>[];
    for (final item in MedicalTestsCatalog.labTests) {
      seen.add(item.name.trim().toLowerCase());
      results.add(item);
    }
    for (final t in _labCache) {
      final key = t.name.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      results.add(TestCatalogItem(id: t.id, name: t.name, group: t.group));
    }
    return results;
  }

  List<TestCatalogItem> mergedRadiologyCatalog() {
    final seen = <String>{};
    final results = <TestCatalogItem>[];
    for (final item in MedicalTestsCatalog.radiologyTests) {
      seen.add(item.name.trim().toLowerCase());
      results.add(item);
    }
    for (final t in _radiologyCache) {
      final key = t.name.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      results.add(TestCatalogItem(id: t.id, name: t.name, group: t.group));
    }
    return results;
  }

  List<String> mergedBodyParts() {
    final seen = <String>{};
    final results = <String>[];
    for (final name in MedicalTestsCatalog.bodyParts) {
      final key = name.toLowerCase();
      if (seen.add(key)) results.add(name);
    }
    for (final part in _bodyPartCache) {
      final key = part.name.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      results.add(part.name);
    }
    return results;
  }

  TestCatalogItem? resolveLabCatalogItem(String id) =>
      MedicalTestsCatalog.labById(id) ?? _labById(id);

  TestCatalogItem? resolveRadiologyCatalogItem(String id) =>
      MedicalTestsCatalog.radiologyById(id) ?? _radiologyById(id);

  Future<CommunityLabTest?> addLabTest({
    required String name,
    required String group,
    required String doctorId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || doctorId.isEmpty) return null;

    final existing = _findLabByName(trimmed);
    if (existing != null) return existing;

    if (!FirebaseBootstrap.isReady) {
      throw StateError('Internet is required to add a community lab test.');
    }

    final docRef = await FirebaseFirestore.instance.collection(FirestorePaths.communityLabTests).add({
      'name': trimmed,
      'nameLower': trimmed.toLowerCase(),
      'group': group.trim().isEmpty ? 'Custom' : group.trim(),
      'addedByDoctorId': doctorId,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final snapshot = await FirestoreReadHelper.getDocument(reference: docRef, preferCache: true);
    final item = _labFromDoc(snapshot);
    _labCache.add(item);
    _labCache.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return item;
  }

  Future<CommunityRadiologyTest?> addRadiologyTest({
    required String name,
    required String group,
    required String doctorId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || doctorId.isEmpty) return null;

    final existing = _findRadiologyByName(trimmed);
    if (existing != null) return existing;

    if (!FirebaseBootstrap.isReady) {
      throw StateError('Internet is required to add a community radiology test.');
    }

    final docRef =
        await FirebaseFirestore.instance.collection(FirestorePaths.communityRadiology).add({
      'name': trimmed,
      'nameLower': trimmed.toLowerCase(),
      'group': group.trim().isEmpty ? 'Custom' : group.trim(),
      'addedByDoctorId': doctorId,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final snapshot = await FirestoreReadHelper.getDocument(reference: docRef, preferCache: true);
    final item = _radiologyFromDoc(snapshot);
    _radiologyCache.add(item);
    _radiologyCache.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return item;
  }

  Future<CommunityBodyPart?> addBodyPart({
    required String name,
    required String doctorId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || doctorId.isEmpty) return null;

    final existing = _findBodyPartByName(trimmed);
    if (existing != null) return existing;

    if (!FirebaseBootstrap.isReady) {
      throw StateError('Internet is required to add a community body part.');
    }

    final doc = await FirebaseFirestore.instance.collection(FirestorePaths.communityBodyParts).add({
      'name': trimmed,
      'nameLower': trimmed.toLowerCase(),
      'addedByDoctorId': doctorId,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final part = CommunityBodyPart(
      id: doc.id,
      name: trimmed,
      addedByDoctorId: doctorId,
    );
    _bodyPartCache.add(part);
    _bodyPartCache.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return part;
  }

  TestCatalogItem? _labById(String id) {
    for (final t in _labCache) {
      if (t.id == id) {
        return TestCatalogItem(id: t.id, name: t.name, group: t.group);
      }
    }
    return null;
  }

  TestCatalogItem? _radiologyById(String id) {
    for (final t in _radiologyCache) {
      if (t.id == id) {
        return TestCatalogItem(id: t.id, name: t.name, group: t.group);
      }
    }
    return null;
  }

  CommunityLabTest? _findLabByName(String name) {
    final key = name.trim().toLowerCase();
    for (final t in _labCache) {
      if (t.name.toLowerCase() == key) return t;
    }
    return null;
  }

  CommunityRadiologyTest? _findRadiologyByName(String name) {
    final key = name.trim().toLowerCase();
    for (final t in _radiologyCache) {
      if (t.name.toLowerCase() == key) return t;
    }
    return null;
  }

  CommunityBodyPart? _findBodyPartByName(String name) {
    final key = name.trim().toLowerCase();
    for (final t in _bodyPartCache) {
      if (t.name.toLowerCase() == key) return t;
    }
    return null;
  }

  static CommunityLabTest _labFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CommunityLabTest(
      id: doc.id,
      name: data['name'] as String? ?? '',
      group: data['group'] as String? ?? 'Custom',
      addedByDoctorId: data['addedByDoctorId'] as String? ?? '',
    );
  }

  static CommunityRadiologyTest _radiologyFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return CommunityRadiologyTest(
      id: doc.id,
      name: data['name'] as String? ?? '',
      group: data['group'] as String? ?? 'Custom',
      addedByDoctorId: data['addedByDoctorId'] as String? ?? '',
    );
  }

  static CommunityBodyPart _bodyPartFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return CommunityBodyPart(
      id: doc.id,
      name: data['name'] as String? ?? '',
      addedByDoctorId: data['addedByDoctorId'] as String? ?? '',
    );
  }
}
