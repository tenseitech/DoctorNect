import 'package:flutter/foundation.dart';

import 'asset_webp_manifest.dart';

/// Platform-aware asset resolver.
///
/// On Web: Automatically swaps raster asset extensions to `.webp` when an
/// optimized WebP counterpart is registered in [kWebpAssets].
/// On Mobile/Desktop: Preserves the original asset path as-is.
abstract final class AssetResolver {
  /// Resolves [originalPath] for the active runtime platform.
  static String resolve(String originalPath) {
    return resolveFor(originalPath, isWeb: kIsWeb);
  }

  /// Resolves [path] for a specified web/non-web runtime flag.
  @visibleForTesting
  static String resolveFor(String path, {required bool isWeb}) {
    if (!isWeb) {
      return path;
    }
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1) {
      return path;
    }
    final candidate = '${path.substring(0, dotIndex)}.webp';
    if (kWebpAssets.contains(candidate)) {
      return candidate;
    }
    return path;
  }
}
