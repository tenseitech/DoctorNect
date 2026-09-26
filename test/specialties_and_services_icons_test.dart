import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/patient/home/widgets/explore_section.dart';
import 'package:medibond/features/patient/home/widgets/services_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Specialties & Services Custom Icon Tests', () {
    testWidgets('ServicesSection mobile renders SOS and Records as Image.asset',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: Scaffold(
            body: ServicesSection(onServiceTap: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find Image widgets in ServicesSection
      final imageFinders = find.descendant(
        of: find.byType(ServicesSection),
        matching: find.byType(Image),
      );
      expect(imageFinders, findsNWidgets(3));

      final images = tester
          .widgetList<Image>(imageFinders)
          .map((img) => img.image)
          .toList();

      expect(images,
          contains(const AssetImage('assets/images/services/records.png')));
      expect(
          images, contains(const AssetImage('assets/images/services/sos.png')));
      expect(images,
          contains(const AssetImage('assets/icons/common/digital_pass.png')));
    });

    testWidgets('ServicesSection web renders SOS and Records as Image.asset',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: Scaffold(
            body: ServicesSection(onServiceTap: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final imageFinders = find.descendant(
        of: find.byType(ServicesSection),
        matching: find.byType(Image),
      );
      expect(imageFinders, findsNWidgets(3));

      final images = tester
          .widgetList<Image>(imageFinders)
          .map((img) => img.image)
          .toList();

      expect(images,
          contains(const AssetImage('assets/images/services/records.png')));
      expect(
          images, contains(const AssetImage('assets/images/services/sos.png')));
      expect(images,
          contains(const AssetImage('assets/icons/common/digital_pass.png')));
    });

    testWidgets(
        'ExploreSection web renders Dentist, Diabetes, Homeopathy, and Veterinary with new png asset paths',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExploreSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final imageFinders = find.descendant(
        of: find.byType(ExploreSection),
        matching: find.byType(Image),
      );

      final images = tester
          .widgetList<Image>(imageFinders)
          .map((img) => img.image)
          .toList();

      expect(
        images,
        contains(const AssetImage('assets/images/specialties/dentist.png')),
      );
      expect(
        images,
        contains(const AssetImage('assets/images/specialties/diabetes.png')),
      );
      expect(
        images,
        contains(const AssetImage('assets/images/specialties/homeopathy.png')),
      );
      expect(
        images,
        contains(const AssetImage('assets/images/specialties/veterinary.png')),
      );
    });
  });
}
