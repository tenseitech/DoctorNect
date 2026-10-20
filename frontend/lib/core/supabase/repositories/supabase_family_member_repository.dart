import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/patient/profile/models/patient_profile_models.dart';
import '../supabase_bootstrap.dart';

/// Supabase Repository for Family Members.
/// Replaces Firestore `family_members/{id}`.
class SupabaseFamilyMemberRepository {
  SupabaseFamilyMemberRepository._();

  static final SupabaseFamilyMemberRepository instance =
      SupabaseFamilyMemberRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<List<FamilyProfileMember>> fetchForPatient(String patientId) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];

    try {
      final res = await _client
          .from('family_members')
          .select()
          .eq('patient_id', patientId);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map(_fromRow).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveMember(String patientId, FamilyProfileMember member) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return;

    final payload = {
      'family_member_id': member.id,
      'patient_id': patientId,
      'name': member.name,
      'relation': member.relation.name,
      'age': member.age,
      'gender': member.gender,
      'blood_group': member.bloodGroup,
      'allergies': member.allergies,
      'conditions': member.conditions,
      'insurance_covered': member.insuranceCovered,
      if (member.dateOfBirth != null)
        'date_of_birth': member.dateOfBirth!.toIso8601String(),
      if (member.photoInitial != null) 'photo_initial': member.photoInitial,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _client.from('family_members').upsert(
      payload,
      onConflict: 'family_member_id',
    );
  }

  Future<void> deleteMember(String memberId) async {
    if (!SupabaseBootstrap.isReady || memberId.isEmpty) return;

    await _client
        .from('family_members')
        .delete()
        .eq('family_member_id', memberId);
  }

  FamilyProfileMember _fromRow(Map<String, dynamic> row) {
    FamilyRelation relation;
    try {
      relation = FamilyRelation.values.byName(
        row['relation'] as String? ?? 'other',
      );
    } catch (_) {
      relation = FamilyRelation.other;
    }

    return FamilyProfileMember(
      id: row['family_member_id'] as String? ?? row['id']?.toString() ?? '',
      name: row['name'] as String? ?? 'Member',
      relation: relation,
      age: (row['age'] as num?)?.toInt() ?? 0,
      gender: row['gender'] as String? ?? '',
      bloodGroup: row['blood_group'] as String? ?? '',
      allergies: (row['allergies'] as List<dynamic>? ?? const []).cast<String>(),
      conditions: (row['conditions'] as List<dynamic>? ?? const []).cast<String>(),
      insuranceCovered: row['insurance_covered'] as bool? ?? false,
      dateOfBirth: row['date_of_birth'] != null
          ? DateTime.tryParse(row['date_of_birth'].toString())
          : null,
      photoInitial: row['photo_initial'] as String?,
    );
  }
}
