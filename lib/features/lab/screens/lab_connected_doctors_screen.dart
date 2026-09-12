import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/app_toast.dart';
import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../shared/partner/partner_connect_doctors_base_screen.dart';
import '../../shared/partner/partner_connected_doctors_base_screen.dart';
import '../../shared/widgets/lab_page_layout.dart';
import '../data/lab_connection_store.dart';
import '../data/lab_worklist_store.dart';

class LabConnectedDoctorsScreen extends StatelessWidget {
  const LabConnectedDoctorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final labId = LabSession.loggedInLabId;
    final connStore = LabConnectionStore.instance;
    final worklistStore = LabWorklistStore.instance;

    return PartnerConnectedDoctorsBaseView(
      accentColor: AppColors.labPurple,
      listenables: [connStore, worklistStore],
      activeConnections: () => connStore
          .activeForLab(labId)
          .map((c) => PartnerConnectionItem(
                id: c.id,
                doctorId: c.doctorId,
                doctorName: c.doctorName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      fromDoctorRequests: () => connStore
          .pendingForLabFromDoctor(labId)
          .map((c) => PartnerConnectionItem(
                id: c.id,
                doctorId: c.doctorId,
                doctorName: c.doctorName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      sentByPartnerInvites: () => connStore
          .pendingSentByLab(labId)
          .map((c) => PartnerConnectionItem(
                id: c.id,
                doctorId: c.doctorId,
                doctorName: c.doctorName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      activitySubtitleBuilder: (doctorId) {
        final count = worklistStore.forLabAndDoctor(labId, doctorId).length;
        final last = worklistStore.forLabAndDoctor(labId, doctorId).firstOrNull?.createdAt;
        return '$count test orders${last != null ? ' · Last: ${DateFormat('dd MMM').format(last)}' : ''}';
      },
      onApprove: (id, doctorName) {
        connStore.approveByLab(id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected with ${partnerDoctorLabel(doctorName)}'),
            backgroundColor: AppColors.labPurple,
          ),
        );
      },
      onReject: (id, doctorName) {
        connStore.rejectByLab(id);
        AppToast.info(context, 'Rejected ${partnerDoctorLabel(doctorName)}');
      },
      onRevoke: (id, doctorName) {
        connStore.removeConnection(id);
        AppToast.info(context, 'Invite revoked for ${partnerDoctorLabel(doctorName)}');
      },
      onRemove: (id, doctorName) {
        connStore.removeConnection(id);
        AppToast.info(context, 'Disconnected from ${partnerDoctorLabel(doctorName)}');
      },
      pageLayoutBuilder: (context, child) => LabPageLayout(child: child),
    );
  }
}