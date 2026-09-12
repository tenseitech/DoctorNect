import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/enums/user_type.dart';
import '../../../core/firebase/firestore_screen_sync.dart';
import '../../../core/location/location_match.dart';
import '../../../core/session/medical_store_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../shared/partner/partner_connect_doctors_base_screen.dart';
import '../data/medical_store_registry.dart';
import '../data/pharmacy_connection_store.dart';
import '../data/pharmacy_prescription_store.dart';
import '../widgets/pharmacy_page_layout.dart';

/// Pharmacy doctor connection and discovery screen.
class ConnectDoctorsScreen extends StatelessWidget {
  const ConnectDoctorsScreen({
    super.key,
    this.showAppBar = false,
    this.appBarTitle,
  });

  final bool showAppBar;
  final String? appBarTitle;

  String? _pharmacyCityLabel() {
    final store = MedicalStoreRegistry.findById(MedicalStoreSession.loggedInStoreId);
    if (store == null) return null;
    return pharmacyCityFilter(city: store.city, address: store.address);
  }

  @override
  Widget build(BuildContext context) {
    final storeId = MedicalStoreSession.loggedInStoreId;
    final connStore = PharmacyConnectionStore.instance;
    final prescStore = PharmacyPrescriptionStore.instance;

    return PartnerConnectDoctorsBaseView(
      partnerRole: UserType.medicalStore,
      partnerId: storeId,
      partnerTypeLabel: 'store',
      accentColor: AppColors.pharmacyGreen,
      showAppBar: showAppBar,
      appBarTitle: appBarTitle,
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
      cityFilter: _pharmacyCityLabel,
      searchDoctorsFn: (query) => sortDoctorsAlphabetically(
        connStore.searchDoctors(
          query,
          storeId: storeId,
          cityFilter: _pharmacyCityLabel(),
        ),
      ),
      activitySubtitleBuilder: (doctorId) {
        final count = prescStore.forStoreAndDoctor(storeId, doctorId).length;
        final last = prescStore.forStoreAndDoctor(storeId, doctorId).firstOrNull?.sentAt;
        return '$count prescriptions${last != null ? ' Â· Last: ${DateFormat('dd MMM').format(last)}' : ''}';
      },
      onApproveConnection: (id, doctorName) => connStore.approveByStore(id),
      onRejectConnection: (id, doctorName) => connStore.rejectByStore(id),
      onRevokeConnection: (id, doctorName) => connStore.removeConnection(id),
      onRemoveConnection: (id, doctorName) => connStore.removeConnection(id),
      onSendRequest: (doctor) => connStore.sendRequest(storeId: storeId, doctorId: doctor.id),
      isConnected: (doctorId) => connStore.isConnected(doctorId, storeId),
      isPendingSent: (doctorId) => connStore.isPendingSentByStore(storeId: storeId, doctorId: doctorId),
      isPendingFromDoctor: (doctorId) => connStore.isPendingFromDoctor(storeId: storeId, doctorId: doctorId),
      attachFirestoreSync: () {
        FirestoreScreenSync.attachPendingConnections(
          role: UserType.medicalStore,
          profileId: storeId,
        );
        unawaited(
          connStore.refreshActiveConnections(
            role: UserType.medicalStore,
            profileId: storeId,
            preferCache: true,
          ),
        );
      },
      detachFirestoreSync: () => FirestoreScreenSync.detachPendingConnections(),
      pageLayoutBuilder: (context, child) => PharmacyPageLayout(child: child),
    );
  }
}