import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';
import '../models/promoted_ad_model.dart';
import '../security/input_sanitize.dart';
import '../models/banner_config_model.dart';
import 'banner_config_service.dart';
import '../storage/s3_storage_service.dart';
import '../storage/storage_feature_flag.dart';

abstract final class PromotedAdsService {
  static final _firestore = FirebaseFirestore.instance;
  static const _collection = 'promotedAds';

  static String _generateAdId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = math.Random();
    return String.fromCharCodes(Iterable.generate(
      20,
      (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
    ));
  }

  @visibleForTesting
  static FirebaseFirestore? firestoreOverride;
  static FirebaseFirestore get _db => firestoreOverride ?? _firestore;

  @visibleForTesting
  static S3StorageService? s3Override;
  static S3StorageService get _s3 => s3Override ?? S3StorageService.instance;

  /// Default pricing map in INR: 1 Day, 3 Days, 1 Week, 1 Month
  static const Map<int, int> defaultPricingTiers = {
    24: 300,
    72: 750,
    168: 1500,
    720: 5000,
  };

  /// Backwards compatibility pricingTiers getter
  static Map<int, int> get pricingTiers => defaultPricingTiers;

  /// Fetches real-time pricing for a given duration in hours from Super Admin config
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

  /// Uploads ad banner image bytes to Firebase Storage and returns public URL.
  static Future<String> uploadAdImage(
    String providerId,
    String adId,
    Uint8List bytes,
  ) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('Firebase is not initialized.');
    }
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
    final ref = FirebaseStorage.instance.ref(
      'promoted_ads/$safeProvider/$safeAd.jpg',
    );
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  /// 1. Create a draft promoted ad in Firestore with status 'draft'
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

    final amountPaid = customAmountPaid ?? pricingTiers[durationHours] ?? 300;
    final adId = adIdOverride ?? _generateAdId();

    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;
    String imageUrl = '';
    String? imageKey;
    String? imageStorage;

    if (useS3) {
      // 1. Upload to S3
      final uploadResult = await _s3.uploadBytes(
        purpose: 'ad_banner',
        parentId: adId,
        fileName: 'banner.jpg',
        contentType: 'image/jpeg',
        bytes: imageBytes,
      );
      imageKey = uploadResult.objectKey;
      imageUrl = uploadResult.downloadUrl ?? '';
      imageStorage = 's3';
    } else {
      // Legacy Firebase upload
      imageUrl = await uploadAdImage(providerId, adId, imageBytes);
      imageStorage = 'firebase';
    }

    final adMap = {
      'adId': adId,
      'providerType': providerType.toLowerCase(),
      'providerId': providerId,
      'title': safeTitle,
      'description': safeDescription,
      'imageUrl': imageUrl,
      if (imageKey != null) 'imageKey': imageKey,
      'imageStorage': imageStorage,
      'ctaLabel': safeCta,
      'durationHours': durationHours,
      'amountPaid': amountPaid,
      if (targetCity != null && targetCity.isNotEmpty)
        'targetCity': InputSanitize.plainText(targetCity, maxLength: 80),
      if (targetCities != null && targetCities.isNotEmpty)
        'targetCities': targetCities
            .map((c) => InputSanitize.plainText(c, maxLength: 80))
            .where((c) => c.isNotEmpty)
            .take(20)
            .toList(),
      'paymentStatus': 'pending',
      'status': 'draft',
      'createdAt': FieldValue.serverTimestamp(),
    };

    // 2. Firestore write
    final docRef = _db.collection(_collection).doc(adId);
    await docRef.set(adMap);

    // 3. Delete old S3 object ONLY after new upload AND Firestore write succeed
    if (useS3 &&
        oldImageKey != null &&
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

    final docSnap = await docRef.get();
    return PromotedAdModel.fromFirestore(docSnap);
  }

  /// Updates the banner image of an existing ad.
  /// Strict ordering:
  /// 1. Upload new banner image (to S3 if enabled, or Firebase Storage if disabled).
  /// 2. Update Firestore document.
  /// 3. Delete old S3 object ONLY AFTER both upload AND Firestore write succeed.
  static Future<PromotedAdModel> updateAdBanner({
    required String adId,
    required String providerId,
    required Uint8List imageBytes,
    String? oldImageKey,
    String? oldImageStorage,
    bool? useS3Override,
  }) async {
    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;

    String imageUrl = '';
    String? newImageKey;
    String? newImageStorage;

    if (useS3) {
      // 1. Upload to S3
      final uploadResult = await _s3.uploadBytes(
        purpose: 'ad_banner',
        parentId: adId,
        fileName: 'banner.jpg',
        contentType: 'image/jpeg',
        bytes: imageBytes,
      );
      newImageKey = uploadResult.objectKey;
      imageUrl = uploadResult.downloadUrl ?? '';
      newImageStorage = 's3';

      // 2. Firestore update
      final docRef = _db.collection(_collection).doc(adId);
      await docRef.update({
        'imageUrl': imageUrl,
        'imageKey': newImageKey,
        'imageStorage': newImageStorage,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Delete old S3 object ONLY after both upload AND Firestore update succeeded
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

      final docSnap = await docRef.get();
      return PromotedAdModel.fromFirestore(docSnap);
    } else {
      // Legacy upload
      imageUrl = await uploadAdImage(providerId, adId, imageBytes);
      final docRef = _db.collection(_collection).doc(adId);
      await docRef.update({
        'imageUrl': imageUrl,
        'imageStorage': 'firebase',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final docSnap = await docRef.get();
      return PromotedAdModel.fromFirestore(docSnap);
    }
  }

  /// 2. Call Cloud Function to create Razorpay Order
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

  /// 3. Call Cloud Function to verify Razorpay Payment server-side
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

  /// 4. Query active ads for Patient Home screen banner carousel
  static Future<List<PromotedAdModel>> fetchActiveAds() async {
    if (!FirebaseBootstrap.isReady) return [];

    try {
      final snap = await _db
          .collection(_collection)
          .where('status', isEqualTo: 'active')
          .get();

      final now = DateTime.now();
      final activeAds = snap.docs
          .map((d) => PromotedAdModel.fromFirestore(d))
          .where((ad) => ad.endTime == null || ad.endTime!.isAfter(now))
          .toList();

      // Shuffle active ads fairly for fair carousel rotation
      activeAds.shuffle();
      return activeAds;
    } catch (e) {
      if (kDebugMode)
        debugPrint('[PromotedAdsService] fetchActiveAds error: $e');
      return [];
    }
  }

  /// Stream of active ads for real-time patient carousel updates (respects Super Admin config.enabled)
  static Stream<List<PromotedAdModel>> streamActiveAds() {
    if (!FirebaseBootstrap.isReady && firestoreOverride == null) return Stream.value([]);

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

    final adsSub = _db
        .collection(_collection)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snap) {
          lastAds = snap.docs
              .map((d) => PromotedAdModel.fromFirestore(d))
              .toList();
          emit();
        }, onError: (_) => emit());

    controller.onCancel = () {
      configSub.cancel();
      adsSub.cancel();
    };

    return controller.stream;
  }

  /// 5. Query provider's own ads for "My Ads" dashboard view
  static Stream<List<PromotedAdModel>> streamProviderAds(String providerId) {
    if ((!FirebaseBootstrap.isReady && firestoreOverride == null) || providerId.isEmpty)
      return Stream.value([]);
    return _db
        .collection(_collection)
        .where('providerId', isEqualTo: providerId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => PromotedAdModel.fromFirestore(d))
              .toList();
          list.sort(
            (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
              a.createdAt ?? DateTime.now(),
            ),
          );
          return list;
        });
  }
}
