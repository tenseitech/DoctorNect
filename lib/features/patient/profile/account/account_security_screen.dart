import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../widgets/patient_profile_form_styles.dart';

class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar(
        'Account & Security',
        context: context,
      ),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PatientProfileFormStyles.contentSurface(
              context: context,
              child: Column(
                children: [
                  PatientProfileFormStyles.settingsRowCard(
                    context: context,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.phone_android_outlined,
                        color: AppColors.patientTeal,
                      ),
                      title: Text('Sign-in method'),
                      subtitle: Text('Phone number & OTP'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
