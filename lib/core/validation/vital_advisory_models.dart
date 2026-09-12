enum VitalAdvisoryLevel { none, normal, caution, warning, critical, hypothermia }

class VitalAdvisory {
  const VitalAdvisory({this.level = VitalAdvisoryLevel.none, this.message});

  const VitalAdvisory.none() : level = VitalAdvisoryLevel.none, message = null;

  final VitalAdvisoryLevel level;
  final String? message;

  bool get hasMessage => message != null && message!.isNotEmpty;
}
