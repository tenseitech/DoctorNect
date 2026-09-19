import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firebase/ambulance_auth_helper.dart';

import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../models/ambulance_models.dart';
import 'ambulance_store.dart';

/// Keeps [AmbulanceStore] in sync with Firestore broadcast + request documents.
class AmbulanceBookingSync {
  AmbulanceBookingSync._();

  static final AmbulanceBookingSync instance = AmbulanceBookingSync._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driverSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _patientSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _patientHistorySub;
  String? _watchingDriverId;
  String? _watchingBroadcastId;
  String? _watchingPatientId;

  void watchDriverRequests(String driverId) {
    if (!FirebaseBootstrap.isReady || driverId.isEmpty) return;
    if (_watchingDriverId == driverId && _driverSub != null) return;

    _driverSub?.cancel();
    _watchingDriverId = driverId;

    _driverSub = FirebaseFirestore.instance
        .collection(FirestorePaths.ambulanceRequests)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .listen(
      (snapshot) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          _mergeDriverRequest(doc.id, data);
        }
      },
      onError: (e, st) {
        if (kDebugMode) debugPrint('Ambulance driver sync error: $e\n$st');
        // Retry after ensuring auth is ready
        _driverSub?.cancel();
        _driverSub = null;
        _watchingDriverId = null;
        Future.delayed(const Duration(seconds: 3), () async {
          await AmbulanceAuthHelper.ensureSignedIn();
          watchDriverRequests(driverId);
        });
      },
    );
  }

  void watchPatientBroadcast(String broadcastId) {
    if (!FirebaseBootstrap.isReady || broadcastId.isEmpty) return;
    if (_watchingBroadcastId == broadcastId && _patientSub != null) return;

    _patientSub?.cancel();
    _watchingBroadcastId = broadcastId;

    _patientSub = FirebaseFirestore.instance
        .collection(FirestorePaths.ambulanceBroadcasts)
        .doc(broadcastId)
        .snapshots()
        .listen(
      (snapshot) {
        final data = snapshot.data();
        if (data == null) return;
        _mergePatientBroadcast(broadcastId, data);
      },
      onError: (e, st) {
        if (kDebugMode) debugPrint('Ambulance patient sync error: $e\n$st');
      },
    );
  }

  void watchPatientHistory(String patientId) {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return;
    if (_watchingPatientId == patientId && _patientHistorySub != null) return;

    _patientHistorySub?.cancel();
    _watchingPatientId = patientId;

    _patientHistorySub = FirebaseFirestore.instance
        .collection(FirestorePaths.ambulanceBroadcasts)
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .listen(
      (snapshot) {
        for (final doc in snapshot.docs) {
          _mergePatientBroadcast(doc.id, doc.data());
        }
      },
      onError: (e, st) {
        if (kDebugMode)
          debugPrint('Ambulance patient history sync error: $e\n$st');
      },
    );
  }

  void stopPatientWatch() {
    _patientSub?.cancel();
    _patientSub = null;
    _watchingBroadcastId = null;
  }

  void stopPatientHistoryWatch() {
    _patientHistorySub?.cancel();
    _patientHistorySub = null;
    _watchingPatientId = null;
  }

  void stopDriverWatch() {
    _driverSub?.cancel();
    _driverSub = null;
    _watchingDriverId = null;
  }

  void dispose() {
    stopPatientWatch();
    stopPatientHistoryWatch();
    stopDriverWatch();
  }

  void _mergeDriverRequest(String requestDocId, Map<String, dynamic> data) {
    final broadcastId = data['broadcastId'] as String? ?? '';
    if (broadcastId.isEmpty) return;

    final statusRaw = data['status'] as String? ?? 'pending';
    final store = AmbulanceStore.instance;
    final existing = store.findBooking(broadcastId);

    final booking = _bookingFromRequestData(
      broadcastId: broadcastId,
      requestDocId: requestDocId,
      data: data,
      existing: existing,
      forceStatus: _driverBookingStatus(statusRaw),
      rawStatus: statusRaw,
    );

    store.upsertBooking(booking);
  }

  void _mergePatientBroadcast(String broadcastId, Map<String, dynamic> data) {
    final store = AmbulanceStore.instance;
    final existing = store.findBooking(broadcastId);
    final statusRaw = data['status'] as String? ?? 'pending';

    final booking = AmbulanceBooking(
      id: broadcastId,
      patientName:
          data['patientName'] as String? ?? existing?.patientName ?? 'Patient',
      pickupLocation:
          data['pickupLocation'] as String? ?? existing?.pickupLocation ?? '',
      contactPhone:
          data['contactPhone'] as String? ?? existing?.contactPhone ?? '',
      notes: existing?.notes ?? 'Destination: ${data['dropLocation'] ?? ''}',
      bookedByRole: _parseRole(data['bookedByRole'] as String?),
      bookedByName:
          data['patientName'] as String? ?? existing?.bookedByName ?? 'Patient',
      bookedById: data['patientId'] as String? ?? existing?.bookedById ?? '',
      createdAt: _parseDate(data['createdAt']) ??
          existing?.createdAt ??
          DateTime.now(),
      status: _patientBookingStatus(statusRaw),
      acceptedAmbulanceId: data['acceptedDriverId'] as String?,
      acceptedAmbulanceName: data['acceptedAmbulanceName'] as String?,
      acceptedDriverName:
          data['acceptedDriverName'] as String? ?? existing?.acceptedDriverName,
      acceptedDriverPhone: data['acceptedDriverPhone'] as String? ??
          existing?.acceptedDriverPhone,
      acceptedVehicleNumber: data['acceptedVehicleNumber'] as String? ??
          existing?.acceptedVehicleNumber,
      acceptedAmbulanceType: data['acceptedAmbulanceType'] as String? ??
          existing?.acceptedAmbulanceType,
      acceptedAt: _parseDate(data['acceptedAt']),
      rating: (data['rating'] as num?)?.toInt() ?? existing?.rating,
      review: data['review'] as String? ?? existing?.review,
      rawStatus:
          (statusRaw == 'cancelled' && data['cancelledByRole'] == 'driver')
              ? 'rejected'
              : statusRaw,
    );

    store.upsertBooking(booking);
  }

  AmbulanceBooking _bookingFromRequestData({
    required String broadcastId,
    required String requestDocId,
    required Map<String, dynamic> data,
    required AmbulanceBooking? existing,
    required AmbulanceBookingStatus forceStatus,
    String? rawStatus,
  }) {
    final drop = data['dropLocation'] as String? ?? '';
    return AmbulanceBooking(
      id: broadcastId,
      firestoreRequestId: requestDocId,
      patientName:
          data['patientName'] as String? ?? existing?.patientName ?? 'Patient',
      pickupLocation:
          data['pickupLocation'] as String? ?? existing?.pickupLocation ?? '',
      contactPhone:
          data['contactPhone'] as String? ?? existing?.contactPhone ?? '',
      notes: drop.isNotEmpty ? 'Destination: $drop' : existing?.notes,
      bookedByRole: _parseRole(data['bookedByRole'] as String?),
      bookedByName:
          data['patientName'] as String? ?? existing?.bookedByName ?? 'Patient',
      bookedById: data['patientId'] as String? ?? existing?.bookedById ?? '',
      createdAt: _parseDate(data['createdAt']) ??
          existing?.createdAt ??
          DateTime.now(),
      status: forceStatus,
      acceptedAmbulanceId:
          _acceptedDriverId(data, forceStatus, existing?.acceptedAmbulanceId),
      acceptedAmbulanceName: data['acceptedAmbulanceName'] as String? ??
          existing?.acceptedAmbulanceName,
      acceptedAt: _parseDate(data['acceptedAt']) ?? existing?.acceptedAt,
      rating: (data['rating'] as num?)?.toInt() ?? existing?.rating,
      review: data['review'] as String? ?? existing?.review,
      rawStatus: rawStatus ?? existing?.rawStatus,
    );
  }

  String? _acceptedDriverId(
    Map<String, dynamic> data,
    AmbulanceBookingStatus status,
    String? existing,
  ) {
    final explicit = data['acceptedDriverId'] as String?;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (existing != null && existing.isNotEmpty) return existing;
    if (status == AmbulanceBookingStatus.accepted ||
        status == AmbulanceBookingStatus.completed) {
      final driverId = data['driverId'] as String?;
      if (driverId != null && driverId.isNotEmpty) return driverId;
    }
    return null;
  }

  AmbulanceBookingStatus _driverBookingStatus(String raw) {
    return switch (raw) {
      'completed' => AmbulanceBookingStatus.completed,
      'accepted' => AmbulanceBookingStatus.accepted,
      'cancelled' || 'expired' => AmbulanceBookingStatus.cancelled,
      'taken' => AmbulanceBookingStatus.cancelled,
      'rejected' => AmbulanceBookingStatus.cancelled,
      _ => AmbulanceBookingStatus.pending,
    };
  }

  AmbulanceBookingStatus _patientBookingStatus(String raw) {
    return switch (raw) {
      'completed' => AmbulanceBookingStatus.completed,
      'accepted' => AmbulanceBookingStatus.accepted,
      'cancelled' || 'expired' => AmbulanceBookingStatus.cancelled,
      _ => AmbulanceBookingStatus.pending,
    };
  }

  AmbulanceBookedByRole _parseRole(String? raw) {
    if (raw == AmbulanceBookedByRole.doctor.name) {
      return AmbulanceBookedByRole.doctor;
    }
    return AmbulanceBookedByRole.patient;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
