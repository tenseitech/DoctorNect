import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../utils/patient_bmi_utils.dart';
import 'patient_profile_form_styles.dart';
import '../../../../core/theme/app_typography.dart';

/// Shared building blocks for patient & family profile edit screens.
abstract final class ProfileEditWidgets {
  static const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  static Widget heroHeader({
    required String initial,
    required String name,
    String? subtitle,
    VoidCallback? onPhotoTap,
    Widget? trailingBadge,
    ImageProvider? avatarImage,
  }) {
    return Builder(
      builder: (context) => Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: onPhotoTap,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.patientTeal,
                        AppColors.patientTeal.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: AppColors.surfaceOf(context),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: AppColors.patientTeal.withValues(alpha: 0.1),
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? Text(
                              initial,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.headlineLarge,
                                fontWeight: FontWeight.w700,
                                color: AppColors.patientTeal,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              if (onPhotoTap != null)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.patientTeal,
                    child: const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: GoogleFonts.inter(
              fontSize: AppTypography.headlineMedium,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
            ),
          ],
          if (trailingBadge != null) ...[
            const SizedBox(height: 8),
            trailingBadge,
          ],
        ],
      ),
    );
  }

  static Widget sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    String? subtitle,
  }) {
    return Builder(
      builder: (context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.patientTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.patientTeal),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  static Widget lockedNote({required String message}) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.patientTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.patientTeal.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 16, color: AppColors.patientTeal.withValues(alpha: 0.85)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  height: 1.4,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget lockedField({
    required String label,
    required String value,
  }) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  static Widget fieldLabel(String text) {
    return Builder(
      builder: (context) => Text(
        text,
        style: GoogleFonts.inter(
          fontSize: AppTypography.bodySmall,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }

  static Widget genderChips({
    required String? selected,
    required ValueChanged<String>? onSelected,
    String? errorText,
  }) {
    final locked = onSelected == null;
    final select = onSelected;

    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fieldLabel('Gender'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppConstants.genders.map((gender) {
              final isSelected = selected == gender;
              return ChoiceChip(
                label: Text(gender),
                selected: isSelected,
                onSelected: locked || select == null ? null : (_) => select(gender),
                selectedColor: AppColors.patientTeal.withValues(alpha: 0.2),
                backgroundColor: AppColors.cardBgOf(context),
                disabledColor: AppColors.cardBgOf(context),
                labelStyle: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? (locked ? AppColors.textPrimaryOf(context) : AppColors.patientTeal)
                      : AppColors.textSecondaryOf(context),
                ),
                side: BorderSide(
                  color: isSelected ? AppColors.patientTeal : AppColors.borderOf(context),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              );
            }).toList(),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 4),
            Text(errorText, style: const TextStyle(color: Colors.red, fontSize: AppTypography.labelMedium)),
          ],
        ],
      ),
    );
  }

  static Widget bloodGroupChips({
    required String? selected,
    required ValueChanged<String>? onSelected,
    String? errorText,
  }) {
    final locked = onSelected == null;
    final select = onSelected;

    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fieldLabel('Blood group'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: bloodGroups.map((group) {
              final isSelected = selected == group;
              return FilterChip(
                label: Text(group),
                selected: isSelected,
                onSelected: locked || select == null ? null : (_) => select(group),
                selectedColor: AppColors.patientTeal.withValues(alpha: 0.2),
                backgroundColor: AppColors.cardBgOf(context),
                disabledColor: AppColors.cardBgOf(context),
                checkmarkColor: AppColors.patientTeal,
                labelStyle: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  color: isSelected
                      ? (locked ? AppColors.textPrimaryOf(context) : AppColors.patientTeal)
                      : AppColors.textSecondaryOf(context),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                side: BorderSide(
                  color: isSelected ? AppColors.patientTeal : AppColors.borderOf(context),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              );
            }).toList(),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 4),
            Text(errorText, style: const TextStyle(color: Colors.red, fontSize: AppTypography.labelMedium)),
          ],
        ],
      ),
    );
  }

  static Widget bmiCard({
    required String bmiResult,
    required double? bmiValue,
  }) {
    final category = PatientBmiUtils.categoryFor(bmiValue);
    final accent = category != null ? PatientBmiUtils.colorFor(category) : AppColors.patientTeal;

    return Builder(
      builder: (context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.08),
              accent.withValues(alpha: 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_weight_outlined, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'BMI (Body Mass Index)',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
                Text(
                  bmiResult,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: AppTypography.headlineMedium,
                    color: accent,
                  ),
                ),
              ],
            ),
            if (category != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  PatientBmiUtils.labelFor(category),
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                PatientBmiUtils.messageFor(category),
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  height: 1.4,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Enter height and weight to calculate your BMI.',
                  style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget changeAction({required VoidCallback onPressed}) {
    return PatientProfileFormStyles.changeSuffixLabel(onPressed: onPressed);
  }

  static InputDecoration contactDecoration({
    required BuildContext context,
    required String labelText,
    required bool editing,
    Widget? suffixIcon,
    String? counterText,
  }) {
    return PatientProfileFormStyles.fieldDecoration(context, 
      labelText: labelText,
      suffixIcon: suffixIcon,
      counterText: counterText,
    ).copyWith(
      fillColor: editing ? AppColors.surfaceOf(context) : AppColors.cardBgOf(context),
    );
  }

  static Widget insuranceToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Insurance covered',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: AppTypography.bodyMedium,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          subtitle: Text(
            'Include this member under your health insurance',
            style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
          ),
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.patientTeal,
        ),
      ),
    );
  }
}
