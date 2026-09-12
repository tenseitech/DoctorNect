import '../models/clinical_models.dart';
import '../../../../core/validation/validation_engine.dart';
import '../../../../core/validation/vital_advisory_engine.dart';
import '../../../../core/validation/vital_advisory_models.dart';

export '../../../../core/validation/vital_advisory_models.dart';

/// Prescription vitals — rules loaded from server via [ValidationEngine].
abstract final class PrescriptionVitalValidators {
  static String? bloodPressure(String? value) =>
      ValidationEngine.validate('bloodPressure', value);

  static VitalAdvisory bloodPressureAdvisory(String? value) =>
      VitalAdvisoryEngine.evaluate('bloodPressure', value);

  static String? temperature(String? value) =>
      ValidationEngine.validate('temperature', value);

  static VitalAdvisory temperatureAdvisory(String? value) =>
      VitalAdvisoryEngine.evaluate('temperature', value);

  static String? pulse(String? value) =>
      ValidationEngine.validate('pulse', value);

  static VitalAdvisory pulseAdvisory(String? value) =>
      VitalAdvisoryEngine.evaluate('pulse', value);

  static String? spo2(String? value) =>
      ValidationEngine.validate('spo2', value);

  static VitalAdvisory spo2Advisory(String? value) =>
      VitalAdvisoryEngine.evaluate('spo2', value);

  static String? respiratoryRate(String? value) =>
      ValidationEngine.validate('respiratoryRate', value);

  static VitalAdvisory respiratoryRateAdvisory(String? value) =>
      VitalAdvisoryEngine.evaluate('respiratoryRate', value);

  static String? validateAll(PrescriptionVitals vitals) {
    return bloodPressure(vitals.bloodPressure) ??
        temperature(vitals.temperature) ??
        pulse(vitals.pulse) ??
        spo2(vitals.spo2) ??
        respiratoryRate(vitals.respiratoryRate);
  }
}
