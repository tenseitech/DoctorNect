import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/enums/user_type.dart';
import '../../../core/firebase/firestore_screen_sync.dart';
import '../../../core/location/location_match.dart';
import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../shared/partner/partner_connect_doctors_base_screen.dart';
import '../../shared/widgets/lab_page_layout.dart';
import '../data/lab_connection_store.dart';
import '../data/lab_registry.dart';
import '../data/lab_worklist_store.dart';

/// Diagnostic Lab doctor connection and discovery screen.
class LabConnectDoctorsScreen extends StatelessWidget {
  const LabConnectDoctorsScreen({
    super.key,
    this.showAppBar = false,
    this.appBarTitle,
  });

  final bool showAppBar;
  final String? appBarTitle;

  String? _labCityLabel() {
    final lab = LabRegistry.findById(LabSession.loggedInLabId);
    if (lab == null) return null;
    return pharmacyCityFilter(city: lab.city, address: lab.address);
  }

  @override
  Widget build(BuildContext context) {
    final labId = LabSession.loggedInLabId;
    final connStore = LabConnectionStore.instance;
    final worklistStore = LabWorklistStore.instance;

    return PartnerConnectDoctorsBaseView(
      partnerRole: UserType.lab,
      partnerId: labId,
      partnerTypeLabel: 'lab',
      accentColor: AppColors.labPurple,
      showAppBar: showAppBar,
      appBarTitle: appBarTitle,
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
      cityFilter: _labCityLabel,
      searchDoctorsFn: (query) => sortDoctorsAlphabetically(
        connStore.searchDoctors(
          query,
          labId: labId,
          cityFilter: _labCityLabel(),
        ),
      ),
      activitySubtitleBuilder: (doctorId) {
        final count = worklistStore.forLabAndDoctor(labId, doctorId).length;
        final last = worklistStore.forLabAndDoctor(labId, doctorId).firstOrNull?.createdAt;
        return '$count test orders${last != null ? ' · Last: ${DateFormat('dd MMM').format(last)}' : ''}';
      },
      onApproveConnection: (id, doctorName) => connStore.approveByLab(id),
      onRejectConnection: (id, doctorName) => connStore.rejectByLab(id),
      onRevokeConnection: (id, doctorName) => connStore.removeConnection(id),
      onRemoveConnection: (id, doctorName) => connStore.removeConnection(id),
      onSendRequest: (doctor) => connStore.sendRequest(labId: labId, doctorId: doctor.id),
      isConnected: (doctorId) => connStore.isConnected(doctorId, labId),
      isPendingSent: (doctorId) => connStore.isPendingSentByLab(labId: labId, doctorId: doctorId),
      isPendingFromDoctor: (doctorId) => connStore.isPendingFromDoctor(labId: labId, doctorId: doctorId),
      attachFirestoreSync: () {
        FirestoreScreenSync.attachLabPendingConnections(
          role: UserType.lab,
          profileId: labId,
        );
        unawaited(
          connStore.refreshActiveConnections(
            role: UserType.lab,
            profileId: labId,
            preferCache: true,
          ),
        );
      },
      detachFirestoreSync: () => FirestoreScreenSync.detachLabPendingConnections(),
      pageLayoutBuilder: (context, child) => LabPageLayout(child: child),
    );
  }
}