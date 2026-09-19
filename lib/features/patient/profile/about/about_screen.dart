import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/legal/legal_document_screen.dart';
import '../../../../core/legal/medibond_legal_content.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/external_launcher.dart';
import '../data/patient_profile_mock.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../../../../core/theme/app_typography.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    this.accentColor = AppColors.patientTeal,
    this.audience = LegalAudience.patient,
  });

  final Color accentColor;
  final LegalAudience audience;

  void _openLegal(BuildContext context, LegalDocumentType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(
          type: type,
          audience: audience,
          accentColor: accentColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('About', context: context),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.local_hospital, size: 40, color: accentColor),
                  ),
                  const SizedBox(height: 12),
                  Text('DoctorNect', style: GoogleFonts.inter(fontSize: AppTypography.headlineLarge, fontWeight: FontWeight.w700)),
                  Text(
                    'Version ${PatientProfileMock.appVersion}',
                    style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                children: [
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.description_outlined, color: accentColor),
                      title: Text('Terms of service'),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () => _openLegal(context, LegalDocumentType.termsOfService),
                    ),
                  ),
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.privacy_tip_outlined, color: accentColor),
                      title: Text('Privacy policy'),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () => _openLegal(context, LegalDocumentType.privacyPolicy),
                    ),
                  ),
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.star_outline, color: accentColor),
                      title: Text('Rate the app'),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () async {
                        await ExternalLauncher.openUrl(PatientProfileMock.appDownloadUrl);
                        if (!context.mounted) return;
                      },
                    ),
                  ),
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share_outlined, color: accentColor),
                      title: Text('Share app link'),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () => ExternalLauncher.shareText(
                        'Download DoctorNect — your healthcare companion: ${PatientProfileMock.appDownloadUrl}',
                        context: context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PatientProfileFormStyles.sectionHeader('CONTACT US'),
            const SizedBox(height: 8),
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                children: [
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.email_outlined, color: accentColor),
                      title: Text('Email Support'),
                      subtitle: Text(PatientProfileMock.supportEmail),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () => ExternalLauncher.openUrl('mailto:${PatientProfileMock.supportEmail}'),
                    ),
                  ),
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
                      title: Text('WhatsApp Support'),
                      subtitle: Text(PatientProfileMock.supportWhatsApp),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () => ExternalLauncher.shareViaWhatsApp(
                        text: 'Hello DoctorNect Support, I have a query about the app.',
                        phone: PatientProfileMock.supportWhatsApp,
                        context: context,
                      ),
                    ),
                  ),
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.phone_outlined, color: accentColor),
                      title: Text('Call Helpline'),
                      subtitle: Text(PatientProfileMock.supportPhone),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () => ExternalLauncher.callPhone(
                        PatientProfileMock.supportPhone,
                        context: context,
                      ),
                    ),
                  ),
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.language_outlined, color: accentColor),
                      title: Text('Official Website'),
                      subtitle: Text(PatientProfileMock.websiteUrl),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: () => ExternalLauncher.openUrl(PatientProfileMock.websiteUrl),
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
