import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/services/promoted_ads_service.dart';
import 'package:medibond/core/storage/s3_storage_service.dart';
import 'package:medibond/core/storage/storage_feature_flag.dart';
import 'package:medibond/core/storage/storage_service.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

class TestS3StorageService extends S3StorageService {
  bool shouldFailUpload = false;
  int uploadCallCount = 0;
  int deleteCallCount = 0;
  final List<String> deletedKeys = [];

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

  setUp(() {
    testS3 = TestS3StorageService();
    PromotedAdsService.s3Override = testS3;
    StorageFeatureFlag.debugOverride = true;
    SupabaseBootstrap.isReady = false;
  });

  tearDown(() {
    PromotedAdsService.s3Override = null;
    StorageFeatureFlag.debugOverride = null;
    SupabaseBootstrap.isReady = false;
  });

  group('PromotedAdsService S3 ordering (no database)', () {
  final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

    test('createDraftAd requires Supabase before persisting', () async {
      await expectLater(
        PromotedAdsService.createDraftAd(
          providerType: 'doctor',
          providerId: 'provider_doc_1',
          title: 'Promo Ad',
          description: 'Comprehensive healthcare for families',
          imageBytes: imageBytes,
          ctaLabel: 'Book Now',
          durationHours: 24,
          useS3Override: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(testS3.deleteCallCount, 0);
    });

    test(
      'Without Supabase client, draft creation fails before S3 delete',
      () async {
        testS3.shouldFailUpload = true;
        await expectLater(
          PromotedAdsService.createDraftAd(
            providerType: 'doctor',
            providerId: 'provider_doc_1',
            title: 'Promo Ad',
            description: 'Comprehensive healthcare for families',
            imageBytes: imageBytes,
            ctaLabel: 'Book Now',
            durationHours: 24,
            oldImageKey: 'old/banner.jpg',
            useS3Override: true,
          ),
          throwsA(isA<StateError>()),
        );
        expect(testS3.deleteCallCount, 0);
      },
    );
  });
}