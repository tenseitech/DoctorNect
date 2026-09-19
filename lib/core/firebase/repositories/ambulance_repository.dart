import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../features/ambulance/data/ambulance_login_cache.dart';
import '../../../features/ambulance/data/ambulance_store.dart';
import '../../../features/ambulance/models/ambulance_models.dart';
import '../../constants/app_constants.dart';
import '../../notifications/ambulance_notification_emitter.dart'; // FIXED: notify booker on accept
import '../firebase_bootstrap.dart';
import '../ambulance_auth_helper.dart';
import '../ambulance_callable_client.dart';
import '../firestore_paths.dart';
import '../firestore_read_helper.dart';
import '../../location/location_match.dart';
import '../../validators/form_validators.dart';
import '../../firebase/firebase_error_messages.dart';

class AmbulanceDriverLoginResult {
  const AmbulanceDriverLoginResult({
    this.profile,
    this.pinUpgradeRequired = false,
    this.errorMessage,
  });

  final RegisteredAmbulance? profile;
  final bool pinUpgradeRequired;
  final String? errorMessage;

  bool get ok => profile != null;
}

class AmbulanceRegisterResult {
  const AmbulanceRegisterResult({this.id, this.error});

  final String? id;
  final String? error;

  bool get ok => id != null && id!.isNotEmpty;
}

class AmbulanceRepository {
  AmbulanceRepository._();

  static final AmbulanceRepository instance = AmbulanceRepository._();

  /// Populated when [acceptBroadcast] returns false — for UI + logcat diagnostics.
  String? lastAcceptFailureDetail;

  /// User-facing cancel failure (Phase 1/2 only; never set for sibling cleanup).
  String? lastAcceptFailureUserMessage;

  /// User-facing message when [cancelBroadcast] / [cancelAcceptedBroadcast] fails.
  String? lastCancelFailureUserMessage;

  /// Temporary accept-flow tracing (logcat: adb logcat | findstr AmbulanceAccept).
  void _acceptLog(String message) {
    if (kDebugMode) debugPrint('[AmbulanceAccept] $message');
  }

  void _setAcceptFailure(String detail, {String? userMessage}) {
    lastAcceptFailureDetail = detail;
    lastAcceptFailureUserMessage = userMessage ?? detail;
    _acceptLog('FAIL: $detail');
  }

  static String normalizeArea(String location) {
    return location.trim().toLowerCase();
  }

  /// Links the current Firebase Auth uid to this ambulance driver doc (optional).
  /// When [username] and [pin] are supplied, falls back to server-side resync if
  /// client-side linking is blocked by hardened Firestore rules.
  Future<bool> linkDriverAuth(
    String ambulanceId, {
    String? username,
    String? pin,
  }) async {
    if (!FirebaseBootstrap.isReady || ambulanceId.isEmpty) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(ambulanceId)
          .set({
        'authUid': uid,
      }, SetOptions(merge: true));
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' &&
          username != null &&
          pin != null &&
          username.trim().isNotEmpty &&
          pin.trim().length >= 6) {
        return resyncDriverAuth(
          username: username,
          pin: pin,
          expectedDriverId: ambulanceId,
        );
      }
      if (kDebugMode) debugPrint('linkDriverAuth failed: $e');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('linkDriverAuth failed: $e');
      return false;
    }
  }

  /// Server-side authUid reclaim after reinstall or device change.
  Future<bool> resyncDriverAuth({
    required String username,
    required String pin,
    String? expectedDriverId,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;

    try {
      final data =
          await AmbulanceCallableClient.call('resyncAmbulanceAuthUid', {
        'username': username.trim().toLowerCase(),
        'pin': pin.trim(),
      });
      if (data['ok'] != true) return false;

      final driverId = data['driverId'] as String? ?? '';
      if (driverId.isEmpty) return false;
      if (expectedDriverId != null &&
          expectedDriverId.isNotEmpty &&
          driverId != expectedDriverId) {
        return false;
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('resyncDriverAuth error: $e\n$st');
      return false;
    }
  }

  /// Saves the device FCM token so Cloud Functions can send push alerts.
  Future<void> saveDriverFcmToken(String ambulanceId, String token) async {
    if (!FirebaseBootstrap.isReady || ambulanceId.isEmpty || token.isEmpty)
      return;

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(ambulanceId)
          .collection('private')
          .doc('settings')
          .set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('saveDriverFcmToken failed: $e');
    }
  }

  /// Removes FCM token on driver logout.
  Future<void> clearDriverFcmToken(String ambulanceId) async {
    if (!FirebaseBootstrap.isReady || ambulanceId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(ambulanceId)
          .collection('private')
          .doc('settings')
          .set({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('clearDriverFcmToken failed: $e');
    }
  }

  /// Register a new ambulance service in Firestore and local store.
  Future<AmbulanceRegisterResult> registerAmbulance(
    RegisteredAmbulance ambulance, {
    Map<String, dynamic>? extraFields,
  }) async {
    AmbulanceStore.instance.registerAmbulance(ambulance);

    if (!FirebaseBootstrap.isReady) {
      if (kDebugMode) debugPrint('registerAmbulance: Firebase not ready');
      return const AmbulanceRegisterResult(
        error: 'Firebase is not available. Check your connection.',
      );
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return const AmbulanceRegisterResult(
          error: 'Secure session expired. Please try again.',
        );
      }

      final ref = FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(ambulance.id);
      final data = {
        ...ambulance.toMap(includePrivateFields: false),
        if (extraFields != null) ...extraFields,
        'createdAt': FieldValue.serverTimestamp(),
        'authUid': uid,
      };
      await ref.set(data);

      if (ambulance.pin.trim().isNotEmpty) {
        try {
          await ref.collection('private').doc('settings').set({
            'pin': ambulance.pin.trim(),
          }, SetOptions(merge: true));
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('registerAmbulance private/settings error: $e\n$st');
          }
          return AmbulanceRegisterResult(
            error: _registerAmbulanceErrorMessage(
              e,
              fallback:
                  'Could not save login credentials. Check permissions and try again.',
            ),
          );
        }
      }

      if (kDebugMode) debugPrint('Ambulance saved to Firestore: ${ref.id}');
      return AmbulanceRegisterResult(id: ref.id);
    } catch (e, st) {
      if (kDebugMode) debugPrint('registerAmbulance Firestore error: $e\n$st');
      return AmbulanceRegisterResult(
        error: _registerAmbulanceErrorMessage(
          e,
          fallback:
              'Could not save ambulance registration. Check connection and try again.',
        ),
      );
    }
  }

  String _registerAmbulanceErrorMessage(Object e, {required String fallback}) {
    if (e is FirebaseException) {
      return describeFirebaseError(e, fallback: fallback);
    }
    return describeUserFacingError(e, fallback: fallback);
  }

  Future<RegisteredAmbulance?> fetchAmbulanceById(String id) async {
    if (id.isEmpty) return null;

    final cached = AmbulanceStore.instance.findAmbulance(id);
    if (cached != null) return cached;

    if (!FirebaseBootstrap.isReady) return null;

    try {
      final ref = FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(id);
      final doc = await FirestoreReadHelper.getDocument(
          reference: ref, preferCache: true);
      if (!doc.exists || doc.data() == null) return null;
      final ambulance = RegisteredAmbulance.fromMap(doc.id, doc.data()!);
      if (!_isRegistered(ambulance)) return null;
      AmbulanceStore.instance.registerAmbulance(ambulance);
      return ambulance;
    } catch (e) {
      if (kDebugMode) debugPrint('fetchAmbulanceById error: $e');
      return null;
    }
  }

  /// Lookup a single driver by username (login) — avoids loading the full collection.
  Future<RegisteredAmbulance?> fetchAmbulanceByUsername(
    String username, {
    bool preferCache = true,
  }) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    RegisteredAmbulance? local =
        await AmbulanceLoginCache.loadForUsername(normalized);
    if (local != null) {
      AmbulanceStore.instance.registerAmbulance(local);
    }

    if (!FirebaseBootstrap.isReady) {
      return local;
    }

    try {
      final snapshot = await FirestoreReadHelper.getQuery(
        query: FirebaseFirestore.instance
            .collection(FirestorePaths.ambulances)
            .where('username', isEqualTo: normalized)
            .limit(1),
        preferCache: preferCache,
      );

      if (snapshot.docs.isEmpty) {
        return local;
      }

      final doc = snapshot.docs.first;
      final ambulance = RegisteredAmbulance.fromMap(doc.id, doc.data());
      if (!_isRegistered(ambulance)) {
        return local;
      }

      AmbulanceStore.instance.registerAmbulance(ambulance);
      await AmbulanceLoginCache.save(ambulance);
      return ambulance;
    } catch (e, st) {
      if (kDebugMode) debugPrint('fetchAmbulanceByUsername error: $e\n$st');
      return local;
    }
  }

  /// Lookup a registered ambulance by phone number (PIN reset after SMS verification).
  Future<RegisteredAmbulance?> fetchAmbulanceByPhone(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return null;

    if (!FirebaseBootstrap.isReady) {
      try {
        return AmbulanceStore.instance.registeredAmbulances
            .firstWhere((a) => a.phone.trim() == trimmed);
      } catch (_) {
        return null;
      }
    }

    final candidates = <String>{
      trimmed,
      trimmed.replaceAll(RegExp(r'\s+'), ''),
    };
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      candidates.add(digits.substring(digits.length - 10));
      candidates.add('+91${digits.substring(digits.length - 10)}');
    }

    try {
      for (final candidate in candidates) {
        final snapshot = await FirestoreReadHelper.getQuery(
          query: FirebaseFirestore.instance
              .collection(FirestorePaths.ambulances)
              .where('phone', isEqualTo: candidate)
              .limit(1),
          preferCache: false,
        );
        if (snapshot.docs.isEmpty) continue;

        final ambulance = RegisteredAmbulance.fromMap(
          snapshot.docs.first.id,
          snapshot.docs.first.data(),
        );
        if (!_isRegistered(ambulance)) continue;
        AmbulanceStore.instance.registerAmbulance(ambulance);
        return ambulance;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('fetchAmbulanceByPhone error: $e\n$st');
    }
    return null;
  }

  /// Fetch all registered ambulances from Firestore.
  ///
  /// For username uniqueness checks, prefer [fetchAmbulanceByUsername] (indexed,
  /// single doc). Full collection load is still used by [fetchAllOnlineDrivers];
  /// see scale thresholds in [FirestoreQueryLimits].
  Future<List<RegisteredAmbulance>> fetchRegisteredAmbulances(
      {bool preferCache = true, bool onlyCache = false}) async {
    if (!FirebaseBootstrap.isReady) {
      return AmbulanceStore.instance.registeredAmbulances
          .where(_isRegistered)
          .toList();
    }

    try {
      final snapshot = await FirestoreReadHelper.getQuery(
        query: FirebaseFirestore.instance.collection(FirestorePaths.ambulances),
        preferCache: preferCache,
        onlyCache: onlyCache,
      );

      final list = snapshot.docs
          .map((doc) => RegisteredAmbulance.fromMap(doc.id, doc.data()))
          .where(_isRegistered)
          .toList();

      if (list.isNotEmpty) {
        AmbulanceStore.instance.loadAmbulances(list);
      }

      return list;
    } catch (e, st) {
      if (kDebugMode) debugPrint('fetchRegisteredAmbulances error: $e\n$st');
      return AmbulanceStore.instance.registeredAmbulances
          .where(_isRegistered)
          .toList();
    }
  }

  /// All registered drivers who are currently online.
  // FIXED: optional service-area filter so only drivers serving the pickup area are returned.
  Future<List<RegisteredAmbulance>> fetchAllOnlineDrivers(
      {String? area, String? userCity, AmbulanceType? type}) async {
    final all = await fetchRegisteredAmbulances();
    final normalizedArea = area == null ? '' : normalizeArea(area);
    final requestCity = userCity?.trim() ?? '';
    return all
        .where((a) => _isRegistered(a) && a.available)
        .where((a) => type == null || a.ambulanceType == type)
        .where((a) {
      if (requestCity.isEmpty) return false;
      return ambulanceMatchesRequestCity(
        requestCity: requestCity,
        ambulanceCity: a.city,
        serviceAreas: a.serviceAreas,
        baseAddress: a.baseAddress,
      );
    }).where((a) {
      if (normalizedArea.isEmpty) return true;
      if (a.serviceAreas.isEmpty) return true;
      return a.serviceAreas.any((s) {
        final serviceArea = normalizeArea(s);
        return serviceArea.contains(normalizedArea) ||
            normalizedArea.contains(serviceArea);
      });
    }).toList()
      ..sort((a, b) => a.serviceName.compareTo(b.serviceName));
  }

  /// Broadcast to every online driver — first to accept gets the trip.
  Future<String?> broadcastAmbulanceRequest({
    required String patientId,
    required String pickupLocation,
    required String dropLocation,
    String? patientName,
    String? contactPhone,
    String? bookedByRole,
    AmbulanceType? requestedType,
    String? userCity,
  }) async {
    if (patientId.isEmpty) return null;
    if (pickupLocation.trim().isEmpty || dropLocation.trim().isEmpty)
      return null;

    final drivers = await fetchAllOnlineDrivers(
      type: requestedType,
      userCity: userCity?.trim().isNotEmpty == true
          ? userCity!.trim()
          : pickupLocation.trim(),
    );
    if (drivers.isEmpty) {
      throw Exception('No ambulance drivers available in this area right now.');
    }

    final driverIds = drivers.map((d) => d.id).toList();

    if (!FirebaseBootstrap.isReady) {
      return AmbulanceStore.instance.createBroadcastRequest(
        driverIds: driverIds,
        patientId: patientId,
        pickupLocation: pickupLocation.trim(),
        dropLocation: dropLocation.trim(),
        patientName: patientName,
        contactPhone: contactPhone,
        bookedByRole: bookedByRole, // FIXED: pass through real booker role
      );
    }

    final broadcastId = 'broadcast-${DateTime.now().millisecondsSinceEpoch}';
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    final broadcastRef = firestore
        .collection(FirestorePaths.ambulanceBroadcasts)
        .doc(broadcastId);
    batch.set(broadcastRef, {
      'broadcastId': broadcastId,
      'patientId': patientId,
      'pickupLocation': pickupLocation.trim(),
      'dropLocation': dropLocation.trim(),
      'pickupArea': normalizeArea(pickupLocation),
      'status': 'pending',
      if (patientName != null && patientName.trim().isNotEmpty)
        'patientName': patientName.trim(),
      if (contactPhone != null && contactPhone.trim().isNotEmpty)
        'contactPhone': contactPhone.trim(),
      if (bookedByRole != null) 'bookedByRole': bookedByRole,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
    });

    final collection = firestore.collection(FirestorePaths.ambulanceRequests);
    for (final driverId in driverIds) {
      if (driverId.isEmpty) continue;
      final ref = collection.doc();
      batch.set(ref, {
        'driverId': driverId,
        'patientId': patientId,
        'pickupLocation': pickupLocation.trim(),
        'dropLocation': dropLocation.trim(),
        'pickupArea': normalizeArea(pickupLocation),
        'status': 'pending',
        'broadcastId': broadcastId,
        if (patientName != null && patientName.trim().isNotEmpty)
          'patientName': patientName.trim(),
        if (contactPhone != null && contactPhone.trim().isNotEmpty)
          'contactPhone': contactPhone.trim(),
        if (bookedByRole != null) 'bookedByRole': bookedByRole,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('broadcastAmbulanceRequest error: $e');
      throw Exception(e.message ?? 'Permission denied or network error.');
    } catch (e, st) {
      if (kDebugMode) debugPrint('broadcastAmbulanceRequest error: $e\n$st');
      throw Exception('Could not send request: $e');
    }

    AmbulanceStore.instance.upsertBooking(
      AmbulanceBooking(
        id: broadcastId,
        patientName: patientName?.trim().isNotEmpty == true
            ? patientName!.trim()
            : 'Patient',
        pickupLocation: pickupLocation.trim(),
        contactPhone: contactPhone?.trim() ?? '',
        notes: 'Destination: ${dropLocation.trim()}',
        bookedByRole: bookedByRole == AmbulanceBookedByRole.doctor.name
            ? AmbulanceBookedByRole.doctor
            : AmbulanceBookedByRole.patient,
        bookedByName: patientName ?? 'Patient',
        bookedById: patientId,
        createdAt: DateTime.now(),
      ),
    );

    return broadcastId;
  }

  /// Driver rejects the broadcast, hiding it from their pending list.
  Future<bool> rejectBroadcast({
    required String broadcastId,
    required String driverId,
  }) async {
    if (broadcastId.isEmpty || driverId.isEmpty) return false;

    if (!FirebaseBootstrap.isReady) {
      return AmbulanceStore.instance.rejectBooking(
        bookingId: broadcastId,
        ambulanceId: driverId,
      );
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final requestSnap = await firestore
          .collection(FirestorePaths.ambulanceRequests)
          .where('broadcastId', isEqualTo: broadcastId)
          .where('driverId', isEqualTo: driverId)
          .get();

      if (requestSnap.docs.isEmpty) return false;

      await requestSnap.docs.first.reference.update({'status': 'rejected'});
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('rejectBroadcast error: $e');
      return false;
    }
  }

  /// First driver to accept wins the broadcast.
  Future<bool> acceptBroadcast({
    required String broadcastId,
    required String driverId,
    required String ambulanceName,
  }) async {
    lastAcceptFailureDetail = null;
    lastAcceptFailureUserMessage = null;
    _acceptLog(
      'start broadcastId=$broadcastId driverId=$driverId',
    );

    if (broadcastId.isEmpty || driverId.isEmpty) {
      _setAcceptFailure(
        'invalid args: broadcastId or driverId empty',
        userMessage: 'Could not accept this trip. Please try again.',
      );
      return false;
    }

    var ambulance = AmbulanceStore.instance.findAmbulance(driverId);
    ambulance ??= await fetchAmbulanceById(driverId);
    if (ambulance == null) {
      _setAcceptFailure(
        'ambulance profile not found for driverId=$driverId',
        userMessage: 'Could not accept this trip. Please try again.',
      );
      return false;
    }
    final resolvedAmbulance = ambulance;

    if (!FirebaseBootstrap.isReady) {
      return AmbulanceStore.instance.acceptBooking(
        bookingId: broadcastId,
        ambulanceId: driverId,
      );
    }

    final store = AmbulanceStore.instance;
    final existing = store.findBooking(broadcastId);
    if (existing != null &&
        existing.isAccepted &&
        existing.acceptedAmbulanceId == driverId) {
      return true;
    }

    final firestore = FirebaseFirestore.instance;
    final broadcastRef = firestore
        .collection(FirestorePaths.ambulanceBroadcasts)
        .doc(broadcastId);

    DocumentReference<Map<String, dynamic>>? requestRef;
    final requestDocId = existing?.firestoreRequestId;
    if (requestDocId != null && requestDocId.isNotEmpty) {
      requestRef = firestore
          .collection(FirestorePaths.ambulanceRequests)
          .doc(requestDocId);
    } else {
      final requestSnap = await firestore
          .collection(FirestorePaths.ambulanceRequests)
          .where('broadcastId', isEqualTo: broadcastId)
          .where('driverId', isEqualTo: driverId)
          .limit(1)
          .get();

      if (requestSnap.docs.isNotEmpty) {
        requestRef = requestSnap.docs.first.reference;
      }
    }

    if (requestRef == null) {
      _setAcceptFailure(
        'no ambulance_requests doc for broadcastId=$broadcastId driverId=$driverId',
        userMessage: 'This request is no longer available.',
      );
      return false;
    }
    final requestDocRef = requestRef;
    final ambulanceNameResolved = ambulanceName.trim().isNotEmpty
        ? ambulanceName.trim()
        : resolvedAmbulance.serviceName;

    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final isAnon = FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
    _acceptLog(
      'auth currentUid=${authUid ?? '(null)'} isAnonymous=$isAnon',
    );

    var storedAuthUid = '(read failed)';
    try {
      final ambSnap = await firestore
          .collection(FirestorePaths.ambulances)
          .doc(driverId)
          .get();
      storedAuthUid = ambSnap.data()?['authUid'] as String? ?? '(empty)';
    } on FirebaseException catch (e) {
      storedAuthUid = '(FirebaseException code=${e.code} message=${e.message})';
    } catch (e) {
      storedAuthUid = '(error: $e)';
    }
    _acceptLog(
      'ambulance docId=$driverId storedAuthUid=$storedAuthUid '
      'authUidMatch=${storedAuthUid == (authUid ?? '')}',
    );

    var requestStatus = '(read failed)';
    try {
      final reqSnap = await requestDocRef.get();
      requestStatus = reqSnap.data()?['status'] as String? ?? '(missing)';
      _acceptLog(
        'request before tx path=${requestDocRef.path} status=$requestStatus',
      );
    } on FirebaseException catch (e) {
      requestStatus = '(FirebaseException code=${e.code} message=${e.message})';
      _acceptLog(
        'request read failed path=${requestDocRef.path} code=${e.code} message=${e.message}',
      );
    } catch (e) {
      requestStatus = '(error: $e)';
      _acceptLog('request read failed path=${requestDocRef.path} error=$e');
    }

    final linkOk = await linkDriverAuth(driverId);
    _acceptLog('linkDriverAuth(without pin)=$linkOk');

    final acceptedFields = <String, dynamic>{
      'status': 'accepted',
      'acceptedDriverId': driverId,
      'acceptedAmbulanceName': ambulanceNameResolved,
      'acceptedDriverName': resolvedAmbulance.driverName,
      'acceptedDriverPhone': resolvedAmbulance.phone,
      'acceptedVehicleNumber': resolvedAmbulance.vehicleNumber,
      'acceptedAmbulanceType': resolvedAmbulance.ambulanceTypeLabel,
      'acceptedAt': FieldValue.serverTimestamp(),
    };

    try {
      _acceptLog('phase1 transaction starting');
      // Phase 1: claim this driver's request copy (driver can read/write own request).
      final claimed = await firestore.runTransaction<bool>((tx) async {
        final requestSnapTx = await tx.get(requestDocRef);
        if (!requestSnapTx.exists) {
          _acceptLog('phase1 tx: request doc missing at ${requestDocRef.path}');
          return false;
        }
        final txStatus = requestSnapTx.data()?['status'];
        if (txStatus != 'pending') {
          _acceptLog(
            'phase1 tx: status=$txStatus (expected pending) path=${requestDocRef.path}',
          );
          return false;
        }
        tx.update(requestDocRef, acceptedFields);
        return true;
      });

      if (!claimed) {
        _setAcceptFailure(
          'phase1: transaction returned false (request missing or status != pending, '
          'pre-tx status=$requestStatus path=${requestDocRef.path})',
          userMessage: 'This request is no longer available.',
        );
        return false;
      }

      _acceptLog('phase1 ok');

      // Phase 2: claim parent broadcast without reading it (update-only rule:
      // driverCanClaimBroadcast). First pending→accepted wins; losers roll back.
      _acceptLog('phase2 broadcast update starting broadcastId=$broadcastId');
      try {
        await broadcastRef.update(acceptedFields);
      } on FirebaseException catch (e) {
        final detail =
            'phase2 FirebaseException code=${e.code} message=${e.message} '
            'plugin=${e.plugin} broadcastId=$broadcastId';
        _setAcceptFailure(
          detail,
          userMessage: 'Another driver accepted this trip first.',
        );
        try {
          await requestDocRef.update({'status': 'taken'});
          _acceptLog('phase2 rollback: request marked taken');
        } on FirebaseException catch (rollbackErr) {
          _acceptLog(
            'phase2 rollback failed code=${rollbackErr.code} message=${rollbackErr.message}',
          );
        } catch (rollbackErr) {
          _acceptLog('phase2 rollback failed error=$rollbackErr');
        }
        return false;
      }

      _acceptLog('phase2 ok');
      // Sibling pending copies → taken via markAmbulanceSiblingRequestsTakenOnAccept CF.

      try {
        if (!store.acceptBooking(
            bookingId: broadcastId, ambulanceId: driverId)) {
          final updated = store.findBooking(broadcastId);
          if (updated != null &&
              !(updated.isAccepted &&
                  updated.acceptedAmbulanceId == driverId)) {
            store.upsertBooking(
              updated.copyWithAccepted(
                ambulance: ambulance,
                acceptedAt: DateTime.now(),
              ),
            );
            AmbulanceNotificationEmitter.notifyBookingAcceptedForBooker(
              booking: store.findBooking(broadcastId) ?? updated,
              ambulance: ambulance,
            );
          }
        }
      } catch (e, st) {
        _acceptLog('local state sync after accept (non-fatal): $e\n$st');
      }

      _acceptLog('success');
      return true;
    } on FirebaseException catch (e, st) {
      _setAcceptFailure(
        'unexpected FirebaseException code=${e.code} message=${e.message} plugin=${e.plugin}',
        userMessage: 'Could not accept this trip. Please try again.',
      );
      _acceptLog('stack: $st');
      return false;
    } catch (e, st) {
      _setAcceptFailure(
        'unexpected error: $e',
        userMessage: 'Could not accept this trip. Please try again.',
      );
      _acceptLog('stack: $st');
      return false;
    }
  }

  /// Driver cancels an already accepted broadcast.
  Future<bool> cancelAcceptedBroadcast({
    required String broadcastId,
    required String driverId,
  }) async {
    lastCancelFailureUserMessage = null;
    if (broadcastId.isEmpty || driverId.isEmpty) {
      lastCancelFailureUserMessage =
          'Could not cancel this trip. Please try again.';
      return false;
    }

    if (!FirebaseBootstrap.isReady) {
      AmbulanceStore.instance.cancelBooking(broadcastId, rawStatus: 'rejected');
      return true;
    }

    final firestore = FirebaseFirestore.instance;
    final broadcastRef = firestore
        .collection(FirestorePaths.ambulanceBroadcasts)
        .doc(broadcastId);

    DocumentReference<Map<String, dynamic>>? requestRef;
    final existing = AmbulanceStore.instance.findBooking(broadcastId);
    final requestDocId = existing?.firestoreRequestId;
    if (requestDocId != null && requestDocId.isNotEmpty) {
      requestRef = firestore
          .collection(FirestorePaths.ambulanceRequests)
          .doc(requestDocId);
    } else {
      final requestSnap = await firestore
          .collection(FirestorePaths.ambulanceRequests)
          .where('broadcastId', isEqualTo: broadcastId)
          .where('driverId', isEqualTo: driverId)
          .limit(1)
          .get();
      if (requestSnap.docs.isNotEmpty) {
        requestRef = requestSnap.docs.first.reference;
      }
    }

    try {
      await broadcastRef.update({
        'status': 'cancelled',
        'cancelledByRole': 'driver',
        'acceptedDriverId': FieldValue.delete(),
        'acceptedAmbulanceName': FieldValue.delete(),
        'acceptedDriverName': FieldValue.delete(),
        'acceptedDriverPhone': FieldValue.delete(),
        'acceptedVehicleNumber': FieldValue.delete(),
        'acceptedAmbulanceType': FieldValue.delete(),
        'acceptedAt': FieldValue.delete(),
      });

      if (requestRef != null) {
        await requestRef.update({'status': 'rejected'});
      }

      // Sibling copies → cancelled/rejected via markAmbulanceSiblingRequestsOnBroadcastCancelled CF.
      AmbulanceStore.instance.cancelBooking(broadcastId, rawStatus: 'rejected');
      return true;
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('cancelAcceptedBroadcast error: $e');
      lastCancelFailureUserMessage =
          'Could not cancel this trip. Please try again.';
      return false;
    } catch (e, st) {
      if (kDebugMode) debugPrint('cancelAcceptedBroadcast error: $e\n$st');
      lastCancelFailureUserMessage =
          'Could not cancel this trip. Please try again.';
      return false;
    }
  }

  Future<bool> completeBroadcast({
    required String broadcastId,
    required String driverId,
  }) async {
    if (broadcastId.isEmpty || driverId.isEmpty) return false;

    final store = AmbulanceStore.instance;
    final booking = store.findBooking(broadcastId);
    if (booking?.isCompleted == true) return true;

    if (!FirebaseBootstrap.isReady) {
      return store.completeBooking(broadcastId, driverId: driverId);
    }

    var firestoreOk = false;

    try {
      final firestore = FirebaseFirestore.instance;
      final completedFields = {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      };

      final broadcastRef = firestore
          .collection(FirestorePaths.ambulanceBroadcasts)
          .doc(broadcastId);
      try {
        await broadcastRef.update(completedFields);
        firestoreOk = true;
      } on FirebaseException catch (e) {
        if (e.code != 'not-found' && kDebugMode) {
          debugPrint('completeBroadcast broadcast update: $e');
        }
      }

      final requestDocId = booking?.firestoreRequestId;
      if (requestDocId != null && requestDocId.isNotEmpty) {
        final requestRef = firestore
            .collection(FirestorePaths.ambulanceRequests)
            .doc(requestDocId);
        await requestRef.update(completedFields);
        firestoreOk = true;
      } else {
        final requests = await firestore
            .collection(FirestorePaths.ambulanceRequests)
            .where('broadcastId', isEqualTo: broadcastId)
            .get();

        for (final doc in requests.docs) {
          if (doc.data()['driverId'] != driverId) continue;
          await doc.reference.update(completedFields);
          firestoreOk = true;
          break;
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('completeBroadcast error: $e\n$st');
    }

    final localOk = store.completeBooking(broadcastId, driverId: driverId);
    return localOk || firestoreOk;
  }

  Future<bool> cancelBroadcast(String broadcastId) async {
    lastCancelFailureUserMessage = null;
    if (broadcastId.isEmpty) {
      lastCancelFailureUserMessage =
          'Could not cancel this request. Please try again.';
      return false;
    }

    if (!FirebaseBootstrap.isReady) {
      return AmbulanceStore.instance.cancelBooking(broadcastId);
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final broadcastRef = firestore
          .collection(FirestorePaths.ambulanceBroadcasts)
          .doc(broadcastId);
      await broadcastRef.set({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Request copies → cancelled via markAmbulanceSiblingRequestsOnBroadcastCancelled CF.
      return AmbulanceStore.instance.cancelBooking(broadcastId);
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('cancelBroadcast error: $e');
      lastCancelFailureUserMessage =
          'Could not cancel this request. Please try again.';
      return false;
    } catch (e, st) {
      if (kDebugMode) debugPrint('cancelBroadcast error: $e\n$st');
      lastCancelFailureUserMessage =
          'Could not cancel this request. Please try again.';
      return false;
    }
  }

  /// Save patient rating for a completed ambulance trip.
  Future<bool> rateBroadcast({
    required String broadcastId,
    required int stars,
    String? review,
  }) async {
    if (broadcastId.isEmpty || (stars != -1 && (stars < 1 || stars > 5)))
      return false;

    final booking = AmbulanceStore.instance.findBooking(broadcastId);
    if (booking != null && booking.isRated) return true;

    final storeOk = AmbulanceStore.instance.rateBooking(
      bookingId: broadcastId,
      stars: stars,
      review: review,
    );

    if (!FirebaseBootstrap.isReady) return storeOk;

    try {
      if (stars > 0) {
        final ambId = booking?.acceptedAmbulanceId;
        if (ambId == null || ambId.isEmpty) return storeOk;

        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('submitAmbulanceRating');
        await callable.call<Map<String, dynamic>>({
          'broadcastId': broadcastId,
          'ambulanceId': ambId,
          'stars': stars,
          if (review != null && review.trim().isNotEmpty)
            'review': review.trim(),
        });
        return true;
      }

      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection(FirestorePaths.ambulanceBroadcasts)
          .doc(broadcastId)
          .update({
        'rating': stars,
        if (review != null && review.trim().isNotEmpty) 'review': review.trim(),
        'ratedAt': FieldValue.serverTimestamp(),
      });

      final reqSnap = await firestore
          .collection(FirestorePaths.ambulanceRequests)
          .where('broadcastId', isEqualTo: broadcastId)
          .get();
      if (reqSnap.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in reqSnap.docs) {
          batch.update(doc.reference, {
            'rating': stars,
            if (review != null && review.trim().isNotEmpty)
              'review': review.trim(),
            'ratedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      return true;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode)
        debugPrint('rateBroadcast function error: ${e.code} ${e.message}');
      return storeOk;
    } catch (e, st) {
      if (kDebugMode) debugPrint('rateBroadcast error: $e\n$st');
      return storeOk;
    }
  }

  /// Update driver profile fields (keeps username, pin, and ratings unchanged).
  Future<bool> updateAmbulanceProfile(RegisteredAmbulance ambulance) async {
    if (ambulance.id.isEmpty) return false;

    final existing = AmbulanceStore.instance.findAmbulance(ambulance.id);
    final merged = (existing ?? ambulance).copyWith(
      serviceName: ambulance.serviceName,
      ownerName: ambulance.ownerName,
      driverName: ambulance.driverName,
      phone: ambulance.phone,
      vehicleNumber: ambulance.vehicleNumber,
      ambulanceType: ambulance.ambulanceType,
      city: ambulance.city,
      serviceAreas: ambulance.serviceAreas,
      baseAddress: ambulance.baseAddress,
      licenseNumber: ambulance.licenseNumber,
      insuranceNumber: ambulance.insuranceNumber,
      hasOxygen: ambulance.hasOxygen,
      hasVentilator: ambulance.hasVentilator,
      hasStretcher: ambulance.hasStretcher,
      is24x7: ambulance.is24x7,
      ratePerKm: ambulance.ratePerKm,
      addressLine1: ambulance.addressLine1,
      addressLine2: ambulance.addressLine2,
      country: ambulance.country,
      state: ambulance.state,
      pincode: ambulance.pincode,
    );

    AmbulanceStore.instance.updateRegisteredAmbulance(merged);

    if (!FirebaseBootstrap.isReady) return true;

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(merged.id)
          .set(merged.toMap(), SetOptions(merge: true));
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('updateAmbulanceProfile error: $e\n$st');
      return false;
    }
  }

  // FIXED: returns success so the UI can revert + warn; awaits Firestore before updating local state.
  Future<bool> updateAvailability(String id, bool available) async {
    if (!FirebaseBootstrap.isReady) {
      AmbulanceStore.instance.updateAvailability(id, available);
      return true;
    }

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(id)
          .set({'isAvailable': available},
              SetOptions(merge: true)); // FIXED: await before local update
      AmbulanceStore.instance.updateAvailability(
          id, available); // FIXED: only update local after confirmed write
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('updateAvailability error: $e');
      return false; // FIXED: report failure (no silent local-only change)
    }
  }

  /// Resets driver PIN via Cloud Function after OTP session verification.
  Future<({bool ok, String? error, String? driverId})> resetDriverPinAfterOtp({
    required String mobile,
    required String otpSessionId,
    required String newPin,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return (ok: false, error: 'Firebase is not available.', driverId: null);
    }

    final digits = FormValidators.registrationMobileDigits(mobile);
    if (digits == null) {
      return (
        ok: false,
        error: 'Enter a valid 10-digit mobile number.',
        driverId: null
      );
    }
    if (otpSessionId.trim().isEmpty) {
      return (
        ok: false,
        error: 'OTP verification session expired. Verify again.',
        driverId: null
      );
    }
    final pin = newPin.trim();
    if (pin.length < 6) {
      return (
        ok: false,
        error: 'Password must be at least 6 characters.',
        driverId: null
      );
    }

    if (FirebaseAuth.instance.currentUser == null) {
      return (
        ok: false,
        error: 'Secure session required. Please try again.',
        driverId: null
      );
    }

    final appCheckError = await _ensureAppCheckTokenForCallable();
    if (appCheckError != null) {
      return (ok: false, error: appCheckError, driverId: null);
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('resetAmbulanceDriverPin');
      final result = await callable.call<Map<String, dynamic>>({
        'mobile': digits,
        'otpSessionId': otpSessionId.trim(),
        'newPin': pin,
      });
      final data = result.data;
      if (data['ok'] != true) {
        return (
          ok: false,
          error: 'Could not reset PIN. Please try again.',
          driverId: null
        );
      }

      final driverId = data['driverId'] as String? ?? '';
      return (
        ok: true,
        error: null,
        driverId: driverId.isEmpty ? null : driverId
      );
    } on FirebaseFunctionsException catch (e) {
      return (ok: false, error: _mapResetPinError(e), driverId: null);
    } catch (e, st) {
      if (kDebugMode) debugPrint('resetDriverPinAfterOtp error: $e\n$st');
      return (
        ok: false,
        error: describeUserFacingError(e,
            fallback: 'Could not reset PIN. Please try again.'),
        driverId: null,
      );
    }
  }

  Future<String?> _ensureAppCheckTokenForCallable() async {
    if (!kIsWeb) return null;
    if (AppConstants.firebaseAppCheckRecaptchaSiteKey.isEmpty) return null;
    if (FirebaseBootstrap.appCheckReady) return null;

    try {
      await FirebaseAppCheck.instance.getToken();
      FirebaseBootstrap.appCheckReady = true;
      return null;
    } catch (_) {
      return 'Security verification failed. Refresh the page and try again.';
    }
  }

  String _mapResetPinError(FirebaseFunctionsException e) {
    final message = e.message?.trim();
    if (message != null &&
        message.isNotEmpty &&
        message != 'error' &&
        message != 'internal') {
      return message;
    }
    return switch (e.code) {
      'not-found' => 'Ambulance account not found with this phone number.',
      'failed-precondition' =>
        'OTP verification session expired. Verify again.',
      'deadline-exceeded' => 'OTP verification session expired. Verify again.',
      'resource-exhausted' => 'Too many attempts. Please try again later.',
      'permission-denied' => 'OTP verification failed. Please verify again.',
      'unauthenticated' => 'Secure session required. Please try again.',
      _ => 'Could not reset PIN. Please try again.',
    };
  }

  Future<AmbulanceDriverLoginResult> verifyDriverLogin({
    required String username,
    required String pin,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const AmbulanceDriverLoginResult(
        errorMessage: 'Firebase is not available. Check your connection.',
      );
    }

    final normalizedUsername = username.trim().toLowerCase();
    final normalizedPin = pin.trim();

    try {
      final data = await AmbulanceCallableClient.verifyDriverLogin(
        {
          'username': normalizedUsername,
          'pin': normalizedPin,
        },
      );
      if (data['ok'] != true) {
        return AmbulanceDriverLoginResult(
          pinUpgradeRequired: data['pinUpgradeRequired'] == true,
        );
      }

      final driverId = data['driverId'] as String? ?? '';
      if (driverId.isEmpty) return const AmbulanceDriverLoginResult();

      final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
      if (!signedIn) {
        return const AmbulanceDriverLoginResult(
          errorMessage:
              'Login verified but secure session failed. Please try again.',
        );
      }

      // Firestore rules only allow reading the ambulance doc when authUid matches
      // the current anonymous session — link before fetching the profile.
      await linkDriverAuth(
        driverId,
        username: normalizedUsername,
        pin: normalizedPin,
      );

      var profile = await fetchAmbulanceById(driverId);
      profile ??= RegisteredAmbulance(
        id: driverId,
        serviceName: data['serviceName'] as String? ?? '',
        driverName: data['driverName'] as String? ?? 'Driver',
        phone: '',
        vehicleNumber: '',
        city: data['city'] as String? ?? '',
        username: data['username'] as String? ?? normalizedUsername,
        available: data['isAvailable'] as bool? ?? true,
      );
      if (AmbulanceStore.instance.findAmbulance(driverId) == null) {
        AmbulanceStore.instance.registerAmbulance(profile);
      }

      final resolved = profile.copyWith(
        username: data['username'] as String? ?? normalizedUsername,
        driverName: data['driverName'] as String? ?? profile.driverName,
        serviceName: data['serviceName'] as String? ?? profile.serviceName,
        available: data['isAvailable'] as bool? ?? profile.available,
      );
      return AmbulanceDriverLoginResult(profile: resolved);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('verifyDriverLogin error: ${e.code} ${e.message}');
      }
      return AmbulanceDriverLoginResult(
        errorMessage: _mapDriverLoginFunctionsError(e),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('verifyDriverLogin error: $e\n$st');
      final text = e.toString();
      if (text.contains('ClientException') ||
          text.contains('Failed to fetch')) {
        return const AmbulanceDriverLoginResult(
          errorMessage:
              'Could not reach login service. Check your connection and try again.',
        );
      }
      return AmbulanceDriverLoginResult(
        errorMessage: describeUserFacingError(
          e,
          fallback: 'Login failed. Check your connection and try again.',
        ),
      );
    }
  }

  String _mapDriverLoginFunctionsError(FirebaseFunctionsException e) {
    return switch (e.code) {
      'unauthenticated' =>
        'Secure session required. Please refresh and try again.',
      'resource-exhausted' =>
        'Too many login attempts. Please try again later.',
      'permission-denied' =>
        'Incorrect username or password. Please try again.',
      'invalid-argument' => (e.message != null && e.message!.trim().isNotEmpty)
          ? e.message!.trim()
          : 'Invalid username or password. Please try again.',
      'internal' => 'Could not verify login right now. Please try again.',
      _ => describeFirebaseError(
          e,
          fallback: 'Incorrect username or password. Please try again.',
        ),
    };
  }

  /// Completes ambulance driver login after mobile OTP verification.
  Future<AmbulanceDriverLoginResult> verifyDriverMobileLogin({
    required String mobile,
    required String sessionId,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const AmbulanceDriverLoginResult();
    }

    final digits = FormValidators.registrationMobileDigits(mobile);
    if (digits == null || digits.isEmpty) {
      return const AmbulanceDriverLoginResult();
    }
    if (sessionId.trim().isEmpty) {
      return const AmbulanceDriverLoginResult();
    }

    if (FirebaseAuth.instance.currentUser == null) {
      return const AmbulanceDriverLoginResult();
    }

    try {
      final data = await AmbulanceCallableClient.call(
          'completeAmbulanceMobileOtpLogin', {
        'mobile': digits,
        'sessionId': sessionId.trim(),
      });
      if (data['ok'] != true) {
        return const AmbulanceDriverLoginResult();
      }

      final driverId = data['driverId'] as String? ?? '';
      if (driverId.isEmpty) return const AmbulanceDriverLoginResult();

      await linkDriverAuth(driverId);

      var profile = await fetchAmbulanceById(driverId);
      profile ??= RegisteredAmbulance(
        id: driverId,
        serviceName: data['serviceName'] as String? ?? '',
        driverName: data['driverName'] as String? ?? 'Driver',
        phone: digits,
        vehicleNumber: '',
        city: data['city'] as String? ?? '',
        username: data['username'] as String? ?? '',
        available: data['isAvailable'] as bool? ?? true,
      );
      if (AmbulanceStore.instance.findAmbulance(driverId) == null) {
        AmbulanceStore.instance.registerAmbulance(profile);
      }

      final resolved = profile.copyWith(
        username: data['username'] as String? ?? profile.username,
        driverName: data['driverName'] as String? ?? profile.driverName,
        serviceName: data['serviceName'] as String? ?? profile.serviceName,
        available: data['isAvailable'] as bool? ?? profile.available,
      );
      return AmbulanceDriverLoginResult(profile: resolved);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('verifyDriverMobileLogin error: ${e.code} ${e.message}');
      }
      return AmbulanceDriverLoginResult(
        errorMessage: _mapDriverLoginFunctionsError(e),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('verifyDriverMobileLogin error: $e\n$st');
      return const AmbulanceDriverLoginResult();
    }
  }

  bool _isRegistered(RegisteredAmbulance a) {
    if (a.username.trim().isEmpty) return false;
    if (a.serviceName.trim().isEmpty) return false;
    final idLower = a.id.toLowerCase();
    if (idLower == 'amb1' ||
        idLower == 'amb2' ||
        idLower == 'amb3' ||
        idLower == 'careplus' ||
        idLower == 'express' ||
        idLower == 'apex') {
      return false;
    }
    final usernameLower = a.username.trim().toLowerCase();
    if (usernameLower == 'amb1' ||
        usernameLower == 'amb2' ||
        usernameLower == 'amb3' ||
        usernameLower == 'careplus' ||
        usernameLower == 'express' ||
        usernameLower == 'apex') {
      return false;
    }
    return true;
  }
}
