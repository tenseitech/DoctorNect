import 'package:flutter/material.dart';

/// Small unread/request indicator dot for nav tabs and action buttons.
class NavRequestDot extends StatelessWidget {
  const NavRequestDot({
    super.key,
    this.color = const Color(0xFFEF4444),
    this.size = 8,
    this.borderColor = Colors.white,
    this.borderWidth = 1.5,
  });

  final Color color;
  final double size;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
    );
  }
}

class IconWithRequestDot extends StatelessWidget {
  const IconWithRequestDot({
    super.key,
    required this.icon,
    required this.showDot,
    this.dotColor = const Color(0xFFEF4444),
  });

  final Widget icon;
  final bool showDot;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    if (!showDot) return icon;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          top: -2,
          child: NavRequestDot(color: dotColor, size: 8),
        ),
      ],
    );
  }
}
