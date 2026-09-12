import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/patient/profile/models/patient_profile_models.dart';
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_read_helper.dart';

class FamilyMemberRepository {
  FamilyMemberRepository._();

  static final FamilyMemberRepository instance = FamilyMemberRepository._();

  Future<List<FamilyProfileMember>> fetchForPatient(String patientId) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.familyMembers)
          .where('patientId', isEqualTo: patientId),
    );

    return snapshot.docs.map(_fromDoc).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> saveMember(String patientId, FamilyProfileMember member) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return;

    await FirebaseFirestore.instance.collection(FirestorePaths.familyMembers).doc(member.id).set({
      'patientId': patientId,
      'name': member.name,
      'relation': member.relation.name,
      'age': member.age,
      'gender': member.gender,
      'bloodGroup': member.bloodGroup,
      'allergies': member.allergies,
      'conditions': member.conditions,
      'insuranceCovered': member.insuranceCovered,
      if (member.dateOfBirth != null) 'dateOfBirth': Timestamp.fromDate(member.dateOfBirth!),
      if (member.photoInitial != null) 'photoInitial': member.photoInitial,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMember(String memberId) async {
    if (!FirebaseBootstrap.isReady || memberId.isEmpty) return;
    await FirebaseFirestore.instance.collection(FirestorePaths.familyMembers).doc(memberId).delete();
  }

  FamilyProfileMember _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return FamilyProfileMember(
      id: doc.id,
      name: data['name'] as String? ?? 'Member',
      relation: FamilyRelation.values.byName(data['relation'] as String? ?? 'other'),
      age: (data['age'] as num?)?.toInt() ?? 0,
      gender: data['gender'] as String? ?? '',
      bloodGroup: data['bloodGroup'] as String? ?? '',
      allergies: (data['allergies'] as List<dynamic>? ?? const []).cast<String>(),
      conditions: (data['conditions'] as List<dynamic>? ?? const []).cast<String>(),
      insuranceCovered: data['insuranceCovered'] as bool? ?? false,
      dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate(),
      photoInitial: data['photoInitial'] as String?,
    );
  }
}
