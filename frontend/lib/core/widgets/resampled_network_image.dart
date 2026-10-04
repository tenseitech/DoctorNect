import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Downsamples remote bitmaps to the on-screen pixel size before decode (Play memory guidance).
/// Uses [CachedNetworkImageProvider] so repeated loads are served from disk cache.
abstract final class ResampledNetworkImage {
  static int? cacheDimension(double? logicalSize, BuildContext context) {
    if (logicalSize == null || !logicalSize.isFinite || logicalSize <= 0) {
      return null;
    }
    return (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
  }

  static ImageProvider provider(
    String url, {
    required BuildContext context,
    double? width,
    double? height,
  }) {
    final cacheW = cacheDimension(width, context);
    final cacheH = cacheDimension(height, context);
    final base = CachedNetworkImageProvider(url);
    if (cacheW == null && cacheH == null) {
      return base;
    }
    return ResizeImage(base, width: cacheW, height: cacheH);
  }
}

/// [Image] with [cacheWidth] / [cacheHeight] derived from layout size,
/// backed by [CachedNetworkImage] for persistent disk caching.
class ResampledNetworkImageWidget extends StatelessWidget {
  const ResampledNetworkImageWidget({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheWidth: ResampledNetworkImage.cacheDimension(width, context),
      memCacheHeight: ResampledNetworkImage.cacheDimension(height, context),
    );
  }
}
