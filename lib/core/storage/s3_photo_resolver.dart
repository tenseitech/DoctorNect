import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 's3_presign_api.dart';

class S3CachedUrl {
  final String url;
  final DateTime expiresAt;

  const S3CachedUrl({required this.url, required this.expiresAt});

  bool isExpiringSoon([Duration threshold = const Duration(minutes: 5)]) {
    return DateTime.now().isAfter(expiresAt.subtract(threshold));
  }
}

/// Shared resolver that caches S3 presigned URLs in-memory, batches requests
/// (max 20 per getS3DownloadUrls call) across the screen build frame, and
/// proactively refreshes ~5 minutes before URL expiration.
class S3PhotoResolver {
  static S3PhotoResolver instance = S3PhotoResolver();

  S3PhotoResolver({S3PresignApi? api, http.Client? httpClient})
      : _api = api ?? S3PresignApi.instance,
        _httpClient = httpClient ?? http.Client();

  final S3PresignApi _api;
  final http.Client _httpClient;

  final Map<String, S3CachedUrl> _cache = {};
  final Map<String, List<Completer<String?>>> _pendingCompleters = {};
  bool _flushScheduled = false;

  /// Default expiration assumed if not specified (backend batch default is 3600 seconds).
  static const Duration defaultUrlTtl = Duration(seconds: 3600);

  /// Resolves an objectKey to a presigned download URL.
  /// If already in cache and not expiring soon, returns immediately.
  /// Otherwise, queues for the next microtask batch.
  Future<String?> resolveUrl(String objectKey,
      {bool forceRefresh = false}) async {
    final cleanKey = objectKey.trim();
    if (cleanKey.isEmpty) return null;

    if (!forceRefresh) {
      final cached = _cache[cleanKey];
      if (cached != null && !cached.isExpiringSoon()) {
        return cached.url;
      }
    }

    final completer = Completer<String?>();
    final completers = _pendingCompleters.putIfAbsent(cleanKey, () => []);
    completers.add(completer);

    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flushPending);
    }

    return completer.future;
  }

  void _flushPending() async {
    _flushScheduled = false;
    if (_pendingCompleters.isEmpty) return;

    final keysToResolve = _pendingCompleters.keys.toList();
    final completersMap =
        Map<String, List<Completer<String?>>>.from(_pendingCompleters);
    _pendingCompleters.clear();

    // Chunk into batches of at most 20 keys (Cloud Function limit)
    for (int i = 0; i < keysToResolve.length; i += 20) {
      final chunk = keysToResolve.sublist(
        i,
        i + 20 > keysToResolve.length ? keysToResolve.length : i + 20,
      );

      try {
        final resolvedUrls = await _api.getDownloadUrls(objectKeys: chunk);
        final now = DateTime.now();

        for (final key in chunk) {
          final url = resolvedUrls[key];
          if (url != null && url.isNotEmpty) {
            _cache[key] = S3CachedUrl(
              url: url,
              expiresAt: now.add(defaultUrlTtl),
            );
          }
          final list = completersMap[key];
          if (list != null) {
            for (final c in list) {
              if (!c.isCompleted) c.complete(url);
            }
          }
        }
      } catch (e) {
        for (final key in chunk) {
          final list = completersMap[key];
          if (list != null) {
            for (final c in list) {
              if (!c.isCompleted) c.complete(null);
            }
          }
        }
      }
    }
  }

  /// Invalidates a key in the cache (e.g. after 403).
  void invalidate(String objectKey) {
    _cache.remove(objectKey.trim());
  }

  /// Clears the in-memory cache completely.
  void clear() {
    _cache.clear();
  }

  /// Direct cache read for synchronous checks/tests.
  S3CachedUrl? getCached(String objectKey) => _cache[objectKey.trim()];

  /// Injects cached URL for testing.
  @visibleForTesting
  void setCachedForTesting(String objectKey, S3CachedUrl cached) {
    _cache[objectKey.trim()] = cached;
  }
}

/// ImageKey identifying an S3 image in Flutter's ImageCache by its canonical objectKey.
/// Crucial: The cache key is purely the objectKey (never the presigned URL).
@immutable
class S3KeyImageKey {
  final String objectKey;
  final double scale;

  const S3KeyImageKey(this.objectKey, {this.scale = 1.0});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is S3KeyImageKey &&
        other.objectKey == objectKey &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(objectKey, scale);

  @override
  String toString() => 'S3KeyImageKey($objectKey, scale: $scale)';
}

/// ImageProvider that loads an S3 image by its canonical objectKey, resolves
/// the presigned URL using [S3PhotoResolver], and retries once on 403/expired URL.
class S3KeyImageProvider extends ImageProvider<S3KeyImageKey> {
  final String objectKey;
  final double scale;
  final S3PhotoResolver resolver;
  final http.Client? httpClient;

  S3KeyImageProvider(
    this.objectKey, {
    this.scale = 1.0,
    S3PhotoResolver? resolver,
    this.httpClient,
  }) : resolver = resolver ?? S3PhotoResolver.instance;

  @override
  Future<S3KeyImageKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<S3KeyImageKey>(
        S3KeyImageKey(objectKey, scale: scale));
  }

  @override
  ImageStreamCompleter loadImage(
      S3KeyImageKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.objectKey,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<S3KeyImageKey>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
      S3KeyImageKey key, ImageDecoderCallback decode) async {
    final client = httpClient ?? resolver._httpClient;

    // 1. Resolve URL from resolver
    String? url = await resolver.resolveUrl(key.objectKey);
    if (url == null || url.isEmpty) {
      throw StateError('Could not resolve S3 URL for key: ${key.objectKey}');
    }

    // 2. Fetch bytes
    http.Response? response;
    try {
      response = await client.get(Uri.parse(url));
    } catch (_) {}

    // 3. On 403 (or expired signature), retry ONCE with a fresh URL
    if (response == null || response.statusCode == 403) {
      resolver.invalidate(key.objectKey);
      url = await resolver.resolveUrl(key.objectKey, forceRefresh: true);
      if (url != null && url.isNotEmpty) {
        try {
          response = await client.get(Uri.parse(url));
        } catch (_) {}
      }
    }

    if (response == null ||
        response.statusCode != 200 ||
        response.bodyBytes.isEmpty) {
      throw StateError(
        'Failed to load S3 image bytes for ${key.objectKey}: HTTP ${response?.statusCode ?? "no response"}',
      );
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
    return decode(buffer);
  }
}
