import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../supabase/supabase_bootstrap.dart';
import '../supabase/supabase_stream_table.dart';
import '../models/promoted_ad_model.dart';
import '../security/input_sanitize.dart';
import '../models/banner_config_model.dart';
import 'banner_config_service.dart';
import '../storage/s3_storage_service.dart';
import '../storage/storage_feature_flag.dart';

abstract final class PromotedAdsService {
  static String _generateAdId() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = math.Random();
    return String.fromCharCodes(Iterable.generate(
      20,
      (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
    ));
  }

  @visibleForTesting
  static S3StorageService? s3Override;
  static S3StorageService get _s3 => s3Override ?? S3StorageService.instance;

  static const Map<int, int> defaultPricingTiers = {
    24: 300,
    72: 750,
    168: 1500,
    720: 5000,
  };

  static Map<int, int> get pricingTiers => defaultPricingTiers;

  static Future<int> getDynamicPlanPrice(int durationHours) async {
    try {
      final config = await BannerConfigService.fetchConfig();
      return config.pricingTiers[durationHours] ??
          defaultPricingTiers[durationHours] ??
          300;
    } catch (_) {
      return defaultPricingTiers[durationHours] ?? 300;
    }
  }

  static Future<String> uploadAdImage(
    String providerId,
    String adId,
    Uint8List bytes,
  ) async {
    final sizeErr = InputSanitize.validateUploadBytes(
      byteLength: bytes.length,
      maxBytes: InputSanitize.maxImageBytes,
      field: 'Banner image',
    );
    if (sizeErr != null) throw ArgumentError(sizeErr);
    final safeProvider = InputSanitize.fileName(
      providerId,
      fallback: 'provider',
    );
    final safeAd = InputSanitize.fileName(adId, fallback: 'ad');
    final uploadResult = await _s3.uploadBytes(
      purpose: 'promoted_ads/$safeProvider',
      parentId: safeAd,
      fileName: 'banner.jpg',
      contentType: 'image/jpeg',
      bytes: bytes,
    );
    return uploadResult.downloadUrl ?? '';
  }

  static Future<PromotedAdModel> createDraftAd({
    required String providerType,
    required String providerId,
    required String title,
    required String description,
    required Uint8List imageBytes,
    required String ctaLabel,
    required int durationHours,
    String? targetCity,
    List<String>? targetCities,
    num? customAmountPaid,
    String? oldImageKey,
    String? oldImageStorage,
    String? adIdOverride,
    bool? useS3Override,
  }) async {
    final safeTitle = InputSanitize.plainText(
      title,
      maxLength: InputSanitize.maxAdTitleLength,
    );
    final safeDescription = InputSanitize.plainText(
      description,
      maxLength: InputSanitize.maxAdDescriptionLength,
    );
    final safeCta = InputSanitize.plainText(ctaLabel, maxLength: 40);
    if (safeTitle.length < 3 || safeDescription.length < 10) {
      throw ArgumentError('Title and description failed validation.');
    }

    if (!SupabaseBootstrap.isReady) {
      throw StateError(
        'Cannot create promoted ad: database connection is not ready.',
      );
    }

    final amountPaid = customAmountPaid ?? pricingTiers[durationHours] ?? 300;
    final adId = adIdOverride ?? _generateAdId();

    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;
    String imageUrl = '';
    String? imageKey;
    String imageStorage = 's3';

    if (useS3) {
      final uploadResult = await _s3.uploadBytes(
        purpose: 'ad_banner',
        parentId: adId,
        fileName: 'banner.jpg',
        contentType: 'image/jpeg',
        bytes: imageBytes,
      );
      imageKey = uploadResult.objectKey;
      imageUrl = uploadResult.downloadUrl ?? '';
    } else {
      imageUrl = await uploadAdImage(providerId, adId, imageBytes);
      imageStorage = 'firebase';
    }

    final supabasePayload = {
      'ad_id': adId,
      'provider_type': providerType.toLowerCase(),
      'provider_id': providerId,
      'title': safeTitle,
      'description': safeDescription,
      'image_url': imageUrl,
      if (imageKey != null) 'image_s3_key': imageKey,
      'image_storage_provider': imageStorage,
      'cta_label': safeCta,
      'duration_hours': durationHours,
      'amount_paid': amountPaid,
      if (targetCity != null && targetCity.isNotEmpty)
        'target_city': InputSanitize.plainText(targetCity, maxLength: 80),
      'payment_status': 'pending',
      'status': 'draft',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await SupabaseBootstrap.client
        .from('promoted_ads')
        .upsert(supabasePayload, onConflict: 'ad_id');

    if (oldImageKey != null &&
        oldImageKey.trim().isNotEmpty &&
        oldImageKey.trim() != imageKey &&
        (oldImageStorage == null || oldImageStorage == 's3')) {
      try {
        await _s3.deleteObject(oldImageKey.trim());
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PromotedAdsService] failed to delete old S3 banner: $e');
        }
      }
    }

    return PromotedAdModel.fromRow(supabasePayload);
  }

  static Future<PromotedAdModel> updateAdBanner({
    required String adId,
    required String providerId,
    required Uint8List imageBytes,
    String? oldImageKey,
    String? oldImageStorage,
    bool? useS3Override,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      throw StateError(
        'Cannot update promoted ad: database connection is not ready.',
      );
    }

    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;

    String imageUrl = '';
    String? newImageKey;
    String newImageStorage = 's3';

    if (useS3) {
      final uploadResult = await _s3.uploadBytes(
        purpose: 'ad_banner',
        parentId: adId,
        fileName: 'banner.jpg',
        contentType: 'image/jpeg',
        bytes: imageBytes,
      );
      newImageKey = uploadResult.objectKey;
      imageUrl = uploadResult.downloadUrl ?? '';
    } else {
      imageUrl = await uploadAdImage(providerId, adId, imageBytes);
      newImageStorage = 'firebase';
    }

    await SupabaseBootstrap.client.from('promoted_ads').update({
      'image_url': imageUrl,
      if (newImageKey != null) 'image_s3_key': newImageKey,
      'image_storage_provider': newImageStorage,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('ad_id', adId);

    if (oldImageKey != null &&
        oldImageKey.trim().isNotEmpty &&
        oldImageKey.trim() != newImageKey &&
        (oldImageStorage == null || oldImageStorage == 's3')) {
      try {
        await _s3.deleteObject(oldImageKey.trim());
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PromotedAdsService] failed to delete old S3 banner: $e');
        }
      }
    }

    final res = await SupabaseBootstrap.client
        .from('promoted_ads')
        .select()
        .eq('ad_id', adId)
        .maybeSingle();
    if (res != null) {
      return PromotedAdModel.fromRow(res);
    }
    throw StateError('Ad not found after banner update.');
  }

  static Future<Map<String, dynamic>> createRazorpayOrder({
    required String adId,
    required int durationHours,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final callable = functions.httpsCallable('createRazorpayOrder');

    final result = await callable.call({
      'adId': adId,
      'durationHours': durationHours,
    });

    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<bool> verifyRazorpayPayment({
    required String adId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final callable = functions.httpsCallable('verifyRazorpayPayment');

    final result = await callable.call({
      'adId': adId,
      'orderId': orderId,
      'paymentId': paymentId,
      'signature': signature,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    return data['success'] == true;
  }

  static Future<List<PromotedAdModel>> fetchActiveAds() async {
    if (!SupabaseBootstrap.isReady) return [];
    try {
      final res = await SupabaseBootstrap.client
          .from('promoted_ads')
          .select()
          .eq('status', 'active');
      final now = DateTime.now();
      final activeAds = (res as List)
          .map((d) => PromotedAdModel.fromRow(d as Map<String, dynamic>))
          .where((ad) => ad.endTime == null || ad.endTime!.isAfter(now))
          .toList();
      activeAds.shuffle();
      return activeAds;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PromotedAdsService] fetchActiveAds error: $e');
      }
      return [];
    }
  }

  static Stream<List<PromotedAdModel>> streamActiveAds() {
    if (!SupabaseBootstrap.isReady) return Stream.value([]);

    final controller = StreamController<List<PromotedAdModel>>.broadcast();
    BannerConfigModel lastConfig = const BannerConfigModel();
    List<PromotedAdModel> lastAds = [];

    void emit() {
      if (!lastConfig.enabled) {
        controller.add([]);
        return;
      }
      final now = DateTime.now();
      final active = lastAds
          .where((ad) => ad.endTime == null || ad.endTime!.isAfter(now))
          .take(
            lastConfig.maxActiveBanners > 0 ? lastConfig.maxActiveBanners : 10,
          )
          .toList();
      active.shuffle();
      controller.add(active);
    }

    final configSub = BannerConfigService.streamConfig().listen((config) {
      lastConfig = config;
      emit();
    }, onError: (_) => emit());

    final Stream<List<Map<String, dynamic>>> adsRows;
    if (SupabaseBootstrap.isProduction) {
      adsRows = streamTable(
        table: 'promoted_ads',
        primaryKey: ['ad_id'],
        filterColumn: 'status',
        filterValue: 'active',
      );
    } else {
      adsRows = SupabaseBootstrap.client
          .from('promoted_ads')
          .stream(primaryKey: ['ad_id']).eq('status', 'active');
    }

    final adsSub = adsRows.listen((rows) {
      lastAds = rows.map(PromotedAdModel.fromRow).toList();
      emit();
    }, onError: (_) => emit());

    controller.onCancel = () {
      configSub.cancel();
      adsSub.cancel();
    };

    return controller.stream;
  }

  static Stream<List<PromotedAdModel>> streamProviderAds(String providerId) {
    if (providerId.isEmpty) return Stream.value([]);
    if (!SupabaseBootstrap.isReady) return Stream.value([]);

    final Stream<List<Map<String, dynamic>>> rows;
    if (SupabaseBootstrap.isProduction) {
      rows = streamTable(
        table: 'promoted_ads',
        primaryKey: ['ad_id'],
        filterColumn: 'provider_id',
        filterValue: providerId,
      );
    } else {
      rows = SupabaseBootstrap.client
          .from('promoted_ads')
          .stream(primaryKey: ['ad_id']).eq('provider_id', providerId);
    }

    return rows.map((list) {
      final ads = list.map(PromotedAdModel.fromRow).toList();
      ads.sort(
        (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        ),
      );
      return ads;
    });
  }
}
