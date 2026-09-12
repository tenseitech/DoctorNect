import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';
import '../mappers/medical_directory_firestore_mapper.dart';
import '../models/doctor_medical_directory_entry.dart';
import '../models/firestore_page.dart';

class MedicalDirectoryRepository {
  MedicalDirectoryRepository._();

  static final MedicalDirectoryRepository instance = MedicalDirectoryRepository._();

  Future<void> save(DoctorMedicalDirectoryEntry entry) async {
    if (!FirebaseBootstrap.isReady) return;

    await FirebaseFirestore.instance.collection(FirestorePaths.medicalDirectory).doc(entry.entryId).set({
      ...MedicalDirectoryFirestoreMapper.toMap(entry),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> update(DoctorMedicalDirectoryEntry entry) async {
    if (!FirebaseBootstrap.isReady) return;

    await FirebaseFirestore.instance.collection(FirestorePaths.medicalDirectory).doc(entry.entryId).set({
      ...MedicalDirectoryFirestoreMapper.toMap(entry),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String entryId) async {
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance.collection(FirestorePaths.medicalDirectory).doc(entryId).delete();
  }

  Future<FirestorePage<DoctorMedicalDirectoryEntry>> fetchForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.medicalDirectoryPage,
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const FirestorePage(items: [], hasMore: false);
    }

    final baseQuery = FirebaseFirestore.instance
        .collection(FirestorePaths.medicalDirectory)
        .where('doctorId', isEqualTo: doctorId)
        .limit(limit);

    final query = startAfter == null ? baseQuery : baseQuery.startAfterDocument(startAfter);
    final snapshot = await FirestoreReadHelper.getQuery(query: query, preferCache: preferCache);

    final items = snapshot.docs
        .map((doc) => MedicalDirectoryFirestoreMapper.fromMap(doc.data()))
        .whereType<DoctorMedicalDirectoryEntry>()
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return FirestorePage(
      items: items,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }
}
