import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firebase/models/doctor_lab_order.dart';
import '../../patient/lab/data/lab_booking_grouper.dart';
import 'lab_notification_store.dart';

/// In-memory worklist for the logged-in lab operator.
// FIXED: lab dashboard reads from this store, kept fresh via prefetch + realtime streams.
class LabWorklistStore extends ChangeNotifier {
  LabWorklistStore._();

  static final LabWorklistStore instance = LabWorklistStore._();

  final List<DoctorLabOrder> _orders = [];
  final List<LabBookingRecord> _bookings = [];

  List<DoctorLabOrder> get orders => List.unmodifiable(_orders);
  List<LabBookingRecord> get bookings =>
      LabBookingGrouper.group(List.unmodifiable(_bookings));

  List<DoctorLabOrder> forLabAndDoctor(String labId, String doctorId) =>
      _orders.where((o) => o.labId == labId && o.doctorId == doctorId).toList();

  void clear() {
    _orders.clear();
    _bookings.clear();
    notifyListeners();
  }

  void mergeOrders(List<DoctorLabOrder> remote) {
    for (final item in remote) {
      final existed = _orders.any((o) => o.orderId == item.orderId);
      _orders.removeWhere((o) => o.orderId == item.orderId);
      _orders.add(item);
      if (!existed) {
        final labId = item.labId;
        if (labId != null && labId.isNotEmpty) {
          LabNotificationStore.instance.addLab(
            labId: labId,
            title: 'New lab order',
            message:
                'Dr. ${item.doctorName} ordered tests for ${item.patientName}',
            referenceId: item.orderId,
            createdAt: item.createdAt,
          );
        }
      }
    }
    _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  void mergeBookings(List<LabBookingRecord> remote) {
    for (final item in remote) {
      final existed = _bookings.any((b) => b.bookingId == item.bookingId);
      _bookings.removeWhere((b) => b.bookingId == item.bookingId);
      _bookings.add(item);
      if (!existed) {
        final labId = item.labId;
        if (labId != null && labId.isNotEmpty) {
          LabNotificationStore.instance.addLab(
            labId: labId,
            title: 'New booking',
            message: '${item.patientName} booked ${item.testName}',
            referenceId: item.bookingId,
            createdAt: item.createdAt ?? item.dateTime,
          );
        }
      }
    }
    _bookings.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    notifyListeners();
  }

  void updateOrderStatusLocal(String orderId, String status) {
    final i = _orders.indexWhere((o) => o.orderId == orderId);
    if (i < 0) return;
    final old = _orders[i];
    _orders[i] = DoctorLabOrder(
      orderId: old.orderId,
      doctorId: old.doctorId,
      doctorName: old.doctorName,
      patientId: old.patientId,
      patientName: old.patientName,
      patientAge: old.patientAge,
      testIds: old.testIds,
      testNames: old.testNames,
      createdAt: old.createdAt,
      appointmentId: old.appointmentId,
      labId: old.labId,
      labName: old.labName,
      indication: old.indication,
      urgency: old.urgency,
      fastingRequired: old.fastingRequired,
      homeCollection: old.homeCollection,
      source: old.source,
      status: status,
      reportFileName: old.reportFileName,
      reportStorageUrl: old.reportStorageUrl,
      reportSubmittedAt: old.reportSubmittedAt,
    );
    notifyListeners();
  }

  void applyOrderReportLocal(DoctorLabOrder updated) {
    final i = _orders.indexWhere((o) => o.orderId == updated.orderId);
    if (i < 0) {
      _orders.add(updated);
    } else {
      _orders[i] = updated;
    }
    _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  void updateBookingStatusLocal(String bookingId, String status) {
    // Collect all booking IDs that should be updated (handles grouped bookings)
    final idsToUpdate = <String>{bookingId};
    for (final b in _bookings) {
      if (b.bookingId == bookingId || b.groupedBookingIds.contains(bookingId)) {
        idsToUpdate.add(b.bookingId);
        idsToUpdate.addAll(b.groupedBookingIds);
      }
    }

    bool changed = false;
    for (final targetId in idsToUpdate) {
      final i = _bookings.indexWhere((b) => b.bookingId == targetId);
      if (i < 0) continue;
      final old = _bookings[i];
      _bookings[i] = LabBookingRecord(
        bookingId: old.bookingId,
        labId: old.labId,
        labName: old.labName,
        patientId: old.patientId,
        patientName: old.patientName,
        testName: old.testName,
        testNames: old.testNames,
        groupedBookingIds: old.groupedBookingIds,
        dateTime: old.dateTime,
        slotLabel: old.slotLabel,
        collectionType: old.collectionType,
        address: old.address,
        status: status,
        reportFileName: old.reportFileName,
        reportStorageUrl: old.reportStorageUrl,
        reportSubmittedAt: old.reportSubmittedAt,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void applyBookingReportLocal(LabBookingRecord updated) {
    final idsToUpdate = {
      updated.bookingId,
      ...updated.groupedBookingIds,
      if (updated.reportBookingId != null) updated.reportBookingId!,
    };

    var changed = false;
    for (final id in idsToUpdate) {
      final i = _bookings.indexWhere((b) => b.bookingId == id);
      if (i < 0) continue;
      final old = _bookings[i];
      _bookings[i] = LabBookingRecord(
        bookingId: old.bookingId,
        labId: old.labId,
        labName: old.labName,
        patientId: old.patientId,
        patientName: old.patientName,
        testName: old.testName,
        testNames: old.testNames,
        groupedBookingIds: old.groupedBookingIds,
        dateTime: old.dateTime,
        slotLabel: old.slotLabel,
        collectionType: old.collectionType,
        address: old.address,
        status: 'completed',
        reportFileName: updated.reportFileName,
        reportStorageUrl: updated.reportStorageUrl,
        reportSubmittedAt: updated.reportSubmittedAt ?? DateTime.now(),
        reportBookingId: updated.reportBookingId ?? updated.bookingId,
        createdAt: old.createdAt,
      );
      changed = true;
    }

    if (!changed) {
      _bookings.add(updated);
    }
    _bookings.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    notifyListeners();
  }
}
