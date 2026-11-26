/// Classifies Supabase/PostgREST errors for retry policy (REL-02).
abstract final class SupabaseErrorClassifier {
  static bool isTransient(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socketexception') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('network is unreachable') ||
        text.contains('failed host lookup')) {
      return true;
    }
    final codeMatch = RegExp(r'code[:\s]+(\d+)').firstMatch(text);
    if (codeMatch != null) {
      final code = int.tryParse(codeMatch.group(1) ?? '');
      if (code == 408 || code == 429 || code == 502 || code == 503 || code == 504) {
        return true;
      }
      if (code != null && code >= 400 && code < 500) {
        return false;
      }
    }
    return false;
  }
}