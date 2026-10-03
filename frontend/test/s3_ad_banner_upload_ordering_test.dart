import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/services/promoted_ads_service.dart';
import 'package:medibond/core/storage/s3_storage_service.dart';
import 'package:medibond/core/storage/storage_feature_flag.dart';
import 'package:medibond/core/storage/storage_service.dart';

class FailingFirestore extends FakeFirebaseFirestore {
  bool failOperations = false;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (failOperations) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Simulated Firestore connection error',
      );
    }
    return super.collection(collectionPath);
  }
}

class TestS3StorageService extends S3StorageService {
  bool shouldFailUpload = false;
  int uploadCallCount = 0;
  int deleteCallCount = 0;
  final List<String> deletedKeys = [];
  String? lastUploadedPurpose;
  String? lastUploadedParentId;
  String? lastUploadedFileName;

  @override
  Future<StorageUploadResult> uploadBytes({
    required String purpose,
    required String parentId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    uploadCallCount++;
    lastUploadedPurpose = purpose;
    lastUploadedParentId = parentId;
    lastUploadedFileName = fileName;

    if (shouldFailUpload) {
      throw Exception('Simulated S3 upload failure');
    }

    final key = '$purpose/$parentId/$fileName';
    return StorageUploadResult(
      objectKey: key,
      downloadUrl: 'https://s3.example.com/$key',
      provider: 's3',
    );
  }

  @override
  Future<bool> deleteObject(String keyOrUrl) async {
    deleteCallCount++;
    deletedKeys.add(keyOrUrl);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestS3StorageService testS3;
  late FailingFirestore fakeFirestore;
  late Directory tempDir;

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    testS3 = TestS3StorageService();
    fakeFirestore = FailingFirestore();

    PromotedAdsService.firestoreOverride = fakeFirestore;
    PromotedAdsService.s3Override = testS3;

    StorageFeatureFlag.debugOverride = true;

    tempDir = Directory.systemTemp.createTempSync('s3_ad_ordering_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() {
    PromotedAdsService.firestoreOverride = null;
    PromotedAdsService.s3Override = null;
    StorageFeatureFlag.debugOverride = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('PromotedAdsService.createDraftAd S3 ordering', () {
    const providerId = 'provider_doc_1';
    const oldKey = 'promoted_ads/provider_doc_1/ad_old/banner.jpg';
    final imageBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

    test('Success: S3 upload -> Firestore doc set -> Old S3 banner deleted',
        () async {
      final ad = await PromotedAdsService.createDraftAd(
        providerType: 'doctor',
        providerId: providerId,
        title: 'New Clinic Opening',
        description: 'Comprehensive healthcare for families',
        imageBytes: imageBytes,
        ctaLabel: 'Book Now',
        durationHours: 24,
        oldImageKey: oldKey,
        useS3Override: true,
      );

      expect(ad.status, 'draft');
      expect(ad.imageStorage, 's3');
      expect(ad.imageKey, startsWith('ad_banner/'));
      expect(testS3.uploadCallCount, 1);
      expect(testS3.lastUploadedPurpose, 'ad_banner');
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, contains(oldKey));

      final doc =
          await fakeFirestore.collection('promotedAds').doc(ad.adId).get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['imageKey'], ad.imageKey);
      expect(doc.data()?['imageStorage'], 's3');
    });

    test('Firestore fails -> Old S3 banner is NOT deleted', () async {
      fakeFirestore.failOperations = true;

      await expectLater(
        PromotedAdsService.createDraftAd(
          providerType: 'doctor',
          providerId: providerId,
          title: 'Failing Promo',
          description: 'Comprehensive healthcare for families',
          imageBytes: imageBytes,
          ctaLabel: 'Book Now',
          durationHours: 24,
          oldImageKey: oldKey,
          useS3Override: true,
        ),
        throwsA(isA<FirebaseException>()),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);
      expect(testS3.deletedKeys, isEmpty);
    });

    test(
        'S3 upload fails -> Firestore not written and Old S3 banner is NOT deleted',
        () async {
      testS3.shouldFailUpload = true;

      await expectLater(
        PromotedAdsService.createDraftAd(
          providerType: 'doctor',
          providerId: providerId,
          title: 'Failing Upload Promo',
          description: 'Comprehensive healthcare for families',
          imageBytes: imageBytes,
          ctaLabel: 'Book Now',
          durationHours: 24,
          oldImageKey: oldKey,
          useS3Override: true,
        ),
        throwsException,
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);

      final snapshot = await fakeFirestore.collection('promotedAds').get();
      expect(snapshot.docs, isEmpty);
    });
  });

  group('PromotedAdsService.updateAdBanner S3 ordering', () {
    const adId = 'ad_existing_777';
    const providerId = 'provider_lab_1';
    const oldKey = 'promoted_ads/provider_lab_1/ad_existing_777/old_banner.jpg';
    final imageBytes = Uint8List.fromList([10, 20, 30, 40, 50]);

    setUp(() async {
      await fakeFirestore.collection('promotedAds').doc(adId).set({
        'adId': adId,
        'providerId': providerId,
        'providerType': 'lab',
        'title': 'Existing Lab Ad',
        'description': 'Diagnostic tests at home',
        'imageUrl': 'https://s3.example.com/$oldKey',
        'imageKey': oldKey,
        'imageStorage': 's3',
        'ctaLabel': 'Book Test',
        'durationHours': 72,
        'amountPaid': 750,
        'paymentStatus': 'pending',
        'status': 'draft',
      });
    });

    test('Success: S3 upload -> Firestore update -> Old S3 banner deleted',
        () async {
      final updated = await PromotedAdsService.updateAdBanner(
        adId: adId,
        providerId: providerId,
        imageBytes: imageBytes,
        oldImageKey: oldKey,
        useS3Override: true,
      );

      expect(updated.imageStorage, 's3');
      expect(updated.imageKey, 'ad_banner/$adId/banner.jpg');
      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, contains(oldKey));

      final doc = await fakeFirestore.collection('promotedAds').doc(adId).get();
      expect(doc.data()?['imageKey'], 'ad_banner/$adId/banner.jpg');
      expect(doc.data()?['imageStorage'], 's3');
    });

    test('Firestore fails -> Old S3 banner is NOT deleted', () async {
      fakeFirestore.failOperations = true;

      await expectLater(
        PromotedAdsService.updateAdBanner(
          adId: adId,
          providerId: providerId,
          imageBytes: imageBytes,
          oldImageKey: oldKey,
          useS3Override: true,
        ),
        throwsA(isA<FirebaseException>()),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);
      expect(testS3.deletedKeys, isEmpty);
    });

    test(
        'S3 upload fails -> Firestore not updated and Old S3 banner is NOT deleted',
        () async {
      testS3.shouldFailUpload = true;

      await expectLater(
        PromotedAdsService.updateAdBanner(
          adId: adId,
          providerId: providerId,
          imageBytes: imageBytes,
          oldImageKey: oldKey,
          useS3Override: true,
        ),
        throwsException,
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);

      final doc = await fakeFirestore.collection('promotedAds').doc(adId).get();
      expect(doc.data()?['imageKey'], oldKey);
    });
  });
}
