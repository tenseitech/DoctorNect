import '../../doctor_profile/data/review_edit_policy.dart';

enum PatientBookingStatus { confirmed, pending }

class PatientAppointment {
  PatientAppointment({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.specialization,
    required this.dateTime,
    required this.tokenNumber,
    required this.status,
    this.slotLabel,
    this.clinicName,
    this.clinicAddress,
    this.mapsUrl,
    this.diagnosis,
    this.hasPrescription = false,
    this.hasReport = false,
    this.hasReview = false,
    this.reviewRating,
    this.reviewId,
    this.reviewCreatedAt,
    this.cancellationReason,
    this.labReports = const [],
    this.clinicalNotes,
    this.reasonForVisit,
    this.appointmentId,
  });

  final String id;
  final String? appointmentId;
  final String doctorId;
  final String doctorName;
  final String specialization;
  final DateTime dateTime;
  final int tokenNumber;
  final PatientBookingStatus status;
  final String? slotLabel;
  final String? clinicName;
  final String? clinicAddress;
  final String? mapsUrl;
  final String? diagnosis;
  final bool hasPrescription;
  final bool hasReport;
  final bool hasReview;
  final int? reviewRating;
  final String? reviewId;
  final DateTime? reviewCreatedAt;
  final String? cancellationReason;
  final List<String> labReports;
  final String? clinicalNotes;
  final String? reasonForVisit;

  bool get isUpcoming =>
      dateTime.isAfter(DateTime.now().subtract(const Duration(hours: 1)));

  bool get canEditReview {
    if (!hasReview || reviewCreatedAt == null) return false;
    return ReviewEditPolicy.withinEditWindow(reviewCreatedAt!);
  }

  Duration get timeUntilStart => dateTime.difference(DateTime.now());

  String get countdownLabel {
    final d = timeUntilStart;
    if (d.isNegative) return 'In progress';
    if (d.inDays > 0)
      return 'Starts in ${d.inDays} day${d.inDays > 1 ? 's' : ''}';
    if (d.inHours > 0) {
      final mins = d.inMinutes % 60;
      return 'Starts in ${d.inHours} hr${d.inHours > 1 ? 's' : ''} ${mins > 0 ? '$mins mins' : ''}'
          .trim();
    }
    if (d.inMinutes > 0) return 'Starts in ${d.inMinutes} mins';
    return 'Starting soon';
  }
}
