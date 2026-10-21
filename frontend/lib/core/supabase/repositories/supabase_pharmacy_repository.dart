import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_bootstrap.dart';

/// Supabase repository for Pharmacy (Medical Stores, Connections, Deliveries).
class SupabasePharmacyRepository {
  SupabasePharmacyRepository._();

  static final SupabasePharmacyRepository instance =
      SupabasePharmacyRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  /// Fetches medical store profile by [storeId].
  Future<Map<String, dynamic>?> fetchMedicalStore(String storeId) async {
    if (!SupabaseBootstrap.isReady || storeId.isEmpty) return null;
    try {
      final res = await _client
          .from('medical_stores')
          .select()
          .eq('store_id', storeId)
          .maybeSingle();
      return res;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchStore error: $e');
      return null;
    }
  }

  /// Lists verified medical stores optionally filtered by [city].
  Future<List<Map<String, dynamic>>> fetchVerifiedStores({String? city}) async {
    if (!SupabaseBootstrap.isReady) return const [];
    try {
      var query = _client.from('medical_stores').select().eq('verified', true);
      if (city != null && city.trim().isNotEmpty) {
        query = query.ilike('city', '%${city.trim()}%');
      }
      final res = await query.order('store_name', ascending: true).limit(100);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchVerifiedStores error: $e');
      return const [];
    }
  }

  /// Fetches pharmacy deliveries assigned to [storeId].
  Future<List<Map<String, dynamic>>> fetchDeliveriesForStore(
    String storeId, {
    String? status,
  }) async {
    if (!SupabaseBootstrap.isReady || storeId.isEmpty) return const [];
    try {
      var query = _client
          .from('pharmacy_deliveries')
          .select('*, pharmacy_delivery_medicines(*)')
          .eq('store_id', storeId);

      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }

      final res = await query.order('sent_at', ascending: false).limit(150);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchDeliveriesForStore error: $e');
      return const [];
    }
  }

  /// Fetches pharmacy deliveries requested by [patientId].
  Future<List<Map<String, dynamic>>> fetchDeliveriesForPatient(
    String patientId,
  ) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];
    try {
      final res = await _client
          .from('pharmacy_deliveries')
          .select('*, pharmacy_delivery_medicines(*)')
          .eq('patient_id', patientId)
          .order('sent_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchDeliveriesForPatient error: $e');
      return const [];
    }
  }

  /// Updates delivery status via validated state-machine RPC.
  Future<bool> updateDeliveryStatus({
    required String deliveryId,
    required String newStatus,
    String? notes,
    List<Map<String, dynamic>>? medicineLines,
  }) async {
    if (!SupabaseBootstrap.isReady || deliveryId.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'update_pharmacy_delivery_status',
        params: {
          'p_delivery_id': deliveryId,
          'p_new_status': newStatus,
          'p_notes': notes,
          'p_medicine_lines': medicineLines,
        },
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] updateDeliveryStatus error: $e');
      return false;
    }
  }

  /// Realtime stream of delivery changes for [storeId].
  Stream<List<Map<String, dynamic>>> watchDeliveriesForStore(String storeId) {
    if (!SupabaseBootstrap.isReady || storeId.isEmpty) {
      return const Stream.empty();
    }
    return _client
        .from('pharmacy_deliveries')
        .stream(primaryKey: ['delivery_id'])
        .eq('store_id', storeId)
        .order('sent_at', ascending: false);
  }
}
