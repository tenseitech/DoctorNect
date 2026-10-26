import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/core/supabase/supabase_stream_table.dart';
import 'package:medibond/core/supabase/supabase_watcher_state_machine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Supabase Realtime Production Bypass Suite', () {
    setUp(() {
      SupabaseBootstrap.debugAppEnvOverride = 'production';
    });

    tearDown(() {
      SupabaseBootstrap.debugAppEnvOverride = null;
    });

    test('isProduction is true when debugAppEnvOverride is production', () {
      expect(SupabaseBootstrap.isProduction, isTrue);
    });

    test('streamTable produces valid stream via adaptive polling without Realtime socket', () async {
      int queryCount = 0;
      final stream = streamTable(
        table: 'users',
        primaryKey: ['id'],
        forcePollingOverride: true,
        options: const StreamTableOptions(
          standardInterval: Duration(milliseconds: 100),
        ),
        customFetcher: () async {
          queryCount++;
          return [
            {'id': 'u1', 'name': 'Alice'},
          ];
        },
      );

      final events = <List<Map<String, dynamic>>>[];
      final sub = stream.listen((data) {
        events.add(data);
      });

      // Wait for initial fetch and at least one poll tick
      await Future.delayed(const Duration(milliseconds: 250));
      await sub.cancel();

      expect(queryCount, greaterThanOrEqualTo(1));
      expect(events.isNotEmpty, isTrue);
      expect(events.first.first['name'], equals('Alice'));
    });

    test('SupabaseWatcherStateMachine operates in polling mode when isProduction is true', () async {
      expect(SupabaseBootstrap.isProduction, isTrue);

      int pollCount = 0;
      final watcher = SupabaseWatcherStateMachine<Map<String, dynamic>>(
        fetcher: () async {
          pollCount++;
          return [
            {'id': 'item_$pollCount', 'val': pollCount},
          ];
        },
        getId: (item) => item['id'] as String,
        pollingInterval: const Duration(milliseconds: 80),
      );

      final results = <List<Map<String, dynamic>>>[];
      final sub = watcher.stream().listen((val) {
        results.add(val);
      });

      await Future.delayed(const Duration(milliseconds: 220));
      await sub.cancel();
      watcher.dispose();

      expect(pollCount, greaterThanOrEqualTo(1));
      expect(results.isNotEmpty, isTrue);
    });
  });
}
