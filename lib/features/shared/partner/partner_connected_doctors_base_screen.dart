import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/confirm_delete_dialog.dart';
import '../../../widgets/doctor_invite_action_button.dart';
import 'partner_connect_doctors_base_screen.dart';

/// Shared simple Connected Doctors list view for Pharmacy and Lab.
class PartnerConnectedDoctorsBaseView extends StatelessWidget {
  const PartnerConnectedDoctorsBaseView({
    super.key,
    required this.accentColor,
    required this.listenables,
    required this.activeConnections,
    required this.fromDoctorRequests,
    required this.sentByPartnerInvites,
    required this.activitySubtitleBuilder,
    required this.onApprove,
    required this.onReject,
    required this.onRevoke,
    required this.onRemove,
    required this.pageLayoutBuilder,
  });

  final Color accentColor;
  final List<Listenable> listenables;
  final List<PartnerConnectionItem> Function() activeConnections;
  final List<PartnerConnectionItem> Function() fromDoctorRequests;
  final List<PartnerConnectionItem> Function() sentByPartnerInvites;
  final String Function(String doctorId) activitySubtitleBuilder;
  final void Function(String id, String doctorName) onApprove;
  final void Function(String id, String doctorName) onReject;
  final void Function(String id, String doctorName) onRevoke;
  final void Function(String id, String doctorName) onRemove;
  final Widget Function(BuildContext context, Widget child) pageLayoutBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final active = activeConnections();
        final fromDoctor = fromDoctorRequests();
        final sentByPartner = sentByPartnerInvites();

        return pageLayoutBuilder(
          context,
          ListView(
            children: [
              Text(
                'Connected Doctors',
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage your doctor connections and pending requests.',
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 20),
              if (fromDoctor.isNotEmpty) ...[
                Text(
                  'Doctor invites',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.doctorBlue),
                ),
                const SizedBox(height: 4),
                Text(
                  'Doctors who sent you an invite',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 8),
                ...fromDoctor.map(
                  (c) => _BaseDoctorRequestCard(
                    connection: c,
                    accentColor: accentColor,
                    onApprove: () => onApprove(c.id, c.doctorName),
                    onReject: () => onReject(c.id, c.doctorName),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (sentByPartner.isNotEmpty) ...[
                Text('Pending invites', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...sentByPartner.map(
                  (c) => _BasePendingInviteTile(
                    connection: c,
                    accentColor: accentColor,
                    onRevoke: () => onRevoke(c.id, c.doctorName),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Active connections', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (active.isEmpty)
                Text('No active connections', style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)))
              else
                ...active.map((c) {
                  final subtitle = activitySubtitleBuilder(c.doctorId);
                  return _BaseSimpleConnectionTile(
                    connection: c,
                    accentColor: accentColor,
                    subtitle: subtitle,
                    onRemove: () => onRemove(c.id, c.doctorName),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _BaseDoctorRequestCard extends StatelessWidget {
  const _BaseDoctorRequestCard({
    required this.connection,
    required this.accentColor,
    required this.onApprove,
    required this.onReject,
  });

  final PartnerConnectionItem connection;
  final Color accentColor;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.doctorBlue.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${partnerDoctorLabel(connection.doctorName)} sent you an invite',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Requested ${DateFormat('dd MMM yyyy, hh:mm a').format(connection.requestedAt)}',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: onReject, child: const Text('Reject')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(backgroundColor: accentColor),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BasePendingInviteTile extends StatelessWidget {
  const _BasePendingInviteTile({
    required this.connection,
    required this.accentColor,
    required this.onRevoke,
  });

  final PartnerConnectionItem connection;
  final Color accentColor;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partnerDoctorLabel(connection.doctorName),
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Invite Sent Â· ${DateFormat('dd MMM yyyy').format(connection.requestedAt)}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          DoctorInviteActionButton(
            isPending: true,
            accentColor: accentColor,
            onInvite: () {},
            onRevoke: onRevoke,
          ),
        ],
      ),
    );
  }
}

class _BaseSimpleConnectionTile extends StatelessWidget {
  const _BaseSimpleConnectionTile({
    required this.connection,
    required this.accentColor,
    this.subtitle,
    this.onRemove,
  });

  final PartnerConnectionItem connection;
  final Color accentColor;
  final String? subtitle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accentColor.withValues(alpha: 0.12),
            child: Text(
              partnerDoctorInitial(connection.doctorName),
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: accentColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partnerDoctorLabel(connection.doctorName),
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Connected',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
          if (onRemove != null)
            FilledButton.icon(
              icon: const Icon(Icons.link_off, size: 16),
              label: Text(
                'Disconnect',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                final confirmed = await showConfirmDeleteDialog(
                  context,
                  title: 'Disconnect doctor?',
                  message:
                      'Disconnect from ${partnerDoctorLabel(connection.doctorName)}? You can send a new invite later.',
                  confirmLabel: 'Disconnect',
                );
                if (confirmed) onRemove!();
              },
            ),
        ],
      ),
    );
  }
}