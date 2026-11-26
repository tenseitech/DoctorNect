import 'dart:async';

import 'package:medibond/core/supabase/supabase_watcher_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resync coalesces overlapping fetches into one follow-up', () async {
  var fetchCount = 0;
  final gate = Completer<void>();

  final machine = SupabaseWatcherStateMachine<Map<String, String>>(
    fetcher: () async {
      fetchCount++;
      await gate.future;
      return [
        {'id': 'a', 'v': '$fetchCount'},
      ];
    },
    getId: (item) => item['id']!,
  );

  final first = machine.resync();
  await Future<void>.delayed(Duration.zero);
  expect(machine.resyncInFlightForTesting, isTrue);

  final second = machine.resync();
  final third = machine.resync();

  gate.complete();
  await Future.wait([first, second, third]);

  expect(fetchCount, 2, reason: 'Second wave of resync should run once after first completes');
  machine.dispose();
  });

  test('slow polls do not stack unbounded concurrent fetches', () async {
  var inFlight = 0;
  var maxInFlight = 0;

  final machine = SupabaseWatcherStateMachine<String>(
    pollingInterval: const Duration(milliseconds: 5),
    fetcher: () async {
      inFlight++;
      maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      inFlight--;
      return ['x'];
    },
    getId: (item) => item,
  );

  final sub = machine.stream().listen((_) {});
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await sub.cancel();
  machine.dispose();

  expect(maxInFlight, lessThanOrEqualTo(1));
  });
}