import 'package:flutter/material.dart';

/// Stomach silhouette for Stomach & Digestion specialty tiles.
class StomachIcon extends StatelessWidget {
  const StomachIcon({
    super.key,
    required this.size,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  static const assetPath = 'assets/images/stomach_digestion_icon.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => CustomPaint(
        size: Size.square(size),
        painter: _StomachIconPainter(color: color),
      ),
    );
  }
}

class _StomachIconPainter extends CustomPainter {
  const _StomachIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final path = Path();

    // Esophagus inlet.
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.36, h * 0.02, w * 0.18, h * 0.13),
        Radius.circular(w * 0.03),
      ),
    );

    // Main stomach body (J-shape).
    path.moveTo(w * 0.34, h * 0.15);
    path.cubicTo(w * 0.14, h * 0.18, w * 0.08, h * 0.40, w * 0.16, h * 0.58);
    path.cubicTo(w * 0.20, h * 0.68, w * 0.18, h * 0.78, w * 0.14, h * 0.88);
    path.cubicTo(w * 0.22, h * 0.84, w * 0.30, h * 0.80, w * 0.38, h * 0.82);
    path.cubicTo(w * 0.58, h * 0.88, w * 0.82, h * 0.78, w * 0.90, h * 0.56);
    path.cubicTo(w * 0.98, h * 0.34, w * 0.82, h * 0.14, w * 0.56, h * 0.12);
    path.cubicTo(w * 0.44, h * 0.11, w * 0.38, h * 0.13, w * 0.34, h * 0.15);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StomachIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
