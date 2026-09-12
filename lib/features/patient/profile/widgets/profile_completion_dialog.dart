import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/patient_profile_mock.dart';
import '../edit_profile_screen.dart';

class ProfileCompletionDialog extends StatelessWidget {
  const ProfileCompletionDialog({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    final percentage = PatientProfileMock.profileCompletionPercentage;
    if (percentage < 100 && !PatientProfileMock.hasDismissedCompletionDialog) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ProfileCompletionDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final percentage = PatientProfileMock.profileCompletionPercentage;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.surfaceOf(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Complete Your Profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      PatientProfileMock.hasDismissedCompletionDialog = true;
                      Navigator.of(context).pop();
                    },
                    child: Icon(Icons.close_rounded, size: 24, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: percentage / 100,
                      strokeWidth: 8,
                      backgroundColor: AppColors.patientTeal.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.patientTeal),
                    ),
                  ),
                  Text(
                    '$percentage%',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.patientTeal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your profile is $percentage% complete. Please complete your profile to book appointments and receive accurate medical care.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EditProfileScreen(
                    profile: PatientProfileMock.profile,
                    onSaved: () {},
                  )),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.patientTeal,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'Complete Profile',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                PatientProfileMock.hasDismissedCompletionDialog = true;
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondaryOf(context),
              ),
              child: Text(
                'Later',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
