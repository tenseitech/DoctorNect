import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/patient/profile/family/add_family_member_profile_screen.dart';

void main() {
  group('Family Patient ID Generation and Schema Bounds', () {
    test('namespaces family patient_id to caller UID with prefix', () {
      const mockUid = 'firebase_user_abc123xyz789';
      final id = AddFamilyMemberProfileScreen.generateFamilyMemberId(
        ownerUid: mockUid,
        timestamp: 1730200000000,
      );

      expect(id, equals('firebase_user_abc123xyz789_fm1730200000000'));
      expect(id.startsWith('${mockUid}_'), isTrue);
    });

    test('generated ID strictly fits inside patients.patient_id VARCHAR(64) for 28-char Firebase UIDs', () {
      // Standard Firebase Auth UID is 28 alphanumeric characters
      const standardFirebaseUid = 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4';
      expect(standardFirebaseUid.length, equals(28));

      final id = AddFamilyMemberProfileScreen.generateFamilyMemberId(
        ownerUid: standardFirebaseUid,
        timestamp: 1730200000000, // 13 digits
      );

      // 28 (uid) + 1 (_) + 2 (fm) + 13 (timestamp) = 44 characters
      expect(id.length, equals(44));
      expect(id.length, lessThanOrEqualTo(64),
          reason: 'Must not exceed PostgreSQL patients.patient_id VARCHAR(64) column limit');
    });

    test('generated ID strictly fits inside patients.patient_id VARCHAR(64) for 36-char UUIDs', () {
      // Max possible length: 36-char UUID format UID
      const uuidFormatUid = '12345678-1234-5678-1234-567812345678';
      expect(uuidFormatUid.length, equals(36));

      final id = AddFamilyMemberProfileScreen.generateFamilyMemberId(
        ownerUid: uuidFormatUid,
        timestamp: 1730200000000,
      );

      // 36 (uid) + 1 (_) + 2 (fm) + 13 (timestamp) = 52 characters
      expect(id.length, equals(52));
      expect(id.length, lessThanOrEqualTo(64),
          reason: 'Must not exceed PostgreSQL patients.patient_id VARCHAR(64) column limit');
    });

    test('fallback without ownerUid produces fm prefix without dangling underscore', () {
      final id = AddFamilyMemberProfileScreen.generateFamilyMemberId(
        ownerUid: '',
        timestamp: 1730200000000,
      );

      expect(id, equals('fm1730200000000'));
      expect(id.length, lessThanOrEqualTo(64));
    });
  });
}

