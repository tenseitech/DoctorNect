import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/patient_mock_data.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../../../core/theme/app_typography.dart';

class HealthTipsSection extends StatelessWidget {
  const HealthTipsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tips = PatientMockData.healthTips;
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, isWide ? 20 : 12, 16, isWide ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health tips',
                style: GoogleFonts.inter(
                  fontSize: isWide ? 17 : 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Quick reads for daily wellness',
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
          SizedBox(height: isWide ? 10 : 8),
          if (isWide)
            Row(
              children: [
                for (var i = 0; i < tips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: _HealthTipTile(tip: tips[i], compact: false)),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < tips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _HealthTipTile(tip: tips[i], compact: true),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _HealthTipTile extends StatelessWidget {
  const _HealthTipTile({required this.tip, required this.compact});

  final HealthTip tip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = _HealthTipPalette.forCategory(tip.category);

    if (!compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HealthTipIcon(palette: palette, size: 38, iconSize: 18),
            const SizedBox(height: 10),
            Text(
              tip.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            _CategoryChip(label: tip.category, color: palette.gradient.first),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          _HealthTipIcon(palette: palette, size: 36, iconSize: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CategoryChip(label: tip.category, color: palette.gradient.first),
        ],
      ),
    );
  }
}

class _HealthTipIcon extends StatelessWidget {
  const _HealthTipIcon({
    required this.palette,
    required this.size,
    required this.iconSize,
  });

  final _HealthTipPalette palette;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.gradient,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: FaIcon(palette.icon, size: iconSize, color: AppColors.white),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _HealthTipPalette {
  const _HealthTipPalette({required this.gradient, required this.icon});

  final List<Color> gradient;
  final FaIconData icon;

  static _HealthTipPalette forCategory(String category) {
    return switch (category) {
      'Cardiology' => const _HealthTipPalette(
          gradient: [Color(0xFFDC2626), Color(0xFFB91C1C)],
          icon: FontAwesomeIcons.heartPulse,
        ),
      'Wellness' => const _HealthTipPalette(
          gradient: [Color(0xFF16A34A), Color(0xFF15803D)],
          icon: FontAwesomeIcons.leaf,
        ),
      'Skin Care' => const _HealthTipPalette(
          gradient: [Color(0xFFEA580C), Color(0xFFC2410C)],
          icon: FontAwesomeIcons.handDots,
        ),
      _ => const _HealthTipPalette(
          gradient: [Color(0xFF0D9488), Color(0xFF0369A1)],
          icon: FontAwesomeIcons.stethoscope,
        ),
    };
  }
}
