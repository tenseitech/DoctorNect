import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/supabase_stream_table.dart';

void main() {
  group('streamTable() Adaptive Polling & Change Detection', () {
    test('emits initial query result immediately on listen', () async {
      final rows = [
        {'id': '1', 'name': 'Dr. Alice', 'status': 'active'}
      ];

      final stream = streamTable(
        table: 'doctors',
        primaryKey: ['id'],
        forcePollingOverride: true,
        customFetcher: () async => rows,
      );

      final emission = await stream.first;
      expect(emission, equals(rows));
    });

    test('suppresses emissions when data is unchanged across polling intervals', () async {
      int fetchCount = 0;
      final emittedBatches = <List<Map<String, dynamic>>>[];

      final stream = streamTable(
        table: 'appointments',
        primaryKey: ['id'],
        forcePollingOverride: true,
        options: const StreamTableOptions(
          standardInterval: Duration(milliseconds: 50),
        ),
        customFetcher: () async {
          fetchCount++;
          // Returns exact same data on every poll
          return [
            {'appointment_id': 'apt_1', 'status': 'confirmed'}
          ];
        },
      );

      final sub = stream.listen((batch) {
        emittedBatches.add(batch);
      });

      // Wait for multiple poll intervals
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await sub.cancel();

      // Fetched multiple times
      expect(fetchCount, greaterThanOrEqualTo(2));
      // But only emitted once because data did not change!
      expect(emittedBatches.length, equals(1));
    });

    test('emits new data when changes are detected during poll', () async {
      int pollIndex = 0;
      final emittedBatches = <List<Map<String, dynamic>>>[];

      final stream = streamTable(
        table: 'ambulance_requests',
        primaryKey: ['id'],
        forcePollingOverride: true,
        isHighFrequency: true,
        options: const StreamTableOptions(
          highFrequencyInterval: Duration(milliseconds: 50),
        ),
        customFetcher: () async {
          pollIndex++;
          if (pollIndex == 1) {
            return [
              {'id': 'amb_1', 'status': 'searching'}
            ];
          } else {
            return [
              {'id': 'amb_1', 'status': 'assigned', 'driver_id': 'drv_99'}
            ];
          }
        },
      );

      final sub = stream.listen((batch) {
        emittedBatches.add(batch);
      });

      // Wait for second poll
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await sub.cancel();

      expect(emittedBatches.length, equals(2));
      expect(emittedBatches[0][0]['status'], equals('searching'));
      expect(emittedBatches[1][0]['status'], equals('assigned'));
    });

    test('responds immediately to pushTrigger before next scheduled poll', () async {
      final pushController = StreamController<void>.broadcast();
      int fetchCount = 0;
      final emittedBatches = <List<Map<String, dynamic>>>[];

      final stream = streamTable(
        table: 'prescriptions',
        primaryKey: ['id'],
        forcePollingOverride: true,
        pushTrigger: pushController.stream,
        options: const StreamTableOptions(
          standardInterval: Duration(seconds: 60), // long interval
        ),
        customFetcher: () async {
          fetchCount++;
          return [
            {'id': 'rx_1', 'version': fetchCount}
          ];
        },
      );

      final sub = stream.listen((batch) {
        emittedBatches.add(batch);
      });

      // Allow initial fetch
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emittedBatches.length, equals(1));
      expect(emittedBatches[0][0]['version'], equals(1));

      // Trigger push event
      pushController.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emittedBatches.length, equals(2));
      expect(emittedBatches[1][0]['version'], equals(2));

      await sub.cancel();
      await pushController.close();
    });

    test('surfaces errors to stream subscriber without terminating controller', () async {
      final errors = <Object>[];

      final stream = streamTable(
        table: 'health_records',
        primaryKey: ['id'],
        forcePollingOverride: true,
        customFetcher: () async {
          throw Exception('Database query timeout');
        },
      );

      final sub = stream.listen(
        (_) {},
        onError: (e) {
          errors.add(e);
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(errors.length, equals(1));
      expect(errors.first.toString(), contains('Database query timeout'));
    });
  });
}
