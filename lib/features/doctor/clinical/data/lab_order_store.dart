import '../../../../core/firebase/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/firebase/models/doctor_lab_order.dart';
import '../../../../core/session/doctor_session.dart';

/// In-memory cache of doctor lab orders (backed by Firestore).
class LabOrderStore extends ChangeNotifier {
  LabOrderStore._();

  static final LabOrderStore instance = LabOrderStore._();

  final List<DoctorLabOrder> _orders = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastPage;
  DocumentSnapshot<Map<String, dynamic>>? _lastPatientPage;
  bool _hasMore = true;
  bool _hasMorePatient = true;

  List<DoctorLabOrder> get all => List.unmodifiable(_orders);
  bool get hasMore => _hasMore;
  bool get hasMorePatient => _hasMorePatient;

  List<DoctorLabOrder> forDoctor(String doctorId) {
    return _orders.where((o) => o.doctorId == doctorId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<DoctorLabOrder> forLabAndDoctor(String labId, String doctorId) {
    return _orders
        .where((o) => o.labId == labId && o.doctorId == doctorId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<DoctorLabOrder> forPatient(String patientId) {
    return _orders.where((o) => o.patientId == patientId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  DoctorLabOrder? findById(String orderId) {
    for (final order in _orders) {
      if (order.orderId == orderId) return order;
    }
    return null;
  }

  bool _hasPatientOrders(String patientId) =>
      _orders.any((o) => o.patientId == patientId);

  bool _hasDoctorOrders(String doctorId) =>
      doctorId.isNotEmpty && _orders.any((o) => o.doctorId == doctorId);

  bool get _isDoctorContext => DoctorSession.loggedInDoctorId.isNotEmpty;

  void _purgePatientOrders(String patientId) {
    final hadOrders = _orders.any((o) => o.patientId == patientId);
    _orders.removeWhere((o) => o.patientId == patientId);
    if (hadOrders) notifyListeners();
  }

  Future<bool> _isPatientVisibleToDoctor(String patientId, {bool preferCache = true}) async {
    if (!_isDoctorContext) return true;
    if (patientId.isEmpty) return true;
    return FirestoreService.instance.patientProfile.isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    );
  }

  Future<List<DoctorLabOrder>> _filterOrdersForDoctor(
    List<DoctorLabOrder> items, {
    bool preferCache = true,
  }) async {
    if (!_isDoctorContext) return items;

    final visible = <DoctorLabOrder>[];
    final decided = <String, bool>{};

    for (final order in items) {
      final patientId = order.patientId;
      if (patientId.isEmpty) {
        visible.add(order);
        continue;
      }

      final cachedDecision = decided[patientId];
      if (cachedDecision == false) continue;
      if (cachedDecision == true) {
        visible.add(order);
        continue;
      }

      final allowed = await _isPatientVisibleToDoctor(patientId, preferCache: preferCache);
      decided[patientId] = allowed;
      if (allowed) {
        visible.add(order);
      } else {
        _purgePatientOrders(patientId);
      }
    }

    return visible;
  }

  Future<void> add(DoctorLabOrder order) async { // FIXED: async + awaited so Firestore save failures surface
    await FirestoreService.instance.labOrder.save(order); // FIXED: persist before updating local state; rethrows on failure
    _orders.removeWhere((o) => o.orderId == order.orderId);
    _orders.insert(0, order);
    notifyListeners();
  }

  void mergeFromFirestore(List<DoctorLabOrder> remote) {
    for (final remoteOrder in remote) {
      _orders.removeWhere((o) => o.orderId == remoteOrder.orderId);
      _orders.add(remoteOrder);
    }
    _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  /// Applies sharing gate before merging doctor-facing Firestore payloads.
  Future<void> mergeFromFirestoreForDoctor(
    List<DoctorLabOrder> remote, {
    bool preferCache = true,
  }) async {
    final visible = await _filterOrdersForDoctor(remote, preferCache: preferCache);
    mergeFromFirestore(visible);
  }

  Future<void> refreshForDoctor({bool preferCache = true}) async {
    final doctorId = DoctorSession.loggedInDoctorId;
    if (preferCache && _hasDoctorOrders(doctorId)) return;

    _lastPage = null;
    _hasMore = true;
    await loadMoreForDoctor(preferCache: preferCache);
  }

  Future<void> loadMoreForDoctor({bool preferCache = true}) async {
    if (!_hasMore) return;
    final page = await FirestoreService.instance.labOrder.fetchForDoctor(
      DoctorSession.loggedInDoctorId,
      startAfter: _lastPage,
      preferCache: preferCache,
    );
    final visible = await _filterOrdersForDoctor(page.items, preferCache: preferCache);
    mergeFromFirestore(visible);
    _lastPage = page.lastDocument;
    _hasMore = page.hasMore;
  }

  Future<void> refreshForPatient(String patientId, {bool preferCache = true}) async {
    if (_isDoctorContext &&
        !await _isPatientVisibleToDoctor(patientId, preferCache: preferCache)) {
      _purgePatientOrders(patientId);
      _lastPatientPage = null;
      _hasMorePatient = false;
      return;
    }

    if (preferCache && _hasPatientOrders(patientId)) return;

    _lastPatientPage = null;
    _hasMorePatient = true;
    await loadMoreForPatient(patientId, preferCache: preferCache);
  }

  Future<void> loadMoreForPatient(String patientId, {bool preferCache = true}) async {
    if (!_hasMorePatient || patientId.isEmpty) return;

    if (_isDoctorContext &&
        !await _isPatientVisibleToDoctor(patientId, preferCache: preferCache)) {
      _purgePatientOrders(patientId);
      _hasMorePatient = false;
      return;
    }

    final page = _isDoctorContext
        ? await FirestoreService.instance.labOrder.fetchForPatientForDoctor(
            patientId,
            startAfter: _lastPatientPage,
            preferCache: preferCache,
          )
        : await FirestoreService.instance.labOrder.fetchForPatient(
            patientId,
            startAfter: _lastPatientPage,
            preferCache: preferCache,
          );
    mergeFromFirestore(page.items);
    _lastPatientPage = page.lastDocument;
    _hasMorePatient = page.hasMore;
  }
}
