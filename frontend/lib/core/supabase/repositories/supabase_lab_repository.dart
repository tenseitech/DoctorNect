import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase/models/doctor_lab_order.dart';
import '../../firebase/models/firestore_page.dart';
import '../../firebase/lab_report_persist_verify.dart';
import '../../firebase/repositories/lab_booking_repository.dart';
import '../../../features/lab/models/lab_connection_models.dart';
import '../../../features/patient/lab/models/lab_models.dart';
import '../mappers/lab_supabase_mapper.dart';
import '../supabase_bootstrap.dart';
import '../supabase_stream_table.dart';
import '../supabase_watcher_state_machine.dart';

/// Supabase repository for Diagnostic Laboratories (Bookings, Orders, Tests, Reports).
class SupabaseLabRepository {
  SupabaseLabRepository._();

  static final SupabaseLabRepository instance = SupabaseLabRepository._();

  static const labReportRpcSkewMessage =
      'Lab report submit requires server SQL migrations 000015 and 000017 (report key RPC). '
      'Ask your administrator to apply the staging database updates, then retry.';

  static String? _labStatusRpcSkewUserMessage(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('p_report_storage_key') ||
        s.contains('could not find the function') ||
        (s.contains('update_lab_') && s.contains('does not exist'))) {
      return labReportRpcSkewMessage;
    }
    return null;
  }

  @visibleForTesting
  static Future<bool> Function({
    required String bookingId,
    required String newStatus,
    String? notes,
  })? debugUpdateLabBookingStatusOverride;

  @visibleForTesting
  static Future<bool> Function({
    required String orderId,
    required String newStatus,
    String? notes,
  })? debugUpdateLabOrderStatusOverride;

  @visibleForTesting
  static Future<void> Function(String bookingId, String key)?
      debugPersistLabBookingReportKeyOverride;

  @visibleForTesting
  static Future<void> Function(String bookingId)?
      debugClearLabBookingReportKeyOverride;

  @visibleForTesting
  static Future<void> Function(String orderId, String key)?
      debugPersistLabOrderReportKeyOverride;

  @visibleForTesting
  static Future<void> Function(String orderId)?
      debugClearLabOrderReportKeyOverride;

  /// Test hook: return `{status, key}` for a booking row.
  @visibleForTesting
  static Future<({String? status, String? key})> Function(String bookingId)?
      debugLabBookingReportStateFetcher;

  @visibleForTesting
  static Future<({String? status, String? key})> Function(String orderId)?
      debugLabOrderReportStateFetcher;

  @visibleForTesting
  static Future<String?> Function(String bookingId)? debugLabBookingReportKeyFetcher;

  @visibleForTesting
  static Future<String?> Function(String orderId)? debugLabOrderReportKeyFetcher;

  static bool reportPersistIsComplete({
    required String? status,
    required String? storedKey,
    required String expectedKey,
  }) {
    return status == 'completed' && storedKey == expectedKey;
  }

  @visibleForTesting
  static void debugResetForTesting() {
    debugUpdateLabBookingStatusOverride = null;
    debugUpdateLabOrderStatusOverride = null;
    debugPersistLabBookingReportKeyOverride = null;
    debugClearLabBookingReportKeyOverride = null;
    debugPersistLabOrderReportKeyOverride = null;
    debugClearLabOrderReportKeyOverride = null;
    debugLabBookingReportStateFetcher = null;
    debugLabOrderReportStateFetcher = null;
    debugLabBookingReportKeyFetcher = null;
    debugLabOrderReportKeyFetcher = null;
  }

  SupabaseClient get _client => SupabaseBootstrap.client;

  /// Fetches lab profile by [labId].
  Future<PartnerLab?> fetchLabProfile(String labId) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return null;
    try {
      final res = await _client
          .from('labs')
          .select()
          .eq('lab_id', labId)
          .maybeSingle();
      if (res == null) return null;
      return LabSupabaseMapper.partnerLabFromRow(res);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchLabProfile error: $e');
      return null;
    }
  }

  /// Lists verified labs optionally filtered by [city].
  Future<List<PartnerLab>> fetchVerifiedLabs({String? city}) async {
    if (!SupabaseBootstrap.isReady) return const [];
    try {
      var query = _client.from('labs').select().eq('verified', true);
      if (city != null && city.trim().isNotEmpty) {
        query = query.ilike('city', '%${city.trim()}%');
      }
      final res = await query.order('lab_name', ascending: true).limit(100);
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map(LabSupabaseMapper.partnerLabFromRow).toList();
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

  /// Saves or creates a lab booking record.
  Future<void> saveBooking(LabBookingRecord record) async {
    if (!SupabaseBootstrap.isReady) return;
    final row = LabSupabaseMapper.bookingToRow(record);
    await _client.from('lab_bookings').upsert(row, onConflict: 'booking_id');
  }

  /// Fetches direct patient lab bookings for [labId].
  Future<List<LabBookingRecord>> fetchBookingsForLab(
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
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(LabSupabaseMapper.bookingFromRow)
          .whereType<LabBookingRecord>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchBookingsForLab error: $e');
      return const [];
    }
  }

  /// Fetches lab bookings made by [patientId].
  Future<List<LabBookingRecord>> fetchBookingsForPatient(
    String patientId,
  ) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];
    try {
      if (!kReleaseMode && debugTableFetcher != null) {
        final rows = await debugTableFetcher!('lab_bookings');
        return rows
            .map(LabSupabaseMapper.bookingFromRow)
            .whereType<LabBookingRecord>()
            .toList();
      }

      final res = await _client
          .from('lab_bookings')
          .select()
          .eq('patient_id', patientId)
          .order('date_time', ascending: false)
          .limit(100);
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(LabSupabaseMapper.bookingFromRow)
          .whereType<LabBookingRecord>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchBookingsForPatient error: $e');
      return const [];
    }
  }

  static bool looksLikeLabReportStorageKey(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final v = value.trim();
    return v.startsWith('lab_reports/') && !v.contains('\n');
  }

  static String? resolveReportKeyFromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    for (final key in [
      'report_storage_key',
      'report_s3_key',
      'reportStorageKey',
    ]) {
      final v = row[key] as String?;
      if (looksLikeLabReportStorageKey(v)) return v!.trim();
    }
    final notes = row['notes'] as String?;
    if (looksLikeLabReportStorageKey(notes)) return notes!.trim();
    return null;
  }

  LabReportKeyCheckResult checkReportKeyMatches(String? stored, String expectedKey) {
    if (stored == null) return LabReportKeyCheckResult.noRowsMatch;
    return stored == expectedKey
        ? LabReportKeyCheckResult.allRowsMatch
        : LabReportKeyCheckResult.noRowsMatch;
  }

  Future<LabReportKeyCheckResult> verifyLinkedLabBookingReportKeys(
    Iterable<String> bookingIds,
    String expectedKey,
  ) async {
    var anyMatch = false;
    var anyMiss = false;
    for (final id in bookingIds.where((id) => id.trim().isNotEmpty)) {
      try {
        final state = await _fetchLabBookingReportState(id);
        if (reportPersistIsComplete(
          status: state.status,
          storedKey: state.key,
          expectedKey: expectedKey,
        )) {
          anyMatch = true;
        } else {
          anyMiss = true;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SupabaseLab] verifyLinkedLabBookingReportKeys error: $e');
        }
        return LabReportKeyCheckResult.inconclusive;
      }
    }
    if (anyMatch && anyMiss) return LabReportKeyCheckResult.partialMatch;
    if (anyMatch) return LabReportKeyCheckResult.allRowsMatch;
    if (anyMiss) return LabReportKeyCheckResult.noRowsMatch;
    return LabReportKeyCheckResult.inconclusive;
  }

  Future<LabReportKeyCheckResult> verifyLabOrderReportKey(
    String orderId,
    String expectedKey,
  ) async {
    try {
      final state = await _fetchLabOrderReportState(orderId);
      if (reportPersistIsComplete(
        status: state.status,
        storedKey: state.key,
        expectedKey: expectedKey,
      )) {
        return LabReportKeyCheckResult.allRowsMatch;
      }
      if (state.key == null && state.status == null) {
        return LabReportKeyCheckResult.inconclusive;
      }
      return LabReportKeyCheckResult.noRowsMatch;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseLab] verifyLabOrderReportKey error: $e');
      }
      return LabReportKeyCheckResult.inconclusive;
    }
  }

  Future<({String? status, String? key})> _fetchLabBookingReportState(
    String bookingId,
  ) async {
    final stateFetch = debugLabBookingReportStateFetcher;
    if (stateFetch != null) {
      return stateFetch(bookingId);
    }
    if (!SupabaseBootstrap.isReady) {
      return (status: null, key: null);
    }
    final res = await _client
        .from('lab_bookings')
        .select('status, report_storage_key, report_s3_key, notes')
        .eq('booking_id', bookingId)
        .maybeSingle();
    return (
      status: res?['status'] as String?,
      key: resolveReportKeyFromRow(res),
    );
  }

  Future<({String? status, String? key})> _fetchLabOrderReportState(
    String orderId,
  ) async {
    final stateFetch = debugLabOrderReportStateFetcher;
    if (stateFetch != null) {
      return stateFetch(orderId);
    }
    if (!SupabaseBootstrap.isReady) {
      return (status: null, key: null);
    }
    final res = await _client
        .from('lab_orders')
        .select('status, report_storage_key, report_s3_key, notes')
        .eq('order_id', orderId)
        .maybeSingle();
    return (
      status: res?['status'] as String?,
      key: resolveReportKeyFromRow(res),
    );
  }

  Future<String?> _fetchLabBookingReportKey(String bookingId) async {
    final state = await _fetchLabBookingReportState(bookingId);
    return state.key;
  }

  Future<String?> _fetchLabOrderReportKey(String orderId) async {
    final state = await _fetchLabOrderReportState(orderId);
    return state.key;
  }

  Future<void> _rollbackLabBookingReportKeyAfterFailedStatusUpdate(
    String bookingId,
    String writtenKey,
  ) async {
    try {
      final state = await _fetchLabBookingReportState(bookingId);
      if (state.status == 'completed') return;
      if (state.key == writtenKey) {
        await _clearLabBookingReportKey(bookingId);
      }
    } catch (_) {}
  }

  Future<void> _rollbackLabOrderReportKeyAfterFailedStatusUpdate(
    String orderId,
    String writtenKey,
  ) async {
    try {
      final state = await _fetchLabOrderReportState(orderId);
      if (state.status == 'completed') return;
      if (state.key == writtenKey) {
        await _clearLabOrderReportKey(orderId);
      }
    } catch (_) {}
  }

  Future<void> _persistLabBookingReportKey(String bookingId, String key) async {
    if (!SupabaseBootstrap.isReady || bookingId.isEmpty || key.isEmpty) return;
    if (debugPersistLabBookingReportKeyOverride != null) {
      await debugPersistLabBookingReportKeyOverride!(bookingId, key);
      return;
    }
    await _client.from('lab_bookings').update({
      'report_storage_key': key,
      'report_s3_key': key,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('booking_id', bookingId);
  }

  Future<void> _clearLabBookingReportKey(String bookingId) async {
    if (!SupabaseBootstrap.isReady || bookingId.isEmpty) return;
    if (debugClearLabBookingReportKeyOverride != null) {
      await debugClearLabBookingReportKeyOverride!(bookingId);
      return;
    }
    await _client.from('lab_bookings').update({
      'report_storage_key': null,
      'report_s3_key': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('booking_id', bookingId);
  }

  Future<void> _persistLabOrderReportKey(String orderId, String key) async {
    if (!SupabaseBootstrap.isReady || orderId.isEmpty || key.isEmpty) return;
    if (debugPersistLabOrderReportKeyOverride != null) {
      await debugPersistLabOrderReportKeyOverride!(orderId, key);
      return;
    }
    await _client.from('lab_orders').update({
      'report_storage_key': key,
      'report_s3_key': key,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('order_id', orderId);
  }

  Future<void> _clearLabOrderReportKey(String orderId) async {
    if (!SupabaseBootstrap.isReady || orderId.isEmpty) return;
    if (debugClearLabOrderReportKeyOverride != null) {
      await debugClearLabOrderReportKeyOverride!(orderId);
      return;
    }
    await _client.from('lab_orders').update({
      'report_storage_key': null,
      'report_s3_key': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('order_id', orderId);
  }

  /// Updates lab booking status via validated state-machine RPC.
  Future<bool> updateLabBookingStatus({
    required String bookingId,
    required String newStatus,
    String? notes,
    String? reportStorageKey,
  }) async {
    if (!SupabaseBootstrap.isReady || bookingId.isEmpty) return false;
    final key = reportStorageKey?.trim();
    final hasKey = key != null && key.isNotEmpty;
    try {
      final override = debugUpdateLabBookingStatusOverride;
      if (override != null) {
        final ok = await override(
          bookingId: bookingId,
          newStatus: newStatus,
          notes: notes,
        );
        if (!ok && hasKey) {
          await _rollbackLabBookingReportKeyAfterFailedStatusUpdate(
            bookingId,
            key,
          );
        }
        return ok;
      }
      final res = await _client.rpc(
        'update_lab_booking_status',
        params: {
          'p_booking_id': bookingId,
          'p_new_status': newStatus,
          if (notes != null) 'p_notes': notes,
          if (hasKey) 'p_report_storage_key': key,
        },
      );
      final ok = res is Map && res['success'] == true;
      if (!ok && hasKey) {
        await _rollbackLabBookingReportKeyAfterFailedStatusUpdate(
          bookingId,
          key,
        );
      }
      return ok;
    } catch (e) {
      if (hasKey) {
        await _rollbackLabBookingReportKeyAfterFailedStatusUpdate(
          bookingId,
          key,
        );
      }
      if (kDebugMode) debugPrint('[SupabaseLab] updateLabBookingStatus error: $e');
      final skew = _labStatusRpcSkewUserMessage(e);
      if (skew != null) throw StateError(skew);
      rethrow;
    }
  }

  /// Saves or creates a doctor lab order.
  Future<void> saveOrder(DoctorLabOrder order) async {
    if (!SupabaseBootstrap.isReady) return;
    final row = LabSupabaseMapper.orderToRow(order);
    await _client.from('lab_orders').upsert(row, onConflict: 'order_id');
  }

  /// Fetches doctor-prescribed lab orders assigned to [labId].
  Future<List<DoctorLabOrder>> fetchOrdersForLab(
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
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(LabSupabaseMapper.orderFromRow)
          .whereType<DoctorLabOrder>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseLab] fetchOrdersForLab error: $e');
      return const [];
    }
  }

  /// Fetches lab orders for a doctor.
  Future<FirestorePage<DoctorLabOrder>> fetchOrdersForDoctor(
    String doctorId, {
    int limit = 50,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }
    try {
      final res = await _client
          .from('lab_orders')
          .select()
          .eq('doctor_id', doctorId)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(LabSupabaseMapper.orderFromRow)
          .whereType<DoctorLabOrder>()
          .toList();
      return FirestorePage(items: items, hasMore: items.length == limit);
    } catch (_) {
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  /// Fetches lab orders for a patient.
  Future<FirestorePage<DoctorLabOrder>> fetchOrdersForPatient(
    String patientId, {
    int limit = 50,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }
    try {
      final res = await _client
          .from('lab_orders')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(LabSupabaseMapper.orderFromRow)
          .whereType<DoctorLabOrder>()
          .toList();
      return FirestorePage(items: items, hasMore: items.length == limit);
    } catch (_) {
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  /// Updates doctor-prescribed lab order status and attaches S3 report via RPC.
  Future<bool> updateLabOrderStatus({
    required String orderId,
    required String newStatus,
    String? notes,
    String? reportStorageKey,
  }) async {
    if (!SupabaseBootstrap.isReady || orderId.isEmpty) return false;
    final key = reportStorageKey?.trim();
    final hasKey = key != null && key.isNotEmpty;
    try {
      final override = debugUpdateLabOrderStatusOverride;
      if (override != null) {
        final ok = await override(
          orderId: orderId,
          newStatus: newStatus,
          notes: notes,
        );
        if (!ok && hasKey) {
          await _rollbackLabOrderReportKeyAfterFailedStatusUpdate(
            orderId,
            key,
          );
        }
        return ok;
      }
      final res = await _client.rpc(
        'update_lab_order_status',
        params: {
          'p_order_id': orderId,
          'p_new_status': newStatus,
          if (notes != null) 'p_notes': notes,
          if (hasKey) 'p_report_storage_key': key,
        },
      );
      final ok = res is Map && res['success'] == true;
      if (!ok && hasKey) {
        await _rollbackLabOrderReportKeyAfterFailedStatusUpdate(
          orderId,
          key,
        );
      }
      return ok;
    } catch (e) {
      if (hasKey) {
        await _rollbackLabOrderReportKeyAfterFailedStatusUpdate(
          orderId,
          key,
        );
      }
      if (kDebugMode) debugPrint('[SupabaseLab] updateLabOrderStatus error: $e');
      final skew = _labStatusRpcSkewUserMessage(e);
      if (skew != null) throw StateError(skew);
      rethrow;
    }
  }

  /// Realtime stream of bookings for [labId].
  Stream<List<LabBookingRecord>> watchBookingsForLab(String labId) {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<LabBookingRecord>(
      fetcher: () => fetchBookingsForLab(labId),
      getId: (b) => b.bookingId,
      sort: (items) => items.sort((a, b) => b.dateTime.compareTo(a.dateTime)),
    );
    return watcher.stream();
  }

  /// Realtime stream of bookings for [patientId].
  Stream<List<LabBookingRecord>> watchBookingsForPatient(String patientId) {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<LabBookingRecord>(
      fetcher: () => fetchBookingsForPatient(patientId),
      getId: (b) => b.bookingId,
      sort: (items) => items.sort((a, b) => b.dateTime.compareTo(a.dateTime)),
    );
    return watcher.stream();
  }

  /// Realtime stream of orders for [labId].
  Stream<List<DoctorLabOrder>> watchOrdersForLab(String labId) {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<DoctorLabOrder>(
      fetcher: () => fetchOrdersForLab(labId),
      getId: (o) => o.orderId,
      sort: (items) => items.sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
    return watcher.stream();
  }

  /// Realtime stream of orders for [doctorId].
  Stream<List<DoctorLabOrder>> watchOrdersForDoctor(String doctorId) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<DoctorLabOrder>(
      fetcher: () async {
        final page = await fetchOrdersForDoctor(doctorId, limit: 100);
        return page.items;
      },
      getId: (o) => o.orderId,
      sort: (items) => items.sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
    return watcher.stream();
  }

  /// Realtime stream of pending connections for [doctorId].
  Stream<List<LabConnection>> watchPendingConnectionsForDoctor(
    String doctorId,
  ) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<LabConnection>(
      fetcher: () async {
        final res = await _client
            .from('lab_connections')
            .select()
            .eq('doctor_id', doctorId)
            .eq('status', 'pending')
            .order('requested_at', ascending: false)
            .limit(50);
        final rows = List<Map<String, dynamic>>.from(res as List);
        return rows
            .map(LabSupabaseMapper.connectionFromRow)
            .whereType<LabConnection>()
            .toList();
      },
      getId: (c) => c.id,
      sort: (items) => items.sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
    );
    return watcher.stream();
  }

  /// Realtime stream of pending connections for [labId].
  Stream<List<LabConnection>> watchPendingConnectionsForLab(String labId) {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) {
      return const Stream.empty();
    }
    final watcher = SupabaseWatcherStateMachine<LabConnection>(
      fetcher: () async {
        final res = await _client
            .from('lab_connections')
            .select()
            .eq('lab_id', labId)
            .eq('status', 'pending')
            .order('requested_at', ascending: false)
            .limit(50);
        final rows = List<Map<String, dynamic>>.from(res as List);
        return rows
            .map(LabSupabaseMapper.connectionFromRow)
            .whereType<LabConnection>()
            .toList();
      },
      getId: (c) => c.id,
      sort: (items) => items.sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
    );
    return watcher.stream();
  }

  /// One-time fetch for active connections for doctor.
  Future<FirestorePage<LabConnection>> fetchActiveConnectionsForDoctor(
    String doctorId, {
    int limit = 50,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }
    try {
      final res = await _client
          .from('lab_connections')
          .select()
          .eq('doctor_id', doctorId)
          .eq('status', 'active')
          .order('requested_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(LabSupabaseMapper.connectionFromRow)
          .whereType<LabConnection>()
          .toList();
      return FirestorePage(items: items, hasMore: items.length == limit);
    } catch (_) {
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  /// One-time fetch for active connections for lab.
  Future<FirestorePage<LabConnection>> fetchActiveConnectionsForLab(
    String labId, {
    int limit = 50,
  }) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }
    try {
      final res = await _client
          .from('lab_connections')
          .select()
          .eq('lab_id', labId)
          .eq('status', 'active')
          .order('requested_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(res as List);
      final items = rows
          .map(LabSupabaseMapper.connectionFromRow)
          .whereType<LabConnection>()
          .toList();
      return FirestorePage(items: items, hasMore: items.length == limit);
    } catch (_) {
      return const FirestorePage(items: [], hasMore: false);
    }
  }

  Future<void> saveConnection(LabConnection connection) async {
    if (!SupabaseBootstrap.isReady) return;
    final row = LabSupabaseMapper.connectionToRow(connection);
    await _client
        .from('lab_connections')
        .upsert(row, onConflict: 'connection_id');
  }

  Future<Set<String>> bookedSlotLabelsForPatientOnDate(
    String patientId,
    DateTime date,
  ) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return {};
    try {
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final res = await _client
          .from('lab_bookings')
          .select('slot_label')
          .eq('patient_id', patientId)
          .gte('date_time', dayStart.toIso8601String())
          .lt('date_time', dayEnd.toIso8601String());
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map((row) => row['slot_label'] as String? ?? '')
          .where((label) => label.isNotEmpty)
          .toSet();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseLab] bookedSlotLabelsForPatientOnDate error: $e');
      }
      return {};
    }
  }
}
