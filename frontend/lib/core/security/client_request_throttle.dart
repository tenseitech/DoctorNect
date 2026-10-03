/// Lightweight client-side request throttle to blunt naive bots / scripts.
///
/// Server-side abuse_rate_limits remain authoritative; this only reduces
/// burst traffic from a single app session.
abstract final class ClientRequestThrottle {
  static final Map<String, List<DateTime>> _windows = {};

  /// Returns false when [action] has been called more than [max] times in [window].
  static bool allow(
    String action, {
    int max = 30,
    Duration window = const Duration(minutes: 1),
  }) {
    final key = action.trim().toLowerCase();
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    final list = (_windows[key] ?? <DateTime>[])
        .where((t) => t.isAfter(cutoff))
        .toList(growable: true);
    if (list.length >= max) {
      _windows[key] = list;
      return false;
    }
    list.add(now);
    _windows[key] = list;
    return true;
  }

  /// Returns an error message when throttled, else null (and records the attempt).
  static String? denyMessage(
    String action, {
    int max = 30,
    Duration window = const Duration(minutes: 1),
    String message = 'Too many requests. Please slow down and try again.',
  }) {
    if (allow(action, max: max, window: window)) return null;
    return message;
  }
}
