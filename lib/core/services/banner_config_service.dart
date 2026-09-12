import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';
import '../models/banner_config_model.dart';

/// Read-only promoted-ads banner config (written by Super Admin console).
abstract final class BannerConfigService {
  static const String _configCollection = 'system_config';
  static const String _configDoc = 'promoted_ads';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Stream<BannerConfigModel> streamConfig() {
    if (!FirebaseBootstrap.isReady) return Stream.value(const BannerConfigModel());

    return _db
        .collection(_configCollection)
        .doc(_configDoc)
        .snapshots()
        .map(BannerConfigModel.fromFirestore);
  }

  static Future<BannerConfigModel> fetchConfig() async {
    if (!FirebaseBootstrap.isReady) return const BannerConfigModel();

    try {
      final snap = await _db.collection(_configCollection).doc(_configDoc).get();
      return BannerConfigModel.fromFirestore(snap);
    } catch (e) {
      if (kDebugMode) debugPrint('[BannerConfigService] fetchConfig error: $e');
      return const BannerConfigModel();
    }
  }
}
