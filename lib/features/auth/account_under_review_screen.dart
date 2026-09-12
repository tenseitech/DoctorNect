import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/mobile_scaffold.dart';

import '../splash/splash_screen.dart';

class AccountUnderReviewScreen extends StatelessWidget {
  const AccountUnderReviewScreen({
    super.key,
    this.reviewMessage =
        'Thank you for registering. Our team is verifying your credentials. You will be notified within 2–3 business days.',
  });

  final String reviewMessage;

  @override
  Widget build(BuildContext context) {
    return MobileScaffold(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.doctorBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 64,
                  color: AppColors.doctorBlue,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Account under review',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                reviewMessage,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.textSecondaryOf(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SplashScreen()),
                  (_) => false,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  side: const BorderSide(color: AppColors.doctorBlue),
                  foregroundColor: AppColors.doctorBlue,
                ),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
