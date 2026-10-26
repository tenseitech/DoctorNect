import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'supabase_bootstrap.dart';

/// StreamTable configuration options for adaptive polling.
class StreamTableOptions {
  const StreamTableOptions({
    this.highFrequencyInterval = const Duration(seconds: 3),
    this.standardInterval = const Duration(seconds: 8),
  });

  final Duration highFrequencyInterval;
  final Duration standardInterval;
}

/// Adaptive polling replacement for Supabase Realtime `.stream()`.
///
/// In Staging (`APP_ENV=staging`):
/// Delegates to native Supabase Realtime `.stream()` WebSocket.
///
/// In Production (`APP_ENV=production`):
/// Uses adaptive polling with change detection (no Realtime WebSocket needed):
/// - Emits current state immediately.
/// - Polls at adaptive frequency (~3s for high-frequency active trips, ~8s standard).
/// - Skips emissions if snapshot is unchanged to prevent redundant widget rebuilds.
/// - Responds immediately when an external push trigger (e.g. FCM message) fires.
/// Test-only hook to supply table rows without a network connection.
Future<List<Map<String, dynamic>>> Function(String table)? _debugTableFetcher;

@visibleForTesting
Future<List<Map<String, dynamic>>> Function(String table)? get debugTableFetcher =>
    _debugTableFetcher;

@visibleForTesting
set debugTableFetcher(
  Future<List<Map<String, dynamic>>> Function(String table)? value,
) {
  if (kReleaseMode && value != null) {
    throw UnsupportedError('debugTableFetcher cannot be set in release mode.');
  }
  _debugTableFetcher = value;
}

Stream<List<Map<String, dynamic>>> streamTable({
  required String table,
  required List<String> primaryKey,
  String? filterColumn,
  dynamic filterValue,
  Map<String, dynamic>? additionalFilters,
  bool isHighFrequency = false,
  Stream<void>? pushTrigger,
  StreamTableOptions options = const StreamTableOptions(),
  Future<List<Map<String, dynamic>>> Function()? customFetcher,
  @visibleForTesting bool? forcePollingOverride,
}) {
  final usePolling = forcePollingOverride ?? SupabaseBootstrap.isProduction;

  // Staging Mode: Use native Supabase Realtime stream
  if (!usePolling && customFetcher == null && SupabaseBootstrap.isReady) {
    var stream = SupabaseBootstrap.client
        .from(table)
        .stream(primaryKey: primaryKey);

    if (filterColumn != null && filterValue != null) {
      stream = stream.eq(filterColumn, filterValue);
    }
    return stream;
  }

  // Production Mode: Adaptive Polling with Change Detection
  late final StreamController<List<Map<String, dynamic>>> controller;
  Timer? pollTimer;
  StreamSubscription<void>? pushSub;
  String? previousHash;
  bool isFetching = false;
  bool isClosed = false;

  Future<void> fetchAndEmit() async {
    if (isFetching || isClosed) return;
    isFetching = true;

    try {
      List<Map<String, dynamic>> rows;

      if (customFetcher != null) {
        rows = await customFetcher();
      } else if (!kReleaseMode && _debugTableFetcher != null) {
        rows = await _debugTableFetcher!(table);
      } else if (SupabaseBootstrap.isReady) {
        var query = SupabaseBootstrap.client.from(table).select();

        if (filterColumn != null && filterValue != null) {
          query = query.eq(filterColumn, filterValue);
        }

        if (additionalFilters != null) {
          for (final entry in additionalFilters.entries) {
            query = query.eq(entry.key, entry.value);
          }
        }

        final response = await query;
        rows = (response as List).cast<Map<String, dynamic>>();
      } else {
        rows = <Map<String, dynamic>>[];
      }

      if (isClosed) return;

      // Deep change detection via deterministic JSON serialization
      final currentHash = jsonEncode(rows);
      if (previousHash == null || previousHash != currentHash) {
        previousHash = currentHash;
        if (!controller.isClosed) {
          controller.add(rows);
        }
      }
    } catch (e, st) {
      if (!isClosed && !controller.isClosed) {
        controller.addError(e, st);
      }
    } finally {
      isFetching = false;
    }
  }

  void startPolling() {
    final interval = isHighFrequency
        ? options.highFrequencyInterval
        : options.standardInterval;

    // Initial immediate fetch
    fetchAndEmit();

    // Setup periodic polling
    pollTimer = Timer.periodic(interval, (_) => fetchAndEmit());

    // Setup push trigger listener (e.g. FCM message)
    if (pushTrigger != null) {
      pushSub = pushTrigger.listen((_) => fetchAndEmit());
    }
  }

  void stopPolling() {
    isClosed = true;
    pollTimer?.cancel();
    pollTimer = null;
    pushSub?.cancel();
    pushSub = null;
  }

  controller = StreamController<List<Map<String, dynamic>>>.broadcast(
    onListen: startPolling,
    onCancel: stopPolling,
  );

  return controller.stream;
}
