import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../supabase/supabase_bootstrap.dart';

class DoctorProfileRepository {
  DoctorProfileRepository._();

  static final DoctorProfileRepository instance = DoctorProfileRepository._();

  Future<void> saveDoctorFcmToken(String doctorId, String token) async {
    if (!SupabaseBootstrap.isReady || token.isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
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
    } catch (e) {
      if (kDebugMode) debugPrint('[saveDoctorFcmToken] Supabase error: $e');
    }
  }

  Future<void> clearDoctorFcmToken(String doctorId) async {
    if (!SupabaseBootstrap.isReady) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
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
    } catch (e) {
      if (kDebugMode) debugPrint('[clearDoctorFcmToken] Supabase error: $e');
    }
  }
}
