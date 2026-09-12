import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/enums/user_type.dart';
import '../../../core/firebase/firestore_screen_sync.dart';
import '../../../core/firebase/firestore_service.dart';
import '../../../core/firebase/models/doctor_lab_order.dart';
import '../../../core/location/location_match.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../lab/data/lab_connection_store.dart';
import '../../shared/widgets/invite_doctor_sheet.dart';
import '../clinical/data/lab_order_store.dart';
import '../profile/data/doctor_profile_store.dart';
import '../shared/doctor_connected_partners_base_screen.dart';
import 'doctor_lab_patients_screen.dart';

class DoctorConnectedLabsScreen extends StatefulWidget {
  const DoctorConnectedLabsScreen({
    super.key,
    this.showAppBar = true,
    this.appBarTitle,
  });

  final bool showAppBar;
  final String? appBarTitle;

  @override
  State<DoctorConnectedLabsScreen> createState() => _DoctorConnectedLabsScreenState();
}

class _DoctorConnectedLabsScreenState extends State<DoctorConnectedLabsScreen> {
  List<DoctorPartnerProfileItem> _searchResults = [];
  StreamSubscription<List<DoctorLabOrder>>? _ordersSub;

  String? _doctorCity() => pharmacyCityFilter(
        city: DoctorProfileStore.instance.profile.city,
        address: DoctorProfileStore.instance.profile.addressLine1,
      );

  @override
  void initState() {
    super.initState();
    final labs = LabConnectionStore.instance.searchLabs(
      '',
      cityFilter: _doctorCity(),
    );
    _searchResults = labs
        .map((l) => DoctorPartnerProfileItem(
              id: l.id,
              name: l.labName,
              ownerName: '',
              address: l.address,
              phone: l.phone,
              email: l.email,
              city: l.city,
              registrationNumber: l.licenseNumber,
            ))
        .toList();
  }

  void _searchLabs(String query) {
    final labs = LabConnectionStore.instance.searchLabs(
      query,
      cityFilter: _doctorCity(),
    );
    final mapped = labs
        .map((l) => DoctorPartnerProfileItem(
              id: l.id,
              name: l.labName,
              ownerName: '',
              address: l.address,
              phone: l.phone,
              email: l.email,
              city: l.city,
              registrationNumber: l.licenseNumber,
            ))
        .toList();
    if (!mounted) {
      _searchResults = mapped;
      return;
    }
    setState(() {
      _searchResults = mapped;
    });
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doctorId = DoctorSession.loggedInDoctorId;
    final connStore = LabConnectionStore.instance;
    final orderStore = LabOrderStore.instance;

    return DoctorConnectedPartnersBaseView(
      partnerRole: UserType.lab,
      partnerHeaderTitle: 'Diagnostic Labs',
      partnerHeaderSubtitle: 'Connect with verified diagnostic labs to send electronic lab orders.',
      partnerTypeLabel: 'Lab',
      accentColor: AppColors.labPurple,
      showAppBar: widget.showAppBar,
      appBarTitle: widget.appBarTitle,
      listenables: [connStore, orderStore],
      activeConnections: () => connStore
          .activeForDoctor(doctorId)
          .map((c) => DoctorPartnerConnectionItem(
                id: c.id,
                partnerId: c.labId,
                partnerName: c.labName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      pendingFromPartner: () => connStore
          .pendingForDoctor(doctorId)
          .map((c) => DoctorPartnerConnectionItem(
                id: c.id,
                partnerId: c.labId,
                partnerName: c.labName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      pendingFromDoctor: () => connStore
          .pendingSentByDoctor(doctorId)
          .map((c) => DoctorPartnerConnectionItem(
                id: c.id,
                partnerId: c.labId,
                partnerName: c.labName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      searchResults: () => _searchResults,
      searchHintText: 'Lab name, area, license no...',
      cityFilterLabel: _doctorCity,
      activitySubtitleBuilder: (partnerId) {
        final count = orderStore.forLabAndDoctor(partnerId, doctorId).length;
        return '$count test order${count == 1 ? '' : 's'}';
      },
      onSearchPartners: _searchLabs,
      onViewPatients: (partnerId, partnerName) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DoctorLabPatientsScreen(
              labId: partnerId,
              labName: partnerName,
              doctorId: doctorId,
            ),
          ),
        );
      },
      onDisconnect: (connectionId, _) => connStore.removeConnection(connectionId),
      onApprove: (connectionId, _) => connStore.approveByDoctor(connectionId),
      onReject: (connectionId, _) => connStore.rejectByDoctor(connectionId),
      onRevoke: (connectionId, _) => connStore.removeConnection(connectionId),
      onSendRequest: (partner) => connStore.sendRequestFromDoctor(doctorId: doctorId, labId: partner.id),
      onOpenAddPartner: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DoctorConnectedLabsScreen(
              showAppBar: true,
              appBarTitle: 'Add Lab',
            ),
          ),
        );
      },
      onOpenInviteSheet: () => InviteDoctorSheet.show(context),
      attachFirestoreSync: () {
        FirestoreScreenSync.attachLabPendingConnections(
          role: UserType.doctor,
          profileId: doctorId,
        );
        unawaited(
          connStore.refreshActiveConnections(
            role: UserType.doctor,
            profileId: doctorId,
            preferCache: true,
          ),
        );
        _ordersSub?.cancel();
        _ordersSub = FirestoreService.instance.labOrder
            .watchOrdersForDoctor(doctorId)
            .listen(orderStore.mergeFromFirestore);
      },
      detachFirestoreSync: () => FirestoreScreenSync.detachLabPendingConnections(),
      isConnected: (partnerId) => connStore.isConnected(doctorId, partnerId),
      isPendingSent: (partnerId) => connStore.isPendingSentByDoctor(doctorId: doctorId, labId: partnerId),
      isPendingFromPartner: (partnerId) => connStore.isPendingFromLab(doctorId: doctorId, labId: partnerId),
    );
  }
}