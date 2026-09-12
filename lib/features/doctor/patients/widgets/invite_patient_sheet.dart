import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/invite/doctor_invite_service.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/external_launcher.dart';
import '../../profile/data/doctor_profile_store.dart';

class InvitePatientSheet extends StatefulWidget {
  const InvitePatientSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const InvitePatientSheet(),
    );
  }

  @override
  State<InvitePatientSheet> createState() => _InvitePatientSheetState();
}

class _InvitePatientSheetState extends State<InvitePatientSheet> {
  String? _link;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    final link = await DoctorInviteService.linkForCurrentDoctor();
    if (!mounted) return;
    setState(() {
      _link = link;
      _loading = false;
    });
  }

  Future<void> _copyLink() async {
    final link = _link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite link copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareLink() async {
    final link = _link;
    if (link == null) return;
    final message = DoctorInviteService.inviteMessage(
      doctorName: DoctorProfileStore.displayName,
      link: link,
    );
    await ExternalLauncher.shareText(message, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final doctorName = DoctorProfileStore.displayNameWithPrefix;

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
              'Invite Patient',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Share your personal DoctorNect link. When patients register with it, they are linked to $doctorName.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.doctorBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 20, color: AppColors.doctorBlue.withValues(alpha: 0.9)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _link ?? DoctorInviteService.buildInviteLink(DoctorSession.loggedInDoctorId),
                            style: GoogleFonts.inter(
                              fontSize: 14,
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
              onPressed: _loading ? null : _copyLink,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.doctorBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.copy_outlined),
              label: Text('Copy Link', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _shareLink,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.doctorBlue,
                side: const BorderSide(color: AppColors.doctorBlue),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.share_outlined),
              label: Text('Share', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
