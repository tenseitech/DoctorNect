import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';
import '../session/doctor_session.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';

enum InviteNetworkUserType {
  patient('Patient'),
  medicalStore('Medical Store'),
  lab('Lab'),
  doctor('Doctor'),
  ambulance('Ambulance');

  const InviteNetworkUserType(this.label);
  final String label;
}

/// Doctor → patient invite links backed by Firestore metadata.
abstract final class DoctorInviteService {
  static const inviteBaseUrl = 'https://doctornect.com/join';

  static String buildInviteLink(String doctorId) {
    return buildNetworkInviteLink(
      doctorId: doctorId,
      userType: InviteNetworkUserType.patient,
    );
  }

  static String buildNetworkInviteLink({
    required String doctorId,
    required InviteNetworkUserType userType,
  }) {
    final id = doctorId.trim().isEmpty ? 'doctor' : doctorId.trim();
    final params = <String, String>{'doctor': id};
    final role = switch (userType) {
      InviteNetworkUserType.patient => null,
      InviteNetworkUserType.medicalStore => 'pharmacy',
      InviteNetworkUserType.lab => 'lab',
      InviteNetworkUserType.doctor => 'doctor',
      InviteNetworkUserType.ambulance => 'ambulance',
    };
    if (role != null) params['role'] = role;

    return Uri.parse(inviteBaseUrl).replace(queryParameters: params).toString();
  }

  static String inviteMessage({required String doctorName, required String link}) {
    return networkInviteMessage(
      doctorName: doctorName,
      link: link,
      userType: InviteNetworkUserType.patient,
    );
  }

  static String networkInviteMessage({
    required String doctorName,
    required String link,
    required InviteNetworkUserType userType,
  }) {
    final name = doctorName.trim().isEmpty ? 'your doctor' : doctorName.trim();
    return switch (userType) {
      InviteNetworkUserType.patient =>
        'Join Dr. $name on DoctorNect for appointments, prescriptions & lab orders: $link',
      InviteNetworkUserType.medicalStore =>
        'Join DoctorNect to connect your medical store with Dr. $name: $link',
      InviteNetworkUserType.lab =>
        'Join DoctorNect to connect your lab with Dr. $name: $link',
      InviteNetworkUserType.doctor =>
        'Join DoctorNect to connect and manage your practice with Dr. $name: $link',
      InviteNetworkUserType.ambulance =>
        'Join DoctorNect to connect your ambulance service with Dr. $name: $link',
    };
  }

  static Future<void> ensureInviteMetadata(String doctorId) async {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return;

    await FirebaseFirestore.instance.collection(FirestorePaths.doctors).doc(doctorId).set({
      'inviteCode': doctorId,
      'inviteLink': buildInviteLink(doctorId),
      'inviteUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<String> linkForCurrentDoctor({
    InviteNetworkUserType userType = InviteNetworkUserType.patient,
  }) async {
    final doctorId = DoctorSession.loggedInDoctorId;
    await ensureInviteMetadata(doctorId);
    return buildNetworkInviteLink(doctorId: doctorId, userType: userType);
  }

  static Future<String> messageForCurrentDoctor({
    InviteNetworkUserType userType = InviteNetworkUserType.patient,
  }) async {
    final link = await linkForCurrentDoctor(userType: userType);
    return networkInviteMessage(
      doctorName: DoctorProfileStore.displayName,
      link: link,
      userType: userType,
    );
  }
}
