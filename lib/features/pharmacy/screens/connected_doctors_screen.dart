import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/app_toast.dart';
import '../../../core/session/medical_store_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../shared/partner/partner_connect_doctors_base_screen.dart';
import '../../shared/partner/partner_connected_doctors_base_screen.dart';
import '../data/pharmacy_connection_store.dart';
import '../data/pharmacy_prescription_store.dart';
import '../widgets/pharmacy_page_layout.dart';

class ConnectedDoctorsScreen extends StatelessWidget {
  const ConnectedDoctorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storeId = MedicalStoreSession.loggedInStoreId;
    final connStore = PharmacyConnectionStore.instance;
    final prescStore = PharmacyPrescriptionStore.instance;

    return PartnerConnectedDoctorsBaseView(
      accentColor: AppColors.pharmacyGreen,
      listenables: [connStore, prescStore],
      activeConnections: () => connStore
          .activeForStore(storeId)
          .map((c) => PartnerConnectionItem(
                id: c.id,
                doctorId: c.doctorId,
                doctorName: c.doctorName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      fromDoctorRequests: () => connStore
          .pendingForStoreFromDoctor(storeId)
          .map((c) => PartnerConnectionItem(
                id: c.id,
                doctorId: c.doctorId,
                doctorName: c.doctorName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      sentByPartnerInvites: () => connStore
          .pendingSentByStore(storeId)
          .map((c) => PartnerConnectionItem(
                id: c.id,
                doctorId: c.doctorId,
                doctorName: c.doctorName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      activitySubtitleBuilder: (doctorId) {
        final count = prescStore.forStoreAndDoctor(storeId, doctorId).length;
        final last = prescStore.forStoreAndDoctor(storeId, doctorId).firstOrNull?.sentAt;
        return '$count prescriptions${last != null ? ' Â· Last: ${DateFormat('dd MMM').format(last)}' : ''}';
      },
      onApprove: (id, doctorName) {
        connStore.approveByStore(id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected with ${partnerDoctorLabel(doctorName)}'),
            backgroundColor: AppColors.pharmacyGreen,
          ),
        );
      },
      onReject: (id, doctorName) {
        connStore.rejectByStore(id);
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
      pageLayoutBuilder: (context, child) => PharmacyPageLayout(child: child),
    );
  }
}