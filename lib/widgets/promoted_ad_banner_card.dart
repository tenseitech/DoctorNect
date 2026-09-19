import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/promoted_ads/screens/promoted_ads_management_screen.dart';
import '../core/theme/app_typography.dart';

/// Prominent front-page promotional ad banner widget for Doctors, Labs, Pharmacies, and Ambulances.
class PromotedAdBannerCard extends StatelessWidget {
  const PromotedAdBannerCard({
    super.key,
    required this.providerType,
    required this.providerId,
    required this.providerEmail,
    required this.providerContact,
    this.isVerified = true,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  final String providerType;
  final String providerId;
  final String providerEmail;
  final String providerContact;
  final bool isVerified;
  final EdgeInsetsGeometry margin;

  String get _providerLabel => switch (providerType.toLowerCase()) {
        'doctor' => 'Medical Practice & Clinic',
        'lab' => 'Diagnostic Lab & Tests',
        'pharmacy' => 'Medical Store & Pharmacy',
        'ambulance' => 'Ambulance & Emergency Service',
        _ => 'Healthcare Business',
      };

  void _open(BuildContext context) {
    PromotedAdsManagementScreen.open(
      context,
      providerType: providerType,
      providerId: providerId,
      providerEmail: providerEmail,
      providerContact: providerContact,
      isVerified: isVerified,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 460;

                final headerRow = Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(
                        TablerIcons.speakerphone,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE047),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'FEATURED PROMOTION',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withValues(alpha: 0.8),
                      size: 14,
                    ),
                  ],
                );

                final titleText = Text(
                  'Promote Your $_providerLabel 🚀',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.25,
                  ),
                );

                final subText = Text(
                  'Showcase your service on the Patient Home screen banner carousel to reach thousands of patients.',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.3,
                  ),
                );

                final bookButton = ElevatedButton(
                  onPressed: () => _open(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                  child: Text(
                    'Book Ad',
                    style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w800),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      headerRow,
                      const SizedBox(height: 8),
                      titleText,
                      const SizedBox(height: 4),
                      subText,
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: bookButton,
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(
                        TablerIcons.speakerphone,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDE047),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'FEATURED PROMOTION',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          titleText,
                          const SizedBox(height: 3),
                          subText,
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    bookButton,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
