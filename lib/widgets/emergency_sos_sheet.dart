import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../features/ambulance/ambulance_booking_screen.dart';
import '../features/ambulance/models/ambulance_models.dart';
import '../core/theme/app_typography.dart';

/// SOS Emergency Sheet for instant 108 Ambulance Hotline and Emergency Trauma Dispatch.
class EmergencySosSheet extends StatelessWidget {
  const EmergencySosSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EmergencySosSheet(),
    );
  }

  Future<void> _callHotline(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emergency_rounded,
                  color: Color(0xFFDC2626),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency SOS Assistance',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF991B1B),
                      ),
                    ),
                    Text(
                      '24/7 Rapid Emergency Response',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Call 108 Emergency Banner
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _callHotline('108'),
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Call 108 Emergency Hotline',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineSmall,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Toll-free immediate trauma & cardiac response',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Book Ambulance Quick Dispatch Button
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AmbulanceBookingScreen(
                    bookedByRole: AmbulanceBookedByRole.patient,
                  ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
              foregroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.airport_shuttle_rounded, size: 20),
            label: Text(
              'Book Nearby ICU Ambulance Dispatcher',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Emergency Trauma Services',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          _SosOptionTile(
            icon: Icons.local_hospital_rounded,
            title: 'National Trauma Hotline (112)',
            subtitle: 'Unified Disaster & Police Emergency',
            onTap: () => _callHotline('112'),
          ),
          const SizedBox(height: 8),
          _SosOptionTile(
            icon: Icons.bloodtype_rounded,
            title: 'National Blood Bank Helpline (104)',
            subtitle: '24x7 Rare Blood Group & Plasma Dispatch',
            onTap: () => _callHotline('104'),
          ),
        ],
        ),
      ),
    );
  }
}

class _SosOptionTile extends StatelessWidget {
  const _SosOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFDC2626), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.call_rounded, color: AppColors.textSecondaryOf(context), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
