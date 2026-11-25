import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/features/splash/splash_design.dart';
import 'package:medibond/features/splash/splash_screen.dart';

Future<void> _pumpSplashDesign(
  WidgetTester tester, {
  required Size logicalSize,
  double devicePixelRatio = 1.0,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(
    logicalSize.width * devicePixelRatio,
    logicalSize.height * devicePixelRatio,
  );
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: const Scaffold(
        backgroundColor: SplashDesign.background,
        body: SplashDesignView(logoKey: SplashScreen.splashLogoKey),
      ),
    ),
  );
  await tester.pump();
}

String _pubspecSplashBlock() {
  final src = File('pubspec.yaml').readAsStringSync().replaceAll('\r\n', '\n');
  final start = src.indexOf('flutter_native_splash:\n');
  final end = src.indexOf('\nflutter:\n', start);
  return src.substring(start, end);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    testWidgets('splash is solid brand blue with a centred 134dp mark ($brightness)',
        (tester) async {
      await _pumpSplashDesign(
        tester,
        logicalSize: const Size(412, 915),
        devicePixelRatio: 2.625,
        brightness: brightness,
      );

      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(SplashDesignView),
          matching: find.byType(ColoredBox),
        ).first,
      );
      expect(box.color, AppColors.doctorBlue);

      final rect = tester.getRect(find.byKey(SplashScreen.splashLogoKey));
      expect(rect.width, closeTo(SplashDesign.logoWidthDp, 0.01));
      expect(rect.center.dx, closeTo(412 / 2, 0.5));
      expect(rect.center.dy, closeTo(915 / 2, 0.5));
    });
  }

  for (final size in const [Size(1080, 2400), Size(720, 1280), Size(320, 480)]) {
    testWidgets('SplashDesign no overflow at ${size.width}×${size.height}',
        (tester) async {
      await _pumpSplashDesign(tester, logicalSize: size);
      expect(tester.takeException(), isNull);
    });
  }

  test('native splash config matches the Flutter splash (colour, light + dark)', () {
    final block = _pubspecSplashBlock();
    final hex = AppColors.doctorBlue
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    expect(RegExp('color: "#$hex"').allMatches(block).length, 2,
        reason: 'pre-12 and Android 12 light colours');
    expect(RegExp('color_dark: "#$hex"').allMatches(block).length, 2,
        reason: 'pre-12 and Android 12 dark colours');
    expect(block, isNot(contains('icon_background_color')),
        reason: 'icon background switches Android 12 to the 160dp mask');
    expect(block, isNot(contains('background_image')));
  });

  test('Android 12+/15+ splash styles use brand blue and no icon background', () {
    for (final dir in ['values-v31', 'values-night-v31', 'values-v35', 'values-night-v35']) {
      final xml = File('android/app/src/main/res/$dir/styles.xml').readAsStringSync();
      expect(xml, contains('windowSplashScreenBackground">#1D4ED8<'), reason: dir);
      expect(xml, isNot(contains('windowSplashScreenIconBackgroundColor')), reason: dir);
    }
  });

  test('splash images are square 1152 px masters and the mark asset exists', () {
    for (final p in ['assets/splash/splash_logo.png', 'assets/splash/splash_android12.png']) {
      final bytes = File(p).readAsBytesSync();
      // PNG IHDR width/height (big endian) at bytes 16..23.
      int u32(int o) => (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
      expect(u32(16), 1152, reason: p);
      expect(u32(20), 1152, reason: p);
    }
    expect(File(SplashDesign.logoAssetPath).existsSync(), isTrue);
  });
}
