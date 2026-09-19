import '../../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/enums/user_type.dart';
import '../../../core/location/location_match.dart';
import '../../patient/data/registered_doctors_store.dart';
import '../../pharmacy/data/pharmacy_connection_store.dart';
import '../../pharmacy/models/pharmacy_models.dart';
import '../models/lab_connection_models.dart';
import 'lab_notification_store.dart';
import 'lab_registry.dart';

class LabConnectionStore extends ChangeNotifier {
  LabConnectionStore._();

  static final LabConnectionStore instance = LabConnectionStore._();

  final List<LabConnection> _connections = [];

  void _persistConnection(LabConnection conn) {
    unawaited(FirestoreService.instance.labConnection.saveConnection(conn));
  }

  List<LabConnection> get all => List.unmodifiable(_connections);

  void clear() {
    _connections.clear();
    notifyListeners();
  }

  List<LabConnection> activeForDoctor(String doctorId) => _connections
      .where(
          (c) => c.doctorId == doctorId && c.status == ConnectionStatus.active)
      .toList();

  List<LabConnection> activeForLab(String labId) => _connections
      .where((c) => c.labId == labId && c.status == ConnectionStatus.active)
      .toList();

  List<LabConnection> pendingForDoctor(String doctorId) => _connections
      .where(
        (c) =>
            c.doctorId == doctorId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == LabConnectionRequester.lab,
      )
      .toList();

  List<LabConnection> pendingSentByLab(String labId) => _connections
      .where(
        (c) =>
            c.labId == labId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == LabConnectionRequester.lab,
      )
      .toList();

  List<LabConnection> pendingForLabFromDoctor(String labId) => _connections
      .where(
        (c) =>
            c.labId == labId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == LabConnectionRequester.doctor,
      )
      .toList();

  List<LabConnection> pendingSentByDoctor(String doctorId) => _connections
      .where(
        (c) =>
            c.doctorId == doctorId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == LabConnectionRequester.doctor,
      )
      .toList();

  bool isConnected(String doctorId, String labId) => _connections.any((c) =>
      c.doctorId == doctorId &&
      c.labId == labId &&
      c.status == ConnectionStatus.active);

  bool hasPendingFromDoctor(String doctorId, String labId) => _connections.any(
        (c) =>
            c.doctorId == doctorId &&
            c.labId == labId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == LabConnectionRequester.doctor,
      );

  bool hasPendingFromLab(String doctorId, String labId) => _connections.any(
        (c) =>
            c.doctorId == doctorId &&
            c.labId == labId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == LabConnectionRequester.lab,
      );

  bool isPendingSentByLab({required String labId, required String doctorId}) =>
      hasPendingFromLab(doctorId, labId);

  bool isPendingFromDoctor({required String labId, required String doctorId}) =>
      hasPendingFromDoctor(doctorId, labId);

  bool isPendingSentByDoctor(
          {required String doctorId, required String labId}) =>
      hasPendingFromDoctor(doctorId, labId);

  bool isPendingFromLab({required String doctorId, required String labId}) =>
      hasPendingFromLab(doctorId, labId);

  String? sendRequest({required String labId, required String doctorId}) =>
      sendRequestFromLab(labId: labId, doctorId: doctorId);

  List<RegisteredLabProfile> searchLabs(String query, {String? cityFilter}) {
    final q = query.trim().toLowerCase();
    final city = cityFilter?.trim() ?? '';
    var labs = LabRegistry.all;
    if (city.isNotEmpty) {
      labs = labs.where((l) => registeredLabMatchesCity(l, city)).toList();
    }
    if (q.isEmpty) return labs;

    return labs
        .where(
          (l) =>
              l.labName.toLowerCase().contains(q) ||
              l.address.toLowerCase().contains(q) ||
              l.licenseNumber.toLowerCase().contains(q) ||
              l.area.toLowerCase().contains(q),
        )
        .toList();
  }

  List<RegisteredDoctorSearchResult> searchDoctors(String query,
      {String? labId, String? cityFilter}) {
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
            councilNumber: PharmacyConnectionStore.councilNumbers[d.id],
          ),
        )
        .toList();
  }

  String? sendRequestFromDoctor(
      {required String doctorId, required String labId}) {
    if (isConnected(doctorId, labId)) {
      return 'Already connected with this lab';
    }
    if (hasPendingFromDoctor(doctorId, labId)) {
      return 'Invite already sent';
    }
    if (hasPendingFromLab(doctorId, labId)) {
      final conn = _connections.firstWhere(
        (c) =>
            c.doctorId == doctorId &&
            c.labId == labId &&
            c.status == ConnectionStatus.pending &&
            c.requestedBy == LabConnectionRequester.lab,
      );
      approveByDoctor(conn.id);
      return null;
    }

    final doctor = RegisteredDoctorsStore.instance.findById(doctorId);
    final lab = LabRegistry.findById(labId);
    if (doctor == null) return 'Doctor not found';
    if (lab == null) return 'Lab not found on DoctorNect';

    final conn = LabConnection(
      id: 'lconn${DateTime.now().millisecondsSinceEpoch}',
      doctorId: doctorId,
      doctorName: doctor.name,
      labId: labId,
      labName: lab.labName,
      status: ConnectionStatus.pending,
      requestedBy: LabConnectionRequester.doctor,
      requestedAt: DateTime.now(),
    );
    _connections.insert(0, conn);
    _persistConnection(conn);

    LabNotificationStore.instance.addLab(
      labId: labId,
      title: 'Doctor invite',
      message: 'Dr. ${doctor.name} sent you an invite',
      referenceId: conn.id,
    );

    notifyListeners();
    return null;
  }

  String? sendRequestFromLab(
      {required String labId, required String doctorId}) {
    if (!RegisteredDoctorsStore.instance.isRegistered(doctorId)) {
      return 'Doctor is not registered on DoctorNect';
    }
    if (isConnected(doctorId, labId) || hasPendingFromLab(doctorId, labId)) {
      return 'Connection already exists or pending';
    }
    if (hasPendingFromDoctor(doctorId, labId)) {
      approveByLab(
        _connections
            .firstWhere(
              (c) =>
                  c.doctorId == doctorId &&
                  c.labId == labId &&
                  c.status == ConnectionStatus.pending &&
                  c.requestedBy == LabConnectionRequester.doctor,
            )
            .id,
      );
      return null;
    }

    final doctor = RegisteredDoctorsStore.instance.findById(doctorId);
    final lab = LabRegistry.findById(labId);
    if (doctor == null || lab == null) return 'Invalid doctor or lab';

    final conn = LabConnection(
      id: 'lconn${DateTime.now().millisecondsSinceEpoch}',
      doctorId: doctorId,
      doctorName: doctor.name,
      labId: labId,
      labName: lab.labName,
      status: ConnectionStatus.pending,
      requestedBy: LabConnectionRequester.lab,
      requestedAt: DateTime.now(),
    );
    _connections.insert(0, conn);
    _persistConnection(conn);

    LabNotificationStore.instance.addLab(
      labId: labId,
      title: 'Request sent',
      message: 'Connection request sent to Dr. ${doctor.name}',
      referenceId: conn.id,
    );

    notifyListeners();
    return null;
  }

  void approveByDoctor(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null ||
        conn.status != ConnectionStatus.pending ||
        conn.requestedBy != LabConnectionRequester.lab) {
      return;
    }
    conn.status = ConnectionStatus.active;
    conn.respondedAt = DateTime.now();

    LabNotificationStore.instance.addLab(
      labId: conn.labId,
      title: 'Connection approved',
      message: 'Dr. ${conn.doctorName} approved your connection request',
      referenceId: conn.id,
    );

    _persistConnection(conn);
    notifyListeners();
  }

  void approveByLab(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null ||
        conn.status != ConnectionStatus.pending ||
        conn.requestedBy != LabConnectionRequester.doctor) {
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
        conn.requestedBy != LabConnectionRequester.lab) {
      return;
    }
    conn.status = ConnectionStatus.rejected;
    conn.respondedAt = DateTime.now();

    LabNotificationStore.instance.addLab(
      labId: conn.labId,
      title: 'Connection rejected',
      message: 'Dr. ${conn.doctorName} rejected your connection request',
      referenceId: conn.id,
    );

    _persistConnection(conn);
    notifyListeners();
  }

  void rejectByLab(String connectionId) {
    final conn = _find(connectionId);
    if (conn == null ||
        conn.status != ConnectionStatus.pending ||
        conn.requestedBy != LabConnectionRequester.doctor) {
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

  LabConnection? _find(String id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  void mergeFirestoreConnections(List<LabConnection> remoteConnections) {
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
        final doctorPage = await FirestoreService.instance.labConnection
            .fetchActiveConnectionsForDoctor(
          profileId,
          preferCache: preferCache,
        );
        mergeFirestoreConnections(doctorPage.items);
        break;
      case UserType.lab:
        final labPage = await FirestoreService.instance.labConnection
            .fetchActiveConnectionsForLab(
          profileId,
          preferCache: preferCache,
        );
        mergeFirestoreConnections(labPage.items);
      case UserType.medicalStore:
      case UserType.patient:
      case UserType.ambulance:
      case UserType.superAdmin:
        break;
    }
  }
}
