import 'package:flutter/foundation.dart';

import '../../../core/notifications/ambulance_notification_emitter.dart';
import '../models/ambulance_models.dart';

class AmbulanceStore extends ChangeNotifier {
  AmbulanceStore._();

  static final AmbulanceStore instance = AmbulanceStore._();

  final List<RegisteredAmbulance> _providers = [];

  final List<AmbulanceBooking> _bookings = [];
  final Map<String, List<AmbulanceDriverAlert>> _driverAlerts = {};
  final Map<String, Set<String>> _driverRejectedBookings = {};

  List<RegisteredAmbulance> get registeredAmbulances =>
      List.unmodifiable(_providers);
  List<AmbulanceBooking> get bookings => List.unmodifiable(_bookings);

  void clear() {
    _bookings.clear();
    _driverAlerts.clear();
    _driverRejectedBookings.clear();
    notifyListeners();
  }

  RegisteredAmbulance? findAmbulance(String id) {
    for (final a in _providers) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ── Registration ────────────────────────────────────────────────────────────

  /// Add a newly-registered ambulance to the local list.
  void registerAmbulance(RegisteredAmbulance ambulance) {
    // Avoid duplicates by id
    _providers.removeWhere((a) => a.id == ambulance.id);
    _providers.insert(0, ambulance);
    notifyListeners();
  }

  /// Update an existing ambulance profile in the local list.
  void updateRegisteredAmbulance(RegisteredAmbulance ambulance) {
    final index = _providers.indexWhere((a) => a.id == ambulance.id);
    if (index >= 0) {
      _providers[index] = ambulance;
    } else {
      _providers.insert(0, ambulance);
    }
    notifyListeners();
  }

  /// Replace the whole list (after Firestore fetch).
  void loadAmbulances(List<RegisteredAmbulance> ambulances) {
    _providers.clear();
    _providers.addAll(ambulances);
    notifyListeners();
  }

  /// Toggle or set driver availability.
  void updateAvailability(String ambulanceId, bool available) {
    final index = _providers.indexWhere((a) => a.id == ambulanceId);
    if (index >= 0) {
      final amb = _providers[index];
      _providers[index] = RegisteredAmbulance(
        id: amb.id,
        serviceName: amb.serviceName,
        ownerName: amb.ownerName,
        driverName: amb.driverName,
        phone: amb.phone,
        vehicleNumber: amb.vehicleNumber,
        ambulanceType: amb.ambulanceType,
        city: amb.city,
        username: amb.username,
        serviceAreas: amb.serviceAreas,
        baseAddress: amb.baseAddress,
        licenseNumber: amb.licenseNumber,
        insuranceNumber: amb.insuranceNumber,
        hasOxygen: amb.hasOxygen,
        hasVentilator: amb.hasVentilator,
        hasStretcher: amb.hasStretcher,
        is24x7: amb.is24x7,
        ratePerKm: amb.ratePerKm,
        pin: amb.pin,
        totalRating: amb.totalRating,
        ratingCount: amb.ratingCount,
        available: available,
        createdAt: amb.createdAt,
      );
      notifyListeners();
    }
  }

  // ── Alerts ──────────────────────────────────────────────────────────────────

  List<AmbulanceDriverAlert> alertsFor(String ambulanceId) =>
      List.unmodifiable(_driverAlerts[ambulanceId] ?? const []);

  int unreadAlertCount(String ambulanceId) =>
      alertsFor(ambulanceId).where((a) => !a.isRead).length;

  void markAlertsRead(String ambulanceId) {
    final list = _driverAlerts[ambulanceId];
    if (list == null || list.isEmpty) return;
    _driverAlerts[ambulanceId] = [
      for (final a in list) a.copyWith(isRead: true),
    ];
    notifyListeners();
  }

  void markAlertRead(String ambulanceId, String alertId) {
    final list = _driverAlerts[ambulanceId];
    if (list == null || list.isEmpty) return;
    _driverAlerts[ambulanceId] = [
      for (final a in list) a.id == alertId ? a.copyWith(isRead: true) : a,
    ];
    notifyListeners();
  }

  // ── Bookings ────────────────────────────────────────────────────────────────

  /// Whether [ambulanceId] declined this pending broadcast (offline / local state).
  bool hasDriverRejectedBooking({
    required String ambulanceId,
    required String bookingId,
  }) =>
      _driverRejectedBookings[ambulanceId]?.contains(bookingId) ?? false;

  /// Pending broadcast visible to a specific driver (excludes their rejections).
  bool isPendingForDriver(AmbulanceBooking booking, String ambulanceId) =>
      booking.isPending &&
      booking.acceptedAmbulanceId == null &&
      !hasDriverRejectedBooking(
          ambulanceId: ambulanceId, bookingId: booking.id);

  /// Driver-declined booking for the cancelled tab (offline fallback).
  bool isDriverRejectedBookingView(
          AmbulanceBooking booking, String ambulanceId) =>
      hasDriverRejectedBooking(
          ambulanceId: ambulanceId, bookingId: booking.id) &&
      booking.isPending &&
      booking.acceptedAmbulanceId == null;

  AmbulanceBooking? findBooking(String id) {
    for (final b in _bookings) {
      if (b.id == id) return b;
    }
    return null;
  }

  AmbulanceBookingStatus _mergeBookingStatus(
    AmbulanceBookingStatus previous,
    AmbulanceBookingStatus incoming,
  ) {
    if (incoming == AmbulanceBookingStatus.completed ||
        previous == AmbulanceBookingStatus.completed) {
      return AmbulanceBookingStatus.completed;
    }
    if (incoming == AmbulanceBookingStatus.cancelled ||
        previous == AmbulanceBookingStatus.cancelled) {
      return AmbulanceBookingStatus.cancelled;
    }
    if (incoming == AmbulanceBookingStatus.accepted ||
        previous == AmbulanceBookingStatus.accepted) {
      return AmbulanceBookingStatus.accepted;
    }
    return incoming;
  }

  void upsertBooking(AmbulanceBooking booking) {
    final index = _bookings.indexWhere((b) => b.id == booking.id);
    if (index >= 0) {
      final previous = _bookings[index];
      _bookings[index] = AmbulanceBooking(
        id: booking.id,
        firestoreRequestId:
            booking.firestoreRequestId ?? previous.firestoreRequestId,
        patientName: booking.patientName,
        pickupLocation: booking.pickupLocation,
        contactPhone: booking.contactPhone,
        notes: booking.notes,
        bookedByRole: booking.bookedByRole,
        bookedByName: booking.bookedByName,
        bookedById: booking.bookedById,
        createdAt: booking.createdAt,
        status: _mergeBookingStatus(previous.status, booking.status),
        acceptedAmbulanceId:
            booking.acceptedAmbulanceId ?? previous.acceptedAmbulanceId,
        acceptedAmbulanceName:
            booking.acceptedAmbulanceName ?? previous.acceptedAmbulanceName,
        acceptedDriverName:
            booking.acceptedDriverName ?? previous.acceptedDriverName,
        acceptedDriverPhone:
            booking.acceptedDriverPhone ?? previous.acceptedDriverPhone,
        acceptedVehicleNumber:
            booking.acceptedVehicleNumber ?? previous.acceptedVehicleNumber,
        acceptedAmbulanceType:
            booking.acceptedAmbulanceType ?? previous.acceptedAmbulanceType,
        acceptedAt: booking.acceptedAt ?? previous.acceptedAt,
        rating: booking.rating ?? previous.rating,
        review: booking.review ?? previous.review,
        rawStatus: booking.rawStatus ?? previous.rawStatus,
      );
    } else {
      _bookings.insert(0, booking);
    }
    notifyListeners();
  }

  String createBooking({
    required String patientName,
    required String pickupLocation,
    required String contactPhone,
    required AmbulanceBookedByRole bookedByRole,
    required String bookedByName,
    required String bookedById,
    String? notes,
  }) {
    final id = 'amb-req-${DateTime.now().millisecondsSinceEpoch}';
    final booking = AmbulanceBooking(
      id: id,
      patientName: patientName.trim(),
      pickupLocation: pickupLocation.trim(),
      contactPhone: contactPhone.trim(),
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      bookedByRole: bookedByRole,
      bookedByName: bookedByName.trim(),
      bookedById: bookedById,
      createdAt: DateTime.now(),
    );
    _bookings.insert(0, booking);

    for (final ambulance in _providers) {
      _pushDriverAlert(
        ambulance.id,
        AmbulanceDriverAlert(
          id: 'alert-$id-${ambulance.id}',
          title: 'New ambulance request',
          body: '${booking.patientName} · ${booking.pickupLocation}',
          createdAt: DateTime.now(),
          bookingId: id,
        ),
      );
    }

    notifyListeners();
    return id;
  }

  /// Direct request to one driver (offline / Firestore fallback).
  String? createDirectRequest({
    required String driverId,
    required String patientId,
    required String pickupLocation,
    required String dropLocation,
    String? patientName,
    String? contactPhone,
  }) {
    final ambulance = findAmbulance(driverId);
    if (ambulance == null) return null;

    final id = 'amb-req-${DateTime.now().millisecondsSinceEpoch}';
    final booking = AmbulanceBooking(
      id: id,
      patientName: patientName?.trim().isNotEmpty == true
          ? patientName!.trim()
          : 'Patient',
      pickupLocation: pickupLocation,
      contactPhone: contactPhone?.trim() ?? '',
      notes: 'Destination: $dropLocation',
      bookedByRole: AmbulanceBookedByRole.patient,
      bookedByName: patientName ?? 'Patient',
      bookedById: patientId,
      createdAt: DateTime.now(),
    );
    _bookings.insert(0, booking);

    _pushDriverAlert(
      driverId,
      AmbulanceDriverAlert(
        id: 'alert-$id-$driverId',
        title: 'New ambulance request',
        body: '${booking.patientName} · $pickupLocation → $dropLocation',
        createdAt: DateTime.now(),
        bookingId: id,
      ),
    );

    notifyListeners();
    return id;
  }

  /// Broadcast request to every driver in [driverIds] (offline / Firestore fallback).
  String? createBroadcastRequest({
    required List<String> driverIds,
    required String patientId,
    required String pickupLocation,
    required String dropLocation,
    String? patientName,
    String? contactPhone,
    String? bookedByRole, // FIXED: accept the real booker role
  }) {
    if (driverIds.isEmpty) return null;

    final id = 'amb-broadcast-${DateTime.now().millisecondsSinceEpoch}';
    final booking = AmbulanceBooking(
      id: id,
      patientName: patientName?.trim().isNotEmpty == true
          ? patientName!.trim()
          : 'Patient',
      pickupLocation: pickupLocation,
      contactPhone: contactPhone?.trim() ?? '',
      notes:
          'Destination: $dropLocation · Broadcast to ${driverIds.length} drivers',
      bookedByRole: bookedByRole ==
              AmbulanceBookedByRole
                  .doctor.name // FIXED: was hardcoded to patient
          ? AmbulanceBookedByRole.doctor
          : AmbulanceBookedByRole.patient,
      bookedByName: patientName ?? 'Patient',
      bookedById: patientId,
      createdAt: DateTime.now(),
    );
    _bookings.insert(0, booking);

    for (final driverId in driverIds) {
      final ambulance = findAmbulance(driverId);
      if (ambulance == null) continue;
      _pushDriverAlert(
        driverId,
        AmbulanceDriverAlert(
          id: 'alert-$id-$driverId',
          title: 'New ambulance request',
          body: '${booking.patientName} · $pickupLocation → $dropLocation',
          createdAt: DateTime.now(),
          bookingId: id,
        ),
      );
    }

    notifyListeners();
    return id;
  }

  /// Returns true when this driver was first to accept.
  bool acceptBooking({required String bookingId, required String ambulanceId}) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index < 0) return false;

    final current = _bookings[index];
    if (!current.isPending) return false;

    final ambulance = findAmbulance(ambulanceId);
    if (ambulance == null) return false;

    final acceptedAt = DateTime.now();
    _bookings[index] = current.copyWithAccepted(
      ambulance: ambulance,
      acceptedAt: acceptedAt,
    );

    AmbulanceNotificationEmitter.notifyBookingAcceptedForBooker(
      booking: _bookings[index],
      ambulance: ambulance,
    );

    for (final other in _providers) {
      if (other.id == ambulanceId) continue;
      _pushDriverAlert(
        other.id,
        AmbulanceDriverAlert(
          id: 'accepted-$bookingId-${other.id}',
          title: 'Request already accepted',
          body:
              '${ambulance.serviceName} accepted ${current.patientName}\'s request.',
          createdAt: acceptedAt,
          bookingId: bookingId,
        ),
      );
    }

    notifyListeners();
    return true;
  }

  /// Cancel a pending or accepted booking locally (booker or driver after Firestore cancel).
  bool cancelBooking(String bookingId, {String? rawStatus}) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index < 0) return false;

    final current = _bookings[index];
    if (current.isCancelled) return true;
    if (current.isCompleted) return false;
    if (!current.isPending && !current.isAccepted) return false;

    _bookings[index] = current.copyWithCancelled(rawStatus: rawStatus);
    notifyListeners();
    return true;
  }

  /// Driver rejects a booking offline fallback — hides it for this driver only.
  bool rejectBooking({required String bookingId, required String ambulanceId}) {
    if (ambulanceId.isEmpty) return false;

    final booking = findBooking(bookingId);
    if (booking == null) return false;
    if (!booking.isPending || booking.acceptedAmbulanceId != null) return false;

    _driverRejectedBookings.putIfAbsent(ambulanceId, () => {}).add(bookingId);
    _removeDriverAlertsForBooking(
        ambulanceId: ambulanceId, bookingId: bookingId);
    notifyListeners();
    return true;
  }

  /// Mark an accepted booking as completed (driver finished the trip).
  bool completeBooking(String bookingId, {String? driverId}) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index < 0) return false;

    final current = _bookings[index];
    if (current.isCompleted) return true;
    if (current.isCancelled) return false;

    final ownsTrip = driverId != null &&
        driverId.isNotEmpty &&
        (current.acceptedAmbulanceId == driverId ||
            (current.acceptedAmbulanceId == null && current.isAccepted));

    if (!current.isAccepted && !ownsTrip) return false;
    if (driverId != null &&
        driverId.isNotEmpty &&
        current.acceptedAmbulanceId != null &&
        current.acceptedAmbulanceId != driverId) {
      return false;
    }

    _bookings[index] = current.copyWithCompleted();
    notifyListeners();
    return true;
  }

  /// Rate a completed booking and update the ambulance's cumulative rating.
  bool rateBooking({
    required String bookingId,
    required int stars,
    String? review,
  }) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index < 0) return false;

    final current = _bookings[index];
    if (!current.isCompleted && !current.isAccepted) return false;
    if (current.isRated) return false; // already rated

    _bookings[index] = current.copyWithRating(stars: stars, reviewText: review);

    // Update ambulance's cumulative rating
    final ambId = current.acceptedAmbulanceId;
    if (ambId != null) {
      final ambIndex = _providers.indexWhere((a) => a.id == ambId);
      if (ambIndex >= 0) {
        final amb = _providers[ambIndex];
        _providers[ambIndex] = RegisteredAmbulance(
          id: amb.id,
          serviceName: amb.serviceName,
          ownerName: amb.ownerName,
          driverName: amb.driverName,
          phone: amb.phone,
          vehicleNumber: amb.vehicleNumber,
          ambulanceType: amb.ambulanceType,
          city: amb.city,
          serviceAreas: amb.serviceAreas,
          baseAddress: amb.baseAddress,
          licenseNumber: amb.licenseNumber,
          insuranceNumber: amb.insuranceNumber,
          hasOxygen: amb.hasOxygen,
          hasVentilator: amb.hasVentilator,
          hasStretcher: amb.hasStretcher,
          is24x7: amb.is24x7,
          ratePerKm: amb.ratePerKm,
          pin: amb.pin,
          totalRating: amb.totalRating + stars,
          ratingCount: amb.ratingCount + 1,
          available: amb.available,
          createdAt: amb.createdAt,
        );
      }
    }

    notifyListeners();
    return true;
  }

  void _pushDriverAlert(String ambulanceId, AmbulanceDriverAlert alert) {
    final list = _driverAlerts.putIfAbsent(ambulanceId, () => []);
    list.insert(0, alert);
  }

  void _removeDriverAlertsForBooking({
    required String ambulanceId,
    required String bookingId,
  }) {
    final list = _driverAlerts[ambulanceId];
    if (list == null || list.isEmpty) return;
    _driverAlerts[ambulanceId] = [
      for (final alert in list)
        if (alert.bookingId != bookingId) alert,
    ];
  }

  /// Push alert for a driver (e.g. from FCM foreground handler).
  void registerDriverAlert(String ambulanceId, AmbulanceDriverAlert alert) {
    _pushDriverAlert(ambulanceId, alert);
    notifyListeners();
  }
}
