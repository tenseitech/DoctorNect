import 'package:flutter/material.dart';

/// Centers ambulance pages on wide screens.
class AmbulancePageLayout extends StatelessWidget {
  const AmbulancePageLayout({
    super.key,
    required this.child,
    this.maxWidth = 960,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
