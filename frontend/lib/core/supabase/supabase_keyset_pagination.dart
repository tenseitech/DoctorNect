import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/data_page.dart';

/// Opaque keyset cursor for stable PostgREST pagination (sort column + tie-breaker id).
class KeysetCursor {
  const KeysetCursor({required this.sortValue, required this.tieBreakerId});

  final String sortValue;
  final String tieBreakerId;

  String encode() {
    return base64Url.encode(utf8.encode(
      jsonEncode({'s': sortValue, 'i': tieBreakerId}),
    ));
  }

  static KeysetCursor? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(raw))) as Map<String, dynamic>;
      final sort = map['s']?.toString() ?? '';
      final id = map['i']?.toString() ?? '';
      if (sort.isEmpty || id.isEmpty) return null;
      return KeysetCursor(sortValue: sort, tieBreakerId: id);
    } catch (_) {
      return null;
    }
  }

  static KeysetCursor? fromRow(
    Map<String, dynamic> row, {
    required String sortColumn,
    required String idColumn,
  }) {
    final sort = row[sortColumn]?.toString() ?? '';
    final id = row[idColumn]?.toString() ?? '';
    if (sort.isEmpty || id.isEmpty) return null;
    return KeysetCursor(sortValue: sort, tieBreakerId: id);
  }
}

/// Keyset helpers for Supabase `.or()` filters (PERF-02).
abstract final class SupabaseKeysetPagination {
  /// Descending sort: next page is rows strictly after the cursor in sort order.
  static PostgrestFilterBuilder<T> applyDescendingPage<T>(
    PostgrestFilterBuilder<T> query, {
    required String sortColumn,
    required String idColumn,
    required KeysetCursor cursor,
  }) {
    final sort = _quoteFilterValue(cursor.sortValue);
    final id = _quoteFilterValue(cursor.tieBreakerId);
    return query.or(
      '$sortColumn.lt.$sort,and($sortColumn.eq.$sort,$idColumn.lt.$id)',
    );
  }

  /// Ascending sort: next page after cursor.
  static PostgrestFilterBuilder<T> applyAscendingPage<T>(
    PostgrestFilterBuilder<T> query, {
    required String sortColumn,
    required String idColumn,
    required KeysetCursor cursor,
  }) {
    final sort = _quoteFilterValue(cursor.sortValue);
    final id = _quoteFilterValue(cursor.tieBreakerId);
    return query.or(
      '$sortColumn.gt.$sort,and($sortColumn.eq.$sort,$idColumn.gt.$id)',
    );
  }

  static String _quoteFilterValue(String value) {
    if (value.isEmpty) return '""';
    if (value.contains(',') || value.contains('(') || value.contains(')')) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    return value;
  }

  /// Fetches pages until [maxItems] or no more data (for legacy list APIs).
  static Future<List<T>> collectPages<T>({
    required Future<DataPage<T>> Function(String? cursor) fetchPage,
    required int maxItems,
  }) async {
    final out = <T>[];
    String? cursor;
    while (out.length < maxItems) {
      final page = await fetchPage(cursor);
      if (page.items.isEmpty) break;
      out.addAll(page.items);
      if (!page.hasMore || page.cursor == null) break;
      cursor = page.cursor;
    }
    if (out.length > maxItems) {
      return out.sublist(0, maxItems);
    }
    return out;
  }
}