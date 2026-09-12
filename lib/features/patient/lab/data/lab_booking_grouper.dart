import '../../../../core/firebase/firestore_service.dart';
import '../utils/patient_selected_investigations_mapper.dart';

/// Combines legacy per-test booking rows that were created in the same checkout.
abstract final class LabBookingGrouper {
  LabBookingGrouper._();

  static List<LabBookingRecord> group(List<LabBookingRecord> bookings) {
    final ready = <LabBookingRecord>[];
    final legacyBuckets = <String, List<LabBookingRecord>>{};

    for (final booking in bookings) {
      if (booking.testNames.length > 1) {
        ready.add(booking);
        continue;
      }
      final key = _legacyGroupKey(booking);
      legacyBuckets.putIfAbsent(key, () => []).add(booking);
    }

    for (final bucket in legacyBuckets.values) {
      if (bucket.length == 1) {
        ready.add(bucket.first);
      } else {
        ready.add(_mergeLegacy(bucket));
      }
    }

    ready.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return ready;
  }

  static String _legacyGroupKey(LabBookingRecord booking) {
    return [
      booking.patientId,
      booking.dateTime.millisecondsSinceEpoch,
      booking.slotLabel,
      booking.labId ?? booking.labName ?? '',
      booking.patientName,
      booking.status,
      booking.collectionType,
    ].join('|');
  }

  static LabBookingRecord _mergeLegacy(List<LabBookingRecord> items) {
    final sorted = [...items]..sort((a, b) => a.bookingId.compareTo(b.bookingId));
    final primary = sorted.first;
    final reportSource = _reportSource(sorted);
    final names = <String>{};
    final orderedNames = <String>[];
    for (final item in sorted) {
      for (final name in item.allTestNames) {
        final trimmed = name.trim();
        if (trimmed.isEmpty || names.contains(trimmed)) continue;
        names.add(trimmed);
        orderedNames.add(trimmed);
      }
    }

    return LabBookingRecord(
      bookingId: primary.bookingId,
      labId: primary.labId,
      labName: primary.labName,
      patientId: primary.patientId,
      patientName: primary.patientName,
      testName: PatientSelectedInvestigationsMapper.summaryFromNames(orderedNames),
      testNames: orderedNames,
      groupedBookingIds: sorted.map((item) => item.bookingId).toList(growable: false),
      dateTime: primary.dateTime,
      slotLabel: primary.slotLabel,
      collectionType: primary.collectionType,
      address: primary.address,
      status: _mergedStatus(sorted),
      reportFileName: reportSource?.reportFileName,
      reportStorageUrl: reportSource?.reportStorageUrl,
      reportSubmittedAt: reportSource?.reportSubmittedAt,
      reportBookingId: reportSource?.bookingId,
      createdAt: primary.createdAt,
    );
  }

  /// Prefer the sibling booking that actually uploaded a report, not always the primary row.
  static LabBookingRecord? _reportSource(List<LabBookingRecord> items) {
    final withReport = items
        .where(
          (item) =>
              item.hasReport &&
              item.reportStorageUrl != null &&
              item.reportStorageUrl!.trim().isNotEmpty,
        )
        .toList();
    if (withReport.isEmpty) {
      final withNameOnly = items.where((item) => item.hasReport).toList();
      if (withNameOnly.isEmpty) return null;
      withNameOnly.sort(
        (a, b) => (b.reportSubmittedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.reportSubmittedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return withNameOnly.first;
    }

    withReport.sort(
      (a, b) => (b.reportSubmittedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.reportSubmittedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return withReport.first;
  }

  static String _mergedStatus(List<LabBookingRecord> items) {
    if (items.any((item) => item.status == 'completed')) return 'completed';
    if (items.any((item) => item.status == 'processing')) return 'processing';
    if (items.any((item) => item.status == 'declined')) return 'declined';
    if (items.any((item) => item.status == 'cancelled')) return 'cancelled';
    return items.first.status;
  }
}
