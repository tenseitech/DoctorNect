import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/user_type.dart';

class DoctorNectUserProfile {
  const DoctorNectUserProfile({
    required this.uid,
    required this.role,
    required this.profileId,
    required this.displayName,
    required this.email,
    this.mobile,
    this.verificationStatus,
    this.rejectionReason,
    this.submittedAt,
  });

  final String uid;
  final UserType role;
  final String profileId;
  final String displayName;
  final String email;
  final String? mobile;
  final String? verificationStatus;
  final String? rejectionReason;
  final DateTime? submittedAt;

  factory DoctorNectUserProfile.fromMap(String uid, Map<String, dynamic> data) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return null;
    }

    return DoctorNectUserProfile(
      uid: uid,
      role: _roleFromString(data['role'] as String? ?? ''),
      profileId: data['profileId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      mobile: data['mobile'] as String?,
      verificationStatus: data['verificationStatus'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      submittedAt: parseTimestamp(data['submittedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'role': _roleToString(role),
        'profileId': profileId,
        'displayName': displayName,
        'email': email,
        if (mobile != null) 'mobile': mobile,
        if (verificationStatus != null)
          'verificationStatus': verificationStatus,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        if (submittedAt != null)
          'submittedAt': Timestamp.fromDate(submittedAt!),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static UserType _roleFromString(String value) => switch (value) {
        'super_admin' || 'superAdmin' => UserType.superAdmin,
        'doctor' => UserType.doctor,
        'medicalStore' => UserType.medicalStore,
        'lab' => UserType.lab,
        'ambulance' => UserType.ambulance,
        _ => UserType.patient,
      };

  static String _roleToString(UserType role) => switch (role) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.medicalStore => 'medicalStore',
        UserType.lab => 'lab',
        UserType.patient => 'patient',
        UserType.ambulance => 'ambulance',
      };
}
