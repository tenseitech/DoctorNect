import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_bootstrap.dart';

/// Supabase repository for Diagnostic Laboratories (Bookings, Orders, Tests, Reports).
class SupabaseLabRepository {
  SupabaseLabRepository._();

  static final SupabaseLabRepository instance = SupabaseLabRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  /// Fetches lab profile by [labId].
  Future<Map<String, dynamic>?> fetchLabProfile(String labId) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return null;
    try {
      final res = await _client
          .from('labs')
          .select()
          .eq('lab_id', labId)
          .maybeSingle();
      return res;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchLabProfile error: $e');
      return null;
    }
  }

  /// Lists verified labs optionally filtered by [city].
  Future<List<Map<String, dynamic>>> fetchVerifiedLabs({String? city}) async {
    if (!SupabaseBootstrap.isReady) return const [];
    try {
      var query = _client.from('labs').select().eq('verified', true);
      if (city != null && city.trim().isNotEmpty) {
        query = query.ilike('city', '%${city.trim()}%');
      }
      final res = await query.order('lab_name', ascending: true).limit(100);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchVerifiedLabs error: $e');
      return const [];
    }
  }

  /// Fetches published catalog tests offered by [labId].
  Future<List<Map<String, dynamic>>> fetchCatalogTests(String labId) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return const [];
    try {
      final res = await _client
          .from('lab_catalog_tests')
          .select()
          .eq('lab_id', labId)
          .eq('is_available', true)
          .order('test_name', ascending: true)
          .limit(200);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchCatalogTests error: $e');
      return const [];
    }
  }

  /// Fetches direct patient lab bookings for [labId].
  Future<List<Map<String, dynamic>>> fetchBookingsForLab(
    String labId, {
    String? status,
  }) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return const [];
    try {
      var query = _client.from('lab_bookings').select().eq('lab_id', labId);
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      final res = await query.order('date_time', ascending: false).limit(150);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchBookingsForLab error: $e');
      return const [];
    }
  }

  /// Fetches lab bookings made by [patientId].
  Future<List<Map<String, dynamic>>> fetchBookingsForPatient(
    String patientId,
  ) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];
    try {
      final res = await _client
          .from('lab_bookings')
          .select()
          .eq('patient_id', patientId)
          .order('date_time', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchBookingsForPatient error: $e');
      return const [];
    }
  }

  /// Updates lab booking status via validated state-machine RPC.
  Future<bool> updateLabBookingStatus({
    required String bookingId,
    required String newStatus,
    String? notes,
  }) async {
    if (!SupabaseBootstrap.isReady || bookingId.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'update_lab_booking_status',
        params: {
          'p_booking_id': bookingId,
          'p_new_status': newStatus,
          'p_notes': notes,
        },
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] updateLabBookingStatus error: $e');
      return false;
    }
  }

  /// Fetches doctor-prescribed lab orders assigned to [labId].
  Future<List<Map<String, dynamic>>> fetchOrdersForLab(
    String labId, {
    String? status,
  }) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return const [];
    try {
      var query = _client.from('lab_orders').select().eq('lab_id', labId);
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      final res = await query.order('created_at', ascending: false).limit(150);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchOrdersForLab error: $e');
      return const [];
    }
  }

  /// Updates doctor-prescribed lab order status and attaches S3 report via RPC.
  Future<bool> updateLabOrderStatus({
    required String orderId,
    required String newStatus,
    String? notes,
  }) async {
    if (!SupabaseBootstrap.isReady || orderId.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'update_lab_order_status',
        params: {
          'p_order_id': orderId,
          'p_new_status': newStatus,
          'p_notes': notes,
        },
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] updateLabOrderStatus error: $e');
      return false;
    }
  }

  /// Realtime stream of bookings for [labId].
  Stream<List<Map<String, dynamic>>> watchBookingsForLab(String labId) {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) {
      return const Stream.empty();
    }
    return _client
        .from('lab_bookings')
        .stream(primaryKey: ['booking_id'])
        .eq('lab_id', labId)
        .order('date_time', ascending: false);
  }
}
