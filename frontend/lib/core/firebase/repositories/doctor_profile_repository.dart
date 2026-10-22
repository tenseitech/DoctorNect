import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../config/doctor_patient_cutover_flag.dart';
import '../../supabase/supabase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firebase_bootstrap.dart';

class DoctorProfileRepository {
  DoctorProfileRepository._();

  static final DoctorProfileRepository instance = DoctorProfileRepository._();

  Future<void> saveDoctorFcmToken(String doctorId, String token) async {
    if (DoctorPatientCutoverFlag.isEnabled && SupabaseBootstrap.isReady) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final platform = kIsWeb
              ? 'web'
              : (defaultTargetPlatform == TargetPlatform.android
                  ? 'android'
                  : (defaultTargetPlatform == TargetPlatform.iOS
                      ? 'ios'
                      : 'unknown'));
          await SupabaseBootstrap.client.from('user_devices').upsert({
            'user_id': uid,
            'platform': platform,
            'fcm_token': token,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id,platform');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[saveDoctorFcmToken] Supabase error: $e');
      }
      return;
    }

    if (!FirebaseBootstrap.isReady || doctorId.isEmpty || token.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId)
        .set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearDoctorFcmToken(String doctorId) async {
    if (DoctorPatientCutoverFlag.isEnabled && SupabaseBootstrap.isReady) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final platform = kIsWeb
              ? 'web'
              : (defaultTargetPlatform == TargetPlatform.android
                  ? 'android'
                  : (defaultTargetPlatform == TargetPlatform.iOS
                      ? 'ios'
                      : 'unknown'));
          await SupabaseBootstrap.client
              .from('user_devices')
              .delete()
              .match({'user_id': uid, 'platform': platform});
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[clearDoctorFcmToken] Supabase error: $e');
      }
      return;
    }

    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId)
        .set({
      'fcmToken': FieldValue.delete(),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
