import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/app_logout.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/external_launcher.dart';
import '../../../widgets/mobile_scaffold.dart';
import '../../../core/theme/app_typography.dart';

/// Hold screen for logged-in doctors awaiting admin verification.
class DoctorVerificationPendingScreen extends StatelessWidget {
  const DoctorVerificationPendingScreen({super.key});

  static const supportEmail = 'support@doctornect.com';

  @override
  Widget build(BuildContext context) {
    final doctorName = DoctorSession.loggedInDoctorName.trim();
    final greeting = doctorName.isEmpty ? 'Doctor' : doctorName;

    return MobileScaffold(
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
              Icons.verified_user_outlined,
              size: 64,
              color: AppColors.doctorBlue,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Verification pending',
            style: GoogleFonts.inter(
              fontSize: AppTypography.headlineLarge,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Hello, $greeting',
            style: GoogleFonts.inter(
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Your doctor account is under review. Our team is verifying your '
            'credentials — full dashboard access unlocks after approval, '
            'usually within 24–48 hours.',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyLarge,
              height: 1.5,
              color: AppColors.textSecondaryOf(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Aapko approve hote hi app automatically update ho jayegi.',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyMedium,
              height: 1.5,
              color: AppColors.textSecondaryOf(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _contactSupport(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: AppColors.doctorBlue,
              foregroundColor: AppColors.white,
            ),
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('Contact support'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _copySupportEmail(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: AppColors.doctorBlue),
              foregroundColor: AppColors.doctorBlue,
            ),
            icon: const Icon(Icons.copy_rounded),
            label: Text(supportEmail),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => AppLogout.confirmAndSignOut(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              side: BorderSide(
                  color: AppColors.textSecondaryOf(context)
                      .withValues(alpha: 0.35)),
              foregroundColor: AppColors.textSecondaryOf(context),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Future<void> _contactSupport(BuildContext context) async {
    final opened = await ExternalLauncher.openUrl('mailto:$supportEmail');
    if (!context.mounted || opened) return;
    await _copySupportEmail(context);
  }

  Future<void> _copySupportEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (!context.mounted) return;
  }
}
