import 'dart:async';

import '../../../core/auth/profile_completion_service.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/firebase/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/session/lab_session.dart';

class LabRegistry extends ChangeNotifier {
  LabRegistry._();

  static final LabRegistry instance = LabRegistry._();

  final List<RegisteredLabProfile> _labs = [];

  static List<RegisteredLabProfile> get all =>
      List.unmodifiable(instance._labs);

  static RegisteredLabProfile? findById(String id) {
    for (final lab in instance._labs) {
      if (lab.id == id) return lab;
    }
    return null;
  }

  static Future<void> refreshFromFirestore({bool preferCache = true}) async {
    final labs = await FirestoreService.instance.lab.fetchVerifiedLabs(
      preferCache: preferCache,
    );
    instance._labs
      ..clear()
      ..addAll(labs);
    instance.notifyListeners();
  }

  static Future<void> ensureLabLoaded(String labId) async {
    if (labId.isEmpty || findById(labId) != null) return;
    final remote = await FirestoreService.instance.lab.fetchLabById(labId);
    if (remote == null) return;
    instance._labs.add(remote);
    instance.notifyListeners();
  }

  static Future<String?> updateLabProfile({
    required String labId,
    String? labName,
    String? phone,
    String? email,
    String? gstNumber,
    bool clearGstNumber = false,
    String? addressLine1,
    String? addressLine2,
    String? country,
    String? state,
    String? city,
    String? pincode,
  }) async {
    var index = instance._labs.indexWhere((l) => l.id == labId);
    if (index < 0) {
      final remote = await FirestoreService.instance.lab.fetchLabById(labId);
      if (remote == null) return 'Lab not found';
      instance._labs.add(remote);
      index = instance._labs.length - 1;
    }

    final current = instance._labs[index];
    final normalizedEmail = email?.trim().toLowerCase();

    Map<String, dynamic>? addressMap;
    String? addressStr;
    if (addressLine1 != null) {
      addressMap = {
        'addressLine1': addressLine1,
        'addressLine2': addressLine2 ?? '',
        'country': country ?? '',
        'state': state ?? '',
        'city': city ?? '',
        'pinCode': pincode ?? '',
      };
      final parts = [
        addressLine1,
        addressLine2 ?? '',
        city ?? '',
        state ?? '',
        pincode ?? ''
      ].where((e) => e.isNotEmpty);
      addressStr = parts.join(', ');
    }

    try {
      await FirestoreService.instance.lab.updateLabFields(
        labId,
        labName: labName,
        address: addressMap,
        phone: phone,
        email: normalizedEmail,
        gstNumber: gstNumber,
        clearGstNumber: clearGstNumber,
      );
    } catch (_) {
      if (FirebaseBootstrap.isReady) {
        return 'Could not save changes. Please try again.';
      }
    }

    instance._labs[index] = current.copyWith(
      labName: labName,
      address: addressStr,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      country: country,
      state: state,
      city: city,
      pincode: pincode,
      phone: phone,
      email: normalizedEmail,
      gstNumber: gstNumber,
      clearGstNumber: clearGstNumber,
    );
    if (labName != null && labId == LabSession.loggedInLabId) {
      LabSession.setLab(id: labId, name: labName);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    unawaited(
      ProfileCompletionService.instance.evaluateAndMarkFromRoleDoc(
        role: UserType.lab,
        uid: uid,
        profileId: labId,
      ),
    );
    instance.notifyListeners();
    return null;
  }
}
