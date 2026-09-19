import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'medibond_legal_content.dart';
import '../../core/theme/app_typography.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.type,
    required this.audience,
    this.accentColor = AppColors.patientTeal,
  });

  final LegalDocumentType type;
  final LegalAudience audience;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final title = DoctorNectLegalContent.title(type);
    final sections = DoctorNectLegalContent.sections(type: type, audience: audience);

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DoctorNect',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DoctorNectLegalContent.lastUpdated,
                  style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(
              section.title,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryOf(context),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            for (final paragraph in section.paragraphs) ...[
              Text(
                paragraph,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  height: 1.55,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
