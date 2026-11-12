import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/security/file_encryption_service.dart';

void main() {
  tearDown(FileEncryptionService.resetForTesting);

  test('clearOnLogout completes and clears the in-memory key', () async {
    FileEncryptionService.setKeyForTesting();
    await expectLater(FileEncryptionService.clearOnLogout(), completes);
  });
}
