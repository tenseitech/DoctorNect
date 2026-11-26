import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tables the app must not query: they were dropped from the Postgres schema (and the gateway
/// would refuse them). Keeps PROJECT_ANALYSIS.md M4 / L3 fixed.
const _dropped = ['lab_catalog', 'medicine_suggestions'];

void main() {
  test('no client code queries a dropped table', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final t in _dropped) {
        if (RegExp(r'''\.from\(\s*['"]''' + t + r'''['"]''').hasMatch(src)) {
          hits.add('${f.path}: $t');
        }
      }
    }
    expect(hits, isEmpty);
  });
}
