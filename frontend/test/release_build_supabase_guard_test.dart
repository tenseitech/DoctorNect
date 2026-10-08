import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release scripts omit Supabase dart-defines unless ENABLE_SUPABASE=1',
      () {
    final ps1 = File('scripts/release_build.ps1').readAsStringSync();
    final sh = File('scripts/release_build.sh').readAsStringSync();

    expect(ps1.contains('--dart-define=USE_SUPABASE_AUTH'), isFalse);
    expect(sh.contains('--dart-define=USE_SUPABASE_AUTH'), isFalse);

    expect(ps1.contains("ENABLE_SUPABASE -eq '1'"), isTrue);
    expect(sh.contains('ENABLE_SUPABASE'), isTrue);
    expect(sh.contains('== "1"'), isTrue);

    final ps1Maps = ps1.indexOf("foreach (\$name in @('GOOGLE_MAPS_API_KEY'");
    final ps1SupabaseGate = ps1.indexOf("ENABLE_SUPABASE -eq '1'");
    final ps1SupabaseDefine = ps1.indexOf("'SUPABASE_URL', 'SUPABASE_ANON_KEY'");
    expect(ps1Maps, greaterThan(0));
    expect(ps1SupabaseGate, greaterThan(ps1Maps));
    expect(ps1SupabaseDefine, greaterThan(ps1SupabaseGate));

    final shMaps = sh.indexOf('GOOGLE_MAPS_API_KEY');
    final shGate = sh.indexOf('ENABLE_SUPABASE');
    final shUrlDefine = sh.indexOf('dart-define=SUPABASE_URL');
    expect(shMaps, greaterThan(0));
    expect(shGate, greaterThan(shMaps));
    expect(shUrlDefine, greaterThan(shGate));
  });
}
