import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/banner_config_model.dart';
import '../supabase/supabase_bootstrap.dart';
import '../supabase/supabase_stream_table.dart';

/// Read-only promoted-ads banner config (written by Super Admin console).
abstract final class BannerConfigService {
  static Stream<BannerConfigModel> streamConfig() {
    if (!SupabaseBootstrap.isReady) {
      return Stream.value(const BannerConfigModel());
    }
    if (SupabaseBootstrap.isProduction) {
      return streamTable(
        table: 'system_config',
        primaryKey: ['config_key'],
        filterColumn: 'config_key',
        filterValue: 'promoted_ads',
      ).asyncMap((rows) async {
        if (rows.isEmpty) return fetchConfig();
        final raw = rows.first['config_value'];
        if (raw is Map) {
          return BannerConfigModel.fromMap(
            Map<String, dynamic>.from(raw),
          );
        }
        return fetchConfig();
      });
    }
    return SupabaseBootstrap.client
        .from('system_config')
        .stream(primaryKey: ['config_key'])
        .eq('config_key', 'promoted_ads')
        .map((rows) {
          if (rows.isEmpty) return const BannerConfigModel();
          final raw = rows.first['config_value'];
          if (raw is Map) {
            return BannerConfigModel.fromMap(
              Map<String, dynamic>.from(raw),
            );
          }
          return const BannerConfigModel();
        });
  }

  static Future<BannerConfigModel> fetchConfig() async {
    if (!SupabaseBootstrap.isReady) return const BannerConfigModel();
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
      if (kDebugMode) debugPrint('[BannerConfigService] fetchConfig error: $e');
    }
    return const BannerConfigModel();
  }
}
