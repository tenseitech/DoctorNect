import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('firebase_options does not ship a hardcoded API key fallback', () {
    final source = File('lib/firebase_options.dart').readAsStringSync();

    expect(source, isNot(contains('AIzaSy')));
    expect(source, isNot(contains('_defaultApiKey')));
    expect(source, isNot(contains('defaultValue:')));
    expect(source, contains("String.fromEnvironment('FIREBASE_API_KEY_WEB')"));
    expect(source, contains('_requireConfiguredApiKey'));
  });
}
