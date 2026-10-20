import 'package:flutter/foundation.dart';

import '../../constants/app_constants.dart';
import '../../data/shared_appointments_store.dart';
import '../../../features/doctor/models/doctor_models.dart';
import '../../../features/patient/appointments/models/patient_appointment_models.dart';

/// Maps Supabase PostgreSQL rows to and from DoctorNect domain models.
abstract final class AppointmentSupabaseMapper {
  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static AppointmentType _parseVisitType(String? raw) {
    if (raw == null) return AppointmentType.newVisit;
    try {
      return AppointmentType.values.byName(raw);
    } catch (_) {
      return AppointmentType.newVisit;
    }
  }

  static PatientBookingStatus _parsePatientBookingStatus(String? raw) {
    if (raw == null) return PatientBookingStatus.pending;
    switch (raw.toLowerCase()) {
      case 'confirmed':
        return PatientBookingStatus.confirmed;
      case 'pending':
      default:
        return PatientBookingStatus.pending;
    }
  }

  static AppointmentStatus _parseDoctorStatus(String? raw) {
    if (raw == null) return AppointmentStatus.pendingRequest;
    try {
      return AppointmentStatus.values.byName(raw);
    } catch (_) {
      switch (raw.toLowerCase()) {
        case 'cancelled':
          return AppointmentStatus.cancelled;
        case 'confirmed':
          return AppointmentStatus.confirmed;
        case 'completed':
          return AppointmentStatus.completed;
        case 'inprogress':
        case 'in_progress':
          return AppointmentStatus.inProgress;
        case 'waiting':
          return AppointmentStatus.waiting;
        case 'noshow':
        case 'no_show':
          return AppointmentStatus.noShow;
        default:
          return AppointmentStatus.pendingRequest;
      }
    }
  }

  /// Maps a PostgreSQL row from table `public.appointments` to a [DoctorNectAppointmentRecord].
  static DoctorNectAppointmentRecord? fromRow(Map<String, dynamic> row) {
    try {
      final apptId = row['appointment_id'] as String? ?? '';
      if (apptId.isEmpty) return null;

      DateTime dt = DateTime.now();
      if (row['date_time'] != null) {
        final parsed = DateTime.tryParse(row['date_time'].toString());
        if (parsed != null) dt = parsed.toLocal();
      }

      DateTime? reviewCreatedAt;
      if (row['review_created_at'] != null) {
        final parsed = DateTime.tryParse(row['review_created_at'].toString());
        if (parsed != null) reviewCreatedAt = parsed.toLocal();
      }

      final patientStatusRaw =
          (row['patient_status'] as String?)?.trim().toLowerCase();
      var doctorStatus = _parseDoctorStatus(row['doctor_status'] as String?);
      final isCancelled = patientStatusRaw == 'cancelled' ||
          doctorStatus == AppointmentStatus.cancelled;
      final cancellationReason = isCancelled
          ? (row['cancellation_reason'] as String?)
          : null;
      if (patientStatusRaw == 'cancelled') {
        doctorStatus = AppointmentStatus.cancelled;
      }

      return DoctorNectAppointmentRecord(
        id: apptId,
        appointmentId: apptId,
        doctorId: row['doctor_id'] as String? ?? '',
        doctorName: row['doctor_name'] as String? ?? '',
        specialization: row['specialization'] as String? ?? '',
        patientName: row['patient_name'] as String? ?? '',
        patientAge: (row['patient_age'] as num?)?.toInt() ?? 0,
        patientGender: AppConstants.normalizePatientGender(
          row['patient_gender'] as String?,
          fallback: 'Male',
        ),
        dateTime: dt,
        slotLabel: row['slot_label'] as String? ?? '',
        tokenNumber: (row['token_number'] as num?)?.toInt() ?? 0,
        visitType: _parseVisitType(row['visit_type'] as String?),
        patientStatus: _parsePatientBookingStatus(
          row['patient_status'] as String?,
        ),
        doctorStatus: doctorStatus,
        clinicName: row['clinic_name'] as String?,
        clinicAddress: row['clinic_address'] as String?,
        mapsUrl: row['maps_url'] as String?,
        cancellationReason: cancellationReason,
        diagnosis: row['diagnosis'] as String?,
        hasPrescription: row['has_prescription'] as bool? ?? false,
        hasReport: row['has_report'] as bool? ?? false,
        hasReview: row['has_review'] as bool? ?? false,
        reviewRating: (row['review_rating'] as num?)?.toInt(),
        reviewId: row['review_id'] as String?,
        reviewCreatedAt: reviewCreatedAt,
        labReports: _parseStringList(row['lab_reports']),
        clinicalNotes: row['clinical_notes'] as String?,
        contactNumber: row['contact_number'] as String?,
        chiefComplaints: _parseStringList(row['chief_complaints']),
        patientId: row['patient_id'] as String?,
        source: row['source'] as String?,
        symptoms: _parseStringList(row['symptoms']),
        observations: _parseStringList(row['observations']),
        bookedByName: row['booked_by_name'] as String?,
        patientRelation: row['patient_relation'] as String?,
        slotShareReason: row['slot_share_reason'] as String?,
        wasRescheduled: row['was_rescheduled'] as bool? ?? false,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to map Supabase appointment row: $e\n$st');
      }
      return null;
    }
  }

  /// Maps a [DoctorNectAppointmentRecord] to a PostgreSQL row for table `public.appointments`.
  static Map<String, dynamic> toRow(
    DoctorNectAppointmentRecord record, {
    String? patientId,
  }) {
    final resolvedPatientId = patientId ?? record.patientId ?? '';
    return <String, dynamic>{
      'appointment_id': record.id,
      'doctor_id': record.doctorId,
      'patient_id': resolvedPatientId,
      'doctor_name': record.doctorName,
      'specialization': record.specialization,
      'patient_name': record.patientName,
      'patient_age': record.patientAge,
      'patient_gender': record.patientGender,
      'date_time': record.dateTime.toIso8601String(),
      'slot_label': record.slotLabel,
      'token_number': record.tokenNumber,
      'visit_type': record.visitType.name,
      'patient_status': record.patientStatus.name,
      'doctor_status': record.doctorStatus.name,
      if (record.clinicName != null) 'clinic_name': record.clinicName,
      if (record.clinicAddress != null) 'clinic_address': record.clinicAddress,
      if (record.mapsUrl != null) 'maps_url': record.mapsUrl,
      if (record.cancellationReason != null)
        'cancellation_reason': record.cancellationReason,
      if (record.diagnosis != null) 'diagnosis': record.diagnosis,
      'has_prescription': record.hasPrescription,
      'has_report': record.hasReport,
      'has_review': record.hasReview,
      if (record.reviewRating != null) 'review_rating': record.reviewRating,
      if (record.reviewId != null) 'review_id': record.reviewId,
      if (record.reviewCreatedAt != null)
        'review_created_at': record.reviewCreatedAt!.toIso8601String(),
      'lab_reports': record.labReports,
      if (record.clinicalNotes != null) 'clinical_notes': record.clinicalNotes,
      if (record.contactNumber != null) 'contact_number': record.contactNumber,
      'chief_complaints': record.chiefComplaints,
      if (record.source != null) 'source': record.source,
      'symptoms': record.symptoms,
      'observations': record.observations,
      if (record.bookedByName != null) 'booked_by_name': record.bookedByName,
      if (record.patientRelation != null)
        'patient_relation': record.patientRelation,
      if (record.slotShareReason != null)
        'slot_share_reason': record.slotShareReason,
      'was_rescheduled': record.wasRescheduled,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
