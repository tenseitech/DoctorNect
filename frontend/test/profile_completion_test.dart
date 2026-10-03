import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/profile_completion_checker.dart';
import 'package:medibond/core/auth/verification_lifecycle.dart';
import 'package:medibond/core/auth/demo_auth_config.dart';
import 'package:medibond/core/enums/user_type.dart';

void main() {
  group('VerificationRequirementItem model integrity', () {
    test('all requirement items have non-empty key, label, and section', () {
      final roles = [
        UserType.doctor,
        UserType.medicalStore,
        UserType.lab,
        UserType.ambulance,
      ];

      for (final role in roles) {
        final items = VerificationRequirementsConfig.requirementsForRole(role);
        expect(items, isNotEmpty,
            reason: 'Role $role should have requirements');
        for (final item in items) {
          expect(item.key.trim(), isNotEmpty);
          expect(item.label.trim(), isNotEmpty);
          expect(item.section.trim(), isNotEmpty);
        }
      }
    });

    test('Doctor document items have isDocument set to true', () {
      final items = VerificationRequirementsConfig.requirementsForRole(
        UserType.doctor,
      );
      final cert = items.firstWhere((i) => i.key == 'registrationCertificate');
      final idProof = items.firstWhere((i) => i.key == 'idProof');
      expect(cert.isDocument, isTrue);
      expect(idProof.isDocument, isTrue);
    });
  });

  group('Doctor profile completeness', () {
    final fullDoctorData = <String, dynamic>{
      'name': 'Dr. Aditi Verma',
      'mobile': '9876543210',
      'qualification': 'MBBS, MD (Medicine)',
      'specialization': 'General Physician',
      'councilNumber': 'DMC-2024-5544',
      'stateCouncil': 'Delhi Medical Council',
      'registrationCertificate': 'https://storage.provider/cert.pdf',
      'idProof': 'https://storage.provider/id.pdf',
      'country': 'India',
      'state': 'Delhi',
      'city': 'New Delhi',
      'addressLine1': '101 Health Park Avenue',
      'pinCode': '110001',
    };

    test('empty data -> 0% and all fields missing', () {
      final empty = <String, dynamic>{};
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.doctor,
        empty,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.doctor,
        empty,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.doctor,
        empty,
      );
      final reqs = VerificationRequirementsConfig.requirementsForRole(
        UserType.doctor,
      );

      expect(percentage, 0);
      expect(isComplete, isFalse);
      expect(missing.length, reqs.length);
      expect(missing.map((e) => e.key).toSet(), reqs.map((e) => e.key).toSet());
      expect(ProfileCompletionChecker.isDoctorDocComplete(empty), isFalse);
    });

    test('fully filled data -> 100% and isComplete true', () {
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.doctor,
        fullDoctorData,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.doctor,
        fullDoctorData,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.doctor,
        fullDoctorData,
      );

      expect(percentage, 100);
      expect(isComplete, isTrue);
      expect(missing, isEmpty);
      expect(
        ProfileCompletionChecker.isDoctorDocComplete(fullDoctorData),
        isTrue,
      );
    });

    test(
        'fully filled data with nested address map -> 100% and isComplete true',
        () {
      final nestedData = <String, dynamic>{
        'name': 'Dr. Aditi Verma',
        'mobile': '9876543210',
        'qualification': 'MBBS, MD (Medicine)',
        'specialization': 'General Physician',
        'councilNumber': 'DMC-2024-5544',
        'stateCouncil': 'Delhi Medical Council',
        'registrationCertificate': 'https://storage.provider/cert.pdf',
        'idProof': 'https://storage.provider/id.pdf',
        'address': {
          'country': 'India',
          'state': 'Delhi',
          'city': 'New Delhi',
          'addressLine1': '101 Health Park Avenue',
          'pinCode': '110001',
        },
      };

      expect(
        VerificationRequirementsConfig.completionPercentage(
          UserType.doctor,
          nestedData,
        ),
        100,
      );
      expect(
        VerificationRequirementsConfig.isComplete(
          UserType.doctor,
          nestedData,
        ),
        isTrue,
      );
      expect(
        VerificationRequirementsConfig.missingFields(
          UserType.doctor,
          nestedData,
        ),
        isEmpty,
      );
      expect(
        ProfileCompletionChecker.isDoctorDocComplete(nestedData),
        isTrue,
      );
    });

    test('one field missing -> correct missingFields and isComplete false', () {
      final copy = Map<String, dynamic>.from(fullDoctorData)
        ..remove('specialization');
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.doctor,
        copy,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.doctor,
        copy,
      );
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.doctor,
        copy,
      );

      expect(isComplete, isFalse);
      expect(missing.length, 1);
      expect(missing.first.key, 'specialization');
      expect(missing.first.section, 'Professional Details');
      expect(percentage, lessThan(100));
      expect(ProfileCompletionChecker.isDoctorDocComplete(copy), isFalse);
    });

    test('missing upload document -> correct missingFields', () {
      final copy = Map<String, dynamic>.from(fullDoctorData)
        ..remove('registrationCertificate');
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.doctor,
        copy,
      );

      expect(missing.length, 1);
      expect(missing.first.key, 'registrationCertificate');
      expect(missing.first.isDocument, isTrue);
      expect(
        VerificationRequirementsConfig.isComplete(UserType.doctor, copy),
        isFalse,
      );
    });

    test(
        'non-required fields (dateOfBirth, gender, languages, email) do not block completion',
        () {
      // fullDoctorData does not contain dateOfBirth, gender, languages, or email
      expect(fullDoctorData.containsKey('dateOfBirth'), isFalse);
      expect(fullDoctorData.containsKey('gender'), isFalse);
      expect(fullDoctorData.containsKey('languages'), isFalse);
      expect(fullDoctorData.containsKey('email'), isFalse);

      expect(
        VerificationRequirementsConfig.isComplete(
          UserType.doctor,
          fullDoctorData,
        ),
        isTrue,
      );
      expect(
        VerificationRequirementsConfig.completionPercentage(
          UserType.doctor,
          fullDoctorData,
        ),
        100,
      );
    });

    test('demo doctor phone always evaluates to 100% and complete', () {
      final demoData = <String, dynamic>{
        'mobile': DemoAuthConfig.demoDoctorPhone,
      };

      expect(
        VerificationRequirementsConfig.isComplete(
          UserType.doctor,
          demoData,
        ),
        isTrue,
      );
      expect(
        VerificationRequirementsConfig.completionPercentage(
          UserType.doctor,
          demoData,
        ),
        100,
      );
      expect(
        VerificationRequirementsConfig.missingFields(
          UserType.doctor,
          demoData,
        ),
        isEmpty,
      );
      expect(
        ProfileCompletionChecker.isDoctorDocComplete(demoData),
        isTrue,
      );
    });
  });

  group('Pharmacy (Medical Store) profile completeness', () {
    final fullPharmacyData = <String, dynamic>{
      'storeName': 'MedPlus Care Chemist',
      'ownerName': 'Suresh Gupta',
      'phone': '9812345678',
      'drugLicenseNumber': 'DL-2026-MED-8899',
      'country': 'India',
      'state': 'Maharashtra',
      'city': 'Mumbai',
      'addressLine1': 'Shop 4, Linking Road, Bandra West',
      'pincode': '400050',
    };

    test('empty data -> 0% and all fields missing', () {
      final empty = <String, dynamic>{};
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.medicalStore,
        empty,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.medicalStore,
        empty,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.medicalStore,
        empty,
      );
      final reqs = VerificationRequirementsConfig.requirementsForRole(
        UserType.medicalStore,
      );

      expect(percentage, 0);
      expect(isComplete, isFalse);
      expect(missing.length, reqs.length);
      expect(missing.map((e) => e.key).toSet(), reqs.map((e) => e.key).toSet());
      expect(ProfileCompletionChecker.isPharmacyDocComplete(empty), isFalse);
    });

    test('fully filled data -> 100% and isComplete true', () {
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.medicalStore,
        fullPharmacyData,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.medicalStore,
        fullPharmacyData,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.medicalStore,
        fullPharmacyData,
      );

      expect(percentage, 100);
      expect(isComplete, isTrue);
      expect(missing, isEmpty);
      expect(
        ProfileCompletionChecker.isPharmacyDocComplete(fullPharmacyData),
        isTrue,
      );
    });

    test('one field missing -> correct missingFields and isComplete false', () {
      final copy = Map<String, dynamic>.from(fullPharmacyData)
        ..remove('drugLicenseNumber');
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.medicalStore,
        copy,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.medicalStore,
        copy,
      );

      expect(isComplete, isFalse);
      expect(missing.length, 1);
      expect(missing.first.key, 'drugLicenseNumber');
      expect(missing.first.section, 'Store Details');
      expect(
        VerificationRequirementsConfig.completionPercentage(
          UserType.medicalStore,
          copy,
        ),
        lessThan(100),
      );
      expect(ProfileCompletionChecker.isPharmacyDocComplete(copy), isFalse);
    });

    test('address subfields nested inside address map work properly', () {
      final nestedData = <String, dynamic>{
        'storeName': 'MedPlus Care Chemist',
        'ownerName': 'Suresh Gupta',
        'phone': '9812345678',
        'drugLicenseNumber': 'DL-2026-MED-8899',
        'address': {
          'country': 'India',
          'state': 'Maharashtra',
          'city': 'Mumbai',
          'addressLine1': 'Shop 4, Linking Road, Bandra West',
          'pincode': '400050',
        },
      };

      expect(
        VerificationRequirementsConfig.isComplete(
          UserType.medicalStore,
          nestedData,
        ),
        isTrue,
      );
      expect(
        VerificationRequirementsConfig.completionPercentage(
          UserType.medicalStore,
          nestedData,
        ),
        100,
      );
      expect(
        VerificationRequirementsConfig.missingFields(
          UserType.medicalStore,
          nestedData,
        ),
        isEmpty,
      );
    });

    test('email is not required for Pharmacy completeness', () {
      expect(fullPharmacyData.containsKey('email'), isFalse);
      expect(
        VerificationRequirementsConfig.isComplete(
          UserType.medicalStore,
          fullPharmacyData,
        ),
        isTrue,
      );
    });
  });

  group('Diagnostic Lab profile completeness', () {
    final fullLabData = <String, dynamic>{
      'labName': 'Metropolis Clinical Labs',
      'phone': '9822334455',
      'licenseNumber': 'NABL-LAB-2026-778',
      'country': 'India',
      'state': 'Karnataka',
      'city': 'Bengaluru',
      'addressLine1': '45 Healthcare Boulevard, Indiranagar',
      'pincode': '560038',
    };

    test('empty data -> 0% and all fields missing', () {
      final empty = <String, dynamic>{};
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.lab,
        empty,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.lab,
        empty,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.lab,
        empty,
      );
      final reqs = VerificationRequirementsConfig.requirementsForRole(
        UserType.lab,
      );

      expect(percentage, 0);
      expect(isComplete, isFalse);
      expect(missing.length, reqs.length);
      expect(missing.map((e) => e.key).toSet(), reqs.map((e) => e.key).toSet());
      expect(ProfileCompletionChecker.isLabDocComplete(empty), isFalse);
    });

    test('fully filled data -> 100% and isComplete true', () {
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.lab,
        fullLabData,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.lab,
        fullLabData,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.lab,
        fullLabData,
      );

      expect(percentage, 100);
      expect(isComplete, isTrue);
      expect(missing, isEmpty);
      expect(ProfileCompletionChecker.isLabDocComplete(fullLabData), isTrue);
    });

    test('one field missing -> correct missingFields and isComplete false', () {
      final copy = Map<String, dynamic>.from(fullLabData)
        ..remove('licenseNumber');
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.lab,
        copy,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.lab,
        copy,
      );

      expect(isComplete, isFalse);
      expect(missing.length, 1);
      expect(missing.first.key, 'licenseNumber');
      expect(missing.first.section, 'Lab Details');
      expect(
        VerificationRequirementsConfig.completionPercentage(
          UserType.lab,
          copy,
        ),
        lessThan(100),
      );
      expect(ProfileCompletionChecker.isLabDocComplete(copy), isFalse);
    });

    test('email is not required for Lab completeness', () {
      expect(fullLabData.containsKey('email'), isFalse);
      expect(
        VerificationRequirementsConfig.isComplete(UserType.lab, fullLabData),
        isTrue,
      );
    });
  });

  group('Ambulance profile completeness', () {
    final fullAmbulanceData = <String, dynamic>{
      'serviceName': 'LifeFirst Emergency Fleet',
      'driverName': 'Vikram Rathore',
      'phone': '9871122334',
      'vehicleNumber': 'DL-01-EQ-9988',
      'licenseNumber': 'DL-COMM-2022-1234',
      'city': 'New Delhi',
      'serviceAreas': ['South Delhi', 'Central Delhi', 'Noida'],
      'country': 'India',
      'state': 'Delhi',
      'addressLine1': 'Hub 12, Emergency Corridor, Okhla',
      'pincode': '110020',
    };

    test('empty data -> 0% and all fields missing', () {
      final empty = <String, dynamic>{};
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.ambulance,
        empty,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.ambulance,
        empty,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.ambulance,
        empty,
      );
      final reqs = VerificationRequirementsConfig.requirementsForRole(
        UserType.ambulance,
      );

      expect(percentage, 0);
      expect(isComplete, isFalse);
      expect(missing.length, reqs.length);
      expect(missing.map((e) => e.key).toSet(), reqs.map((e) => e.key).toSet());
      expect(ProfileCompletionChecker.isAmbulanceDocComplete(empty), isFalse);
    });

    test('fully filled data -> 100% and isComplete true', () {
      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.ambulance,
        fullAmbulanceData,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.ambulance,
        fullAmbulanceData,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.ambulance,
        fullAmbulanceData,
      );

      expect(percentage, 100);
      expect(isComplete, isTrue);
      expect(missing, isEmpty);
      expect(
        ProfileCompletionChecker.isAmbulanceDocComplete(fullAmbulanceData),
        isTrue,
      );
    });

    test('one field missing (vehicleNumber) -> correct missingFields', () {
      final copy = Map<String, dynamic>.from(fullAmbulanceData)
        ..remove('vehicleNumber');
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.ambulance,
        copy,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.ambulance,
        copy,
      );

      expect(isComplete, isFalse);
      expect(missing.length, 1);
      expect(missing.first.key, 'vehicleNumber');
      expect(missing.first.section, 'Service Details');
      expect(
        VerificationRequirementsConfig.completionPercentage(
          UserType.ambulance,
          copy,
        ),
        lessThan(100),
      );
      expect(ProfileCompletionChecker.isAmbulanceDocComplete(copy), isFalse);
    });

    test('empty serviceAreas list -> missingFields includes serviceAreas', () {
      final copy = Map<String, dynamic>.from(fullAmbulanceData)
        ..['serviceAreas'] = <String>[];
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.ambulance,
        copy,
      );
      final isComplete = VerificationRequirementsConfig.isComplete(
        UserType.ambulance,
        copy,
      );

      expect(isComplete, isFalse);
      expect(missing.any((item) => item.key == 'serviceAreas'), isTrue);
    });

    test('ownerName is explicitly NOT required for Ambulance', () {
      expect(fullAmbulanceData.containsKey('ownerName'), isFalse);
      expect(
        VerificationRequirementsConfig.isComplete(
          UserType.ambulance,
          fullAmbulanceData,
        ),
        isTrue,
      );
    });
  });

  group('Patient and SuperAdmin completeness', () {
    test('Patient has empty requirements list and returns isComplete true', () {
      final reqs = VerificationRequirementsConfig.requirementsForRole(
        UserType.patient,
      );
      expect(reqs, isEmpty);
      expect(
        VerificationRequirementsConfig.isComplete(UserType.patient, {}),
        isTrue,
      );
      expect(
        VerificationRequirementsConfig.completionPercentage(
            UserType.patient, {}),
        100,
      );
      expect(
        VerificationRequirementsConfig.missingFields(UserType.patient, {}),
        isEmpty,
      );
    });

    test('SuperAdmin has empty requirements list and returns isComplete true',
        () {
      final reqs = VerificationRequirementsConfig.requirementsForRole(
        UserType.superAdmin,
      );
      expect(reqs, isEmpty);
      expect(
        VerificationRequirementsConfig.isComplete(UserType.superAdmin, {}),
        isTrue,
      );
    });
  });
}
