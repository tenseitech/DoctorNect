import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medibond/core/storage/s3_photo_resolver.dart';
import 'package:medibond/core/storage/s3_presign_api.dart';
import 'package:medibond/core/widgets/s3_aware_network_image.dart';

class FakeS3PresignApi implements S3PresignApi {
  final List<List<String>> batchCalls = [];
  Map<String, String> urlsToReturn = {};
  int uploadUrlCalls = 0;
  int downloadUrlCalls = 0;
  int deleteObjectCalls = 0;

  @override
  Future<Map<String, String>> getDownloadUrls({
    required List<String> objectKeys,
  }) async {
    batchCalls.add(List<String>.from(objectKeys));
    final map = <String, String>{};
    for (final key in objectKeys) {
      map[key] =
          urlsToReturn[key] ?? 'https://s3.example.com/$key?presigned=true';
    }
    return map;
  }

  @override
  Future<S3UploadCredentials> getUploadUrl({
    required String purpose,
    required String parentId,
    required String fileName,
    required String contentType,
    required int sizeBytes,
  }) async {
    uploadUrlCalls++;
    return S3UploadCredentials(
      uploadUrl: 'https://s3.example.com/upload',
      objectKey: '$purpose/$parentId/$fileName',
    );
  }

  @override
  Future<S3DownloadResult> getDownloadUrl({
    required String objectKey,
    int expiresIn = 600,
  }) async {
    downloadUrlCalls++;
    return S3DownloadResult(
      url: 'https://s3.example.com/$objectKey',
      expiresIn: expiresIn,
    );
  }

  @override
  Future<bool> deleteObject({required String objectKey}) async {
    deleteObjectCalls++;
    return true;
  }
}

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._handler);
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  int callCount = 0;
  final List<Uri> requestedUris = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    requestedUris.add(request.url);
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeS3PresignApi fakeApi;
  late S3PhotoResolver resolver;

  // Minimal valid 1x1 PNG bytes for codec decode test
  final validPngBytes = Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    10,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    0,
    1,
    0,
    0,
    5,
    0,
    1,
    13,
    10,
    45,
    180,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130
  ]);

  setUp(() {
    fakeApi = FakeS3PresignApi();
    resolver = S3PhotoResolver(api: fakeApi);
  });

  group('S3PhotoResolver microtask batching and chunking', () {
    test(
        'Multiple requests within one microtask are batched into a single API call',
        () async {
      final f1 = resolver.resolveUrl('patients/p1/profile/profile.jpg');
      final f2 = resolver.resolveUrl('patients/p2/profile/profile.jpg');
      final f3 = resolver.resolveUrl('doctor_profiles/d1/profile/profile.jpg');

      final results = await Future.wait([f1, f2, f3]);

      expect(fakeApi.batchCalls.length, 1);
      expect(fakeApi.batchCalls[0].length, 3);
      expect(
          fakeApi.batchCalls[0],
          containsAll([
            'patients/p1/profile/profile.jpg',
            'patients/p2/profile/profile.jpg',
            'doctor_profiles/d1/profile/profile.jpg',
          ]));

      expect(results[0],
          'https://s3.example.com/patients/p1/profile/profile.jpg?presigned=true');
      expect(results[1],
          'https://s3.example.com/patients/p2/profile/profile.jpg?presigned=true');
      expect(results[2],
          'https://s3.example.com/doctor_profiles/d1/profile/profile.jpg?presigned=true');
    });

    test('Requests exceeding 20 keys are chunked into max-20 batches',
        () async {
      final keys = List.generate(25, (i) => 'patients/p$i/profile/profile.jpg');
      final futures = keys.map((k) => resolver.resolveUrl(k)).toList();

      final results = await Future.wait(futures);

      expect(fakeApi.batchCalls.length, 2);
      expect(fakeApi.batchCalls[0].length, 20);
      expect(fakeApi.batchCalls[1].length, 5);
      expect(results.length, 25);
    });
  });

  group('S3PhotoResolver memory caching and proactive refresh', () {
    test('Subsequent resolution of cached key does not call backend API',
        () async {
      const key = 'patients/cached_user/profile/profile.jpg';
      final url1 = await resolver.resolveUrl(key);
      expect(fakeApi.batchCalls.length, 1);

      fakeApi.batchCalls.clear();

      final url2 = await resolver.resolveUrl(key);
      expect(fakeApi.batchCalls.length, 0);
      expect(url2, equals(url1));
    });

    test(
        'Proactive refresh: key expiring within 5 minutes triggers fresh fetch',
        () async {
      const key = 'patients/expiring_user/profile/profile.jpg';
      const staleUrl = 'https://s3.example.com/stale-url';
      const freshUrl = 'https://s3.example.com/fresh-url';

      // Inject cached URL that expires in 2 minutes (< 5 min threshold)
      resolver.setCachedForTesting(
        key,
        S3CachedUrl(
          url: staleUrl,
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        ),
      );

      fakeApi.urlsToReturn[key] = freshUrl;

      final resolvedUrl = await resolver.resolveUrl(key);

      expect(fakeApi.batchCalls.length, 1);
      expect(resolvedUrl, freshUrl);
    });

    test('Key expiring in > 5 minutes returns cached URL without fetch',
        () async {
      const key = 'patients/valid_user/profile/profile.jpg';
      const validUrl = 'https://s3.example.com/valid-url';

      resolver.setCachedForTesting(
        key,
        S3CachedUrl(
          url: validUrl,
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        ),
      );

      final resolvedUrl = await resolver.resolveUrl(key);

      expect(fakeApi.batchCalls.length, 0);
      expect(resolvedUrl, validUrl);
    });
  });

  group('S3KeyImageKey cache identity', () {
    test(
        'Equality and hash code are strictly based on objectKey and scale (not presigned URL)',
        () {
      const key1 = S3KeyImageKey('patients/p1/profile/profile.jpg', scale: 1.0);
      const key2 = S3KeyImageKey('patients/p1/profile/profile.jpg', scale: 1.0);
      const keyDiffScale =
          S3KeyImageKey('patients/p1/profile/profile.jpg', scale: 2.0);
      const keyDiffObject =
          S3KeyImageKey('patients/p2/profile/profile.jpg', scale: 1.0);

      expect(key1, equals(key2));
      expect(key1.hashCode, equals(key2.hashCode));

      expect(key1, isNot(equals(keyDiffScale)));
      expect(key1, isNot(equals(keyDiffObject)));
    });
  });

  group('S3AwareImageProvider.resolveProvider', () {
    test('Resolves S3 key to S3KeyImageProvider', () {
      final provider = S3AwareImageProvider.resolveProvider(
        photoKey: 'patients/p1/profile/profile.jpg',
        photoStorage: 's3',
      );

      expect(provider, isA<S3KeyImageProvider>());
      final s3Provider = provider as S3KeyImageProvider;
      expect(s3Provider.objectKey, 'patients/p1/profile/profile.jpg');
    });

    test('Resolves legacy network URL to NetworkImage', () {
      final provider = S3AwareImageProvider.resolveProvider(
        legacyUrl: 'https://cdn.example.com/avatar.jpg',
        photoStorage: 'firebase',
      );

      expect(provider, isA<NetworkImage>());
      final netProvider = provider as NetworkImage;
      expect(netProvider.url, 'https://cdn.example.com/avatar.jpg');
    });

    test('Resolves Base64 data URI to MemoryImage', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      final base64Url = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      final provider = S3AwareImageProvider.resolveProvider(
        legacyUrl: base64Url,
      );

      expect(provider, isA<MemoryImage>());
      final memProvider = provider as MemoryImage;
      expect(memProvider.bytes, equals(bytes));
    });

    test('In-memory draft bytes take highest priority', () {
      final bytes = Uint8List.fromList([99, 88, 77]);
      final provider = S3AwareImageProvider.resolveProvider(
        photoBytes: bytes,
        photoKey: 'patients/p1/profile/profile.jpg',
        legacyUrl: 'https://example.com/old.jpg',
      );

      expect(provider, isA<MemoryImage>());
      expect((provider as MemoryImage).bytes, equals(bytes));
    });

    test('Returns null when no photo source is provided', () {
      final provider = S3AwareImageProvider.resolveProvider();
      expect(provider, isNull);
    });
  });

  group('S3KeyImageProvider 403 single retry', () {
    test(
        'Retries on HTTP 403 by invalidating cache and fetching a fresh presigned URL',
        () async {
      const key = 'patients/p_retry/profile/profile.jpg';
      const initialExpiredUrl = 'https://s3.example.com/expired-url';
      const refreshedUrl = 'https://s3.example.com/fresh-working-url';

      resolver.setCachedForTesting(
        key,
        S3CachedUrl(
          url: initialExpiredUrl,
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        ),
      );

      fakeApi.urlsToReturn[key] = refreshedUrl;

      int callCount = 0;
      final fakeClient = FakeHttpClient((request) async {
        callCount++;
        if (request.url.toString() == initialExpiredUrl) {
          // First attempt returns 403 Forbidden (e.g. expired URL)
          return http.Response('Forbidden', 403);
        } else if (request.url.toString() == refreshedUrl) {
          // Second attempt with fresh URL succeeds
          return http.Response.bytes(validPngBytes, 200,
              headers: {'content-type': 'image/png'});
        }
        return http.Response('Not Found', 404);
      });

      final provider = S3KeyImageProvider(
        key,
        resolver: resolver,
        httpClient: fakeClient,
      );

      final keyObj = await provider.obtainKey(ImageConfiguration.empty);
      expect(keyObj.objectKey, key);

      // Verify that after encountering 403 on the first call, it made a 2nd call with refreshed URL
      // We can directly call the private loader or simulate image loading
      final completer = provider.loadImage(
          keyObj, PaintingBinding.instance.instantiateImageCodecWithSize);

      var imageLoaded = false;
      var failed = false;
      completer.addListener(ImageStreamListener(
        (info, sync) {
          imageLoaded = true;
        },
        onError: (err, st) {
          failed = true;
        },
      ));

      // Wait a moment for async network + codec decoding
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(callCount, 2);
      expect(fakeClient.requestedUris[0].toString(), initialExpiredUrl);
      expect(fakeClient.requestedUris[1].toString(), refreshedUrl);
      expect(imageLoaded, isTrue);
      expect(failed, isFalse);
    });
  });
}
