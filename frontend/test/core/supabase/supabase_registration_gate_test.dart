import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

void main() {
  tearDown(SupabaseBootstrap.resetForTesting);

  group('Supabase registration profile id', () {
    test('always returns the client-generated profile id', () async {
      const clientGeneratedId = 'p_client_12345';
      final resolvedId = await SupabaseBootstrap.resolveRegistrationProfileId(
        role: 'patient',
        defaultClientId: clientGeneratedId,
      );
      expect(resolvedId, clientGeneratedId);
    });
  });
}
