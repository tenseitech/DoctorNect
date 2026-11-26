/// Parses dates from JSON/Map payloads (ISO strings or legacy {_seconds} maps).
DateTime? parseMapDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final seconds = value['_seconds'] ?? value['seconds'];
    if (seconds is num) {
      final nanos = value['_nanoseconds'] ?? value['nanoseconds'];
      final ms = seconds.toInt() * 1000 +
          (nanos is num ? nanos.toInt() ~/ 1000000 : 0);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
  }
  if (value is num) {
    final epoch = value.toInt();
    if (epoch > 10000000000) {
      return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true).toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true)
        .toLocal();
  }
  return null;
}

/// ISO-8601 string for writes (replaces Firestore server timestamps in maps).
String mapDateTimeToIso(DateTime value) => value.toUtc().toIso8601String();
