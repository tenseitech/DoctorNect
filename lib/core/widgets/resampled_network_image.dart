import 'package:flutter/material.dart';

/// Downsamples remote bitmaps to the on-screen pixel size before decode (Play memory guidance).
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
    if (cacheW == null && cacheH == null) {
      return NetworkImage(url);
    }
    return ResizeImage(
      NetworkImage(url),
      width: cacheW,
      height: cacheH,
    );
  }
}

/// [Image.network] with [cacheWidth] / [cacheHeight] derived from layout size.
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
    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      cacheWidth: ResampledNetworkImage.cacheDimension(width, context),
      cacheHeight: ResampledNetworkImage.cacheDimension(height, context),
    );
  }
}
