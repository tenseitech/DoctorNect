import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../features/ambulance/data/ambulance_pin.dart';
import '../../features/ambulance/models/ambulance_invite.dart';
import '../../features/ambulance/models/ambulance_models.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';
import '../session/doctor_session.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';

/// Doctor-created ambulance invites — driver completes setup via invite link.
abstract final class AmbulanceInviteService {
  static const inviteBaseUrl = 'https://doctornect.com/ambulance-setup';

  static String buildInviteLink(
      {required String inviteId, required String token}) {
    return '$inviteBaseUrl?invite=${Uri.encodeComponent(inviteId)}&token=${Uri.encodeComponent(token)}';
  }

  static String inviteMessage({
    required String doctorName,
    required String serviceName,
    required String link,
  }) {
    final doctor =
        doctorName.trim().isEmpty ? 'Your doctor' : doctorName.trim();
    final service =
        serviceName.trim().isEmpty ? 'ambulance service' : serviceName.trim();
    return '$doctor invited you to join DoctorNect as the driver for $service. '
        'Download the app, open this link, set your PIN and login:\n$link';
  }

  static String _generateToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static Future<({String inviteId, String link})?> createInvite({
    required RegisteredAmbulance draft,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;

    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty) return null;

    // Unguessable IDs — never use timestamps (enumerable IDOR).
    final inviteId = 'amb-inv-${_generateToken()}';
    final token = _generateToken();
    final ambulanceId =
        draft.id.isNotEmpty ? draft.id : 'amb-reg-${_generateToken()}';
    final expiresAt = DateTime.now().add(const Duration(days: 30));

    final invite = AmbulanceInvite(
      id: inviteId,
      token: token,
      doctorId: doctorId,
      doctorName: DoctorProfileStore.displayName,
      ambulanceId: ambulanceId,
      status: AmbulanceInviteStatus.pending,
      serviceName: draft.serviceName,
      ownerName: draft.ownerName,
      driverName: draft.driverName,
      phone: draft.phone,
      vehicleNumber: draft.vehicleNumber,
      ambulanceType: draft.ambulanceType,
      city: draft.city,
      serviceAreas: draft.serviceAreas,
      baseAddress: draft.baseAddress,
      licenseNumber: draft.licenseNumber,
      insuranceNumber: draft.insuranceNumber,
      hasOxygen: draft.hasOxygen,
      hasVentilator: draft.hasVentilator,
      hasStretcher: draft.hasStretcher,
      is24x7: draft.is24x7,
      ratePerKm: draft.ratePerKm,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulanceInvites)
          .doc(inviteId)
          .set({
        ...invite.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
      return (
        inviteId: inviteId,
        link: buildInviteLink(inviteId: inviteId, token: token),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('createInvite failed: $e\n$st');
      return null;
    }
  }

  /// Fetches invite via Cloud Function with token proof (no anonymous get-by-id).
  static Future<AmbulanceInvite?> fetchInvite(
    String inviteId, {
    required String token,
  }) async {
    if (!FirebaseBootstrap.isReady || inviteId.isEmpty || token.isEmpty) {
      return null;
    }
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('getAmbulanceInvite')
          .call<Map<String, dynamic>>({
        'inviteId': inviteId,
        'token': token,
      });
      final data = Map<String, dynamic>.from(result.data);
      if (data['ok'] != true) return null;
      final inviteMap = Map<String, dynamic>.from(data['invite'] as Map);
      return AmbulanceInvite.fromMap(
        data['inviteId'] as String? ?? inviteId,
        inviteMap,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('fetchInvite failed: $e');
      return null;
    }
  }

  static Future<String?> completeInviteSetup({
    required String inviteId,
    required String token,
    required String username,
    required String pin,
  }) async {
    final invite = await fetchInvite(inviteId, token: token);
    if (invite == null) return 'Invite not found or invalid';
    if (invite.token != token) return 'Invalid invite link';
    if (!invite.isPending) return 'This invite has already been used';
    if (invite.expiresAt != null && DateTime.now().isAfter(invite.expiresAt!)) {
      return 'This invite link has expired';
    }

    final cleanUsername = username.trim().toLowerCase();
    if (cleanUsername.length < 3)
      return 'Username must be at least 3 characters';

    final taken =
        await FirestoreService.instance.ambulance.fetchAmbulanceByUsername(
      cleanUsername,
      preferCache: false,
    );
    if (taken != null) {
      return 'Username is already taken';
    }

    final ambulance = invite.toRegisteredAmbulance(
      username: cleanUsername,
      pinHash: AmbulancePin.hash(pin),
    );

    final result =
        await FirestoreService.instance.ambulance.registerAmbulance(ambulance);
    if (!result.ok) {
      return result.error ??
          'Could not create ambulance profile. Check connection.';
    }

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulanceInvites)
          .doc(inviteId)
          .set({
        'status': AmbulanceInviteStatus.completed.name,
        'username': cleanUsername,
        'completedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode)
        debugPrint('completeInviteSetup mark completed failed: $e');
    }

    return null;
  }
}
