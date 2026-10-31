import '../../supabase/supabase_bootstrap.dart';

class MedicineSuggestionRepository {
  MedicineSuggestionRepository._();

  static final MedicineSuggestionRepository instance =
      MedicineSuggestionRepository._();

  Future<void> submit({
    required String doctorId,
    required String medicineName,
  }) async {
    final trimmed = medicineName.trim();
    if (trimmed.isEmpty || !SupabaseBootstrap.isReady) return;

    await SupabaseBootstrap.client.from('medicine_suggestions').insert({
      'medicine_name': trimmed,
      'medicine_name_lower': trimmed.toLowerCase(),
      'doctor_id': doctorId,
      'status': 'pending',
      'source': 'doctor_prescription',
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
