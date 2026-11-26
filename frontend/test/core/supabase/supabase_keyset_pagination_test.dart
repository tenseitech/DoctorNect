import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/supabase_keyset_pagination.dart';

void main() {
  test('KeysetCursor round-trip encode/decode', () {
    const c = KeysetCursor(
      sortValue: '2024-06-01T10:00:00.000Z',
      tieBreakerId: 'appt_abc',
    );
    final encoded = c.encode();
    final decoded = KeysetCursor.decode(encoded);
    expect(decoded?.sortValue, c.sortValue);
    expect(decoded?.tieBreakerId, c.tieBreakerId);
  });

  test('fromRow builds cursor from map', () {
    final c = KeysetCursor.fromRow(
      {'date_time': '2024-01-02', 'appointment_id': 'x1'},
      sortColumn: 'date_time',
      idColumn: 'appointment_id',
    );
    expect(c?.tieBreakerId, 'x1');
  });

  test('decode rejects invalid cursor', () {
    expect(KeysetCursor.decode(null), isNull);
    expect(KeysetCursor.decode('not-valid'), isNull);
  });
}