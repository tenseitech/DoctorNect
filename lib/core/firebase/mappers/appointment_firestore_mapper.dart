import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';



import '../../data/shared_appointments_store.dart';

import '../../constants/app_constants.dart';

import '../../../features/doctor/models/doctor_models.dart';

import '../../../features/patient/appointments/models/patient_appointment_models.dart';



abstract final class AppointmentFirestoreMapper {

  static List<String> parseChiefComplaints(Map<String, dynamic> data) {
    final list = data['chiefComplaints'];
    if (list is List) {
      return list
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final legacy = data['reasonForVisit'];
    if (legacy is String && legacy.trim().isNotEmpty) {
      return [legacy.trim()];
    }
    return const [];
  }

  static List<String> parseObservations(Map<String, dynamic> data) {
    final list = data['observations'];
    if (list is List) {
      return list
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final legacy = data['observation'];
    if (legacy is String && legacy.trim().isNotEmpty) {
      return [legacy.trim()];
    }
    return const [];
  }

  static Map<String, dynamic> toMap(DoctorNectAppointmentRecord record, {String? patientId}) {
    final resolvedPatientId = patientId ?? record.patientId;

    return {

      'appointmentId': record.appointmentId,

      'doctorId': record.doctorId,

      'doctorName': record.doctorName,

      'specialization': record.specialization,

      if (resolvedPatientId != null && resolvedPatientId.isNotEmpty)
        'patientId': resolvedPatientId,

      'patientName': record.patientName,

      'patientAge': record.patientAge,

      'patientGender': record.patientGender,

      'dateTime': Timestamp.fromDate(record.dateTime),

      'slotLabel': record.slotLabel,

      'tokenNumber': record.tokenNumber,

      'visitType': record.visitType.name,

      'patientStatus': record.patientStatus.name,

      'doctorStatus': record.doctorStatus.name,

      if (record.clinicName != null) 'clinicName': record.clinicName,

      if (record.clinicAddress != null) 'clinicAddress': record.clinicAddress,

      if (record.mapsUrl != null) 'mapsUrl': record.mapsUrl,

      if (record.cancellationReason != null) 'cancellationReason': record.cancellationReason,

      if (record.diagnosis != null) 'diagnosis': record.diagnosis,

      'hasPrescription': record.hasPrescription,

      'hasReport': record.hasReport,

      'hasReview': record.hasReview,

      if (record.reviewRating != null) 'reviewRating': record.reviewRating,

      if (record.reviewId != null && record.reviewId!.isNotEmpty) 'reviewId': record.reviewId,

      if (record.reviewCreatedAt != null)
        'reviewCreatedAt': Timestamp.fromDate(record.reviewCreatedAt!),

      'labReports': record.labReports,

      if (record.clinicalNotes != null) 'clinicalNotes': record.clinicalNotes,

      if (record.contactNumber != null) 'contactNumber': record.contactNumber,

      'chiefComplaints': record.chiefComplaints,

      if (record.source != null && record.source!.isNotEmpty) 'source': record.source,

      'symptoms': record.symptoms,

      'observations': record.observations,

      if (record.bookedByName != null) 'bookedByName': record.bookedByName,

      if (record.patientRelation != null) 'patientRelation': record.patientRelation,

      if (record.slotShareReason != null) 'slotShareReason': record.slotShareReason,

      'wasRescheduled': record.wasRescheduled,

      'updatedAt': FieldValue.serverTimestamp(),

    };

  }



  static DoctorNectAppointmentRecord? fromMap(String id, Map<String, dynamic> data) {

    try {

      return DoctorNectAppointmentRecord(

        id: id,

        appointmentId: data['appointmentId'] as String? ?? id,

        doctorId: data['doctorId'] as String? ?? '',

        doctorName: data['doctorName'] as String? ?? '',

        specialization: data['specialization'] as String? ?? '',

        patientName: data['patientName'] as String? ?? '',

        patientAge: (data['patientAge'] as num?)?.toInt() ?? 0,

        patientGender: AppConstants.normalizePatientGender(
          data['patientGender'] as String?,
          fallback: 'Male',
        ),

        dateTime: (data['dateTime'] as Timestamp?)?.toDate() ?? DateTime.now(),

        slotLabel: data['slotLabel'] as String? ?? '',

        tokenNumber: (data['tokenNumber'] as num?)?.toInt() ?? 0,

        visitType: AppointmentType.values.byName(data['visitType'] as String? ?? 'newVisit'),

        patientStatus: PatientBookingStatus.values.byName(

          data['patientStatus'] as String? ?? 'pending',

        ),

        doctorStatus: AppointmentStatus.values.byName(

          data['doctorStatus'] as String? ?? 'pendingRequest',

        ),

        clinicName: data['clinicName'] as String?,

        clinicAddress: data['clinicAddress'] as String?,

        mapsUrl: data['mapsUrl'] as String?,

        cancellationReason: data['cancellationReason'] as String?,

        diagnosis: data['diagnosis'] as String?,

        hasPrescription: data['hasPrescription'] as bool? ?? false,

        hasReport: data['hasReport'] as bool? ?? false,

        hasReview: data['hasReview'] as bool? ?? false,

        reviewRating: (data['reviewRating'] as num?)?.toInt(),

        reviewId: data['reviewId'] as String?,

        reviewCreatedAt: (data['reviewCreatedAt'] as Timestamp?)?.toDate(),

        labReports: (data['labReports'] as List<dynamic>? ?? const []).cast<String>(),

        clinicalNotes: data['clinicalNotes'] as String?,

        contactNumber: data['contactNumber'] as String?,

        chiefComplaints: parseChiefComplaints(data),

        patientId: data['patientId'] as String?,

        source: data['source'] as String?,

        symptoms: (data['symptoms'] as List<dynamic>? ?? const []).cast<String>(),

        observations: parseObservations(data),

        bookedByName: data['bookedByName'] as String?,

        patientRelation: data['patientRelation'] as String?,

        slotShareReason: data['slotShareReason'] as String?,

        wasRescheduled: data['wasRescheduled'] as bool? ?? false,

      );

    } catch (e, st) {
      debugPrint('Failed to map appointment $id: $e\n$st');
      return null;
    }

  }

}


