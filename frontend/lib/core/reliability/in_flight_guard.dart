/// Prevents duplicate overlapping mutations (REL-04 / REL-05).
class InFlightGuard {
  final Set<String> _keys = {};

  bool tryAcquire(String key) {
    if (key.isEmpty) return false;
    if (_keys.contains(key)) return false;
    _keys.add(key);
    return true;
  }

  void release(String key) {
    _keys.remove(key);
  }

  Future<T> run<T>(String key, Future<T> Function() action) async {
    if (!tryAcquire(key)) {
      throw StateError('Operation already in progress: $key');
    }
    try {
      return await action();
    } finally {
      release(key);
    }
  }
}