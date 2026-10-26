import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase/models/firestore_page.dart';
import '../../../features/pharmacy/models/pharmacy_models.dart';
import '../mappers/pharmacy_supabase_mapper.dart';
import '../supabase_bootstrap.dart';
import '../supabase_watcher_state_machine.dart';

/// Supabase repository for Pharmacy (Medical Stores, Connections, Deliveries).
class SupabasePharmacyRepository {
  SupabasePharmacyRepository._();

  static final SupabasePharmacyRepository instance =
      SupabasePharmacyRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  /// Fetches medical store profile by [storeId].
  Future<MedicalStoreProfile?> fetchMedicalStore(String storeId) async {
    if (!SupabaseBootstrap.isReady || storeId.isEmpty) return null;
    try {
      final res = await _client
          .from('medical_stores')
          .select()
          .eq('store_id', storeId)
          .maybeSingle();
      if (res == null) return null;
      return PharmacySupabaseMapper.storeFromRow(res);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchStore error: $e');
      return null;
    }
  }

  /// Lists verified medical stores optionally filtered by [city].
  Future<List<MedicalStoreProfile>> fetchVerifiedStores({String? city}) async {
    if (!SupabaseBootstrap.isReady) return const [];
    try {
      var query = _client.from('medical_stores').select().eq('verified', true);
      if (city != null && city.trim().isNotEmpty) {
        query = query.ilike('city', '%${city.trim()}%');
      }
      final res = await query.order('store_name', ascending: true).limit(100);
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map(PharmacySupabaseMapper.storeFromRow).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchVerifiedStores error: $e');
      return const [];
    }
  }

  /// Saves or upserts a pharmacy connection.
  Future<void> saveConnection(PharmacyConnection connection) async {
    if (!SupabaseBootstrap.isReady) return;
    final row = PharmacySupabaseMapper.connectionToRow(connection);
    await _client.from('pharmacy_connections').upsert(row, onConflict: 'connection_id');
  }

  /// Saves or creates a pharmacy prescription delivery.
  Future<void> saveDelivery(PharmacyPrescriptionDelivery delivery) async {
    if (!SupabaseBootstrap.isReady) return;
    final row = PharmacySupabaseMapper.deliveryToRow(delivery);
    await _client.from('pharmacy_deliveries').upsert(row, onConflict: 'delivery_id');
  }

  /// Updates delivery status and dispensing notes.
  Future<void> updateDelivery(PharmacyPrescriptionDelivery delivery) async {
    if (!SupabaseBootstrap.isReady) return;
    await updateDeliveryStatus(
      deliveryId: delivery.id,
      newStatus: delivery.status.name,
      notes: delivery.dispensingNotes,
    );
  }

  /// Fetches a single delivery by its [deliveryId].
  Future<PharmacyPrescriptionDelivery?> fetchDeliveryById(
    String deliveryId,
  ) async {
    if (!SupabaseBootstrap.isReady || deliveryId.isEmpty) return null;
    try {
      final res = await _client
          .from('pharmacy_deliveries')
          .select('*, pharmacy_delivery_medicines(*)')
          .eq('delivery_id', deliveryId)
          .maybeSingle();
      if (res == null) return null;
      return PharmacySupabaseMapper.deliveryFromRow(res);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchDeliveryById error: $e');
      return null;
    }
  }

  /// Fetches a single delivery by associated [prescriptionId].
  Future<PharmacyPrescriptionDelivery?> fetchDeliveryByPrescriptionId(
    String prescriptionId,
  ) async {
    if (!SupabaseBootstrap.isReady || prescriptionId.isEmpty) return null;
    try {
      final res = await _client
          .from('pharmacy_deliveries')
          .select('*, pharmacy_delivery_medicines(*)')
          .eq('prescription_id', prescriptionId)
          .maybeSingle();
      if (res == null) return null;
      return PharmacySupabaseMapper.deliveryFromRow(res);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabasePharmacy] fetchDeliveryByPrescriptionId error: $e');
      }
      return null;
    }
  }

  /// Fetches pharmacy deliveries assigned to [storeId].
  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForStore(
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
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(PharmacySupabaseMapper.deliveryFromRow)
          .whereType<PharmacyPrescriptionDelivery>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchDeliveriesForStore error: $e');
      return const [];
    }
  }

  /// Fetches pharmacy deliveries created by [doctorId].
  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForDoctor(
    String doctorId,
  ) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return const [];
    try {
      final res = await _client
          .from('pharmacy_deliveries')
          .select('*, pharmacy_delivery_medicines(*)')
          .eq('doctor_id', doctorId)
          .order('sent_at', ascending: false)
          .limit(100);
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(PharmacySupabaseMapper.deliveryFromRow)
          .whereType<PharmacyPrescriptionDelivery>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabasePharmacy] fetchDeliveriesForDoctor error: $e');
      return const [];
    }
  }

  /// Fetches pharmacy deliveries requested by [patientId].
  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForPatient(
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
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(PharmacySupabaseMapper.deliveryFromRow)
          .whereType<PharmacyPrescriptionDelivery>()
          .toList();
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
  Stream<List<PharmacyPrescriptionDelivery>> watchDeliveriesForStore(
    String storeId,
  ) {
    if (!SupabaseBootstrap.isReady || storeId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<PharmacyPrescriptionDelivery>(
      fetcher: () => fetchDeliveriesForStore(storeId),
      getId: (item) => item.id,
      sort: (items) => items.sort((a, b) => b.sentAt.compareTo(a.sentAt)),
    );
    return watcher.stream();
  }

  /// Realtime stream of deliveries for [doctorId].
  Stream<List<PharmacyPrescriptionDelivery>> watchDeliveriesForDoctor(
    String doctorId,
  ) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<PharmacyPrescriptionDelivery>(
      fetcher: () => fetchDeliveriesForDoctor(doctorId),
      getId: (item) => item.id,
      sort: (items) => items.sort((a, b) => b.sentAt.compareTo(a.sentAt)),
    );
    return watcher.stream();
  }

  /// Realtime stream of pending connections for [doctorId].
  Stream<List<PharmacyConnection>> watchPendingConnectionsForDoctor(
    String doctorId,
  ) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<PharmacyConnection>(
      fetcher: () async {
        final res = await _client
            .from('pharmacy_connections')
            .select()
            .eq('doctor_id', doctorId)
            .eq('status', 'pending')
            .order('requested_at', ascending: false)
            .limit(50);
        final rows = List<Map<String, dynamic>>.from(res as List);
        return rows
            .map(PharmacySupabaseMapper.connectionFromRow)
            .whereType<PharmacyConnection>()
            .toList();
      },
      getId: (c) => c.id,
      sort: (items) => items.sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
    );
    return watcher.stream();
  }

  /// Realtime stream of pending connections for [storeId].
  Stream<List<PharmacyConnection>> watchPendingConnectionsForStore(
    String storeId,
  ) {
    if (!SupabaseBootstrap.isReady || storeId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<PharmacyConnection>(
      fetcher: () async {
        final res = await _client
            .from('pharmacy_connections')
            .select()
            .eq('store_id', storeId)
            .eq('status', 'pending')
            .order('requested_at', ascending: false)
            .limit(50);
        final rows = List<Map<String, dynamic>>.from(res as List);
        return rows
            .map(PharmacySupabaseMapper.connectionFromRow)
            .whereType<PharmacyConnection>()
            .toList();
      },
      getId: (c) => c.id,
      sort: (items) => items.sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
    );
    return watcher.stream();
  }

  /// One-time fetch for active connections for doctor.
  Future<FirestorePage<PharmacyConnection>> fetchActiveConnectionsForDoctor(
    String doctorId, {
    int limit = 50,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }
    try {
      final res = await _client
          .from('pharmacy_connections')
          .select()
          .eq('doctor_id', doctorId)
          .eq('status', 'active')
          .order('requested_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(PharmacySupabaseMapper.connectionFromRow)
          .whereType<PharmacyConnection>()
          .toList();
      return FirestorePage(items: items, hasMore: items.length == limit);
    } catch (_) {
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  /// One-time fetch for active connections for store.
  Future<FirestorePage<PharmacyConnection>> fetchActiveConnectionsForStore(
    String storeId, {
    int limit = 50,
  }) async {
    if (!SupabaseBootstrap.isReady || storeId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }
    try {
      final res = await _client
          .from('pharmacy_connections')
          .select()
          .eq('store_id', storeId)
          .eq('status', 'active')
          .order('requested_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(PharmacySupabaseMapper.connectionFromRow)
          .whereType<PharmacyConnection>()
          .toList();
      return FirestorePage(items: items, hasMore: items.length == limit);
    } catch (_) {
      return const FirestorePage(items: [], hasMore: false);
    }
  }
}
