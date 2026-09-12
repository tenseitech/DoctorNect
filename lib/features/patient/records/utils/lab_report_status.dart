import '../../../../core/firebase/firestore_service.dart';
import '../../../../core/firebase/models/doctor_lab_order.dart';
import '../models/health_record_models.dart';

class LabReportStatusDisplay {
  const LabReportStatusDisplay({
    required this.kind,
    required this.label,
  });

  final LabReportStatusKind kind;
  final String label;
}

abstract final class LabReportStatus {
  LabReportStatus._();

  static LabReportStatusDisplay resolveForBooking(LabBookingRecord booking) {
    if (booking.hasReport) {
      return const LabReportStatusDisplay(
        kind: LabReportStatusKind.reportReady,
        label: 'Report ready',
      );
    }

    return switch (booking.status.toLowerCase()) {
      'processing' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.processing,
          label: 'Processing',
        ),
      'confirmed' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.confirmed,
          label: 'Confirmed',
        ),
      'requested' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.awaitingLab,
          label: 'Awaiting lab',
        ),
      'completed' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.completedPendingReport,
          label: 'Report pending',
        ),
      'declined' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.declined,
          label: 'Declined',
        ),
      'cancelled' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.cancelled,
          label: 'Cancelled',
        ),
      _ => const LabReportStatusDisplay(
          kind: LabReportStatusKind.confirmed,
          label: 'Confirmed',
        ),
    };
  }

  static LabReportStatusDisplay resolveForOrder(DoctorLabOrder order) {
    if (order.hasReport) {
      return const LabReportStatusDisplay(
        kind: LabReportStatusKind.reportReady,
        label: 'Report ready',
      );
    }

    return switch (order.status.toLowerCase()) {
      'processing' ||
      'in_progress' ||
      'sample_collected' =>
        const LabReportStatusDisplay(
          kind: LabReportStatusKind.processing,
          label: 'Processing',
        ),
      'confirmed' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.confirmed,
          label: 'Confirmed',
        ),
      'requested' || 'ordered' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.orderedByDoctor,
          label: 'Ordered by doctor',
        ),
      'completed' => const LabReportStatusDisplay(
          kind: LabReportStatusKind.completedPendingReport,
          label: 'Report pending',
        ),
      'declined' || 'cancelled' => LabReportStatusDisplay(
          kind: order.status.toLowerCase() == 'declined'
              ? LabReportStatusKind.declined
              : LabReportStatusKind.cancelled,
          label: order.status.toLowerCase() == 'declined' ? 'Declined' : 'Cancelled',
        ),
      _ => const LabReportStatusDisplay(
          kind: LabReportStatusKind.orderedByDoctor,
          label: 'Ordered by doctor',
        ),
    };
  }
}
