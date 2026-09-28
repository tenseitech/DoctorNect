import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../storage/s3_photo_resolver.dart';
import 'resampled_network_image.dart';

/// Helper for resolving image providers across S3, legacy URLs, Base64 data URLs, and local files/memory.
abstract final class S3AwareImageProvider {
  static ImageProvider? resolveProvider({
    String? photoKey,
    String? photoStorage,
    String? legacyUrl,
    Uint8List? photoBytes,
    String? photoPath,
    BuildContext? context,
    double? width,
    double? height,
    double scale = 1.0,
  }) {
    // 1. In-memory bytes have highest priority (local offline/draft cache)
    if (photoBytes != null && photoBytes.isNotEmpty) {
      return MemoryImage(photoBytes, scale: scale);
    }

    // 2. On-device file path
    if (photoPath != null && photoPath.isNotEmpty && !kIsWeb) {
      try {
        final file = File(photoPath);
        if (file.existsSync()) {
          return FileImage(file, scale: scale);
        }
      } catch (_) {}
    }

    int? cacheW;
    int? cacheH;
    if (context != null) {
      cacheW = ResampledNetworkImage.cacheDimension(width, context);
      cacheH = ResampledNetworkImage.cacheDimension(height, context);
    }

    // 3. S3 canonical object key
    final isS3 = photoStorage == 's3' ||
        (photoKey != null &&
            photoKey.trim().isNotEmpty &&
            (photoStorage == null || photoStorage == 's3'));

    if (isS3 && photoKey != null && photoKey.trim().isNotEmpty) {
      final provider = S3KeyImageProvider(photoKey.trim(), scale: scale);
      if (cacheW != null || cacheH != null) {
        return ResizeImage(provider, width: cacheW, height: cacheH);
      }
      return provider;
    }

    // 4. Legacy URL or Base64 data URL
    final url = legacyUrl?.trim();
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('data:image')) {
        try {
          final commaIdx = url.indexOf(',');
          if (commaIdx != -1) {
            final b64 = url.substring(commaIdx + 1);
            final decoded = base64Decode(b64);
            return MemoryImage(decoded, scale: scale);
          }
        } catch (_) {}
      }

      final provider = NetworkImage(url, scale: scale);
      if (cacheW != null || cacheH != null) {
        return ResizeImage(provider, width: cacheW, height: cacheH);
      }
      return provider;
    }

    return null;
  }
}

/// Central S3-aware network image widget that supports S3 object keys, legacy network URLs,
/// Base64 data URLs, and local draft bytes with automated downsampling and 403-retry.
class S3AwareNetworkImage extends StatelessWidget {
  const S3AwareNetworkImage({
    super.key,
    this.photoKey,
    this.photoStorage,
    this.legacyUrl,
    this.photoBytes,
    this.photoPath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  final String? photoKey;
  final String? photoStorage;
  final String? legacyUrl;
  final Uint8List? photoBytes;
  final String? photoPath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final provider = S3AwareImageProvider.resolveProvider(
      photoKey: photoKey,
      photoStorage: photoStorage,
      legacyUrl: legacyUrl,
      photoBytes: photoBytes,
      photoPath: photoPath,
      context: context,
      width: width,
      height: height,
    );

    if (provider == null) {
      return SizedBox(
        width: width,
        height: height,
        child: errorWidget ?? placeholder ?? const SizedBox.shrink(),
      );
    }

    Widget imageWidget = Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return placeholder ??
            SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
      },
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: width,
          height: height,
          child: errorWidget ?? const Icon(Icons.broken_image_outlined, size: 24),
        );
      },
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
