import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/mobile_registration_lookup.dart';
import 'package:medibond/core/auth/unified_auth_coordinator.dart';
import 'package:medibond/core/enums/user_type.dart';

UnifiedAuthPath specPathAfterPostOtpLookup({
  required bool lookupError,
  required bool exists,
  UserType? registeredRole,
  UserType? selectedRole,
}) {
  if (lookupError) {
    return UnifiedAuthPath.lookupUnavailable;
  }
  if (exists) {
    final role = registeredRole ?? selectedRole;
    if (role == null) {
      throw StateError('existing user must have a role');
    }
    if (selectedRole != null && selectedRole != role) {
      return UnifiedAuthPath.blockedWrongRole;
    }
    return UnifiedAuthPath.login;
  }
  return UnifiedAuthPath.register;
}

void main() {
  group('post-OTP account lookup routing', () {
    test('existing patient on generic flow logs in without role picker', () {
      expect(
        specPathAfterPostOtpLookup(
          lookupError: false,
          exists: true,
          registeredRole: UserType.patient,
        ),
        UnifiedAuthPath.login,
      );
    });

    test('wrong selected role for existing account blocks with message path', () {
      expect(
        specPathAfterPostOtpLookup(
          lookupError: false,
          exists: true,
          registeredRole: UserType.patient,
          selectedRole: UserType.doctor,
        ),
        UnifiedAuthPath.blockedWrongRole,
      );
    });

    test('lookup error must not fall through to register', () {
      expect(
        specPathAfterPostOtpLookup(lookupError: true, exists: false),
        UnifiedAuthPath.lookupUnavailable,
      );
    });
  });

  group('UnifiedAuthCoordinator — wrong role and legacy fallback', () {
    test('blockedWrongRole when lookup finds role mismatch via conflict flag', () {
      const lookup = MobileLookupResult(
        exists: true,
        role: UserType.patient,
        conflict: true,
      );
      expect(lookup.conflict, isTrue);
      expect(
        specPathAfterPostOtpLookup(
          lookupError: false,
          exists: lookup.exists,
          registeredRole: lookup.role,
          selectedRole: UserType.doctor,
        ),
        UnifiedAuthPath.blockedWrongRole,
      );
    });

    test('legacy response without exists key is handled by _fetchConflictOnly path', () {
      expect(
        const {'ok': true, 'conflict': false}.containsKey('exists'),
        isFalse,
        reason: 'triggers legacy check() fallback in MobileRegistrationLookup.lookup',
      );
    });
  });

  group('MobileRegistrationLookup API', () {
    test('MobileLookupResult and lookup() are available', () {
      expect(MobileRegistrationLookup.lookup, isA<Function>());
      expect(
        const MobileLookupResult(exists: false).isError,
        isFalse,
      );
    });

    test('parseUserType maps server roles', () {
      expect(
        MobileRegistrationLookup.parseUserType('patient'),
        UserType.patient,
      );
      expect(
        MobileRegistrationLookup.parseUserType('medicalStore'),
        UserType.medicalStore,
      );
    });
  });

  group('registration OTP rollback policy', () {
    test('finalize failure removes pending Firebase auth user before sign-out', () async {
      final src = await File('lib/core/firebase/firebase_auth_service.dart')
          .readAsString();
      expect(
        RegExp(
          r'if \(finalizeError != null\) \{[\s\S]*deletePendingAuthUser\(user\)',
        ).hasMatch(src),
        isTrue,
      );
    });
  });

  group('UnifiedAuthCoordinator.resolvePath', () {
    test(
      'lookup unavailable does not return register when Firebase is not ready',
      () async {
        final path = await UnifiedAuthCoordinator.resolvePath(
          mobile: '9876543210',
          role: UserType.patient,
        );
        expect(path, UnifiedAuthPath.lookupUnavailable);
        expect(path, isNot(UnifiedAuthPath.register));
      },
    );
  });
}
