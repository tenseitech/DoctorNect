import 'vital_advisory_models.dart';
import 'server_validation_service.dart';

/// Interprets vital advisory thresholds downloaded from the server.
abstract final class VitalAdvisoryEngine {
  static VitalAdvisory evaluate(String ruleName, String? value) {
    final thresholds = ServerValidationService.vitalThresholds;
    if (thresholds == null) return const VitalAdvisory.none();

    final str = value?.trim() ?? '';
    if (str.isEmpty) return const VitalAdvisory.none();

    switch (ruleName) {
      case 'bloodPressure':
        return _bloodPressure(str, thresholds['bloodPressure']);
      case 'temperature':
        return _temperature(str, thresholds['temperature']);
      case 'pulse':
        return _rangeAdvisory(
          str,
          thresholds['pulse'],
          unitLabel: 'bpm',
          criticalLowKey: 'criticalLow',
          criticalHighKey: 'criticalHigh',
          criticalLowLabel: (t) => 'Pulse < ${t['criticalLow']} bpm — critically low',
          criticalHighLabel: (t) =>
              'Pulse > ${t['criticalHigh']} bpm — critically high',
        );
      case 'spo2':
        return _spo2(str, thresholds['spo2']);
      case 'respiratoryRate':
        return _rangeAdvisory(
          str,
          thresholds['respiratoryRate'],
          unitLabel: 'breaths/min',
          criticalLowKey: 'criticalLow',
          criticalHighKey: 'criticalHigh',
          criticalLowLabel: (t) =>
              'Resp. rate < ${t['criticalLow']} — critically low',
          criticalHighLabel: (t) =>
              'Resp. rate > ${t['criticalHigh']} — critically high',
        );
      default:
        return const VitalAdvisory.none();
    }
  }

  static VitalAdvisory _bloodPressure(String str, dynamic raw) {
    if (raw is! Map) return const VitalAdvisory.none();
    final t = Map<String, dynamic>.from(raw);
    final match = RegExp(r'^(\d{2,3})/(\d{2,3})$').firstMatch(str);
    if (match == null) return const VitalAdvisory.none();

    final sys = int.tryParse(match.group(1)!);
    final dia = int.tryParse(match.group(2)!);
    if (sys == null || dia == null || sys <= dia) {
      return const VitalAdvisory.none();
    }

    final criticalLow = (t['criticalSysLow'] as num?)?.toInt() ?? 80;
    final criticalHigh = (t['criticalSysHigh'] as num?)?.toInt() ?? 180;
    final sysMin = (t['normalSysMin'] as num?)?.toInt() ?? 90;
    final sysMax = (t['normalSysMax'] as num?)?.toInt() ?? 120;
    final diaMin = (t['normalDiaMin'] as num?)?.toInt() ?? 60;
    final diaMax = (t['normalDiaMax'] as num?)?.toInt() ?? 80;

    if (sys < criticalLow) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.critical,
        message: 'Systolic BP < $criticalLow mmHg — possible shock',
      );
    }
    if (sys > criticalHigh) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.critical,
        message: 'Systolic BP > $criticalHigh mmHg — hypertensive crisis',
      );
    }

    final sysNormal = sys >= sysMin && sys <= sysMax;
    final diaNormal = dia >= diaMin && dia <= diaMax;
    if (sysNormal && diaNormal) {
      return const VitalAdvisory(
        level: VitalAdvisoryLevel.normal,
        message: 'Within normal range',
      );
    }

    final parts = <String>[];
    if (!sysNormal) parts.add('systolic $sysMin–$sysMax');
    if (!diaNormal) parts.add('diastolic $diaMin–$diaMax');
    return VitalAdvisory(
      level: VitalAdvisoryLevel.warning,
      message: 'Outside normal range (${parts.join(', ')} mmHg)',
    );
  }

  static VitalAdvisory _temperature(String str, dynamic raw) {
    if (raw is! Map) return const VitalAdvisory.none();
    final t = Map<String, dynamic>.from(raw);
    final parsed = double.tryParse(str);
    if (parsed == null) return const VitalAdvisory.none();

    final hypothermia = (t['hypothermia'] as num?)?.toDouble() ?? 95;
    final belowNormal = (t['belowNormal'] as num?)?.toDouble() ?? 97;
    final normalMax = (t['normalMax'] as num?)?.toDouble() ?? 99;
    final lowGradeFever = (t['lowGradeFever'] as num?)?.toDouble() ?? 100.3;
    final fever = (t['fever'] as num?)?.toDouble() ?? 103;
    final highFever = (t['highFever'] as num?)?.toDouble() ?? 105;

    if (parsed < hypothermia) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.hypothermia,
        message: 'Hypothermia (< ${hypothermia.toStringAsFixed(0)}°F)',
      );
    }
    if (parsed < belowNormal) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.caution,
        message: 'Below normal (${belowNormal.toStringAsFixed(0)}–${normalMax.toStringAsFixed(0)}°F)',
      );
    }
    if (parsed <= normalMax) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.normal,
        message: 'Normal (${belowNormal.toStringAsFixed(0)}–${normalMax.toStringAsFixed(0)}°F)',
      );
    }
    if (parsed <= lowGradeFever) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.caution,
        message:
            'Low-grade fever (${(normalMax + 0.1).toStringAsFixed(1)}–$lowGradeFever°F)',
      );
    }
    if (parsed <= fever) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.warning,
        message: 'Fever (${(lowGradeFever + 0.1).toStringAsFixed(1)}–$fever°F)',
      );
    }
    if (parsed <= highFever) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.critical,
        message: 'High fever (${(fever + 0.1).toStringAsFixed(1)}–$highFever°F)',
      );
    }
    return VitalAdvisory(
      level: VitalAdvisoryLevel.critical,
      message: 'Hyperpyrexia / Emergency (> $highFever°F)',
    );
  }

  static VitalAdvisory _spo2(String str, dynamic raw) {
    if (raw is! Map) return const VitalAdvisory.none();
    final t = Map<String, dynamic>.from(raw);
    final parsed = double.tryParse(str);
    if (parsed == null) return const VitalAdvisory.none();

    final critical = (t['critical'] as num?)?.toDouble() ?? 85;
    final emergency = (t['emergency'] as num?)?.toDouble() ?? 90;
    final cautionMin = (t['cautionMin'] as num?)?.toDouble() ?? 91;
    final normalMin = (t['normalMin'] as num?)?.toDouble() ?? 95;
    final normalMax = (t['normalMax'] as num?)?.toDouble() ?? 100;

    if (parsed < critical) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.critical,
        message: 'SpO2 < ${critical.toStringAsFixed(0)}% — critical',
      );
    }
    if (parsed < emergency) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.critical,
        message: 'SpO2 < ${emergency.toStringAsFixed(0)}% — emergency',
      );
    }
    if (parsed >= normalMin && parsed <= normalMax) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.normal,
        message:
            'Within normal range (${normalMin.toStringAsFixed(0)}–${normalMax.toStringAsFixed(0)}%)',
      );
    }
    if (parsed >= cautionMin) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.caution,
        message:
            'SpO2 ${cautionMin.toStringAsFixed(0)}–${(normalMin - 1).toStringAsFixed(0)}% — caution zone',
      );
    }
    return VitalAdvisory(
      level: VitalAdvisoryLevel.warning,
      message:
          'SpO2 ${(emergency + 1).toStringAsFixed(0)}–${emergency.toStringAsFixed(0)}% — concern zone',
    );
  }

  static VitalAdvisory _rangeAdvisory(
    String str,
    dynamic raw, {
    required String unitLabel,
    required String criticalLowKey,
    required String criticalHighKey,
    required String Function(Map<String, dynamic>) criticalLowLabel,
    required String Function(Map<String, dynamic>) criticalHighLabel,
  }) {
    if (raw is! Map) return const VitalAdvisory.none();
    final t = Map<String, dynamic>.from(raw);
    final parsed = double.tryParse(str);
    if (parsed == null) return const VitalAdvisory.none();

    final normalMin = (t['normalMin'] as num?)?.toDouble() ?? 0;
    final normalMax = (t['normalMax'] as num?)?.toDouble() ?? 0;
    final criticalLow = (t[criticalLowKey] as num?)?.toDouble();
    final criticalHigh = (t[criticalHighKey] as num?)?.toDouble();

    if (criticalLow != null && parsed < criticalLow) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.critical,
        message: criticalLowLabel(t),
      );
    }
    if (criticalHigh != null && parsed > criticalHigh) {
      return VitalAdvisory(
        level: VitalAdvisoryLevel.critical,
        message: criticalHighLabel(t),
      );
    }
    if (parsed >= normalMin && parsed <= normalMax) {
      return const VitalAdvisory(
        level: VitalAdvisoryLevel.normal,
        message: 'Within normal range',
      );
    }
    return VitalAdvisory(
      level: VitalAdvisoryLevel.warning,
      message:
          'Outside normal range (${normalMin.toStringAsFixed(0)}–${normalMax.toStringAsFixed(0)} $unitLabel)',
    );
  }
}
