import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';

class MedicineSuggestionRepository {
  MedicineSuggestionRepository._();

  static final MedicineSuggestionRepository instance =
      MedicineSuggestionRepository._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> submit({
    required String doctorId,
    required String medicineName,
  }) async {
    final trimmed = medicineName.trim();
    if (trimmed.isEmpty) return;

    await _db.collection(FirestorePaths.medicineSuggestions).add({
      'medicineName': trimmed,
      'medicineNameLower': trimmed.toLowerCase(),
      'doctorId': doctorId,
      'status': 'pending',
      'source': 'doctor_prescription',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
