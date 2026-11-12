import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/splash/splash_design.dart';
import 'package:medibond/features/splash/splash_screen.dart';

Future<void> _pumpSplashDesign(
  WidgetTester tester, {
  required Size logicalSize,
  double devicePixelRatio = 1.0,
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
    const MaterialApp(
      home: Scaffold(
        body: SplashDesignView(logoKey: SplashScreen.splashLogoKey),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SplashDesign matches SVG at 1242×2208 (dpr 1)', (tester) async {
    await _pumpSplashDesign(
      tester,
      logicalSize: const Size(
        SplashDesign.designCanvasWidth,
        SplashDesign.designCanvasHeight,
      ),
    );

    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(SplashDesignView),
        matching: find.byType(DecoratedBox),
      ),
    );
    final gradient = decorated.decoration as BoxDecoration;
    final lg = gradient.gradient! as LinearGradient;
    expect(lg.begin, SplashDesign.gradientBegin);
    expect(lg.end, SplashDesign.gradientEnd);
    expect(lg.stops, SplashDesign.gradientStops);
    expect(lg.colors, SplashDesign.gradientColors);

    final rect = tester.getRect(find.byKey(SplashScreen.splashLogoKey));
    expect(rect.left, closeTo(SplashDesign.designLogoLeft, 1));
    expect(rect.top, closeTo(SplashDesign.designLogoTop, 1));
    expect(rect.width, closeTo(SplashDesign.designLogoWidth, 1));
    expect(rect.height, closeTo(SplashDesign.designLogoHeight, 1));
  });

  for (final size in const [
    Size(1080, 2400),
    Size(720, 1280),
  ]) {
    testWidgets('SplashDesign no overflow at ${size.width}×${size.height}',
        (tester) async {
      await _pumpSplashDesign(tester, logicalSize: size);
      expect(tester.takeException(), isNull);
      expect(find.byType(OverflowBar), findsNothing);
    });
  }
}
