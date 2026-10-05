import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/utils/asset_resolver.dart';
import 'package:medibond/core/utils/asset_webp_manifest.dart';

void main() {
  group('AssetResolver', () {
    test('kWebpAssets manifest contains expected converted assets', () {
      expect(
        kWebpAssets,
        contains('assets/icons/doctor/appointment.webp'),
      );
      expect(
        kWebpAssets,
        contains('assets/icons/common/digital_pass.webp'),
      );
      expect(
        kWebpAssets,
        contains('assets/images/services/records.webp'),
      );
      expect(
        kWebpAssets,
        contains('assets/images/services/sos.webp'),
      );
      expect(
        kWebpAssets,
        contains('assets/images/specialties/dentist.webp'),
      );
      expect(
        kWebpAssets,
        contains('assets/images/doctor_illustration.webp'),
      );
    });

    group('resolveFor (isWeb: false - Mobile/Desktop)', () {
      test('preserves original PNG paths intact', () {
        expect(
          AssetResolver.resolveFor(
            'assets/icons/doctor/appointment.png',
            isWeb: false,
          ),
          equals('assets/icons/doctor/appointment.png'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/icons/doctor/today_queue.png',
            isWeb: false,
          ),
          equals('assets/icons/doctor/today_queue.png'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/images/services/sos.png',
            isWeb: false,
          ),
          equals('assets/images/services/sos.png'),
        );
      });

      test('preserves original JPG paths intact', () {
        expect(
          AssetResolver.resolveFor(
            'assets/images/doctor_illustration.jpg',
            isWeb: false,
          ),
          equals('assets/images/doctor_illustration.jpg'),
        );
      });

      test('preserves unknown or non-image paths', () {
        expect(
          AssetResolver.resolveFor('unknown/path/test.png', isWeb: false),
          equals('unknown/path/test.png'),
        );
        expect(
          AssetResolver.resolveFor('data/file.txt', isWeb: false),
          equals('data/file.txt'),
        );
      });
    });

    group('resolveFor (isWeb: true - Website)', () {
      test('swaps extension to .webp for assets registered in kWebpAssets', () {
        expect(
          AssetResolver.resolveFor(
            'assets/icons/doctor/appointment.png',
            isWeb: true,
          ),
          equals('assets/icons/doctor/appointment.webp'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/icons/doctor/today_queue.png',
            isWeb: true,
          ),
          equals('assets/icons/doctor/today_queue.webp'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/images/services/records.png',
            isWeb: true,
          ),
          equals('assets/images/services/records.webp'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/images/services/sos.png',
            isWeb: true,
          ),
          equals('assets/images/services/sos.webp'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/images/specialties/dentist.png',
            isWeb: true,
          ),
          equals('assets/images/specialties/dentist.webp'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/images/doctor_illustration.jpg',
            isWeb: true,
          ),
          equals('assets/images/doctor_illustration.webp'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/images/intro_slide_1.png',
            isWeb: true,
          ),
          equals('assets/images/intro_slide_1.webp'),
        );
        expect(
          AssetResolver.resolveFor(
            'assets/images/stomach_digestion_icon.png',
            isWeb: true,
          ),
          equals('assets/images/stomach_digestion_icon.webp'),
        );
      });

      test('returns original path for assets not in kWebpAssets', () {
        expect(
          AssetResolver.resolveFor(
            'assets/icons/doctor/non_existent.png',
            isWeb: true,
          ),
          equals('assets/icons/doctor/non_existent.png'),
        );
        expect(
          AssetResolver.resolveFor('data/diagnoses.txt', isWeb: true),
          equals('data/diagnoses.txt'),
        );
        expect(
          AssetResolver.resolveFor('no_extension_path', isWeb: true),
          equals('no_extension_path'),
        );
      });

      test('returns already-webp path if it exists in manifest', () {
        expect(
          AssetResolver.resolveFor(
            'assets/images/specialties/dentist.webp',
            isWeb: true,
          ),
          equals('assets/images/specialties/dentist.webp'),
        );
      });
    });

    group('resolve (runtime environment)', () {
      test('returns original path in unit test environment (kIsWeb == false)',
          () {
        expect(
          AssetResolver.resolve('assets/icons/doctor/appointment.png'),
          equals('assets/icons/doctor/appointment.png'),
        );
      });
    });
  });
}
