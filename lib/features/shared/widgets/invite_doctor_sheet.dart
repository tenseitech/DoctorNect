import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/external_launcher.dart';
import '../../lab/data/lab_registry.dart';
import '../../../core/theme/app_typography.dart';

abstract final class LabDoctorInviteService {
  static const appDownloadUrl = 'https://doctornect.com/download';

  static String buildInviteLink(String labId, {String? role}) {
    final id = labId.trim().isEmpty ? 'lab' : labId.trim();
    final params = <String, String>{'lab': id};
    if (role != null) {
      params['role'] = role;
    }
    return Uri.parse(appDownloadUrl).replace(queryParameters: params).toString();
  }

  static String inviteMessage({required String labName, required String link, String? role}) {
    final name = labName.trim().isEmpty ? 'A diagnostic lab' : labName.trim();
    if (role == 'doctor') {
      return '$name invited you to download DoctorNect and register as a doctor to connect with their lab. '
          'Download the app and sign up using this link:\n$link';
    }
    return '$name invited you to download DoctorNect to connect with their lab. '
        'Download the app and sign up using this link:\n$link';
  }

  static String labNameForCurrentLab() {
    final labId = LabSession.loggedInLabId;
    final lab = LabRegistry.findById(labId);
    final name = lab?.labName.trim();
    if (name != null && name.isNotEmpty) return name;
    final sessionName = LabSession.loggedInLabName.trim();
    return sessionName.isEmpty ? 'Your lab' : sessionName;
  }
}

typedef InviteDoctorSheet = LabInviteDoctorSheet;

class LabInviteDoctorSheet extends StatefulWidget {
  const LabInviteDoctorSheet({super.key, this.role});

  final String? role;

  static Future<void> show(BuildContext context, {String? role}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceOf(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LabInviteDoctorSheet(role: role),
    );
  }

  @override
  State<LabInviteDoctorSheet> createState() => _LabInviteDoctorSheetState();
}

class _LabInviteDoctorSheetState extends State<LabInviteDoctorSheet> {
  static const _labPurple = AppColors.labPurple;

  String get _link => LabDoctorInviteService.buildInviteLink(LabSession.loggedInLabId, role: widget.role);

  Future<void> _copyLink() async {
    final message = LabDoctorInviteService.inviteMessage(
      labName: LabDoctorInviteService.labNameForCurrentLab(),
      link: _link,
      role: widget.role,
    );
    await Clipboard.setData(ClipboardData(text: message));
  }

  Future<void> _shareLink() async {
    final message = LabDoctorInviteService.inviteMessage(
      labName: LabDoctorInviteService.labNameForCurrentLab(),
      link: _link,
      role: widget.role,
    );
    await ExternalLauncher.shareText(message, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final labName = LabDoctorInviteService.labNameForCurrentLab();

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
                  color: AppColors.textSecondaryOf(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Invite to download app',
              style: GoogleFonts.inter(fontSize: AppTypography.headlineMedium, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              widget.role == 'doctor'
                  ? 'Share this link with a doctor who is not on DoctorNect yet. They can download the app, register as a doctor, and connect with $labName.'
                  : 'Share this link with anyone who is not on DoctorNect yet. They can download the app and connect with $labName.',
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _labPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _labPurple.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 20, color: _labPurple.withValues(alpha: 0.9)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      _link,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _copyLink,
              style: FilledButton.styleFrom(
                backgroundColor: _labPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.copy_outlined),
              label: Text('Copy invite', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _shareLink,
              style: OutlinedButton.styleFrom(
                foregroundColor: _labPurple,
                side: const BorderSide(color: _labPurple),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.share_outlined),
              label: Text('Share invite', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
