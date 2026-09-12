import '../../../doctor/clinical/data/medical_tests_catalog.dart';
import '../models/lab_models.dart';

abstract final class PatientLabCatalogBuilder {
  static const _popularIds = {
    'lab_cbc',
    'lab_hba1c',
    'lab_lft',
    'lab_rft',
    'lab_lipid',
    'lab_tsh',
    'lab_bsf',
    'lab_urine_routine',
    'lab_vit_d',
  };

  static const _fastingIds = {
    'lab_bsf',
    'lab_bspp',
    'lab_insulin_fasting',
    'lab_lipid',
    'lab_homa_ir',
  };

  static const _cultureIds = {
    'lab_blood_culture',
    'lab_urine_culture',
    'lab_stool_culture',
    'lab_sputum_culture',
    'lab_throat_swab',
    'lab_wound_swab',
  };

  static List<LabTestItem> allTests() {
    return MedicalTestsCatalog.labTests.map(_fromCatalogItem).toList(growable: false);
  }

  static LabTestItem _fromCatalogItem(TestCatalogItem item) {
    return LabTestItem(
      id: item.id,
      name: item.name,
      parameters: [item.group],
      fastingRequired: _fastingIds.contains(item.id),
      sampleType: _sampleTypeForGroup(item.group),
      reportHours: _cultureIds.contains(item.id) ? 72 : 24,
      popular: _popularIds.contains(item.id),
      category: item.group,
    );
  }

  static SampleType _sampleTypeForGroup(String group) {
    if (group == 'Urine') return SampleType.urine;
    if (group == 'Stool') return SampleType.stool;
    return SampleType.blood;
  }

  static String normalizeId(String id) {
    return switch (id) {
      'lt_cbc' => 'lab_cbc',
      'lt_hba1c' => 'lab_hba1c',
      'lt_lipid' => 'lab_lipid',
      'lt_thyroid' => 'lab_tsh',
      _ => id,
    };
  }

  static List<LabTestItem> mergeTests(List<LabTestItem> remote) {
    final standard = allTests();
    if (remote.isEmpty) return standard;

    final remoteById = <String, LabTestItem>{
      for (final test in remote)
        normalizeId(test.id): _withId(test, normalizeId(test.id)),
    };
    final merged = <LabTestItem>[
      for (final test in standard) remoteById[test.id] ?? test,
    ];

    for (final test in remote) {
      final normalizedId = normalizeId(test.id);
      if (!merged.any((item) => item.id == normalizedId)) {
        merged.add(_withId(test, normalizedId));
      }
    }
    return merged;
  }

  static LabTestItem _withId(LabTestItem test, String id) {
    return LabTestItem(
      id: id,
      name: test.name,
      parameters: test.parameters,
      fastingRequired: test.fastingRequired,
      sampleType: test.sampleType,
      reportHours: test.reportHours,
      popular: test.popular,
      category: test.category,
    );
  }

  static Map<String, List<LabTestItem>> grouped(List<LabTestItem> tests) {
    final groups = <String, List<LabTestItem>>{};
    for (final test in tests) {
      final key = test.category?.trim().isNotEmpty == true ? test.category!.trim() : 'Other';
      groups.putIfAbsent(key, () => []).add(test);
    }
    return groups;
  }
}
