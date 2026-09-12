import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/patient_profile_models.dart';
import '../utils/patient_bmi_utils.dart';

class ProfileHeroSection extends StatelessWidget {
  const ProfileHeroSection({
    super.key,
    required this.profile,
    required this.avatar,
    required this.onEdit,
    required this.onPickPhoto,
  });

  final PatientProfile profile;
  final Widget avatar;
  final VoidCallback onEdit;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveLayout.isCompact(context);
    final hasBmi = profile.height > 0 && profile.weight > 0;

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isWide ? 24 : 16,
          isWide ? 22 : 18,
          isWide ? 24 : 16,
          isWide ? 20 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(onTap: onPickPhoto, child: avatar),
                SizedBox(width: isWide ? 20 : 16),
                Expanded(child: _ProfileMeta(profile: profile, isWide: isWide)),
                if (isWide) ...[
                  const SizedBox(width: 16),
                  _EditProfileButton(onEdit: onEdit, compact: false),
                ],
              ],
            ),
            if (hasBmi) ...[
              SizedBox(height: isWide ? 18 : 16),
              _PatientBmiCard(
                heightCm: profile.height,
                weightKg: profile.weight,
                isWide: isWide,
              ),
            ],
            if (!isWide) ...[
              SizedBox(height: hasBmi ? 14 : 16),
              _EditProfileButton(onEdit: onEdit, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileMeta extends StatelessWidget {
  const _ProfileMeta({required this.profile, required this.isWide});

  final PatientProfile profile;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.name.isNotEmpty ? profile.name : 'Your profile',
          maxLines: isWide ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: isWide ? 24 : 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
            height: 1.15,
          ),
        ),
        if (profile.age > 0 || profile.gender.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (profile.age > 0) _MetaChip('${profile.age} yrs'),
              if (profile.gender.trim().isNotEmpty) _MetaChip(profile.gender),
            ],
          ),
        ],
        if (profile.mobile.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _MetaLine(icon: Icons.phone_outlined, text: profile.mobile),
        ],
        if (profile.email.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          _MetaLine(icon: Icons.mail_outline, text: profile.email),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.9)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
          ),
        ),
      ],
    );
  }
}

class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.onEdit, required this.compact});

  final VoidCallback onEdit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: Text(
        'Edit Profile',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.patientTeal,
        side: const BorderSide(color: AppColors.patientTeal),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 18,
          vertical: compact ? 12 : 10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (compact) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

class _PatientBmiCard extends StatelessWidget {
  const _PatientBmiCard({
    required this.heightCm,
    required this.weightKg,
    required this.isWide,
  });

  final double heightCm;
  final double weightKg;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final bmi = PatientBmiUtils.calculate(heightCm: heightCm, weightKg: weightKg);
    final category = PatientBmiUtils.categoryFor(bmi);
    if (bmi == null || category == null) return const SizedBox.shrink();

    final scoreBox = Container(
      width: isWide ? 80 : 72,
      height: isWide ? 80 : 72,
      decoration: BoxDecoration(
        color: AppColors.patientTeal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'BMI',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.patientTeal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            bmi.toStringAsFixed(1),
            style: GoogleFonts.inter(
              fontSize: isWide ? 24 : 22,
              fontWeight: FontWeight.w800,
              color: AppColors.patientTeal,
              height: 1,
            ),
          ),
        ],
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.patientTeal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            PatientBmiUtils.labelFor(category),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.patientTeal,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PatientBmiUtils.messageFor(category),
          style: GoogleFonts.inter(
            fontSize: isWide ? 14 : 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        if (isWide) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _StatPill(label: 'Height', value: '${heightCm.toStringAsFixed(0)} cm'),
              const SizedBox(width: 8),
              _StatPill(label: 'Weight', value: '${weightKg.toStringAsFixed(0)} kg'),
            ],
          ),
        ],
      ],
    );

    return Container(
      padding: EdgeInsets.all(isWide ? 16 : 14),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          scoreBox,
          SizedBox(width: isWide ? 16 : 12),
          Expanded(child: details),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text(
        '$label · $value',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }
}
