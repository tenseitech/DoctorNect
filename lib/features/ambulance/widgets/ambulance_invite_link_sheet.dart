import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/invite/ambulance_invite_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/external_launcher.dart';
import '../../doctor/profile/data/doctor_profile_store.dart';
import '../../../core/theme/app_typography.dart';

class AmbulanceInviteLinkSheet extends StatelessWidget {
  const AmbulanceInviteLinkSheet({
    super.key,
    required this.serviceName,
    required this.driverName,
    required this.link,
  });

  final String serviceName;
  final String driverName;
  final String link;

  static Future<void> show(
    BuildContext context, {
    required String serviceName,
    required String driverName,
    required String link,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AmbulanceInviteLinkSheet(
        serviceName: serviceName,
        driverName: driverName,
        link: link,
      ),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: link));
  }

  Future<void> _shareLink(BuildContext context) async {
    final message = AmbulanceInviteService.inviteMessage(
      doctorName: DoctorProfileStore.displayName,
      serviceName: serviceName,
      link: link,
    );
    await ExternalLauncher.shareText(message, context: context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      AppColors.textSecondaryOf(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Invite link created',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineMedium,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this link with $driverName. They can download DoctorNect, open the link, set a username & PIN, and login to the ambulance dashboard.',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBgOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: SelectableText(
                link,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textPrimaryOf(context)),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy link'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _shareLink(context),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share with driver'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
