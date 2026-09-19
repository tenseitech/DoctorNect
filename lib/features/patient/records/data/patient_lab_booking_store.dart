import '../../../../core/firebase/firestore_service.dart';
import 'package:flutter/foundation.dart';

import '../../lab/data/lab_booking_grouper.dart';

/// In-memory cache of patient lab bookings (blood tests booked via lab / shared by lab).
class PatientLabBookingStore extends ChangeNotifier {
  PatientLabBookingStore._();

  static final PatientLabBookingStore instance = PatientLabBookingStore._();

  final List<LabBookingRecord> _bookings = [];

  void clear() {
    _bookings.clear();
    notifyListeners();
  }

  List<LabBookingRecord> forPatient(String patientId) {
    final items = _bookings.where((b) => b.patientId == patientId).toList();
    return LabBookingGrouper.group(items);
  }

  LabBookingRecord? findById(String bookingId) {
    if (bookingId.isEmpty) return null;
    for (final grouped
        in LabBookingGrouper.group(List<LabBookingRecord>.from(_bookings))) {
      if (grouped.bookingId == bookingId ||
          grouped.groupedBookingIds.contains(bookingId)) {
        return grouped;
      }
    }
    return null;
  }

  void upsertBooking(LabBookingRecord booking) {
    _bookings.removeWhere((b) => b.bookingId == booking.bookingId);
    _bookings.add(booking);
    _bookings.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    notifyListeners();
  }

  void mergeFromFirestore(List<LabBookingRecord> remote) {
    for (final remoteBooking in remote) {
      _bookings.removeWhere((b) => b.bookingId == remoteBooking.bookingId);
      _bookings.add(remoteBooking);
    }
    _bookings.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    notifyListeners();
  }

  Future<void> refreshForPatient(String patientId,
      {bool preferCache = true}) async {
    if (patientId.isEmpty) return;
    final items = await FirestoreService.instance.labBooking.fetchForPatient(
      patientId,
      preferCache: preferCache,
    );
    mergeFromFirestore(items);
  }
}
