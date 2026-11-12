import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/update/minimum_build_gate.dart';

void main() {
  tearDown(() {
    MinimumBuildGate.debugSnapshot = null;
  });

  MinimumBuildSnapshot snapshot({
    bool isWeb = false,
    bool configReadable = true,
    int? installedBuild = 10,
    int? minimumBuild = 0,
    String storeUrl = '',
  }) {
    return MinimumBuildSnapshot(
      isWeb: isWeb,
      configReadable: configReadable,
      installedBuild: installedBuild,
      minimumBuild: minimumBuild,
      storeUrl: storeUrl,
    );
  }

  test('default config never blocks', () {
    expect(MinimumBuildGate.shouldBlock(snapshot()), isFalse);
  });

  test('installed build below the minimum blocks when a store URL is set', () {
    expect(
      MinimumBuildGate.shouldBlock(
        snapshot(installedBuild: 6, minimumBuild: 7, storeUrl: 'https://example.com/app'),
      ),
      isTrue,
    );
  });

  test('installed build equal to or above the minimum does not block', () {
    expect(
      MinimumBuildGate.shouldBlock(
        snapshot(installedBuild: 7, minimumBuild: 7, storeUrl: 'https://example.com/app'),
      ),
      isFalse,
    );
    expect(
      MinimumBuildGate.shouldBlock(
        snapshot(installedBuild: 8, minimumBuild: 7, storeUrl: 'https://example.com/app'),
      ),
      isFalse,
    );
  });

  test('an empty store URL does not block', () {
    expect(
      MinimumBuildGate.shouldBlock(
        snapshot(installedBuild: 1, minimumBuild: 9, storeUrl: '  '),
      ),
      isFalse,
    );
  });

  test('a failed config read does not block', () {
    expect(
      MinimumBuildGate.shouldBlock(
        snapshot(configReadable: false, installedBuild: 1, minimumBuild: 9, storeUrl: 'https://example.com/app'),
      ),
      isFalse,
    );
  });

  test('a malformed minimum does not block', () {
    expect(
      MinimumBuildGate.shouldBlock(
        snapshot(installedBuild: 1, minimumBuild: null, storeUrl: 'https://example.com/app'),
      ),
      isFalse,
    );
  });

  test('web does not block', () {
    expect(
      MinimumBuildGate.shouldBlock(
        snapshot(isWeb: true, installedBuild: 1, minimumBuild: 9, storeUrl: 'https://example.com/app'),
      ),
      isFalse,
    );
  });

  testWidgets('a blocking snapshot replaces the app with the update screen', (tester) async {
    MinimumBuildGate.debugSnapshot = snapshot(
      installedBuild: 1,
      minimumBuild: 9,
      storeUrl: 'https://example.com/app',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: MinimumBuildHost(child: Text('Home')),
      ),
    );
    await tester.pump();
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Update'), findsOneWidget);
  });
}
