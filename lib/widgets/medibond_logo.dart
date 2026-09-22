import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';

class DoctorNectLogo extends StatelessWidget {
  const DoctorNectLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Full brand mark includes icon + "DoctorNect" wordmark.
    final height = size * 1.15;
    return Image.asset(
      'assets/images/logo.webp',
      width: size * 1.4,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.practoTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(size * 0.22),
            ),
            child: Icon(
              Icons.local_hospital_rounded,
              size: size * 0.55,
              color: AppColors.practoTeal,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'DoctorNect',
            style: TextStyle(
              fontSize: size * 0.38,
              fontWeight: FontWeight.w700,
              color: AppColors.practoTeal,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// DoctorNect branding for desktop/web side rails — hidden on mobile shells.
class SidebarDoctorNectLogo extends StatelessWidget {
  const SidebarDoctorNectLogo({super.key, this.extended = true});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        extended ? 'DoctorNect' : 'DN',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: extended ? 20 : 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          height: 1.1,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}
