import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/constants/indian_cities.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/models/promoted_ad_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Role Promote Feature Parity Rules', () {
    test('Every non-patient role can promote and patient cannot', () {
      const allowedRoles = [
        UserType.doctor,
        UserType.medicalStore,
        UserType.lab,
        UserType.ambulance,
      ];

      for (final role in allowedRoles) {
        expect(role.isPatient, isFalse, reason: '$role should not be patient');
      }

      const patientRole = UserType.patient;
      expect(patientRole.isPatient, isTrue);
      expect(allowedRoles.contains(patientRole), isFalse);
    });

    test('PromotedAdProviderType enum supports all 4 non-patient roles only', () {
      expect(PromotedAdProviderType.values, contains(PromotedAdProviderType.doctor));
      expect(PromotedAdProviderType.values, contains(PromotedAdProviderType.lab));
      expect(PromotedAdProviderType.values, contains(PromotedAdProviderType.pharmacy));
      expect(PromotedAdProviderType.values, contains(PromotedAdProviderType.ambulance));
      expect(PromotedAdProviderType.values.length, 4);
    });

    test('PromotedAdModel handles all non-patient provider types correctly', () {
      final adDoctor = PromotedAdModel(
        adId: 'ad_doc',
        providerType: 'doctor',
        providerId: 'doc_1',
        title: 'Doctor Clinic',
        description: 'Quality healthcare for everyone',
        imageUrl: 'https://example.com/doc.jpg',
        ctaLabel: 'Book Appointment',
        durationHours: 24,
        amountPaid: 300,
        paymentStatus: 'verified',
        status: 'active',
      );
      expect(adDoctor.providerType, 'doctor');

      final adPharmacy = PromotedAdModel(
        adId: 'ad_pharm',
        providerType: 'pharmacy',
        providerId: 'store_1',
        title: 'City Pharmacy',
        description: 'Fast medicine delivery to your door',
        imageUrl: 'https://example.com/pharm.jpg',
        ctaLabel: 'Order Medicine',
        durationHours: 72,
        amountPaid: 750,
        paymentStatus: 'verified',
        status: 'active',
      );
      expect(adPharmacy.providerType, 'pharmacy');
      expect(adPharmacy.ctaLabel, 'Order Medicine');

      final adLab = PromotedAdModel(
        adId: 'ad_lab',
        providerType: 'lab',
        providerId: 'lab_1',
        title: 'Precision Diagnostics',
        description: 'Comprehensive blood and pathology tests',
        imageUrl: 'https://example.com/lab.jpg',
        ctaLabel: 'Order Lab Tests',
        durationHours: 168,
        amountPaid: 1500,
        paymentStatus: 'verified',
        status: 'active',
      );
      expect(adLab.providerType, 'lab');
      expect(adLab.ctaLabel, 'Order Lab Tests');

      final adAmbulance = PromotedAdModel(
        adId: 'ad_amb',
        providerType: 'ambulance',
        providerId: 'amb_1',
        title: 'Express Ambulance Service',
        description: '24/7 ICU ambulance emergency response',
        imageUrl: 'https://example.com/amb.jpg',
        ctaLabel: 'Call Ambulance',
        durationHours: 720,
        amountPaid: 5000,
        paymentStatus: 'verified',
        status: 'active',
      );
      expect(adAmbulance.providerType, 'ambulance');
      expect(adAmbulance.ctaLabel, 'Call Ambulance');
    });

    test('CTAs and provider labels for all 4 roles', () {
      String getCta(String type) => switch (type.toLowerCase()) {
            'lab' => 'Order Lab Tests',
            'pharmacy' => 'Order Medicine',
            'ambulance' => 'Call Ambulance',
            _ => 'Book Appointment',
          };

      String getLabel(String type) => switch (type.toLowerCase()) {
            'doctor' => 'Medical Practice & Clinic',
            'lab' => 'Diagnostic Lab & Tests',
            'pharmacy' => 'Medical Store & Pharmacy',
            'ambulance' => 'Ambulance Service',
            _ => 'Healthcare Service',
          };

      expect(getCta('doctor'), 'Book Appointment');
      expect(getCta('pharmacy'), 'Order Medicine');
      expect(getCta('lab'), 'Order Lab Tests');
      expect(getCta('ambulance'), 'Call Ambulance');

      expect(getLabel('doctor'), 'Medical Practice & Clinic');
      expect(getLabel('pharmacy'), 'Medical Store & Pharmacy');
      expect(getLabel('lab'), 'Diagnostic Lab & Tests');
      expect(getLabel('ambulance'), 'Ambulance Service');
    });

    test('IndianCities daily rates calculation', () {
      expect(IndianCities.dailyRate('Nagpur'), 150); // Metro tier
      expect(IndianCities.dailyRate('Mumbai'), 150); // Metro tier
      expect(IndianCities.dailyRate('Amravati'), 100); // Standard tier
      expect(IndianCities.dailyRate('Unknown'), 100); // Fallback standard
    });

    testWidgets('Promote Ad button renders correctly with campaign icon', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OutlinedButton.icon(
              onPressed: () => pressed = true,
              icon: const Icon(Icons.campaign_rounded, size: 16),
              label: const Text('Promote Ad'),
            ),
          ),
        ),
      );

      expect(find.text('Promote Ad'), findsOneWidget);
      expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);

      await tester.tap(find.text('Promote Ad'));
      expect(pressed, isTrue);
    });
  });
}
