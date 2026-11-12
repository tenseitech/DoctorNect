/// Thrown when [SupabaseUserRepository.createProfile] cannot persist after retries.
class ProfileCreationException implements Exception {
  ProfileCreationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ProfileCreationException: $message';
}
