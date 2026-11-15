/// Paginated query result (Postgres / gateway-backed repos).
class DataPage<T> {
  const DataPage({
    required this.items,
    this.cursor,
    required this.hasMore,
  });

  final List<T> items;

  /// Opaque pagination cursor (offset key, etc.).
  final String? cursor;
  final bool hasMore;

  /// Legacy Firestore snapshot cursor — now the same as [cursor].
  String? get lastDocument => cursor;
}