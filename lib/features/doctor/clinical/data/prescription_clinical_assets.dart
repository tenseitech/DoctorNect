import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'community_diagnosis_repository.dart';
import 'icd10_diagnoses_database.dart';
import 'indian_medicines_database.dart';
import 'symptoms_database.dart';

/// Defers heavy prescription autocomplete assets until after the UI has painted.
abstract final class PrescriptionClinicalAssets {
  static Future<void>? _loading;
  static bool _idleScheduled = false;

  static Future<void> ensureLoaded() {
    return _loading ??= Future.wait([
      IndianMedicinesDatabase.instance.ensureLoaded(),
      Icd10DiagnosesDatabase.instance.ensureLoaded(),
      SymptomsDatabase.instance.ensureLoaded(),
      CommunityDiagnosisRepository.instance.fetchAll(),
    ]);
  }

  static void scheduleIdleLoad(void Function() onLoaded) {
    if (_loading != null) {
      unawaited(_loading!.then((_) => onLoaded()));
      return;
    }
    if (_idleScheduled) return;
    _idleScheduled = true;

    SchedulerBinding.instance.scheduleTask(
      () async {
        await ensureLoaded();
        onLoaded();
      },
      Priority.idle,
    );
  }
}
