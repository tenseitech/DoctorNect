import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/ambulance_icons.dart';
import '../../../features/ambulance/ambulance_booking_screen.dart';
import '../../../features/ambulance/models/ambulance_models.dart';
import '../app_notification.dart';

class AmbulanceActionButton extends StatefulWidget {
  const AmbulanceActionButton({
    super.key,
    required this.audience,
    this.iconOnly = false,
  });

  final NotificationAudience audience;
  final bool iconOnly;

  @override
  State<AmbulanceActionButton> createState() => _AmbulanceActionButtonState();
}

class _AmbulanceActionButtonState extends State<AmbulanceActionButton> {
  bool _pressed = false;

  void _openBooking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AmbulanceBookingScreen(
          bookedByRole: widget.audience == NotificationAudience.doctor
              ? AmbulanceBookedByRole.doctor
              : AmbulanceBookedByRole.patient,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.iconOnly ? 14.0 : 999.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openBooking,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(radius),
        splashColor: Colors.white.withValues(alpha: 0.18),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: widget.iconOnly ? 44 : null,
          height: widget.iconOnly ? 44 : null,
          padding: widget.iconOnly
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AmbulanceIcons.gradient,
            ),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: AmbulanceIcons.gradient.last.withValues(
                  alpha: _pressed ? 0.18 : 0.34,
                ),
                blurRadius: _pressed ? 6 : 12,
                offset: Offset(0, _pressed ? 2 : 4),
              ),
            ],
          ),
          child: widget.iconOnly
              ? const Center(child: AmbulancePlusSign(size: 24))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AmbulancePlusSign(size: 20),
                    const SizedBox(width: 7),
                    Text(
                      'Ambulance',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
