import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/app_logout.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

class LogoutIconButton extends StatelessWidget {
  const LogoutIconButton({super.key, this.tooltip = 'Log out', this.color});

  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondaryOf(context);
    return TextButton(
      onPressed: () => AppLogout.confirmAndSignOut(context),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(44, 44),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.logout, size: 18, color: c),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Logout',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LogoutTextButton extends StatelessWidget {
  const LogoutTextButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => AppLogout.confirmAndSignOut(context),
      child: Text(
        'Log out',
        style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w600, color: AppColors.error),
      ),
    );
  }
}

class LogoutRailTile extends StatelessWidget {
  const LogoutRailTile({super.key, required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AppLogout.confirmAndSignOut(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 12, vertical: 12),
        child: Row(
          mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout, color: AppColors.error, size: 22),
            if (extended) ...[
              const SizedBox(width: 12),
              Text(
                'Log out',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
