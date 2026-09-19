import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Compact action tile for the web profile dashboard grid.
class ProfileWebActionCard extends StatefulWidget {
  const ProfileWebActionCard({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.iconGradient,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final List<Color>? iconGradient;

  @override
  State<ProfileWebActionCard> createState() => _ProfileWebActionCardState();
}

class _ProfileWebActionCardState extends State<ProfileWebActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final gradient = widget.iconGradient ?? const [Color(0xFF0D9488), Color(0xFF0369A1)];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered
                    ? AppColors.patientTeal.withValues(alpha: 0.35)
                    : AppColors.borderOf(context),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, size: 21, color: AppColors.white),
                ),
                const Spacer(),
                Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                    height: 1.2,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
