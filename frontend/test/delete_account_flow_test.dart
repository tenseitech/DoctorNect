import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/account/delete_account_flow.dart';

void main() {
  group('userFacingDeleteAccountError', () {
    test('uses callable message when present', () {
      expect(
        userFacingDeleteAccountError(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Recent login required.',
          ),
        ),
        'Recent login required.',
      );
    });

    test('falls back for empty callable message', () {
      expect(
        userFacingDeleteAccountError(
          FirebaseFunctionsException(code: 'internal', message: '   '),
        ),
        'Could not delete account. Please try again.',
      );
    });

    test('generic message for unknown errors', () {
      expect(
        userFacingDeleteAccountError(StateError('boom')),
        'Failed to delete account. Please try again.',
      );
    });
  });
}