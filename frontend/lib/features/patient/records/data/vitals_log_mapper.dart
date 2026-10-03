import 'dart:convert';

import '../models/health_record_models.dart';

abstract final class VitalsLogMapper {
  static VitalsLog? fromHealthRecord(HealthRecord record) {
    if (record.fileName != 'vitals') return null;

    final raw = record.notes;
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['kind'] != 'vitalsLog') return null;

      GlucoseReadingType? glucoseType;
      final glucoseTypeName = map['glucoseType'] as String?;
      if (glucoseTypeName != null) {
        glucoseType = GlucoseReadingType.values.byName(glucoseTypeName);
      }

      return VitalsLog(
        id: record.id,
        dateTime:
            DateTime.tryParse(map['dateTime'] as String? ?? '') ?? record.date,
        systolic: (map['systolic'] as num?)?.toInt(),
        diastolic: (map['diastolic'] as num?)?.toInt(),
        pulse: (map['pulse'] as num?)?.toInt(),
        glucose: (map['glucose'] as num?)?.toDouble(),
        glucoseType: glucoseType,
        weightKg: (map['weightKg'] as num?)?.toDouble(),
        heightCm: (map['heightCm'] as num?)?.toDouble(),
        temperatureF: (map['temperatureF'] as num?)?.toDouble(),
        spo2: (map['spo2'] as num?)?.toInt(),
        steps: (map['steps'] as num?)?.toInt(),
        sleepHours: (map['sleepHours'] as num?)?.toDouble(),
        notes: map['userNotes'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static List<VitalsLog> fromHealthRecords(List<HealthRecord> records) {
    final logs = <VitalsLog>[];
    for (final record in records) {
      final log = fromHealthRecord(record);
      if (log != null) logs.add(log);
    }
    logs.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return logs;
  }
}
