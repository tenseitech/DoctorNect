import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/doctor_models.dart';
import '../../widgets/doctor_ui_widgets.dart';
import '../models/doctor_profile_data.dart';

class DoctorProfileHeroSection extends StatelessWidget {
  const DoctorProfileHeroSection({
    super.key,
    required this.profile,
    required this.displayName,
    required this.verificationStatus,
    required this.avatar,
    required this.onEdit,
    required this.onPickPhoto,
  });

  final DoctorProfileData profile;
  final String displayName;
  final VerificationStatus verificationStatus;
  final Widget avatar;
  final VoidCallback onEdit;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveLayout.isCompact(context);

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
                Expanded(
                  child: _DoctorProfileMeta(
                    profile: profile,
                    displayName: displayName,
                    verificationStatus: verificationStatus,
                    isWide: isWide,
                  ),
                ),
                if (isWide) ...[
                  const SizedBox(width: 16),
                  _EditProfileButton(onEdit: onEdit, compact: false),
                ],
              ],
            ),
            SizedBox(height: isWide ? 18 : 16),
            _DoctorPracticeStats(
              rating: profile.rating,
              reviewCount: profile.reviewCount,
              isWide: isWide,
            ),
            if (!isWide) ...[
              const SizedBox(height: 14),
              _EditProfileButton(onEdit: onEdit, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoctorProfileMeta extends StatelessWidget {
  const _DoctorProfileMeta({
    required this.profile,
    required this.displayName,
    required this.verificationStatus,
    required this.isWide,
  });

  final DoctorProfileData profile;
  final String displayName;
  final VerificationStatus verificationStatus;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                displayName,
                maxLines: isWide ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: isWide ? 24 : 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                  height: 1.15,
                ),
              ),
            ),
            SizedBox(width: isWide ? 10 : 8),
            VerificationBadge(status: verificationStatus),
          ],
        ),
        if (profile.specialization.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _MetaChip(profile.specialization.trim()),
        ],
        if (profile.qualification.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _MetaChip(profile.qualification.trim()),
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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

class _DoctorPracticeStats extends StatelessWidget {
  const _DoctorPracticeStats({
    required this.rating,
    required this.reviewCount,
    required this.isWide,
  });

  final double rating;
  final int reviewCount;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isWide ? 16 : 14),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFF59E0B),
              label: 'Rating',
              value: rating > 0 ? rating.toStringAsFixed(1) : '—',
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: AppColors.borderOf(context),
          ),
          Expanded(
            child: _StatTile(
              icon: Icons.rate_review_outlined,
              iconColor: AppColors.doctorBlue,
              label: 'Reviews',
              value: '$reviewCount',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimaryOf(context),
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
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
        foregroundColor: AppColors.doctorBlue,
        side: const BorderSide(color: AppColors.doctorBlue),
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
