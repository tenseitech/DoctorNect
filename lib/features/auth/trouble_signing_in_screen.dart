import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../patient/profile/support/help_support_screen.dart';

/// Full-screen help page opened from "Trouble signing in?" on auth screens.
class TroubleSigningInScreen extends StatelessWidget {
  const TroubleSigningInScreen({
    super.key,
    required this.accentColor,
    this.onReenterMobile,
  });

  final Color accentColor;

  /// Called when the first card CTA is tapped. DoctorNect has no email/password
  /// sign-in — the reference label "Sign in with email" maps to returning to the
  /// mobile number field so the user can re-enter their number.
  final VoidCallback? onReenterMobile;

  void _close(BuildContext context) => Navigator.of(context).pop();

  void _onSignInWithEmail(BuildContext context) {
    Navigator.of(context).pop();
    onReenterMobile?.call();
  }

  void _openSupport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: AppColors.cardBgOf(context),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _close(context),
                    color: AppColors.textPrimaryOf(context),
                    tooltip: 'Close',
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need help logging in?',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineLarge,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Try the following',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _HelpOptionCard(
                    accentColor: accentColor,
                    icon: Icons.mail_outline_rounded,
                    title: 'Already have an account?',
                    description:
                        'You can sign in with your registered email id and password',
                    ctaLabel: 'Sign in with email',
                    onCtaTap: () => _onSignInWithEmail(context),
                  ),
                  const SizedBox(height: 20),
                  _HelpOptionCard(
                    accentColor: accentColor,
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Can not sign in?',
                    description:
                        'Get instant answers to your queries from our support team',
                    ctaLabel: 'Contact Customer Support',
                    onCtaTap: () => _openSupport(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpOptionCard extends StatelessWidget {
  const _HelpOptionCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.description,
    required this.ctaLabel,
    required this.onCtaTap,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String description;
  final String ctaLabel;
  final VoidCallback onCtaTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 24,
              color: AppColors.textPrimaryOf(context).withValues(alpha: 0.75),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: AppTypography.headlineMedium,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryOf(context),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyLarge,
                color: AppColors.textSecondaryOf(context),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Divider(
                height: 1, thickness: 1, color: AppColors.borderOf(context)),
            InkWell(
              onTap: onCtaTap,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ctaLabel,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 24,
                      color: accentColor,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
