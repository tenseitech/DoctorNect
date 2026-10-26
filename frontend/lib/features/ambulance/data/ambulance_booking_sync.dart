import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/supabase/repositories/supabase_ambulance_repository.dart';
import '../models/ambulance_models.dart';
import 'ambulance_store.dart';

/// Keeps [AmbulanceStore] in sync with Supabase broadcast + request records.
class AmbulanceBookingSync {
  AmbulanceBookingSync._();

  static final AmbulanceBookingSync instance = AmbulanceBookingSync._();

  StreamSubscription? _driverSub;
  StreamSubscription? _patientSub;
  StreamSubscription? _patientHistorySub;
  String? _watchingDriverId;
  String? _watchingBroadcastId;
  String? _watchingPatientId;

  void watchDriverRequests(String driverId) {
    if (driverId.isEmpty) return;
    if (_watchingDriverId == driverId && _driverSub != null) return;

    _driverSub?.cancel();
    _watchingDriverId = driverId;

    _driverSub = SupabaseAmbulanceRepository.instance
        .watchIncomingRequests(driverId)
        .listen(
      (requests) {
        final store = AmbulanceStore.instance;
        for (final req in requests) {
          final existing = store.findBooking(req.id);
          final booking = AmbulanceBooking(
            id: req.id,
            patientName: req.pickupLocation.isNotEmpty
                ? req.pickupLocation
                : (existing?.patientName ?? 'Patient'),
            pickupLocation: req.pickupLocation,
            contactPhone: existing?.contactPhone ?? '',
            bookedByRole: AmbulanceBookedByRole.patient,
            bookedByName: existing?.bookedByName ?? 'Patient',
            bookedById: existing?.bookedById ?? '',
            createdAt: existing?.createdAt ?? DateTime.now(),
            status: req.status == AmbulanceRequestStatus.accepted
                ? AmbulanceBookingStatus.accepted
                : (req.status == AmbulanceRequestStatus.cancelled
                    ? AmbulanceBookingStatus.cancelled
                    : AmbulanceBookingStatus.pending),
          );
          store.upsertBooking(booking);
        }
      },
      onError: (e, st) {
        if (kDebugMode) debugPrint('Ambulance driver Supabase sync error: $e\n$st');
      },
    );
  }

  void watchPatientBroadcast(String broadcastId) {
    if (broadcastId.isEmpty) return;
    if (_watchingBroadcastId == broadcastId && _patientSub != null) return;

    _patientSub?.cancel();
    _watchingBroadcastId = broadcastId;

    _patientSub = SupabaseAmbulanceRepository.instance
        .watchPatientBroadcast(broadcastId)
        .listen(
      (booking) {
        if (booking != null) {
          AmbulanceStore.instance.upsertBooking(booking);
        }
      },
      onError: (e, st) {
        if (kDebugMode) debugPrint('Ambulance patient Supabase sync error: $e\n$st');
      },
    );
  }

  void watchPatientHistory(String patientId) {
    if (patientId.isEmpty) return;
    if (_watchingPatientId == patientId && _patientHistorySub != null) return;

    _patientHistorySub?.cancel();
    _watchingPatientId = patientId;

    _patientHistorySub = SupabaseAmbulanceRepository.instance
        .watchPatientHistory(patientId)
        .listen(
      (bookings) {
        for (final b in bookings) {
          AmbulanceStore.instance.upsertBooking(b);
        }
      },
      onError: (e, st) {
        if (kDebugMode) debugPrint('Ambulance history Supabase sync error: $e\n$st');
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
}
