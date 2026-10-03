import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/supabase_auth_service.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

void main() {
  setUp(() {
    SupabaseBootstrap.debugUseSupabaseAuthOverride = null;
    SupabaseBootstrap.debugFirebaseUserActiveOverride = false;
    SupabaseBootstrap.debugSupabaseUserLoggedInOverride = true;
    SupabaseBootstrap.debugHasActiveSessionOverride = true;

    SupabaseAuthService.instance.debugUserProfileOverride = null;
    SupabaseAuthService.instance.debugSignOutCalled = false;
  });

  tearDown(() {
    SupabaseBootstrap.debugUseSupabaseAuthOverride = null;
    SupabaseBootstrap.debugFirebaseUserActiveOverride = null;
    SupabaseBootstrap.debugSupabaseUserLoggedInOverride = null;
    SupabaseBootstrap.debugHasActiveSessionOverride = null;

    SupabaseAuthService.instance.debugUserProfileOverride = null;
    SupabaseAuthService.instance.debugSignOutCalled = false;
  });

  group('Supabase Registration Gating & Session Lifecycle Tests', () {
    test(
      'TEST 1: Flag OFF + stale Supabase session -> client id used and session cleared',
      () async {
        // Flag explicitly disabled
        SupabaseBootstrap.debugUseSupabaseAuthOverride = false;

        // Active stale Supabase session present
        SupabaseBootstrap.debugHasActiveSessionOverride = true;
        SupabaseBootstrap.debugSupabaseUserLoggedInOverride = true;
        SupabaseAuthService.instance.debugUserProfileOverride =
            const SupabaseUserProfile(
                profileId: 'p_server_999', role: 'patient');

        const clientGeneratedId = 'p_client_12345';
        final resolvedId = await SupabaseBootstrap.resolveRegistrationProfileId(
          role: 'patient',
          defaultClientId: clientGeneratedId,
        );

        // Expect client-generated ID
        expect(resolvedId, equals(clientGeneratedId));

        // Expect stale Supabase session to be signed out
        expect(SupabaseAuthService.instance.debugSignOutCalled, isTrue);
      },
    );

    test(
      'TEST 2: Flag ON + matching role -> server id used and session preserved',
      () async {
        // Flag explicitly enabled
        SupabaseBootstrap.debugUseSupabaseAuthOverride = true;
        SupabaseBootstrap.debugFirebaseUserActiveOverride = false;
        SupabaseBootstrap.debugSupabaseUserLoggedInOverride = true;
        SupabaseBootstrap.debugHasActiveSessionOverride = true;

        SupabaseAuthService.instance.debugUserProfileOverride =
            const SupabaseUserProfile(
                profileId: 'p_server_auth_profile', role: 'patient');

        const clientGeneratedId = 'p_client_12345';
        final resolvedId = await SupabaseBootstrap.resolveRegistrationProfileId(
          role: 'patient',
          defaultClientId: clientGeneratedId,
        );

        // Expect authoritative server-provisioned profile ID
        expect(resolvedId, equals('p_server_auth_profile'));

        // Session must NOT be signed out
        expect(SupabaseAuthService.instance.debugSignOutCalled, isFalse);
      },
    );

    test(
      'TEST 3: Flag ON + role mismatch -> client id used and session cleared',
      () async {
        // Flag enabled, but user has 'doctor' profile while registering as 'patient'
        SupabaseBootstrap.debugUseSupabaseAuthOverride = true;
        SupabaseBootstrap.debugFirebaseUserActiveOverride = false;
        SupabaseBootstrap.debugSupabaseUserLoggedInOverride = true;
        SupabaseBootstrap.debugHasActiveSessionOverride = true;

        SupabaseAuthService.instance.debugUserProfileOverride =
            const SupabaseUserProfile(
                profileId: 'd_server_doc_profile', role: 'doctor');

        const clientGeneratedId = 'p_client_12345';
        final resolvedId = await SupabaseBootstrap.resolveRegistrationProfileId(
          role: 'patient',
          defaultClientId: clientGeneratedId,
        );

        // Fallback to client ID due to role mismatch
        expect(resolvedId, equals(clientGeneratedId));

        // Stale mismatched session signed out
        expect(SupabaseAuthService.instance.debugSignOutCalled, isTrue);
      },
    );

    test(
      'TEST 4: Flag ON + active Firebase user -> client id used and session cleared',
      () async {
        // Flag enabled, but Firebase user is active (conflict avoidance)
        SupabaseBootstrap.debugUseSupabaseAuthOverride = true;
        SupabaseBootstrap.debugFirebaseUserActiveOverride = true;
        SupabaseBootstrap.debugSupabaseUserLoggedInOverride = true;
        SupabaseBootstrap.debugHasActiveSessionOverride = true;

        SupabaseAuthService.instance.debugUserProfileOverride =
            const SupabaseUserProfile(
                profileId: 'p_server_profile', role: 'patient');

        const clientGeneratedId = 'p_client_12345';
        final resolvedId = await SupabaseBootstrap.resolveRegistrationProfileId(
          role: 'patient',
          defaultClientId: clientGeneratedId,
        );

        // Fallback to client ID because Firebase session is active
        expect(resolvedId, equals(clientGeneratedId));

        // Supabase session signed out to prevent split auth
        expect(SupabaseAuthService.instance.debugSignOutCalled, isTrue);
      },
    );
  });
}
