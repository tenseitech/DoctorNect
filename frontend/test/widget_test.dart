import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/splash/splash_screen.dart';
import 'package:medibond/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DoctorNectApp shows design splash on first frame', (
    tester,
  ) async {
    await tester.pumpWidget(const DoctorNectApp());
    await tester.pump();

    expect(find.text('Your Health, Our Priority'), findsNothing);
    expect(find.byKey(SplashScreen.splashLogoKey), findsOneWidget);
  });
}
