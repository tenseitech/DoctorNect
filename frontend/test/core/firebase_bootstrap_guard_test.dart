import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:path/path.dart' as p;

void main() {
  test('only firebase_bootstrap.dart may call Firebase.initializeApp', () {
    final libDir = Directory(p.join(Directory.current.path, 'lib'));
    expect(libDir.existsSync(), isTrue, reason: 'run from frontend/ package root');

    const needle = 'Firebase.initializeApp';
    final allowed =
        p.normalize(p.join('lib', 'core', 'firebase', 'firebase_bootstrap.dart'));
    final violations = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = p.normalize(p.relative(entity.path, from: Directory.current.path));
      final content = entity.readAsStringSync();
      if (!content.contains(needle)) continue;
      if (relative == allowed) continue;
      violations.add(relative);
    }

    expect(
      violations,
      isEmpty,
      reason: 'Call FirebaseBootstrap.initialize() instead of:\n${violations.join('\n')}',
    );
  });

  test('FirebaseBootstrap.initialize twice concurrently does not throw', () async {
    FirebaseBootstrap.resetForTesting();
    final results = await Future.wait([
      FirebaseBootstrap.initialize(),
      FirebaseBootstrap.initialize(),
      FirebaseBootstrap.initialize(),
    ]);
    expect(results.length, 3);
    for (final ok in results) {
      expect(ok, isA<bool>());
    }
  });

  test('FirebaseBootstrap.initialize twice sequentially does not throw', () async {
    FirebaseBootstrap.resetForTesting();
    final first = await FirebaseBootstrap.initialize();
    final second = await FirebaseBootstrap.initialize();
    expect(first, isA<bool>());
    expect(second, isA<bool>());
    if (first && second) {
      expect(FirebaseBootstrap.isReady, isTrue);
    }
  });
}
