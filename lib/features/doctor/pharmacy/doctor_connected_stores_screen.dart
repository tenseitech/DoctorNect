import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/enums/user_type.dart';
import '../../../core/firebase/firestore_screen_sync.dart';
import '../../../core/firebase/firestore_service.dart';
import '../../../core/location/location_match.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../pharmacy/data/pharmacy_connection_store.dart';
import '../../pharmacy/data/pharmacy_prescription_store.dart';
import '../../pharmacy/models/pharmacy_models.dart';
import '../../shared/widgets/invite_doctor_sheet.dart';
import '../profile/data/doctor_profile_store.dart';
import '../shared/doctor_connected_partners_base_screen.dart';
import 'doctor_store_patients_screen.dart';

class DoctorConnectedStoresScreen extends StatefulWidget {
  const DoctorConnectedStoresScreen({
    super.key,
    this.showAppBar = true,
    this.appBarTitle,
  });

  final bool showAppBar;
  final String? appBarTitle;

  @override
  State<DoctorConnectedStoresScreen> createState() => _DoctorConnectedStoresScreenState();
}

class _DoctorConnectedStoresScreenState extends State<DoctorConnectedStoresScreen> {
  List<DoctorPartnerProfileItem> _searchResults = [];
  StreamSubscription<List<PharmacyPrescriptionDelivery>>? _deliverySub;

  String? _doctorCity() => pharmacyCityFilter(
        city: DoctorProfileStore.instance.profile.city,
        address: DoctorProfileStore.instance.profile.addressLine1,
      );

  @override
  void initState() {
    super.initState();
    final stores = PharmacyConnectionStore.instance.searchStores(
      '',
      cityFilter: _doctorCity(),
    );
    _searchResults = stores
        .map((s) => DoctorPartnerProfileItem(
              id: s.id,
              name: s.storeName,
              ownerName: s.ownerName,
              address: s.address,
              phone: s.phone,
              email: s.email,
              city: s.city,
              registrationNumber: s.drugLicenseNumber,
            ))
        .toList();
  }

  void _searchStores(String query) {
    final stores = PharmacyConnectionStore.instance.searchStores(
      query,
      cityFilter: _doctorCity(),
    );
    final mapped = stores
        .map((s) => DoctorPartnerProfileItem(
              id: s.id,
              name: s.storeName,
              ownerName: s.ownerName,
              address: s.address,
              phone: s.phone,
              email: s.email,
              city: s.city,
              registrationNumber: s.drugLicenseNumber,
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
    _deliverySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doctorId = DoctorSession.loggedInDoctorId;
    final connStore = PharmacyConnectionStore.instance;
    final prescStore = PharmacyPrescriptionStore.instance;

    return DoctorConnectedPartnersBaseView(
      partnerRole: UserType.medicalStore,
      partnerHeaderTitle: 'Medical Stores',
      partnerHeaderSubtitle: 'Connect with verified pharmacies to send digital prescriptions.',
      partnerTypeLabel: 'Medical Store',
      accentColor: AppColors.pharmacyGreen,
      showAppBar: widget.showAppBar,
      appBarTitle: widget.appBarTitle,
      listenables: [connStore, prescStore],
      activeConnections: () => connStore
          .activeForDoctor(doctorId)
          .map((c) => DoctorPartnerConnectionItem(
                id: c.id,
                partnerId: c.medicalStoreId,
                partnerName: c.storeName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      pendingFromPartner: () => connStore
          .pendingForDoctor(doctorId)
          .map((c) => DoctorPartnerConnectionItem(
                id: c.id,
                partnerId: c.medicalStoreId,
                partnerName: c.storeName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      pendingFromDoctor: () => connStore
          .pendingSentByDoctor(doctorId)
          .map((c) => DoctorPartnerConnectionItem(
                id: c.id,
                partnerId: c.medicalStoreId,
                partnerName: c.storeName,
                requestedAt: c.requestedAt,
                respondedAt: c.respondedAt,
              ))
          .toList(),
      searchResults: () => _searchResults,
      searchHintText: 'Store name, area, license no...',
      cityFilterLabel: _doctorCity,
      activitySubtitleBuilder: (partnerId) {
        final count = prescStore.forStoreAndDoctor(partnerId, doctorId).length;
        return '$count prescription${count == 1 ? '' : 's'}';
      },
      onSearchPartners: _searchStores,
      onViewPatients: (partnerId, partnerName) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DoctorStorePatientsScreen(
              storeId: partnerId,
              storeName: partnerName,
              doctorId: doctorId,
            ),
          ),
        );
      },
      onDisconnect: (connectionId, _) => connStore.removeConnection(connectionId),
      onApprove: (connectionId, _) => connStore.approveByDoctor(connectionId),
      onReject: (connectionId, _) => connStore.rejectByDoctor(connectionId),
      onRevoke: (connectionId, _) => connStore.removeConnection(connectionId),
      onSendRequest: (partner) => connStore.sendRequestFromDoctor(doctorId: doctorId, storeId: partner.id),
      onOpenAddPartner: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DoctorConnectedStoresScreen(
              showAppBar: true,
              appBarTitle: 'Add Medical Store',
            ),
          ),
        );
      },
      onOpenInviteSheet: () => InviteDoctorSheet.show(context),
      attachFirestoreSync: () {
        FirestoreScreenSync.attachPendingConnections(
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
        _deliverySub?.cancel();
        _deliverySub = FirestoreService.instance.pharmacyFirestore
            .watchDeliveriesForDoctor(doctorId)
            .listen(prescStore.mergeFromFirestore);
      },
      detachFirestoreSync: () => FirestoreScreenSync.detachPendingConnections(),
      isConnected: (partnerId) => connStore.isConnected(doctorId, partnerId),
      isPendingSent: (partnerId) => connStore.isPendingSentByDoctor(doctorId: doctorId, storeId: partnerId),
      isPendingFromPartner: (partnerId) => connStore.isPendingFromStore(doctorId: doctorId, storeId: partnerId),
    );
  }
}