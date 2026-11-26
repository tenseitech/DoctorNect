import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../features/ambulance/data/ambulance_login_cache.dart';
import '../../../features/ambulance/data/ambulance_store.dart';
import '../../../features/ambulance/models/ambulance_models.dart';
import '../../constants/app_constants.dart';
import '../../location/location_match.dart';
import '../../notifications/ambulance_notification_emitter.dart';
import '../../supabase/mappers/ambulance_supabase_mapper.dart';
import '../../supabase/repositories/supabase_ambulance_repository.dart';
import '../../supabase/supabase_bootstrap.dart';
import '../../validators/form_validators.dart';
import '../ambulance_auth_helper.dart';
import '../ambulance_callable_client.dart';
import '../firebase_bootstrap.dart';
import '../firebase_error_messages.dart';

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

  String? lastAcceptFailureDetail;
  String? lastAcceptFailureUserMessage;
  String? lastCancelFailureUserMessage;

  void _acceptLog(String message) {
    if (kDebugMode) debugPrint('[AmbulanceAccept] $message');
  }

  void _setAcceptFailure(String detail, {String? userMessage}) {
    lastAcceptFailureDetail = detail;
    lastAcceptFailureUserMessage = userMessage ?? detail;
    _acceptLog('FAIL: $detail');
  }

  static String normalizeArea(String location) => location.trim().toLowerCase();

  RegisteredAmbulance? _profileFromRow(Map<String, dynamic> row) {
    final id = row['ambulance_id'] as String? ?? '';
    if (id.isEmpty) return null;
    final meta = (row['metadata'] as Map<String, dynamic>?) ?? const {};
    final merged = <String, dynamic>{
      ...meta,
      'serviceName':
          meta['service_name'] ?? meta['serviceName'] ?? row['service_name'],
      'driverName':
          row['driver_name'] ?? meta['driver_name'] ?? meta['driverName'],
      'phone': row['phone'],
      'vehicleNumber': row['vehicle_number'] ?? meta['vehicle_number'],
      'city': row['city'] ?? meta['city'],
      'username': row['username'] ?? meta['username'],
      'isAvailable': row['is_available'] ?? meta['isAvailable'] ?? true,
      'verified': row['verified'] ?? meta['verified'] ?? false,
    };
    return RegisteredAmbulance.fromMap(id, merged);
  }

  Map<String, dynamic> _rowFromProfile(
    RegisteredAmbulance ambulance,
    String? authUid,
  ) {
    final base =
        AmbulanceSupabaseMapper.driverToRow(ambulance, ownerUid: authUid);
    return {
      ...base,
      'username': ambulance.username.trim().toLowerCase(),
      if (authUid != null) 'auth_uid': authUid,
      'metadata': {
        ...?base['metadata'] as Map<String, dynamic>?,
        ...ambulance.toMap(includePrivateFields: false),
        if (ambulance.pin.isNotEmpty) 'pin_hash': ambulance.pin,
      },
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<bool> linkDriverAuth(
    String ambulanceId, {
    String? username,
    String? pin,
  }) async {
    if (!FirebaseBootstrap.isReady || ambulanceId.isEmpty) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    if (SupabaseBootstrap.isReady) {
      try {
        await SupabaseBootstrap.client.from('ambulances').update({
          'auth_uid': uid,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('ambulance_id', ambulanceId);
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('linkDriverAuth Supabase failed: $e');
      }
    }
    if (username != null &&
        pin != null &&
        username.trim().isNotEmpty &&
        pin.trim().length >= 6) {
      return resyncDriverAuth(
        username: username,
        pin: pin,
        expectedDriverId: ambulanceId,
      );
    }
    return false;
  }

  Future<bool> resyncDriverAuth({
    required String username,
    required String pin,
    String? expectedDriverId,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    try {
      final data = await AmbulanceCallableClient.call(
        'resyncAmbulanceAuthUid',
        {'username': username.trim().toLowerCase(), 'pin': pin.trim()},
      );
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

  Future<void> saveDriverFcmToken(String ambulanceId, String token) async {
    if (!SupabaseBootstrap.isReady || token.isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final platform = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : (defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'unknown'));
      await SupabaseBootstrap.client.from('user_devices').upsert({
        'user_id': uid,
        'platform': platform,
        'fcm_token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,platform');
    } catch (e) {
      if (kDebugMode) debugPrint('saveDriverFcmToken failed: $e');
    }
  }

  Future<void> clearDriverFcmToken(String ambulanceId) async {
    if (!SupabaseBootstrap.isReady) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final platform = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : (defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'unknown'));
      await SupabaseBootstrap.client
          .from('user_devices')
          .delete()
          .match({'user_id': uid, 'platform': platform});
    } catch (e) {
      if (kDebugMode) debugPrint('clearDriverFcmToken failed: $e');
    }
  }

  Future<AmbulanceRegisterResult> registerAmbulance(
    RegisteredAmbulance ambulance, {
    Map<String, dynamic>? extraFields,
  }) async {
    AmbulanceStore.instance.registerAmbulance(ambulance);

    if (!FirebaseBootstrap.isReady) {
      return const AmbulanceRegisterResult(
        error: 'Firebase is not available. Check your connection.',
      );
    }
    if (!SupabaseBootstrap.isReady) {
      return const AmbulanceRegisterResult(
        error: 'Database connection is not ready.',
      );
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return const AmbulanceRegisterResult(
          error: 'Secure session expired. Please try again.',
        );
      }

      final row = _rowFromProfile(ambulance, uid);
      if (extraFields != null) {
        final meta = Map<String, dynamic>.from(row['metadata'] as Map);
        meta.addAll(extraFields);
        row['metadata'] = meta;
      }
      await SupabaseBootstrap.client
          .from('ambulances')
          .upsert(row, onConflict: 'ambulance_id');
      return AmbulanceRegisterResult(id: ambulance.id);
    } catch (e, st) {
      if (kDebugMode) debugPrint('registerAmbulance error: $e\n$st');
      return AmbulanceRegisterResult(
        error: describeUserFacingError(
          e,
          fallback:
              'Could not save ambulance registration. Check connection and try again.',
        ),
      );
    }
  }

  Future<RegisteredAmbulance?> fetchAmbulanceById(String id) async {
    if (id.isEmpty) return null;
    final cached = AmbulanceStore.instance.findAmbulance(id);
    if (cached != null) return cached;

    if (SupabaseBootstrap.isReady) {
      final profile =
          await SupabaseAmbulanceRepository.instance.fetchProfile(id);
      if (profile != null) {
        AmbulanceStore.instance.registerAmbulance(profile);
        return profile;
      }
      try {
        final res = await SupabaseBootstrap.client
            .from('ambulances')
            .select()
            .eq('ambulance_id', id)
            .maybeSingle();
        if (res != null) {
          final mapped = _profileFromRow(Map<String, dynamic>.from(res));
          if (mapped != null && _isRegistered(mapped)) {
            AmbulanceStore.instance.registerAmbulance(mapped);
            return mapped;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('fetchAmbulanceById error: $e');
      }
    }
    return null;
  }

  Future<RegisteredAmbulance?> fetchAmbulanceByUsername(
    String username, {
    bool preferCache = true,
  }) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    var local = await AmbulanceLoginCache.loadForUsername(normalized);
    if (local != null) {
      AmbulanceStore.instance.registerAmbulance(local);
    }

    if (!SupabaseBootstrap.isReady) return local;

    try {
      var res = await SupabaseBootstrap.client
          .from('ambulances')
          .select()
          .eq('username', normalized)
          .limit(1)
          .maybeSingle();
      res ??= await SupabaseBootstrap.client
          .from('ambulances')
          .select()
          .filter('metadata->>username', 'eq', normalized)
          .limit(1)
          .maybeSingle();
      if (res == null) return local;
      final ambulance = _profileFromRow(Map<String, dynamic>.from(res));
      if (ambulance == null || !_isRegistered(ambulance)) return local;
      AmbulanceStore.instance.registerAmbulance(ambulance);
      await AmbulanceLoginCache.save(ambulance);
      return ambulance;
    } catch (e, st) {
      if (kDebugMode) debugPrint('fetchAmbulanceByUsername error: $e\n$st');
      return local;
    }
  }

  Future<RegisteredAmbulance?> fetchAmbulanceByPhone(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return null;

    final candidates = <String>{
      trimmed,
      trimmed.replaceAll(RegExp(r'\s+'), ''),
    };
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      candidates.add(digits.substring(digits.length - 10));
      candidates.add('+91${digits.substring(digits.length - 10)}');
    }

    if (!SupabaseBootstrap.isReady) {
      try {
        return AmbulanceStore.instance.registeredAmbulances.firstWhere(
          (a) => candidates.contains(a.phone.trim()),
        );
      } catch (_) {
        return null;
      }
    }

    for (final candidate in candidates) {
      try {
        final res = await SupabaseBootstrap.client
            .from('ambulances')
            .select()
            .eq('phone', candidate)
            .limit(1)
            .maybeSingle();
        if (res == null) continue;
        final ambulance = _profileFromRow(Map<String, dynamic>.from(res));
        if (ambulance == null || !_isRegistered(ambulance)) continue;
        AmbulanceStore.instance.registerAmbulance(ambulance);
        return ambulance;
      } catch (e) {
        if (kDebugMode) debugPrint('fetchAmbulanceByPhone error: $e');
      }
    }
    return null;
  }

  Future<List<RegisteredAmbulance>> fetchRegisteredAmbulances({
    bool preferCache = true,
    bool onlyCache = false,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      return AmbulanceStore.instance.registeredAmbulances
          .where(_isRegistered)
          .toList();
    }
    if (onlyCache) {
      return AmbulanceStore.instance.registeredAmbulances
          .where(_isRegistered)
          .toList();
    }
    try {
      final res =
          await SupabaseBootstrap.client.from('ambulances').select().limit(500);
      final list = (res as List)
          .map((r) => _profileFromRow(Map<String, dynamic>.from(r)))
          .whereType<RegisteredAmbulance>()
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

  Future<List<RegisteredAmbulance>> fetchAllOnlineDrivers({
    String? area,
    String? userCity,
    AmbulanceType? type,
  }) async {
    if (SupabaseBootstrap.isReady) {
      final remote =
          await SupabaseAmbulanceRepository.instance.fetchAvailableAmbulances(
        city: userCity,
      );
      if (remote.isNotEmpty) {
        AmbulanceStore.instance.loadAmbulances(remote);
      }
    }

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
    if (pickupLocation.trim().isEmpty || dropLocation.trim().isEmpty) {
      return null;
    }

    final drivers = await fetchAllOnlineDrivers(
      type: requestedType,
      userCity: userCity?.trim().isNotEmpty == true
          ? userCity!.trim()
          : pickupLocation.trim(),
    );
    if (drivers.isEmpty) {
      throw Exception('No ambulance drivers available in this area right now.');
    }

    final broadcastId = 'broadcast-${DateTime.now().millisecondsSinceEpoch}';
    final booking = AmbulanceBooking(
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
      status: AmbulanceBookingStatus.pending,
      createdAt: DateTime.now(),
    );

    if (SupabaseBootstrap.isReady) {
      await SupabaseAmbulanceRepository.instance.saveBroadcast(booking);
      AmbulanceStore.instance.upsertBooking(booking);
      return broadcastId;
    }

    return AmbulanceStore.instance.createBroadcastRequest(
      driverIds: drivers.map((d) => d.id).toList(),
      patientId: patientId,
      pickupLocation: pickupLocation.trim(),
      dropLocation: dropLocation.trim(),
      patientName: patientName,
      contactPhone: contactPhone,
      bookedByRole: bookedByRole,
    );
  }

  Future<bool> rejectBroadcast({
    required String broadcastId,
    required String driverId,
  }) async {
    if (broadcastId.isEmpty || driverId.isEmpty) return false;
    if (SupabaseBootstrap.isReady) {
      try {
        await SupabaseBootstrap.client
            .from('ambulance_requests')
            .update({'status': 'rejected'})
            .eq('broadcast_id', broadcastId)
            .eq('driver_id', driverId);
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('rejectBroadcast error: $e');
      }
    }
    return AmbulanceStore.instance.rejectBooking(
      bookingId: broadcastId,
      ambulanceId: driverId,
    );
  }

  Future<bool> acceptBroadcast({
    required String broadcastId,
    required String driverId,
    required String ambulanceName,
  }) async {
    lastAcceptFailureDetail = null;
    lastAcceptFailureUserMessage = null;
    _acceptLog('start broadcastId=$broadcastId driverId=$driverId');

    if (broadcastId.isEmpty || driverId.isEmpty) {
      _setAcceptFailure(
        'invalid args',
        userMessage: 'Could not accept this trip. Please try again.',
      );
      return false;
    }

    var ambulance = AmbulanceStore.instance.findAmbulance(driverId);
    ambulance ??= await fetchAmbulanceById(driverId);
    if (ambulance == null) {
      _setAcceptFailure(
        'profile missing',
        userMessage: 'Could not accept this trip. Please try again.',
      );
      return false;
    }

    if (SupabaseBootstrap.isReady) {
      final existing = AmbulanceStore.instance.findBooking(broadcastId);
      final ok =
          await SupabaseAmbulanceRepository.instance.acceptAmbulanceRequest(
        broadcastId: broadcastId,
        requestId: existing?.firestoreRequestId,
      );
      if (ok) {
        AmbulanceStore.instance.acceptBooking(
          bookingId: broadcastId,
          ambulanceId: driverId,
        );
        final acceptedBooking =
            AmbulanceStore.instance.findBooking(broadcastId);
        if (acceptedBooking != null) {
          AmbulanceNotificationEmitter.notifyBookingAcceptedForBooker(
            booking: acceptedBooking,
            ambulance: ambulance,
          );
        }
      } else {
        _setAcceptFailure(
          'supabase accept failed',
          userMessage: 'This request is no longer available.',
        );
      }
      return ok;
    }

    return AmbulanceStore.instance.acceptBooking(
      bookingId: broadcastId,
      ambulanceId: driverId,
    );
  }

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
    if (SupabaseBootstrap.isReady) {
      final ok = await SupabaseAmbulanceRepository.instance.cancelTrip(
        broadcastId: broadcastId,
        reason: 'driver_cancelled',
      );
      if (ok) {
        AmbulanceStore.instance
            .cancelBooking(broadcastId, rawStatus: 'rejected');
        return true;
      }
      lastCancelFailureUserMessage =
          'Could not cancel this trip. Please try again.';
      return false;
    }
    AmbulanceStore.instance.cancelBooking(broadcastId, rawStatus: 'rejected');
    return true;
  }

  Future<bool> completeBroadcast({
    required String broadcastId,
    required String driverId,
  }) async {
    if (broadcastId.isEmpty || driverId.isEmpty) return false;
    final store = AmbulanceStore.instance;
    if (store.findBooking(broadcastId)?.isCompleted == true) return true;

    var remoteOk = false;
    if (SupabaseBootstrap.isReady) {
      remoteOk = await SupabaseAmbulanceRepository.instance.completeTrip(
        broadcastId,
      );
    }
    final localOk = store.completeBooking(broadcastId, driverId: driverId);
    return localOk || remoteOk;
  }

  Future<bool> cancelBroadcast(String broadcastId) async {
    lastCancelFailureUserMessage = null;
    if (broadcastId.isEmpty) {
      lastCancelFailureUserMessage =
          'Could not cancel this request. Please try again.';
      return false;
    }
    if (SupabaseBootstrap.isReady) {
      final ok = await SupabaseAmbulanceRepository.instance.cancelTrip(
        broadcastId: broadcastId,
      );
      if (!ok) {
        lastCancelFailureUserMessage =
            'Could not cancel this request. Please try again.';
        return false;
      }
    }
    return AmbulanceStore.instance.cancelBooking(broadcastId);
  }

  Future<bool> rateBroadcast({
    required String broadcastId,
    required int stars,
    String? review,
  }) async {
    if (broadcastId.isEmpty || (stars != -1 && (stars < 1 || stars > 5))) {
      return false;
    }

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
      if (SupabaseBootstrap.isReady) {
        await SupabaseBootstrap.client.from('ambulance_broadcasts').update({
          'rating': stars,
          if (review != null && review.trim().isNotEmpty)
            'review': review.trim(),
          'rated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('broadcast_id', broadcastId);
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('rateBroadcast function error: ${e.code} ${e.message}');
      }
      return storeOk;
    } catch (e, st) {
      if (kDebugMode) debugPrint('rateBroadcast error: $e\n$st');
      return storeOk;
    }
  }

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

    if (!SupabaseBootstrap.isReady) return true;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final row = _rowFromProfile(merged, uid);
      await SupabaseBootstrap.client
          .from('ambulances')
          .upsert(row, onConflict: 'ambulance_id');
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('updateAmbulanceProfile error: $e\n$st');
      return false;
    }
  }

  Future<bool> updateAvailability(String id, bool available) async {
    AmbulanceStore.instance.updateAvailability(id, available);
    if (!SupabaseBootstrap.isReady) return true;
    try {
      await SupabaseBootstrap.client.from('ambulances').update({
        'is_available': available,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('ambulance_id', id);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('updateAvailability error: $e');
      return false;
    }
  }

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
        driverId: null,
      );
    }
    if (otpSessionId.trim().isEmpty) {
      return (
        ok: false,
        error: 'OTP verification session expired. Verify again.',
        driverId: null,
      );
    }
    final pin = newPin.trim();
    if (pin.length < 6) {
      return (
        ok: false,
        error: 'Password must be at least 6 characters.',
        driverId: null,
      );
    }

    if (FirebaseAuth.instance.currentUser == null) {
      return (
        ok: false,
        error: 'Secure session required. Please try again.',
        driverId: null,
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
          driverId: null,
        );
      }
      final driverId = data['driverId'] as String? ?? '';
      return (
        ok: true,
        error: null,
        driverId: driverId.isEmpty ? null : driverId,
      );
    } on FirebaseFunctionsException catch (e) {
      return (ok: false, error: _mapResetPinError(e), driverId: null);
    } catch (e, st) {
      if (kDebugMode) debugPrint('resetDriverPinAfterOtp error: $e\n$st');
      return (
        ok: false,
        error: describeUserFacingError(
          e,
          fallback: 'Could not reset PIN. Please try again.',
        ),
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
      final data = await AmbulanceCallableClient.verifyDriverLogin({
        'username': normalizedUsername,
        'pin': normalizedPin,
      });
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
      AmbulanceStore.instance.registerAmbulance(profile);

      return AmbulanceDriverLoginResult(
        profile: profile.copyWith(
          username: data['username'] as String? ?? normalizedUsername,
          driverName: data['driverName'] as String? ?? profile.driverName,
          serviceName: data['serviceName'] as String? ?? profile.serviceName,
          available: data['isAvailable'] as bool? ?? profile.available,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      return AmbulanceDriverLoginResult(
        errorMessage: _mapDriverLoginFunctionsError(e),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('verifyDriverLogin error: $e\n$st');
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

  Future<AmbulanceDriverLoginResult> verifyDriverMobileLogin({
    required String mobile,
    required String sessionId,
  }) async {
    if (!FirebaseBootstrap.isReady) return const AmbulanceDriverLoginResult();

    final digits = FormValidators.registrationMobileDigits(mobile);
    if (digits == null || digits.isEmpty || sessionId.trim().isEmpty) {
      return const AmbulanceDriverLoginResult();
    }
    if (FirebaseAuth.instance.currentUser == null) {
      return const AmbulanceDriverLoginResult();
    }

    try {
      final data = await AmbulanceCallableClient.call(
        'completeAmbulanceMobileOtpLogin',
        {'mobile': digits, 'sessionId': sessionId.trim()},
      );
      if (data['ok'] != true) return const AmbulanceDriverLoginResult();

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
      AmbulanceStore.instance.registerAmbulance(profile);

      return AmbulanceDriverLoginResult(
        profile: profile.copyWith(
          username: data['username'] as String? ?? profile.username,
          driverName: data['driverName'] as String? ?? profile.driverName,
          serviceName: data['serviceName'] as String? ?? profile.serviceName,
          available: data['isAvailable'] as bool? ?? profile.available,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      return AmbulanceDriverLoginResult(
        errorMessage: _mapDriverLoginFunctionsError(e),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('verifyDriverMobileLogin error: $e\n$st');
      return const AmbulanceDriverLoginResult();
    }
  }

  bool _isRegistered(RegisteredAmbulance a) {
    if (a.username.trim().isEmpty || a.serviceName.trim().isEmpty) return false;
    final idLower = a.id.toLowerCase();
    const demo = {'amb1', 'amb2', 'amb3', 'careplus', 'express', 'apex'};
    if (demo.contains(idLower)) return false;
    if (demo.contains(a.username.trim().toLowerCase())) return false;
    return true;
  }
}
