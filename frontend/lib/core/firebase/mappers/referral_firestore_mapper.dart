import '../../util/map_date_time.dart';

import '../models/doctor_referral.dart';

abstract final class ReferralFirestoreMapper {
  static Map<String, dynamic> toMap(DoctorReferral referral) => {
        'referralId': referral.referralId,
        'fromDoctorId': referral.fromDoctorId,
        'fromDoctorName': referral.fromDoctorName,
        'toDoctorId': referral.toDoctorId,
        'toDoctorName': referral.toDoctorName,
        'toSpecialization': referral.toSpecialization,
        'patientId': referral.patientId,
        'patientName': referral.patientName,
        'patientAge': referral.patientAge,
        if (referral.appointmentId != null)
          'appointmentId': referral.appointmentId,
        if (referral.reason != null && referral.reason!.isNotEmpty)
          'reason': referral.reason,
        'status': referral.status,
        'createdAt': referral.createdAt,
      };

  static DoctorReferral? fromMap(Map<String, dynamic> data) {
    try {
      return DoctorReferral(
        referralId: data['referralId'] as String? ?? '',
        fromDoctorId: data['fromDoctorId'] as String? ?? '',
        fromDoctorName: data['fromDoctorName'] as String? ?? '',
        toDoctorId: data['toDoctorId'] as String? ?? '',
        toDoctorName: data['toDoctorName'] as String? ?? '',
        toSpecialization: data['toSpecialization'] as String? ?? '',
        patientId: data['patientId'] as String? ?? '',
        patientName: data['patientName'] as String? ?? '',
        patientAge: (data['patientAge'] as num?)?.toInt() ?? 0,
        appointmentId: data['appointmentId'] as String?,
        reason: data['reason'] as String?,
        status: data['status'] as String? ?? 'sent',
        createdAt: _parseDate(data['createdAt']),
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime _parseDate(dynamic value) =>
      parseMapDateTime(value) ?? DateTime.now();
}
