import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/demo_auth_config.dart';
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
    this.photoUrl,
    this.photoKey,
    this.photoStorage,
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
  final String? photoUrl;
  final String? photoKey;
  final String? photoStorage;

  factory DoctorNectUserProfile.fromMap(String uid, Map<String, dynamic> data) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return null;
    }

    final role = _roleFromString(data['role'] as String? ?? '');
    final mobile = data['mobile'] as String? ?? data['phone'] as String?;
    final isDemoDoctor =
        role == UserType.doctor && DemoAuthConfig.isDemoDoctorPhone(mobile);

    return DoctorNectUserProfile(
      uid: uid,
      role: role,
      profileId: data['profileId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      mobile: mobile,
      verificationStatus: isDemoDoctor
          ? 'verified'
          : data['verificationStatus'] as String?,
      rejectionReason: isDemoDoctor ? null : data['rejectionReason'] as String?,
      submittedAt: parseTimestamp(data['submittedAt']),
      photoUrl: data['photoUrl'] as String? ?? data['photoURL'] as String?,
      photoKey: data['photoKey'] as String?,
      photoStorage: data['photoStorage'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'role': _roleToString(role),
    'profileId': profileId,
    'displayName': displayName,
    'email': email,
    if (mobile != null) 'mobile': mobile,
    if (verificationStatus != null) 'verificationStatus': verificationStatus,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
    if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (photoKey != null) 'photoKey': photoKey,
    if (photoStorage != null) 'photoStorage': photoStorage,
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
