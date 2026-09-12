import 'package:flutter/material.dart';

import '../models/lab_models.dart';

/// Resolves a representative icon for a lab test (popular avatars, etc.).
abstract final class LabTestIcon {
  LabTestIcon._();

  static IconData forTest(LabTestItem test) {
    return switch (test.id) {
      'lab_cbc' => Icons.bloodtype_rounded,
      'lab_bsf' => Icons.no_meals_rounded,
      'lab_hba1c' => Icons.analytics_rounded,
      'lab_lft' => Icons.healing_rounded,
      'lab_rft' => Icons.water_drop_rounded,
      'lab_lipid' => Icons.monitor_heart_rounded,
      'lab_tsh' => Icons.medication_rounded,
      'lab_urine_routine' => Icons.science_rounded,
      'lab_vit_d' => Icons.wb_sunny_rounded,
      _ => _fromNameAndSample(test),
    };
  }

  static IconData _fromNameAndSample(LabTestItem test) {
    final name = test.name.toLowerCase();

    if (name.contains('urine')) return Icons.water_drop_rounded;
    if (name.contains('stool')) return Icons.biotech_rounded;
    if (name.contains('thyroid') || name.contains('tsh')) return Icons.medication_rounded;
    if (name.contains('liver') || name.contains('lft')) return Icons.healing_rounded;
    if (name.contains('renal') || name.contains('kidney') || name.contains('kft')) {
      return Icons.water_drop_rounded;
    }
    if (name.contains('lipid') || name.contains('cholesterol')) {
      return Icons.monitor_heart_rounded;
    }
    if (name.contains('vitamin') || name.contains('vit d')) return Icons.wb_sunny_rounded;
    if (name.contains('sugar') || name.contains('glucose') || name.contains('hba1c')) {
      return Icons.analytics_rounded;
    }
    if (name.contains('blood') || name.contains('cbc') || name.contains('haem')) {
      return Icons.bloodtype_rounded;
    }

    return switch (test.sampleType) {
      SampleType.blood => Icons.science_rounded,
      SampleType.urine => Icons.water_drop_rounded,
      SampleType.stool => Icons.biotech_rounded,
    };
  }
}
