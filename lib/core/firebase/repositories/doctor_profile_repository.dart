import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../firebase_bootstrap.dart';

class DoctorProfileRepository {
  DoctorProfileRepository._();

  static final DoctorProfileRepository instance = DoctorProfileRepository._();

  Future<void> saveDoctorFcmToken(String doctorId, String token) async {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty || token.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId)
        .set(
      {
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> clearDoctorFcmToken(String doctorId) async {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId)
        .set(
      {
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
