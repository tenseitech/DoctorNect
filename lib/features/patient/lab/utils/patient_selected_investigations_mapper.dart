import '../../../doctor/clinical/models/clinical_models.dart' hide LabTestItem;
import '../models/lab_models.dart';

abstract final class PatientSelectedInvestigationsMapper {
  static List<LabTestItem> toLabTests(PrescriptionDraft draft) {
    final items = <LabTestItem>[];

    for (final entry in draft.validInvestigations) {
      items.add(_fromInvestigation(entry));
    }

    for (final bodyPart in draft.bodyParts) {
      final trimmed = bodyPart.trim();
      if (trimmed.isEmpty) continue;
      items.add(
        LabTestItem(
          id: 'body_${trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
          name: trimmed,
          parameters: const ['Body Part / Region'],
          fastingRequired: false,
          sampleType: SampleType.blood,
          reportHours: 48,
          category: 'Body Part / Region',
        ),
      );
    }

    return items;
  }

  static LabTestItem _fromInvestigation(InvestigationEntry entry) {
    final sampleType = switch (entry.type) {
      InvestigationType.radiology => SampleType.blood,
      InvestigationType.lab => SampleType.blood,
      InvestigationType.custom => SampleType.blood,
    };

    return LabTestItem(
      id: entry.catalogId ?? entry.id,
      name: entry.name.trim(),
      parameters: [
        if (entry.group.trim().isNotEmpty) entry.group.trim() else entry.categoryLabel,
      ],
      fastingRequired: false,
      sampleType: sampleType,
      reportHours: 48,
      category: entry.categoryLabel,
    );
  }

  static String summaryLabel(Iterable<LabTestItem> tests) {
    final names = tests.map((test) => test.name).where((name) => name.isNotEmpty).toList();
    return summaryFromNames(names);
  }

  static String summaryFromNames(List<String> names) {
    final cleaned = names.map((name) => name.trim()).where((name) => name.isNotEmpty).toList();
    if (cleaned.isEmpty) return 'Lab tests';
    if (cleaned.length == 1) return cleaned.first;
    if (cleaned.length == 2) return '${cleaned[0]}, ${cleaned[1]}';
    return '${cleaned[0]}, ${cleaned[1]} +${cleaned.length - 2} more';
  }
}
