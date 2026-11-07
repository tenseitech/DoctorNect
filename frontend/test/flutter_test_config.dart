import 'package:medibond/core/config/firestore_forbidden_guard.dart';

/// Default test harness: allow Firestore fakes unless a test sets
/// [FirestoreForbiddenGuard.debugForceReleaseMode] to assert release behavior.
Future<void> testExecutable(Future<void> Function() testMain) async {
  FirestoreForbiddenGuard.debugOverrideForTesting = false;
  await testMain();
}
