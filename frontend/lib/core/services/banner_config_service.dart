import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';
import '../models/banner_config_model.dart';
import '../config/doctor_patient_cutover_flag.dart';
import '../config/firestore_forbidden_guard.dart';
import '../supabase/supabase_bootstrap.dart';

/// Read-only promoted-ads banner config (written by Super Admin console).
abstract final class BannerConfigService {
  static const String _configCollection = 'system_config';
  static const String _configDoc = 'promoted_ads';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Stream<BannerConfigModel> streamConfig() {
    final bool useSupabase = DoctorPatientCutoverFlag.isEnabled ||
        FirestoreForbiddenGuard.isForbidden;
    if (useSupabase) {
      return Stream.fromFuture(fetchConfig());
    }

    if (!FirebaseBootstrap.isReady)
      return Stream.value(const BannerConfigModel());

    return _db
        .collection(_configCollection)
        .doc(_configDoc)
        .snapshots()
        .map(BannerConfigModel.fromFirestore);
  }

  static Future<BannerConfigModel> fetchConfig() async {
    final bool useSupabase = DoctorPatientCutoverFlag.isEnabled ||
        FirestoreForbiddenGuard.isForbidden;
    if (useSupabase) {
      if (SupabaseBootstrap.isReady) {
        try {
          final res = await SupabaseBootstrap.client
              .from('system_config')
              .select('config_value')
              .eq('config_key', 'promoted_ads')
              .maybeSingle();
          if (res != null && res['config_value'] is Map) {
            return BannerConfigModel.fromMap(
              Map<String, dynamic>.from(res['config_value'] as Map),
            );
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[BannerConfigService] Supabase fetchConfig error: $e');
        }
      }
      return const BannerConfigModel();
    }

    if (!FirebaseBootstrap.isReady) return const BannerConfigModel();

    try {
      final snap =
          await _db.collection(_configCollection).doc(_configDoc).get();
      return BannerConfigModel.fromFirestore(snap);
    } catch (e) {
      if (kDebugMode) debugPrint('[BannerConfigService] fetchConfig error: $e');
      return const BannerConfigModel();
    }
  }
}
