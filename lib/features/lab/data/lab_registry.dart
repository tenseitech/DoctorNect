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

  static int _seq = 0;

  static String register({
    String? id,
    required String labName,
    required String address,
    required String licenseNumber,
    String phone = '',
    String email = '',
    String? gstNumber,
    bool verified = false,
  }) {
    final labId = id ?? 'lab${DateTime.now().millisecondsSinceEpoch}_${++_seq}';
    instance._labs.removeWhere((l) => l.id == labId);
    instance._labs.add(
      RegisteredLabProfile(
        id: labId,
        labName: labName,
        address: address,
        licenseNumber: licenseNumber,
        phone: phone,
        email: email,
        gstNumber: gstNumber,
        verified: verified,
      ),
    );
    instance.notifyListeners();
    return labId;
  }

  static Future<String?> updateLabProfile({
    required String labId,
    String? labName,
    String? licenseNumber,
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
    bool? verified,
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
        licenseNumber: licenseNumber,
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
      licenseNumber: licenseNumber,
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
      verified: verified,
    );
    if (labName != null && labId == LabSession.loggedInLabId) {
      LabSession.setLab(id: labId, name: labName);
    }
    if (FirebaseBootstrap.isReady) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      unawaited(
        ProfileCompletionService.instance.evaluateAndMarkFromRoleDoc(
          role: UserType.lab,
          uid: uid,
          profileId: labId,
        ),
      );
    }
    instance.notifyListeners();
    return null;
  }
}
