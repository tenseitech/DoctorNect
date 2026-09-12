import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/enums/user_type.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_controller.dart';
import 'digital_health_card_sheet.dart';
import 'emergency_sos_sheet.dart';

/// Consolidated three-dot (⋮) overflow menu for top header bars.
/// Contains QR Credentials Pass, Emergency SOS Hotline, and Theme Toggle.
class HeaderOverflowMenu extends StatelessWidget {
  const HeaderOverflowMenu({
    super.key,
    required this.userType,
  });

  final UserType userType;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accentColor = userType == UserType.doctor
            ? AppColors.doctorBlue
            : AppColors.patientTeal;

        return PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert_rounded,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            size: 22,
          ),
          tooltip: 'More options',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: AppColors.surfaceOf(context),
          elevation: 6,
          onSelected: (value) {
            if (value == 'pass') {
              DigitalHealthCardSheet.show(context, userType: userType);
            } else if (value == 'emergency') {
              EmergencySosSheet.show(context);
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem<String>(
              value: 'pass',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.qr_code_scanner_rounded, color: accentColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    userType == UserType.doctor ? 'Doctor Pass (QR)' : 'Health Pass ID',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'emergency',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.emergency_rounded, color: Color(0xFFDC2626), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Emergency SOS',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
