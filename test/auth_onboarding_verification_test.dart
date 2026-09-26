import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/verification_lifecycle.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/models/medibond_user_profile.dart';
import 'package:medibond/core/admin/super_admin_verification_service.dart';

void main() {
  group('VerificationStage enum and helpers', () {
    test('fromString parses correctly for all stages', () {
      expect(VerificationStage.fromString('registered'),
          VerificationStage.registered);
      expect(VerificationStage.fromString('profile_incomplete'),
          VerificationStage.profileIncomplete);
      expect(VerificationStage.fromString('submitted_for_verification'),
          VerificationStage.submittedForVerification);
      expect(VerificationStage.fromString('pending_review'),
          VerificationStage.submittedForVerification);
      expect(
          VerificationStage.fromString('verified'), VerificationStage.verified);
      expect(
          VerificationStage.fromString('approved'), VerificationStage.verified);
      expect(VerificationStage.fromString('revision_requested'),
          VerificationStage.revisionRequested);
      expect(
          VerificationStage.fromString('rejected'), VerificationStage.rejected);
      expect(VerificationStage.fromString('unknown_value'),
          VerificationStage.registered);
    });

    test('VerificationStage helper getters work accurately', () {
      const reg = VerificationStage.registered;
      expect(reg.isVerified, isFalse);
      expect(reg.isPending, isFalse);
      expect(reg.isIncomplete, isTrue);

      const sub = VerificationStage.submittedForVerification;
      expect(sub.isVerified, isFalse);
      expect(sub.isPending, isTrue);
      expect(sub.isIncomplete, isFalse);

      const ver = VerificationStage.verified;
      expect(ver.isVerified, isTrue);
      expect(ver.isPending, isFalse);
      expect(ver.isIncomplete, isFalse);

      const rev = VerificationStage.revisionRequested;
      expect(rev.isVerified, isFalse);
      expect(rev.isPending, isFalse);
      expect(rev.isRevisionRequested, isTrue);
      expect(rev.displayLabel, 'Action Required');

      const rej = VerificationStage.rejected;
      expect(rej.isVerified, isFalse);
      expect(rej.isPending, isFalse);
      expect(rej.displayLabel, 'Rejected');
    });
  });

  group('VerificationRequirementsConfig checklist per role', () {
    test('Patient requires no verification', () {
      final reqs =
          VerificationRequirementsConfig.requirementsForRole(UserType.patient);
      expect(reqs, isEmpty);
    });

    test('Doctor checklist evaluated correctly', () {
      final reqs =
          VerificationRequirementsConfig.requirementsForRole(UserType.doctor);
      expect(reqs.length, greaterThanOrEqualTo(4));

      final emptyProfile = <String, dynamic>{};
      expect(
        VerificationRequirementsConfig.isRequirementsMet(
          UserType.doctor,
          emptyProfile,
        ),
        isFalse,
      );

      final completeProfile = <String, dynamic>{
        'qualification': 'MBBS, MD (Medicine)',
        'councilNumber': 'MED-12345',
        'stateCouncil': 'Delhi Medical Council',
        'registrationCertificate':
            'https://storage.googleapis.com/test/certificate.pdf',
        'idProof': 'https://storage.googleapis.com/test/aadhaar.pdf',
      };

      expect(
        VerificationRequirementsConfig.isRequirementsMet(
          UserType.doctor,
          completeProfile,
        ),
        isTrue,
      );
    });

    test('Pharmacy checklist evaluated correctly', () {
      final reqs = VerificationRequirementsConfig.requirementsForRole(
          UserType.medicalStore);
      expect(reqs.length, greaterThanOrEqualTo(3));

      final incompleteProfile = <String, dynamic>{
        'storeName': 'Apollo Pharmacy',
      };
      expect(
        VerificationRequirementsConfig.isRequirementsMet(
          UserType.medicalStore,
          incompleteProfile,
        ),
        isFalse,
      );

      final completeProfile = <String, dynamic>{
        'storeName': 'Apollo Pharmacy',
        'drugLicenseNumber': 'DL-2026-9988',
        'ownerName': 'Ramesh Kumar',
        'address': '123 Health Ave, City, PIN 110001',
      };
      expect(
        VerificationRequirementsConfig.isRequirementsMet(
          UserType.medicalStore,
          completeProfile,
        ),
        isTrue,
      );
    });

    test('Lab checklist evaluated correctly', () {
      final reqs =
          VerificationRequirementsConfig.requirementsForRole(UserType.lab);
      expect(reqs.length, greaterThanOrEqualTo(3));

      final completeProfile = <String, dynamic>{
        'labName': 'PathKind Diagnostics',
        'licenseNumber': 'LAB-REG-101',
        'address': 'Sector 4, City, PIN 110001',
      };
      expect(
        VerificationRequirementsConfig.isRequirementsMet(
          UserType.lab,
          completeProfile,
        ),
        isTrue,
      );
    });

    test('Ambulance checklist evaluated correctly', () {
      final reqs = VerificationRequirementsConfig.requirementsForRole(
          UserType.ambulance);
      expect(reqs.length, greaterThanOrEqualTo(4));

      final completeProfile = <String, dynamic>{
        'serviceName': 'Emergency Care Unit',
        'vehicleNumber': 'DL-01-AB-1234',
        'driverName': 'Suresh Singh',
        'licenseNumber': 'DL-LIC-9988',
      };
      expect(
        VerificationRequirementsConfig.isRequirementsMet(
          UserType.ambulance,
          completeProfile,
        ),
        isTrue,
      );
    });
  });

  group('DoctorNectUserProfile with verification lifecycle', () {
    test('deserializes verificationStatus, rejectionReason, and submittedAt',
        () {
      final submittedDate = DateTime(2026, 9, 20, 10, 30);
      final map = <String, dynamic>{
        'email': 'doctor@example.com',
        'role': 'doctor',
        'profileId': 'doc-123',
        'displayName': 'Dr. Sharma',
        'verified': false,
        'verificationStatus': 'revision_requested',
        'rejectionReason':
            'Please upload clear copy of medical council registration.',
        'submittedAt': submittedDate,
      };

      final profile = DoctorNectUserProfile.fromMap('uid-123', map);
      expect(profile.role, UserType.doctor);
      expect(profile.profileId, 'doc-123');
      expect(profile.verificationStatus, 'revision_requested');
      expect(profile.rejectionReason,
          'Please upload clear copy of medical council registration.');
      expect(profile.submittedAt, isNotNull);

      final serialized = profile.toMap();
      expect(serialized['verificationStatus'], 'revision_requested');
      expect(serialized['rejectionReason'],
          'Please upload clear copy of medical council registration.');
      expect(serialized['role'], 'doctor');
    });

    test('handles null verificationStatus gracefully', () {
      final map = <String, dynamic>{
        'email': 'patient@example.com',
        'role': 'patient',
        'profileId': 'p-99',
        'displayName': 'Patient Name',
      };

      final profile = DoctorNectUserProfile.fromMap('uid-patient', map);
      expect(profile.role, UserType.patient);
      expect(profile.verificationStatus, isNull);
      expect(profile.rejectionReason, isNull);
    });
  });

  group('VerificationApplicant model in SuperAdminVerificationService', () {
    test('parses applicant from user data map correctly', () {
      final docData = <String, dynamic>{
        'displayName': 'Dr. Sharma',
        'email': 'sharma@example.com',
        'mobile': '9876543210',
        'role': 'doctor',
        'profileId': 'doc-789',
        'verified': false,
        'verificationStatus': 'submitted_for_verification',
      };

      final applicant = VerificationApplicant.fromMap('uid-001', docData);
      expect(applicant.uid, 'uid-001');
      expect(applicant.displayName, 'Dr. Sharma');
      expect(applicant.role, UserType.doctor);
      expect(applicant.profileId, 'doc-789');
      expect(applicant.verified, isFalse);
      expect(applicant.verificationStatus,
          VerificationStage.submittedForVerification);
      expect(applicant.verificationStatus.isPending, isTrue);
    });

    test('maps revision_requested with rejection reason', () {
      final pharmacyData = <String, dynamic>{
        'displayName': 'City Care Chemist',
        'email': 'care@example.com',
        'mobile': '9811122233',
        'role': 'medicalStore',
        'profileId': 'store-456',
        'verified': false,
        'verificationStatus': 'revision_requested',
        'rejectionReason':
            'Drug license expired; please upload latest renewal.',
      };

      final applicant = VerificationApplicant.fromMap('uid-002', pharmacyData);
      expect(applicant.role, UserType.medicalStore);
      expect(applicant.verificationStatus, VerificationStage.revisionRequested);
      expect(applicant.rejectionReason, contains('Drug license expired'));
      expect(applicant.verificationStatus.isRevisionRequested, isTrue);
    });
  });
}
