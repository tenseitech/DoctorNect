import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_bootstrap.dart';

/// Supabase repository for Emergency Ambulance Dispatch & Live Tracking.
class SupabaseAmbulanceRepository {
  SupabaseAmbulanceRepository._();

  static final SupabaseAmbulanceRepository instance =
      SupabaseAmbulanceRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  /// Fetches registered ambulance profile by [ambulanceId].
  Future<Map<String, dynamic>?> fetchProfile(String ambulanceId) async {
    if (!SupabaseBootstrap.isReady || ambulanceId.isEmpty) return null;
    try {
      final res = await _client
          .from('ambulances')
          .select()
          .eq('ambulance_id', ambulanceId)
          .maybeSingle();
      return res;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] fetchProfile error: $e');
      return null;
    }
  }

  /// Lists currently available ambulance drivers optionally filtered by [city].
  Future<List<Map<String, dynamic>>> fetchAvailableAmbulances({
    String? city,
  }) async {
    if (!SupabaseBootstrap.isReady) return const [];
    try {
      var query = _client
          .from('ambulances')
          .select()
          .eq('verified', true)
          .eq('is_available', true);

      if (city != null && city.trim().isNotEmpty) {
        query = query.ilike('city', '%${city.trim()}%');
      }

      final res = await query.order('rating', ascending: false).limit(100);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] fetchAvailable error: $e');
      return const [];
    }
  }

  /// Lists pending emergency broadcasts for driver dispatch.
  Future<List<Map<String, dynamic>>> fetchPendingBroadcasts({
    String? city,
  }) async {
    if (!SupabaseBootstrap.isReady) return const [];
    try {
      var query = _client
          .from('ambulance_broadcasts')
          .select()
          .eq('status', 'pending');

      if (city != null && city.trim().isNotEmpty) {
        query = query.ilike('city', '%${city.trim()}%');
      }

      final res = await query.order('created_at', ascending: false).limit(50);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] fetchPendingBroadcasts error: $e');
      return const [];
    }
  }

  /// Lists dispatch requests targeted to driver [driverId].
  Future<List<Map<String, dynamic>>> fetchRequestsForDriver(
    String driverId,
  ) async {
    if (!SupabaseBootstrap.isReady || driverId.isEmpty) return const [];
    try {
      final res = await _client
          .from('ambulance_requests')
          .select('*, ambulance_broadcasts(*)')
          .eq('driver_id', driverId)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] fetchRequestsForDriver error: $e');
      return const [];
    }
  }

  /// Atomically accepts an emergency broadcast via RPC (row-locked, race-safe).
  /// Sibling requests for other drivers are automatically marked as 'taken'.
  Future<bool> acceptAmbulanceRequest({
    required String broadcastId,
    String? requestId,
  }) async {
    if (!SupabaseBootstrap.isReady || broadcastId.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'accept_ambulance_request',
        params: {
          'p_broadcast_id': broadcastId,
          'p_request_id': requestId,
        },
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] acceptAmbulanceRequest error: $e');
      return false;
    }
  }

  /// Sends live GPS location ping from driver.
  Future<bool> updateDriverLocation({
    required String broadcastId,
    required String driverId,
    required double latitude,
    required double longitude,
    double? heading,
    double? speed,
  }) async {
    if (!SupabaseBootstrap.isReady || broadcastId.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'update_ambulance_location',
        params: {
          'p_broadcast_id': broadcastId,
          'p_driver_id': driverId,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_heading': heading,
          'p_speed': speed,
        },
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] updateDriverLocation error: $e');
      return false;
    }
  }

  /// Fetches private counterpart contact & coordinates during active trip via RPC.
  Future<Map<String, dynamic>?> getTripLocation(String broadcastId) async {
    if (!SupabaseBootstrap.isReady || broadcastId.isEmpty) return null;
    try {
      final res = await _client.rpc(
        'get_ambulance_trip_location',
        params: {'p_broadcast_id': broadcastId},
      );
      if (res is Map<String, dynamic>) {
        return res;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] getTripLocation error: $e');
      return null;
    }
  }

  /// Completes trip via RPC (wipes active coordinates & temporary trip contacts).
  Future<bool> completeTrip(String broadcastId) async {
    if (!SupabaseBootstrap.isReady || broadcastId.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'complete_ambulance_trip',
        params: {'p_broadcast_id': broadcastId},
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] completeTrip error: $e');
      return false;
    }
  }

  /// Cancels active or pending ambulance trip via RPC.
  Future<bool> cancelTrip({
    required String broadcastId,
    String? reason,
  }) async {
    if (!SupabaseBootstrap.isReady || broadcastId.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'cancel_ambulance_trip',
        params: {
          'p_broadcast_id': broadcastId,
          'p_reason': reason,
        },
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAmbulance] cancelTrip error: $e');
      return false;
    }
  }

  /// Realtime stream of incoming dispatch requests for driver [driverId].
  Stream<List<Map<String, dynamic>>> watchIncomingRequests(String driverId) {
    if (!SupabaseBootstrap.isReady || driverId.isEmpty) {
      return const Stream.empty();
    }
    return _client
        .from('ambulance_requests')
        .stream(primaryKey: ['request_id'])
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);
  }

  /// Realtime stream of location-update change signals (contains ZERO PII / coords).
  Stream<List<Map<String, dynamic>>> watchLocationSignals(String broadcastId) {
    if (!SupabaseBootstrap.isReady || broadcastId.isEmpty) {
      return const Stream.empty();
    }
    return _client
        .from('ambulance_location_updates')
        .stream(primaryKey: ['broadcast_id'])
        .eq('broadcast_id', broadcastId);
  }
}
