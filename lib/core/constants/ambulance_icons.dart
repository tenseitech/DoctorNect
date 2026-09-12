import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ambulance action icon used across doctor and patient UI.
abstract final class AmbulanceIcons {
  static const IconData sign = TablerIcons.ambulance;
  static const IconData signFilled = TablerIcons.ambulance;

  static const gradient = [Color(0xFFDC2626), Color(0xFFB91C1C)];
}

/// Ambulance vehicle with a medical "+" badge.
class AmbulanceWithPlusIcon extends StatelessWidget {
  const AmbulanceWithPlusIcon({
    super.key,
    required this.size,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final vehicleSize = size * 0.82;
    final badgeSize = size * 0.42;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(TablerIcons.ambulance, size: vehicleSize, color: color),
          Positioned(
            right: -badgeSize * 0.08,
            top: -badgeSize * 0.12,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(badgeSize * 0.28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '+',
                style: GoogleFonts.inter(
                  fontSize: badgeSize * 0.7,
                  fontWeight: FontWeight.w800,
                  color: AmbulanceIcons.gradient.last,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ambulance marker — vehicle with medical "+" on red/gradient backgrounds; plain vehicle elsewhere.
class AmbulancePlusSign extends StatelessWidget {
  const AmbulancePlusSign({
    super.key,
    required this.size,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (color == Colors.white) {
      return AmbulanceWithPlusIcon(size: size, color: color);
    }

    return Icon(TablerIcons.ambulance, size: size * 0.88, color: color);
  }
}
