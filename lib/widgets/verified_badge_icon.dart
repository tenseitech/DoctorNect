import 'package:flutter/material.dart';

/// Reusable green verified tick icon with tooltip shown for Super Admin verified professional accounts.
class VerifiedBadgeIcon extends StatelessWidget {
  const VerifiedBadgeIcon({
    super.key,
    this.size = 18,
    this.color = const Color(0xFF16A34A),
    this.tooltip = 'Verified by DoctorNect',
  });

  final double size;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(
        Icons.verified,
        size: size,
        color: color,
      ),
    );
  }
}
