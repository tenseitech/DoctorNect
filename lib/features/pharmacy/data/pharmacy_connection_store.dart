import '../../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/enums/user_type.dart';
import '../../../core/location/location_match.dart';
import '../../patient/data/registered_doctors_store.dart';
import '../models/pharmacy_models.dart';
import 'medical_store_registry.dart';
import 'pharmacy_notification_store.dart';

class PharmacyConnectionStore extends ChangeNotifier {
  PharmacyConnectionStore._();

  static final PharmacyConnectionStore instance = PharmacyConnectionStore._();

  final List<PharmacyConnection> _connections = [];

  static const councilNumbers = <String, String>{};

  void _persistConnection(PharmacyConnection conn) {
    unawaited(FirestoreService.instance.pharmacyFirestore.saveConnection(conn));
  }

  List<PharmacyConnection> get all => List.unmodifiable(_connections);

  void clear() {
    _connections.clear();
    notifyListeners();
  }

  List<PharmacyConnection> activeForDoctor(String doctorId) => _connections
      .where(
          (c) => c.doctorId == doctorId && c.status == ConnectionStatus.active)
      .toList();

  List<PharmacyConnection> activeForStore(String storeId) => _connections
      .where((c) =>
          c.medicalStoreId == storeId && c.status == ConnectionStatus.active)
      .toList();

  /// Pending requests that stores sent — doctor must approve.
  List<PharmacyConnection> pendingForDoctor(String doctorId) => _connections
      .where(
        (c) =>
            c.doctorId == doctorId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == ConnectionRequester.store,
      )
      .toList();

  /// Pending requests this store sent — waiting for doctor.
  List<PharmacyConnection> pendingSentByStore(String storeId) => _connections
      .where(
        (c) =>
            c.medicalStoreId == storeId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == ConnectionRequester.store,
      )
      .toList();

  /// Pending requests doctors sent — store must approve.
  List<PharmacyConnection> pendingForStoreFromDoctor(String storeId) =>
      _connections
          .where(
            (c) =>
                c.medicalStoreId == storeId &&
                c.status == ConnectionStatus.pending &&
                c.requestedBy == ConnectionRequester.doctor,
          )
          .toList();

  /// Pending requests this doctor sent — waiting for store.
  List<PharmacyConnection> pendingSentByDoctor(String doctorId) => _connections
      .where(
        (c) =>
            c.doctorId == doctorId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == ConnectionRequester.doctor,
      )
      .toList();

  bool isConnected(String doctorId, String storeId) => _connections.any((c) =>
      c.doctorId == doctorId &&
      c.medicalStoreId == storeId &&
      c.status == ConnectionStatus.active);

  bool hasPendingRequest(String doctorId, String storeId) => _connections.any(
      (c) =>
          c.doctorId == doctorId &&
          c.medicalStoreId == storeId &&
          c.status == ConnectionStatus.pending);

  bool hasPendingFromDoctor(String doctorId, String storeId) =>
      _connections.any(
        (c) =>
            c.doctorId == doctorId &&
            c.medicalStoreId == storeId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == ConnectionRequester.doctor,
      );

  bool hasPendingFromStore(String doctorId, String storeId) => _connections.any(
        (c) =>
            c.doctorId == doctorId &&
            c.medicalStoreId == storeId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == ConnectionRequester.store,
      );

  bool isPendingSentByStore(
          {required String storeId, required String doctorId}) =>
      hasPendingFromStore(doctorId, storeId);

  bool isPendingFromDoctor(
          {required String storeId, required String doctorId}) =>
      hasPendingFromDoctor(doctorId, storeId);

  bool isPendingSentByDoctor(
          {required String doctorId, required String storeId}) =>
      hasPendingFromDoctor(doctorId, storeId);

  bool isPendingFromStore(
          {required String doctorId, required String storeId}) =>
      hasPendingFromStore(doctorId, storeId);

  List<MedicalStoreProfile> searchStores(String query, {String? cityFilter}) {
    final q = query.trim().toLowerCase();
    final city = cityFilter?.trim() ?? '';
    var stores = MedicalStoreRegistry.all;
    if (city.isNotEmpty) {
      stores = stores.where((s) => medicalStoreMatchesCity(s, city)).toList();
    }
    if (q.isEmpty) return stores;

    return stores
        .where(
          (s) =>
              s.storeName.toLowerCase().contains(q) ||
              s.ownerName.toLowerCase().contains(q) ||
              s.address.toLowerCase().contains(q) ||
              s.drugLicenseNumber.toLowerCase().contains(q) ||
              s.phone.contains(q) ||
              s.email.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Doctor sends connection request to a registered medical store.
  String? sendRequestFromDoctor(
      {required String doctorId, required String storeId}) {
    if (isConnected(doctorId, storeId)) {
      return 'Already connected with this store';
    }
    if (hasPendingFromDoctor(doctorId, storeId)) {
      return 'Invite already sent';
    }
    if (hasPendingFromStore(doctorId, storeId)) {
      final conn = _connections.firstWhere(
        (c) =>
            c.doctorId == doctorId &&
            c.medicalStoreId == storeId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == ConnectionRequester.store,
      );
      approveByDoctor(conn.id);
      return null;
    }

    final doctor = RegisteredDoctorsStore.instance.findById(doctorId);
    final store = MedicalStoreRegistry.findById(storeId);
    if (doctor == null) return 'Doctor not found';
    if (store == null) return 'Medical store not found on DoctorNect';

    final conn = PharmacyConnection(
      id: 'conn${DateTime.now().millisecondsSinceEpoch}',
      doctorId: doctorId,
      doctorName: doctor.name,
      medicalStoreId: storeId,
      storeName: store.storeName,
      status: ConnectionStatus.pending,
      requestedBy: ConnectionRequester.doctor,
      requestedAt: DateTime.now(),
    );
    _connections.insert(0, conn);
    _persistConnection(conn);

    PharmacyNotificationStore.instance.addStore(
      storeId: storeId,
      title: 'Doctor invite',
      message: 'Dr. ${doctor.name} sent you an invite',
      referenceId: conn.id,
    );

    notifyListeners();
    return null;
  }

  List<RegisteredDoctorSearchResult> searchDoctors(
    String query, {
    String? storeId,
    String? cityFilter,
  }) {
    final q = query.trim().toLowerCase();
    final city = cityFilter?.trim() ?? '';

    final docs = RegisteredDoctorsStore.instance.searchableDoctors.where((d) {
      if (city.isNotEmpty && !doctorMatchesCity(d, city)) return false;
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) ||
          d.clinicName.toLowerCase().contains(q) ||
          d.specialization.toLowerCase().contains(q) ||
          d.id.toLowerCase() == q;
    });

    return docs
        .map(
          (d) => RegisteredDoctorSearchResult(
            id: d.id,
            name: d.name,
            specialization: d.specialization,
            clinicName: d.clinicName,
            councilNumber: councilNumbers[d.id],
          ),
        )
        .toList();
  }

  /// Store sends connection request to a registered doctor.
  String? sendRequest({required String storeId, required String doctorId}) {
    if (!RegisteredDoctorsStore.instance.isRegistered(doctorId)) {
      return 'Doctor is not registered on DoctorNect';
    }
    if (isConnected(doctorId, storeId) ||
        hasPendingFromStore(doctorId, storeId)) {
      return 'Connection already exists or pending';
    }
    if (hasPendingFromDoctor(doctorId, storeId)) {
      approveByStore(
        _connections
            .firstWhere(
              (c) =>
                  c.doctorId == doctorId &&
                  c.medicalStoreId == storeId &&
                  c.status == ConnectionStatus.pending &&
                  c.requestedBy == ConnectionRequester.doctor,
            )
            .id,
      );
      return null;
    }

    final doctor = RegisteredDoctorsStore.instance.findById(doctorId);
    final store = MedicalStoreRegistry.findById(storeId);
    if (doctor == null || store == null) return 'Invalid doctor or store';

    final conn = PharmacyConnection(
      id: 'conn${DateTime.now().millisecondsSinceEpoch}',
      doctorId: doctorId,
      doctorName: doctor.name,
      medicalStoreId: storeId,
      storeName: store.storeName,
      status: ConnectionStatus.pending,
      requestedBy: ConnectionRequester.store,
      requestedAt: DateTime.now(),
    );
    _connections.insert(0, conn);
    _persistConnection(conn);

    PharmacyNotificationStore.instance.addStore(
      storeId: storeId,
      title: 'Request sent',
      message: 'Connection request sent to Dr. ${doctor.name}',
      referenceId: conn.id,
    );

    notifyListeners();
    return null;
  }

  /// Used when a doctor registers via a pharmacy invite link (doctor may not be in directory yet).
  String? sendInviteConnection({
    required String storeId,
    required String doctorId,
    required String doctorName,
  }) {
    if (storeId.isEmpty || doctorId.isEmpty) return 'Invalid invite';
    if (isConnected(doctorId, storeId) ||
        hasPendingFromStore(doctorId, storeId)) {
      return null;
    }
    if (hasPendingFromDoctor(doctorId, storeId)) {
      approveByStore(
        _connections
            .firstWhere(
              (c) =>
                  c.doctorId == doctorId &&
                  c.medicalStoreId == storeId &&
                  c.status == ConnectionStatus.pending &&
                  c.requestedBy == ConnectionRequester.doctor,
            )
            .id,
      );
      return null;
    }

    final store = MedicalStoreRegistry.findById(storeId);
    final storeName = store?.storeName ?? 'Medical Store';
    final trimmedDoctorName =
        doctorName.trim().isEmpty ? 'Doctor' : doctorName.trim();

    final conn = PharmacyConnection(
      id: 'conn${DateTime.now().millisecondsSinceEpoch}',
      doctorId: doctorId,
      doctorName: trimmedDoctorName,
      medicalStoreId: storeId,
      storeName: storeName,
      status: ConnectionStatus.pending,
      requestedBy: ConnectionRequester.store,
      requestedAt: DateTime.now(),
    );
    _connections.insert(0, conn);
    _persistConnection(conn);

    PharmacyNotificationStore.instance.addStore(
      storeId: storeId,
      title: 'Doctor joined via invite',
      message: 'Connection request sent to Dr. $trimmedDoctorName',
      referenceId: conn.id,
    );

    notifyListeners();
    return null;
  }

  void approveByDoctor(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null ||
        conn.status != ConnectionStatus.pending ||
        conn.requestedBy != ConnectionRequester.store) {
      return;
    }
    conn.status = ConnectionStatus.active;
    conn.respondedAt = DateTime.now();

    PharmacyNotificationStore.instance.addStore(
      storeId: conn.medicalStoreId,
      title: 'Connection approved',
      message: 'Dr. ${conn.doctorName} approved your connection request',
      referenceId: conn.id,
    );

    _persistConnection(conn);
    notifyListeners();
  }

  void approveByStore(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null ||
        conn.status != ConnectionStatus.pending ||
        conn.requestedBy != ConnectionRequester.doctor) {
      return;
    }
    conn.status = ConnectionStatus.active;
    conn.respondedAt = DateTime.now();

    _persistConnection(conn);
    notifyListeners();
  }

  void rejectByDoctor(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null ||
        conn.status != ConnectionStatus.pending ||
        conn.requestedBy != ConnectionRequester.store) {
      return;
    }
    conn.status = ConnectionStatus.rejected;
    conn.respondedAt = DateTime.now();

    PharmacyNotificationStore.instance.addStore(
      storeId: conn.medicalStoreId,
      title: 'Connection rejected',
      message: 'Dr. ${conn.doctorName} rejected your connection request',
      referenceId: conn.id,
    );

    _persistConnection(conn);
    notifyListeners();
  }

  void rejectByStore(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null ||
        conn.status != ConnectionStatus.pending ||
        conn.requestedBy != ConnectionRequester.doctor) {
      return;
    }
    conn.status = ConnectionStatus.rejected;
    conn.respondedAt = DateTime.now();

    _persistConnection(conn);
    notifyListeners();
  }

  void removeConnection(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null) return;
    conn.status = ConnectionStatus.removed;
    conn.respondedAt = DateTime.now();
    _persistConnection(conn);
    notifyListeners();
  }

  PharmacyConnection? _find(String id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Merges Firestore documents without clearing local demo data.
  void mergeFirestoreConnections(List<PharmacyConnection> remoteConnections) {
    for (final remote in remoteConnections) {
      _connections.removeWhere((c) => c.id == remote.id);
      _connections.insert(0, remote);
    }
    notifyListeners();
  }

  Future<void> refreshActiveConnections({
    required UserType role,
    required String profileId,
    bool preferCache = true,
  }) async {
    switch (role) {
      case UserType.doctor:
        final doctorPage = await FirestoreService.instance.pharmacyFirestore
            .fetchActiveConnectionsForDoctor(
          profileId,
          preferCache: preferCache,
        );
        mergeFirestoreConnections(doctorPage.items);
        break;
      case UserType.medicalStore:
        final storePage = await FirestoreService.instance.pharmacyFirestore
            .fetchActiveConnectionsForStore(
          profileId,
          preferCache: preferCache,
        );
        mergeFirestoreConnections(storePage.items);
      case UserType.patient:
        break;
      case UserType.lab:
        break;
      case UserType.ambulance:
      case UserType.superAdmin:
        break;
    }
  }
}

class RegisteredDoctorSearchResult {
  const RegisteredDoctorSearchResult({
    required this.id,
    required this.name,
    required this.specialization,
    required this.clinicName,
    this.councilNumber,
  });

  final String id;
  final String name;
  final String specialization;
  final String clinicName;
  final String? councilNumber;
}
