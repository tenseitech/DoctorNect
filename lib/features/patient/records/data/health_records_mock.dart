import 'package:flutter/foundation.dart';

import '../models/health_record_models.dart';
import 'vitals_log_mapper.dart';

class HealthRecordsMock extends ChangeNotifier {
  HealthRecordsMock._();

  static HealthRecordsMock? _instance;
  static HealthRecordsMock get instance => _instance ??= HealthRecordsMock._();

  List<HealthRecord> _records = [];
  List<VitalsLog> _vitals = [];
  double? _heightCm;

  static List<HealthRecord> records() => List.unmodifiable(instance._records);

  static List<VitalsLog> vitalsHistory() => List.unmodifiable(instance._vitals);

  static double? patientHeightCm() => instance._heightCm;

  static void applyFromFirestore(List<HealthRecord> records) {
    final uploads = <HealthRecord>[];
    final vitals = <VitalsLog>[];
    double? latestHeight;

    for (final record in records) {
      final log = VitalsLogMapper.fromHealthRecord(record);
      if (log != null) {
        vitals.add(log);
        if (log.heightCm != null) latestHeight = log.heightCm;
      } else {
        uploads.add(record);
      }
    }

    vitals.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    instance._records = uploads;
    instance._vitals = vitals;
    instance._heightCm = latestHeight;
    instance.notifyListeners();
  }

  static void addVitalsLog(VitalsLog log) {
    instance._vitals.insert(0, log);
    if (log.heightCm != null) instance._heightCm = log.heightCm;
    instance.notifyListeners();
  }

  static void addRecord(HealthRecord record) {
    instance._records.insert(0, record);
    instance.notifyListeners();
  }

  static void removeRecord(String id) {
    instance._records.removeWhere((r) => r.id == id);
    instance.notifyListeners();
  }

  static void updateRecord(HealthRecord record) {
    final index = instance._records.indexWhere((r) => r.id == record.id);
    if (index < 0) return;
    instance._records[index] = record;
    instance.notifyListeners();
  }

  static void applyVitalsFromFirestore(List<VitalsLog> vitals, {double? heightCm}) {
    instance._vitals = List.from(vitals);
    instance._heightCm = heightCm;
    instance.notifyListeners();
  }
}
