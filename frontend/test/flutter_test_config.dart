/// Global test entry — does **not** disable [FirestoreForbiddenGuard].
/// Tests that need Firestore must call [allowFirestoreInThisTestFile] in that file.
Future<void> testExecutable(Future<void> Function() testMain) async {
  await testMain();
}
